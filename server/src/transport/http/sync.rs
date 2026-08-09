use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use ledger_contracts::{
    MutationReceiptDto, SyncChangeDto, SyncPullResponse, SyncPushRequest, SyncPushResponse,
};
use ledger_domain::{validate_balanced, EntryDraft};
use serde::Deserialize;
use time::{format_description::well_known::Rfc3339, OffsetDateTime, UtcOffset};
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{AccountRecord, AppState, ChangeRecord, MutationReceipt, TxRecord};
use crate::transport::http::authz::{require_book_member, AuthUser};

// Separate advisory-lock roles so hash collisions can only add contention, not invert lock order.
const ACCOUNT_MUTATION_LOCK_NAMESPACE: i32 = 0x4C41_0001;
const ACCOUNT_HIERARCHY_LOCK_NAMESPACE: i32 = 0x4C41_0002;
const ACCOUNT_ENTITY_LOCK_NAMESPACE: i32 = 0x4C41_0003;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/v1/books/{book_id}/sync/push", post(push))
        .route("/v1/books/{book_id}/sync/pull", get(pull))
        .route("/v1/books/{book_id}/sync/bootstrap", post(bootstrap))
}

#[derive(Debug, Deserialize)]
struct PullQuery {
    cursor: Option<i64>,
    limit: Option<usize>,
}

#[derive(sqlx::FromRow)]
struct PullChangeRow {
    sequence: i64,
    commit_id: String,
    entity_type: String,
    entity_id: String,
    operation: String,
    entity_version: i64,
    payload: serde_json::Value,
    occurred_at: Option<OffsetDateTime>,
}

#[derive(Debug)]
struct AccountPayload {
    name: String,
    account_type: String,
    currency: String,
    // Missing preserves the existing parent; explicit null moves to the root.
    parent_account_id: Option<Option<String>>,
}

fn parse_account_payload(
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> Result<AccountPayload, MutationReceiptDto> {
    if mutation.operation != "create" && mutation.operation != "update" {
        return Err(rejected_receipt(mutation, "UNSUPPORTED_MUTATION", None));
    }

    let scoped_prefix = format!("{book_id}:");
    if mutation
        .entity_id
        .strip_prefix(&scoped_prefix)
        .is_none_or(|suffix| suffix.is_empty())
    {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    }

    let Some(name) = mutation
        .payload
        .get("name")
        .and_then(|value| value.as_str())
    else {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    };
    let name = name.trim();
    let Some(account_type) = mutation
        .payload
        .get("accountType")
        .and_then(|value| value.as_str())
    else {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    };
    let Some(currency) = mutation
        .payload
        .get("currency")
        .and_then(|value| value.as_str())
    else {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    };

    if name.is_empty()
        || name.chars().count() > 24
        || !matches!(
            account_type,
            "asset" | "liability" | "income" | "expense" | "equity"
        )
        || currency.len() != 3
        || !currency.bytes().all(|byte| byte.is_ascii_uppercase())
    {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    }

    let parent_account_id = match mutation.payload.get("parentAccountId") {
        None => None,
        Some(serde_json::Value::Null) => Some(None),
        Some(serde_json::Value::String(parent_id))
            if parent_id.starts_with(&scoped_prefix) && parent_id.len() > scoped_prefix.len() =>
        {
            Some(Some(parent_id.clone()))
        }
        Some(_) => return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None)),
    };

    Ok(AccountPayload {
        name: name.to_string(),
        account_type: account_type.to_string(),
        currency: currency.to_string(),
        parent_account_id,
    })
}

async fn valid_account_parent_pg(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    book_id: &str,
    account_id: &str,
    account_type: &str,
    parent_account_id: Option<&str>,
) -> Result<bool, sqlx::Error> {
    let Some(parent_id) = parent_account_id else {
        return Ok(true);
    };
    if !matches!(account_type, "expense" | "income") || parent_id == account_id {
        return Ok(false);
    }
    let parent: Option<(String, String, Option<String>)> = sqlx::query_as(
        "SELECT book_id, account_type, parent_account_id
         FROM accounts WHERE id=$1",
    )
    .bind(parent_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((parent_book_id, parent_type, grandparent_id)) = parent else {
        return Ok(false);
    };
    if parent_book_id != book_id || parent_type != account_type || grandparent_id.is_some() {
        return Ok(false);
    }
    let child_count: (i64,) =
        sqlx::query_as("SELECT COUNT(*)::bigint FROM accounts WHERE parent_account_id=$1")
            .bind(account_id)
            .fetch_one(&mut **tx)
            .await?;
    Ok(child_count.0 == 0)
}

fn valid_account_parent_mem(
    store: &crate::state::MemoryStore,
    book_id: &str,
    account_id: &str,
    account_type: &str,
    parent_account_id: Option<&str>,
) -> bool {
    let Some(parent_id) = parent_account_id else {
        return true;
    };
    if !matches!(account_type, "expense" | "income") || parent_id == account_id {
        return false;
    }
    let Some(parent) = store.accounts.get(parent_id) else {
        return false;
    };
    parent.book_id == book_id
        && parent.account_type == account_type
        && parent.parent_account_id.is_none()
        && !store
            .accounts
            .values()
            .any(|account| account.parent_account_id.as_deref() == Some(account_id))
}

async fn push(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<SyncPushRequest>,
) -> Result<Json<SyncPushResponse>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let mut receipts = Vec::new();
    for mutation in req.mutations {
        if let Some(pool) = &state.pool {
            let existing: Option<(String, String, Option<i64>)> = sqlx::query_as(
                "SELECT status, result_code, entity_version FROM sync_mutations
                 WHERE book_id=$1 AND device_id=$2 AND mutation_id=$3",
            )
            .bind(&book_id)
            .bind(&req.device_id)
            .bind(&mutation.mutation_id)
            .fetch_optional(pool)
            .await
            .map_err(db_err)?;
            if let Some((status, result_code, entity_version)) = existing {
                receipts.push(MutationReceiptDto {
                    mutation_id: mutation.mutation_id.clone(),
                    status,
                    result_code,
                    entity_version,
                });
                continue;
            }
            let receipt = process_mutation_pg(&state, &book_id, &req.device_id, &mutation).await;
            sqlx::query(
                "INSERT INTO sync_mutations
                 (book_id, device_id, mutation_id, status, result_code, entity_version)
                 VALUES ($1,$2,$3,$4,$5,$6)
                 ON CONFLICT (book_id, device_id, mutation_id) DO NOTHING",
            )
            .bind(&book_id)
            .bind(&req.device_id)
            .bind(&mutation.mutation_id)
            .bind(&receipt.status)
            .bind(&receipt.result_code)
            .bind(receipt.entity_version)
            .execute(pool)
            .await
            .map_err(db_err)?;
            receipts.push(receipt);
            continue;
        }

        let _memory_sync_guard = state.memory_sync_lock.lock().await;
        let key = (
            book_id.clone(),
            req.device_id.clone(),
            mutation.mutation_id.clone(),
        );
        {
            let store = state.store.read().await;
            if let Some(existing) = store.mutations.get(&key) {
                receipts.push(MutationReceiptDto {
                    mutation_id: mutation.mutation_id.clone(),
                    status: existing.status.clone(),
                    result_code: existing.result_code.clone(),
                    entity_version: existing.entity_version,
                });
                continue;
            }
        }
        let receipt = process_mutation_mem(&state, &book_id, &mutation).await;
        {
            let mut store = state.store.write().await;
            store.mutations.insert(
                key,
                MutationReceipt {
                    status: receipt.status.clone(),
                    result_code: receipt.result_code.clone(),
                    entity_version: receipt.entity_version,
                },
            );
        }
        receipts.push(receipt);
    }
    Ok(Json(SyncPushResponse { receipts }))
}

fn parse_entries(
    mutation: &ledger_contracts::SyncMutationDto,
) -> Result<Vec<EntryDraft>, MutationReceiptDto> {
    let entries = mutation
        .payload
        .get("entries")
        .and_then(|v| v.as_array())
        .ok_or_else(|| MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "INVALID_PAYLOAD".into(),
            entity_version: None,
        })?;

    let mut drafts = Vec::new();
    for e in entries {
        let account_id = e
            .get("accountId")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let amount_minor = e
            .get("amountMinor")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<i128>().ok())
            .unwrap_or(0);
        let currency = e
            .get("currency")
            .and_then(|v| v.as_str())
            .unwrap_or("CNY")
            .to_string();
        drafts.push(EntryDraft {
            account_id,
            amount_minor,
            currency,
        });
    }
    Ok(drafts)
}

fn parse_occurred_at(
    mutation: &ledger_contracts::SyncMutationDto,
) -> Result<Option<OffsetDateTime>, MutationReceiptDto> {
    let Some(raw) = mutation.payload.get("occurredAt") else {
        return Ok(None);
    };
    let Some(raw) = raw.as_str() else {
        return Err(rejected_receipt(mutation, "INVALID_PAYLOAD", None));
    };
    OffsetDateTime::parse(raw, &Rfc3339)
        .map(|value| Some(value.to_offset(UtcOffset::UTC)))
        .map_err(|_| rejected_receipt(mutation, "INVALID_PAYLOAD", None))
}

pub(crate) fn format_occurred_at(value: OffsetDateTime) -> String {
    value
        .to_offset(UtcOffset::UTC)
        .format(&Rfc3339)
        .expect("UTC timestamp must be representable as RFC3339")
}

pub(crate) fn canonical_transaction_payload(
    payload: &serde_json::Value,
    occurred_at: OffsetDateTime,
) -> serde_json::Value {
    let mut payload = payload.clone();
    if let Some(object) = payload.as_object_mut() {
        object.insert(
            "occurredAt".into(),
            serde_json::Value::String(format_occurred_at(occurred_at)),
        );
    }
    payload
}

fn backfill_transaction_occurred_at(
    payload: serde_json::Value,
    occurred_at: OffsetDateTime,
) -> serde_json::Value {
    if payload.get("occurredAt").is_some() {
        payload
    } else {
        canonical_transaction_payload(&payload, occurred_at)
    }
}

fn validate_or_reject(
    mutation: &ledger_contracts::SyncMutationDto,
    drafts: &[EntryDraft],
) -> Option<MutationReceiptDto> {
    if mutation.entity_type != "transaction"
        || (mutation.operation != "create"
            && mutation.operation != "update"
            && mutation.operation != "delete")
    {
        return Some(MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "UNSUPPORTED_MUTATION".into(),
            entity_version: None,
        });
    }
    if mutation.operation == "delete" {
        return None;
    }
    if let Err(err) = validate_balanced(drafts) {
        let code = if err == ledger_domain::DomainError::Unbalanced {
            "LEDGER_UNBALANCED"
        } else {
            "LEDGER_INVALID"
        };
        return Some(MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: code.into(),
            entity_version: None,
        });
    }
    None
}

async fn process_mutation_pg(
    state: &AppState,
    book_id: &str,
    device_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    if mutation.entity_type == "account" {
        return process_account_mutation_pg(state, book_id, device_id, mutation).await;
    }
    if mutation.entity_type != "transaction" {
        return rejected_receipt(mutation, "UNSUPPORTED_MUTATION", None);
    }
    let pool = state.pool.as_ref().unwrap();
    let (drafts, requested_occurred_at) = if mutation.operation == "delete" {
        (None, None)
    } else {
        let requested_occurred_at = match parse_occurred_at(mutation) {
            Ok(value) => value,
            Err(receipt) => return receipt,
        };
        let drafts = match parse_entries(mutation) {
            Ok(drafts) => {
                if let Some(receipt) = validate_or_reject(mutation, &drafts) {
                    return receipt;
                }
                Some(drafts)
            }
            Err(receipt) => return receipt,
        };
        (drafts, requested_occurred_at)
    };

    let Ok(mut tx) = pool.begin().await else {
        return db_error_receipt(mutation);
    };

    let result: Result<MutationReceiptDto, sqlx::Error> = async {
        let lock_key = format!("{book_id}:{}", mutation.entity_id);
        sqlx::query("SELECT pg_advisory_xact_lock(hashtext($1))")
            .bind(lock_key)
            .execute(&mut *tx)
            .await?;

        let existing_receipt: Option<(String, String, Option<i64>)> = sqlx::query_as(
            "SELECT status, result_code, entity_version
             FROM sync_mutations
             WHERE book_id=$1 AND device_id=$2 AND mutation_id=$3",
        )
        .bind(book_id)
        .bind(device_id)
        .bind(&mutation.mutation_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((status, result_code, entity_version)) = existing_receipt {
            let receipt = MutationReceiptDto {
                mutation_id: mutation.mutation_id.clone(),
                status,
                result_code,
                entity_version,
            };
            tx.commit().await?;
            return Ok(receipt);
        }

        if let Some(drafts) = drafts.as_ref() {
            let mut account_ids = drafts
                .iter()
                .map(|draft| draft.account_id.clone())
                .collect::<Vec<_>>();
            account_ids.sort_unstable();
            account_ids.dedup();
            let found: (i64,) = sqlx::query_as(
                "SELECT COUNT(*)::bigint FROM accounts
                 WHERE book_id=$1 AND id=ANY($2)",
            )
            .bind(book_id)
            .bind(&account_ids)
            .fetch_one(&mut *tx)
            .await?;
            if found.0 != account_ids.len() as i64 {
                let receipt = rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
        }

        let existing: Option<(i64, OffsetDateTime)> = sqlx::query_as(
            "SELECT version, occurred_at FROM transactions
             WHERE id=$1 AND book_id=$2
             FOR UPDATE",
        )
        .bind(&mutation.entity_id)
        .bind(book_id)
        .fetch_optional(&mut *tx)
        .await?;

        if mutation.operation == "delete" {
            let Some((version, _)) = existing else {
                let receipt = rejected_receipt(mutation, "NOT_FOUND", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            };
            if mutation.base_version != 0 && mutation.base_version != version {
                let receipt = rejected_receipt(mutation, "LEDGER_VERSION_CONFLICT", Some(version));
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }

            let new_version = version + 1;
            let commit_id = Uuid::now_v7().to_string();
            let updated = sqlx::query(
                "UPDATE transactions SET deleted_at=now(), version=$1
                 WHERE id=$2 AND book_id=$3 AND version=$4",
            )
            .bind(new_version)
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(version)
            .execute(&mut *tx)
            .await?;
            if updated.rows_affected() != 1 {
                return Err(sqlx::Error::Protocol("transaction CAS failed".into()));
            }
            insert_delete_change(&mut tx, book_id, mutation, &commit_id, new_version).await?;
            let receipt = applied_receipt(mutation, new_version);
            insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
            tx.commit().await?;
            return Ok(receipt);
        }

        if let Some((version, _)) = existing.as_ref() {
            if mutation.operation == "create" || mutation.base_version != *version {
                let receipt = rejected_receipt(mutation, "LEDGER_VERSION_CONFLICT", Some(*version));
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
        }

        let is_update = existing.is_some();
        let version = existing
            .as_ref()
            .map(|(version, _)| version + 1)
            .unwrap_or(1);
        let occurred_at = requested_occurred_at
            .or_else(|| existing.as_ref().map(|(_, occurred_at)| *occurred_at))
            .unwrap_or_else(OffsetDateTime::now_utc);
        let canonical_payload = canonical_transaction_payload(&mutation.payload, occurred_at);
        let description = mutation
            .payload
            .get("description")
            .and_then(|value| value.as_str())
            .map(str::to_string);
        if is_update {
            let updated = sqlx::query(
                "UPDATE transactions SET description=$1, occurred_at=$2, version=$3
                 WHERE id=$4 AND book_id=$5 AND version=$6",
            )
            .bind(&description)
            .bind(occurred_at)
            .bind(version)
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(mutation.base_version)
            .execute(&mut *tx)
            .await?;
            if updated.rows_affected() != 1 {
                return Err(sqlx::Error::Protocol("transaction CAS failed".into()));
            }
            sqlx::query("DELETE FROM transaction_entries WHERE transaction_id=$1")
                .bind(&mutation.entity_id)
                .execute(&mut *tx)
                .await?;
        } else {
            sqlx::query(
                "INSERT INTO transactions (id, book_id, description, occurred_at, version)
                 VALUES ($1,$2,$3,$4,$5)",
            )
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(&description)
            .bind(occurred_at)
            .bind(version)
            .execute(&mut *tx)
            .await?;
        }

        for (idx, entry) in drafts
            .as_ref()
            .expect("non-delete drafts")
            .iter()
            .enumerate()
        {
            let entry_id = format!("{}-{idx}", mutation.entity_id);
            sqlx::query(
                "INSERT INTO transaction_entries
                 (id, transaction_id, account_id, amount_minor, currency_code, entry_index)
                 VALUES ($1,$2,$3,$4,$5,$6)",
            )
            .bind(&entry_id)
            .bind(&mutation.entity_id)
            .bind(&entry.account_id)
            .bind(entry.amount_minor as i64)
            .bind(&entry.currency)
            .bind(idx as i32)
            .execute(&mut *tx)
            .await?;
        }

        let commit_id = Uuid::now_v7().to_string();
        sqlx::query(
            "INSERT INTO sync_changes
             (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
             VALUES ($1,$2,'transaction',$3,'upsert',$4,$5)",
        )
        .bind(book_id)
        .bind(&commit_id)
        .bind(&mutation.entity_id)
        .bind(version)
        .bind(&canonical_payload)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO transaction_revisions
             (id, book_id, transaction_id, version, operation, payload)
             VALUES ($1,$2,$3,$4,$5,$6)",
        )
        .bind(Uuid::now_v7().to_string())
        .bind(book_id)
        .bind(&mutation.entity_id)
        .bind(version)
        .bind(&mutation.operation)
        .bind(&canonical_payload)
        .execute(&mut *tx)
        .await?;
        let receipt = applied_receipt(mutation, version);
        insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
        tx.commit().await?;
        Ok(receipt)
    }
    .await;

    result.unwrap_or_else(|_| db_error_receipt(mutation))
}

async fn process_account_mutation_pg(
    state: &AppState,
    book_id: &str,
    device_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    let pool = state.pool.as_ref().unwrap();
    let Ok(mut tx) = pool.begin().await else {
        return db_error_receipt(mutation);
    };

    let result: Result<MutationReceiptDto, sqlx::Error> = async {
        let mutation_lock_key = format!("{book_id}:mutation:{device_id}:{}", mutation.mutation_id);
        sqlx::query("SELECT pg_advisory_xact_lock($1, hashtext($2))")
            .bind(ACCOUNT_MUTATION_LOCK_NAMESPACE)
            .bind(mutation_lock_key)
            .execute(&mut *tx)
            .await?;

        let existing_receipt: Option<(String, String, Option<i64>)> = sqlx::query_as(
            "SELECT status, result_code, entity_version
             FROM sync_mutations
             WHERE book_id=$1 AND device_id=$2 AND mutation_id=$3",
        )
        .bind(book_id)
        .bind(device_id)
        .bind(&mutation.mutation_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((status, result_code, entity_version)) = existing_receipt {
            let receipt = MutationReceiptDto {
                mutation_id: mutation.mutation_id.clone(),
                status,
                result_code,
                entity_version,
            };
            tx.commit().await?;
            return Ok(receipt);
        }

        let payload = match parse_account_payload(book_id, mutation) {
            Ok(payload) => payload,
            Err(receipt) => {
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
        };

        let hierarchy_lock_key = format!("{book_id}:account-hierarchy");
        sqlx::query("SELECT pg_advisory_xact_lock($1, hashtext($2))")
            .bind(ACCOUNT_HIERARCHY_LOCK_NAMESPACE)
            .bind(hierarchy_lock_key)
            .execute(&mut *tx)
            .await?;

        let account_lock_key = format!("{book_id}:account:{}", mutation.entity_id);
        sqlx::query("SELECT pg_advisory_xact_lock($1, hashtext($2))")
            .bind(ACCOUNT_ENTITY_LOCK_NAMESPACE)
            .bind(account_lock_key)
            .execute(&mut *tx)
            .await?;

        let existing: Option<(String, i64, String, String, Option<String>)> = sqlx::query_as(
            "SELECT book_id, version, account_type, currency_code, parent_account_id
             FROM accounts WHERE id=$1 FOR UPDATE",
        )
        .bind(&mutation.entity_id)
        .fetch_optional(&mut *tx)
        .await?;

        let (version, account_type, currency, parent_account_id) = if mutation.operation == "create"
        {
            if let Some((_, version, _, _, _)) = existing {
                let receipt = rejected_receipt(mutation, "LEDGER_VERSION_CONFLICT", Some(version));
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
            let parent_account_id = payload.parent_account_id.clone().flatten();
            if !valid_account_parent_pg(
                &mut tx,
                book_id,
                &mutation.entity_id,
                &payload.account_type,
                parent_account_id.as_deref(),
            )
            .await?
            {
                let receipt = rejected_receipt(mutation, "INVALID_CATEGORY_PARENT", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
            sqlx::query(
                "INSERT INTO accounts
                 (id, book_id, name, account_type, currency_code,
                  parent_account_id, version)
                 VALUES ($1,$2,$3,$4,$5,$6,1)",
            )
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(&payload.name)
            .bind(&payload.account_type)
            .bind(&payload.currency)
            .bind(&parent_account_id)
            .execute(&mut *tx)
            .await?;
            (
                1,
                payload.account_type.clone(),
                payload.currency.clone(),
                parent_account_id,
            )
        } else {
            let Some((
                existing_book_id,
                current_version,
                account_type,
                currency,
                current_parent_account_id,
            )) = existing
            else {
                let receipt = rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            };
            if existing_book_id != book_id {
                let receipt = rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
            let parent_account_id = payload
                .parent_account_id
                .clone()
                .unwrap_or(current_parent_account_id);
            if !valid_account_parent_pg(
                &mut tx,
                book_id,
                &mutation.entity_id,
                &account_type,
                parent_account_id.as_deref(),
            )
            .await?
            {
                let receipt = rejected_receipt(mutation, "INVALID_CATEGORY_PARENT", None);
                insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
                tx.commit().await?;
                return Ok(receipt);
            }
            let version = current_version + 1;
            sqlx::query(
                "UPDATE accounts
                 SET name=$1, parent_account_id=$2, version=$3
                 WHERE id=$4 AND book_id=$5",
            )
            .bind(&payload.name)
            .bind(&parent_account_id)
            .bind(version)
            .bind(&mutation.entity_id)
            .bind(book_id)
            .execute(&mut *tx)
            .await?;
            (version, account_type, currency, parent_account_id)
        };

        let canonical_payload = serde_json::json!({
            "name": payload.name,
            "accountType": account_type,
            "currency": currency,
            "parentAccountId": parent_account_id,
        });
        sqlx::query(
            "INSERT INTO sync_changes
             (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
             VALUES ($1,$2,'account',$3,'upsert',$4,$5)",
        )
        .bind(book_id)
        .bind(Uuid::now_v7().to_string())
        .bind(&mutation.entity_id)
        .bind(version)
        .bind(canonical_payload)
        .execute(&mut *tx)
        .await?;
        let receipt = applied_receipt(mutation, version);
        insert_pg_receipt(&mut tx, book_id, device_id, &receipt).await?;
        tx.commit().await?;
        Ok(receipt)
    }
    .await;

    result.unwrap_or_else(|_| db_error_receipt(mutation))
}

fn db_error_receipt(mutation: &ledger_contracts::SyncMutationDto) -> MutationReceiptDto {
    rejected_receipt(mutation, "DB_ERROR", None)
}

fn rejected_receipt(
    mutation: &ledger_contracts::SyncMutationDto,
    result_code: &str,
    entity_version: Option<i64>,
) -> MutationReceiptDto {
    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "rejected".into(),
        result_code: result_code.into(),
        entity_version,
    }
}

fn applied_receipt(
    mutation: &ledger_contracts::SyncMutationDto,
    version: i64,
) -> MutationReceiptDto {
    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(version),
    }
}

async fn insert_pg_receipt(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    book_id: &str,
    device_id: &str,
    receipt: &MutationReceiptDto,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO sync_mutations
         (book_id, device_id, mutation_id, status, result_code, entity_version)
         VALUES ($1,$2,$3,$4,$5,$6)",
    )
    .bind(book_id)
    .bind(device_id)
    .bind(&receipt.mutation_id)
    .bind(&receipt.status)
    .bind(&receipt.result_code)
    .bind(receipt.entity_version)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn insert_delete_change(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
    commit_id: &str,
    version: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO sync_changes
         (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
         VALUES ($1,$2,'transaction',$3,'delete',$4,$5)",
    )
    .bind(book_id)
    .bind(commit_id)
    .bind(&mutation.entity_id)
    .bind(version)
    .bind(&mutation.payload)
    .execute(&mut **tx)
    .await?;
    sqlx::query(
        "INSERT INTO transaction_revisions
         (id, book_id, transaction_id, version, operation, payload)
         VALUES ($1,$2,$3,$4,'delete',$5)",
    )
    .bind(Uuid::now_v7().to_string())
    .bind(book_id)
    .bind(&mutation.entity_id)
    .bind(version)
    .bind(&mutation.payload)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn process_mutation_mem(
    state: &AppState,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    if mutation.entity_type == "account" {
        return process_account_mutation_mem(state, book_id, mutation).await;
    }
    if mutation.entity_type != "transaction" {
        return rejected_receipt(mutation, "UNSUPPORTED_MUTATION", None);
    }
    if mutation.operation == "delete" {
        return process_delete_mem(state, book_id, mutation).await;
    }
    let requested_occurred_at = match parse_occurred_at(mutation) {
        Ok(value) => value,
        Err(receipt) => return receipt,
    };
    let drafts = match parse_entries(mutation) {
        Ok(d) => d,
        Err(r) => return r,
    };
    if let Some(r) = validate_or_reject(mutation, &drafts) {
        return r;
    }

    let mut store = state.store.write().await;
    if !drafts.iter().all(|draft| {
        store
            .accounts
            .get(&draft.account_id)
            .is_some_and(|account| account.book_id == book_id)
    }) {
        return rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
    }
    let existing = store.transactions.get(&mutation.entity_id).cloned();
    if let Some(existing) = existing.as_ref() {
        if mutation.operation == "create" || mutation.base_version != existing.version {
            return rejected_receipt(mutation, "LEDGER_VERSION_CONFLICT", Some(existing.version));
        }
    }

    let version = existing
        .as_ref()
        .map(|transaction| transaction.version + 1)
        .unwrap_or(1);
    let occurred_at = requested_occurred_at
        .or_else(|| existing.as_ref().map(|transaction| transaction.occurred_at))
        .unwrap_or_else(OffsetDateTime::now_utc);
    let canonical_payload = canonical_transaction_payload(&mutation.payload, occurred_at);
    let commit_id = Uuid::now_v7().to_string();
    let entry_tuples: Vec<(String, i64, String)> = drafts
        .iter()
        .map(|d| {
            (
                d.account_id.clone(),
                d.amount_minor as i64,
                d.currency.clone(),
            )
        })
        .collect();
    store.transactions.insert(
        mutation.entity_id.clone(),
        TxRecord {
            id: mutation.entity_id.clone(),
            book_id: book_id.to_string(),
            occurred_at,
            description: mutation
                .payload
                .get("description")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            version,
            deleted: false,
            entries: entry_tuples,
        },
    );
    let sequence = (store.changes.len() as i64) + 1;
    store.changes.push(ChangeRecord {
        sequence,
        book_id: book_id.to_string(),
        commit_id,
        entity_type: "transaction".into(),
        entity_id: mutation.entity_id.clone(),
        operation: "upsert".into(),
        entity_version: version,
        payload: canonical_payload,
    });

    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(version),
    }
}

async fn process_account_mutation_mem(
    state: &AppState,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    let payload = match parse_account_payload(book_id, mutation) {
        Ok(payload) => payload,
        Err(receipt) => return receipt,
    };

    let mut store = state.store.write().await;
    let existing = store.accounts.get(&mutation.entity_id).cloned();
    let (version, account_type, currency, parent_account_id) = if mutation.operation == "create" {
        if let Some(existing) = existing {
            return rejected_receipt(mutation, "LEDGER_VERSION_CONFLICT", Some(existing.version));
        }
        let parent_account_id = payload.parent_account_id.clone().flatten();
        if !valid_account_parent_mem(
            &store,
            book_id,
            &mutation.entity_id,
            &payload.account_type,
            parent_account_id.as_deref(),
        ) {
            return rejected_receipt(mutation, "INVALID_CATEGORY_PARENT", None);
        }
        store.accounts.insert(
            mutation.entity_id.clone(),
            AccountRecord {
                id: mutation.entity_id.clone(),
                book_id: book_id.to_string(),
                name: payload.name.clone(),
                account_type: payload.account_type.clone(),
                currency: payload.currency.clone(),
                parent_account_id: parent_account_id.clone(),
                version: 1,
            },
        );
        (1, payload.account_type, payload.currency, parent_account_id)
    } else {
        let Some(existing) = existing else {
            return rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
        };
        if existing.book_id != book_id {
            return rejected_receipt(mutation, "ACCOUNT_NOT_FOUND", None);
        }
        let parent_account_id = payload
            .parent_account_id
            .clone()
            .unwrap_or(existing.parent_account_id);
        if !valid_account_parent_mem(
            &store,
            book_id,
            &mutation.entity_id,
            &existing.account_type,
            parent_account_id.as_deref(),
        ) {
            return rejected_receipt(mutation, "INVALID_CATEGORY_PARENT", None);
        }
        let account = store.accounts.get_mut(&mutation.entity_id).unwrap();
        account.name = payload.name.clone();
        account.parent_account_id = parent_account_id.clone();
        account.version += 1;
        (
            account.version,
            account.account_type.clone(),
            account.currency.clone(),
            parent_account_id,
        )
    };

    let canonical_payload = serde_json::json!({
        "name": payload.name,
        "accountType": account_type,
        "currency": currency,
        "parentAccountId": parent_account_id,
    });
    let sequence = (store.changes.len() as i64) + 1;
    store.changes.push(ChangeRecord {
        sequence,
        book_id: book_id.to_string(),
        commit_id: Uuid::now_v7().to_string(),
        entity_type: "account".into(),
        entity_id: mutation.entity_id.clone(),
        operation: "upsert".into(),
        entity_version: version,
        payload: canonical_payload,
    });
    applied_receipt(mutation, version)
}

async fn pull(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Query(q): Query<PullQuery>,
) -> Result<Json<SyncPullResponse>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let cursor = q.cursor.unwrap_or(0);
    let limit = q.limit.unwrap_or(500).min(1000);

    if let Some(pool) = &state.pool {
        let rows: Vec<PullChangeRow> = sqlx::query_as(
            "SELECT sc.sequence, sc.commit_id, sc.entity_type, sc.entity_id, sc.operation,
                        sc.entity_version, sc.payload, t.occurred_at
                 FROM sync_changes sc
                 LEFT JOIN transactions t
                   ON sc.entity_type='transaction' AND sc.entity_id=t.id AND sc.book_id=t.book_id
                 WHERE sc.book_id=$1 AND sc.sequence > $2
                 ORDER BY sc.sequence ASC
                 LIMIT $3",
        )
        .bind(&book_id)
        .bind(cursor)
        .bind((limit as i64) + 50)
        .fetch_all(pool)
        .await
        .map_err(db_err)?;

        let mut page = Vec::new();
        let mut last_commit: Option<String> = None;
        for row in rows {
            let PullChangeRow {
                sequence,
                commit_id,
                entity_type,
                entity_id,
                operation,
                entity_version,
                payload,
                occurred_at,
            } = row;
            let payload = if entity_type == "transaction" && operation == "upsert" {
                match occurred_at {
                    Some(value) => backfill_transaction_occurred_at(payload, value),
                    None => payload,
                }
            } else {
                payload
            };
            if page.len() >= limit {
                if last_commit.as_ref() == Some(&commit_id) {
                    page.push(SyncChangeDto {
                        sequence: sequence.to_string(),
                        commit_id,
                        entity_type,
                        entity_id,
                        operation,
                        version: entity_version,
                        payload,
                    });
                    continue;
                }
                break;
            }
            last_commit = Some(commit_id.clone());
            page.push(SyncChangeDto {
                sequence: sequence.to_string(),
                commit_id,
                entity_type,
                entity_id,
                operation,
                version: entity_version,
                payload,
            });
        }
        let next_cursor = page
            .last()
            .and_then(|c| c.sequence.parse::<i64>().ok())
            .unwrap_or(cursor);
        let has_more: (i64,) = sqlx::query_as(
            "SELECT COUNT(*)::bigint FROM sync_changes WHERE book_id=$1 AND sequence > $2",
        )
        .bind(&book_id)
        .bind(next_cursor)
        .fetch_one(pool)
        .await
        .map_err(db_err)?;
        return Ok(Json(SyncPullResponse {
            next_cursor: next_cursor.to_string(),
            has_more: has_more.0 > 0,
            changes: page,
        }));
    }

    let store = state.store.read().await;
    let mut changes: Vec<_> = store
        .changes
        .iter()
        .filter(|c| c.book_id == book_id && c.sequence > cursor)
        .cloned()
        .collect();
    changes.sort_by_key(|c| c.sequence);

    let mut page = Vec::new();
    let mut last_commit = None;
    for change in changes {
        if page.len() >= limit {
            if last_commit.as_ref() == Some(&change.commit_id) {
                page.push(change);
                continue;
            }
            break;
        }
        last_commit = Some(change.commit_id.clone());
        page.push(change);
    }

    let next_cursor = page.last().map(|c| c.sequence).unwrap_or(cursor);
    let has_more = store
        .changes
        .iter()
        .any(|c| c.book_id == book_id && c.sequence > next_cursor);

    Ok(Json(SyncPullResponse {
        next_cursor: next_cursor.to_string(),
        has_more,
        changes: page
            .into_iter()
            .map(|c| {
                let payload = if c.entity_type == "transaction" && c.operation == "upsert" {
                    store
                        .transactions
                        .get(&c.entity_id)
                        .map(|transaction| {
                            backfill_transaction_occurred_at(
                                c.payload.clone(),
                                transaction.occurred_at,
                            )
                        })
                        .unwrap_or(c.payload)
                } else {
                    c.payload
                };
                SyncChangeDto {
                    sequence: c.sequence.to_string(),
                    commit_id: c.commit_id,
                    entity_type: c.entity_type,
                    entity_id: c.entity_id,
                    operation: c.operation,
                    version: c.entity_version,
                    payload,
                }
            })
            .collect(),
    }))
}

async fn bootstrap(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let exists: Option<(String,)> = sqlx::query_as("SELECT id FROM books WHERE id=$1")
            .bind(&book_id)
            .fetch_optional(pool)
            .await
            .map_err(db_err)?;
        if exists.is_none() {
            return Err(ApiError::new(
                StatusCode::NOT_FOUND,
                "BOOK_NOT_FOUND",
                "book missing",
            ));
        }
        let high: (i64,) = sqlx::query_as(
            "SELECT COALESCE(MAX(sequence),0)::bigint FROM sync_changes WHERE book_id=$1",
        )
        .bind(&book_id)
        .fetch_one(pool)
        .await
        .map_err(db_err)?;
        let txs: Vec<(String, i64, Option<String>, OffsetDateTime)> = sqlx::query_as(
            "SELECT id, version, description, occurred_at
             FROM transactions WHERE book_id=$1 AND deleted_at IS NULL",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(db_err)?;
        let accounts: Vec<(String, i64, String, String, String, Option<String>)> = sqlx::query_as(
            "SELECT id, version, name, account_type, currency_code, parent_account_id
             FROM accounts WHERE book_id=$1 ORDER BY id",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(db_err)?;
        let mut out = Vec::new();
        for (id, version, description, occurred_at) in txs {
            let entries: Vec<(String, i64, String)> = sqlx::query_as(
                "SELECT account_id, amount_minor, currency_code FROM transaction_entries
                 WHERE transaction_id=$1 ORDER BY entry_index",
            )
            .bind(&id)
            .fetch_all(pool)
            .await
            .map_err(db_err)?;
            out.push(serde_json::json!({
                "id": id,
                "version": version,
                "occurredAt": format_occurred_at(occurred_at),
                "description": description,
                "entries": entries.iter().map(|(a,m,c)| serde_json::json!({
                    "accountId": a, "amountMinor": m.to_string(), "currency": c
                })).collect::<Vec<_>>(),
            }));
        }
        return Ok(Json(serde_json::json!({
            "bootstrapId": Uuid::now_v7().to_string(),
            "highWaterCursor": high.0.to_string(),
            "accounts": accounts.iter().map(|(id, version, name, account_type, currency, parent_account_id)| serde_json::json!({
                "id": id,
                "version": version,
                "name": name,
                "accountType": account_type,
                "currency": currency,
                "parentAccountId": parent_account_id,
            })).collect::<Vec<_>>(),
            "transactions": out,
        })));
    }

    let store = state.store.read().await;
    if !store.books.contains_key(&book_id) {
        return Err(ApiError::new(
            StatusCode::NOT_FOUND,
            "BOOK_NOT_FOUND",
            "book missing",
        ));
    }
    let high_water = store
        .changes
        .iter()
        .filter(|c| c.book_id == book_id)
        .map(|c| c.sequence)
        .max()
        .unwrap_or(0);
    let txs: Vec<_> = store
        .transactions
        .values()
        .filter(|t| t.book_id == book_id && !t.deleted)
        .cloned()
        .collect();
    let accounts = store
        .accounts
        .values()
        .filter(|account| account.book_id == book_id)
        .map(|account| {
            serde_json::json!({
                "id": account.id,
                "version": account.version,
                "name": account.name,
                "accountType": account.account_type,
                "currency": account.currency,
                "parentAccountId": account.parent_account_id,
            })
        })
        .collect::<Vec<_>>();
    Ok(Json(serde_json::json!({
        "bootstrapId": Uuid::now_v7().to_string(),
        "highWaterCursor": high_water.to_string(),
        "accounts": accounts,
        "transactions": txs.iter().map(|t| serde_json::json!({
            "id": t.id,
            "version": t.version,
            "occurredAt": format_occurred_at(t.occurred_at),
            "description": t.description,
            "entries": t.entries.iter().map(|(account_id, amount_minor, currency)| serde_json::json!({
                "accountId": account_id,
                "amountMinor": amount_minor.to_string(),
                "currency": currency,
            })).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
    })))
}

async fn process_delete_mem(
    state: &AppState,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    let mut store = state.store.write().await;
    let Some(existing) = store.transactions.get_mut(&mutation.entity_id) else {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "NOT_FOUND".into(),
            entity_version: None,
        };
    };
    if existing.book_id != book_id {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "NOT_FOUND".into(),
            entity_version: None,
        };
    }
    if mutation.base_version != 0 && mutation.base_version != existing.version {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "LEDGER_VERSION_CONFLICT".into(),
            entity_version: Some(existing.version),
        };
    }
    existing.deleted = true;
    existing.version += 1;
    let version = existing.version;
    let sequence = (store.changes.len() as i64) + 1;
    store.changes.push(ChangeRecord {
        sequence,
        book_id: book_id.to_string(),
        commit_id: Uuid::now_v7().to_string(),
        entity_type: "transaction".into(),
        entity_id: mutation.entity_id.clone(),
        operation: "delete".into(),
        entity_version: version,
        payload: mutation.payload.clone(),
    });
    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(version),
    }
}

fn db_err(e: sqlx::Error) -> ApiError {
    ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
}

#[cfg(test)]
mod tests {
    use ledger_contracts::SyncMutationDto;
    use serde_json::json;

    use super::{
        parse_account_payload, parse_occurred_at, process_account_mutation_mem,
        process_mutation_mem,
    };
    use crate::{state::AccountRecord, AppState, Config};

    fn account_mutation(
        mutation_id: &str,
        entity_id: &str,
        operation: &str,
        base_version: i64,
        name: &str,
        account_type: &str,
        currency: &str,
    ) -> SyncMutationDto {
        SyncMutationDto {
            mutation_id: mutation_id.to_string(),
            entity_type: "account".into(),
            entity_id: entity_id.to_string(),
            operation: operation.to_string(),
            base_version,
            schema_version: 1,
            payload: json!({
                "name": name,
                "accountType": account_type,
                "currency": currency,
            }),
        }
    }

    fn transaction_mutation(payload: serde_json::Value) -> SyncMutationDto {
        SyncMutationDto {
            mutation_id: "transaction-date".into(),
            entity_type: "transaction".into(),
            entity_id: "tx-1".into(),
            operation: "create".into(),
            base_version: 0,
            schema_version: 1,
            payload,
        }
    }

    #[test]
    fn occurred_at_accepts_rfc3339_and_normalizes_to_utc() {
        let mutation = transaction_mutation(json!({
            "occurredAt": "2024-04-13T12:34:56+08:00",
        }));

        let occurred_at = parse_occurred_at(&mutation).unwrap().unwrap();

        assert_eq!(occurred_at.offset(), time::UtcOffset::UTC);
        assert_eq!(occurred_at.date().to_string(), "2024-04-13");
        assert_eq!(occurred_at.hour(), 4);
        assert_eq!(occurred_at.minute(), 34);
        assert_eq!(occurred_at.second(), 56);
    }

    #[test]
    fn occurred_at_allows_missing_and_rejects_invalid_values() {
        assert!(parse_occurred_at(&transaction_mutation(json!({})))
            .unwrap()
            .is_none());

        for invalid in [json!(null), json!(42), json!("2024-04-13")] {
            let mutation = transaction_mutation(json!({"occurredAt": invalid}));
            let receipt = parse_occurred_at(&mutation).unwrap_err();
            assert_eq!(receipt.status, "rejected");
            assert_eq!(receipt.result_code, "INVALID_PAYLOAD");
        }
    }

    #[test]
    fn account_payload_validation_trims_name_and_rejects_invalid_fields() {
        let valid = account_mutation(
            "valid",
            "book-1:category",
            "create",
            0,
            "  Groceries  ",
            "expense",
            "CNY",
        );
        let parsed = parse_account_payload("book-1", &valid).unwrap();
        assert_eq!(parsed.name, "Groceries");
        let boundary = account_mutation(
            "boundary",
            "book-1:boundary",
            "create",
            0,
            &"x".repeat(24),
            "expense",
            "CNY",
        );
        assert!(parse_account_payload("book-1", &boundary).is_ok());

        for invalid in [
            account_mutation(
                "wrong-scope",
                "book-2:category",
                "create",
                0,
                "Name",
                "expense",
                "CNY",
            ),
            account_mutation("empty-id", "book-1:", "create", 0, "Name", "expense", "CNY"),
            account_mutation(
                "blank-name",
                "book-1:blank",
                "create",
                0,
                "   ",
                "expense",
                "CNY",
            ),
            account_mutation(
                "long-name",
                "book-1:long",
                "create",
                0,
                &"x".repeat(25),
                "expense",
                "CNY",
            ),
            account_mutation(
                "bad-type",
                "book-1:type",
                "create",
                0,
                "Name",
                "other",
                "CNY",
            ),
            account_mutation(
                "bad-currency",
                "book-1:currency",
                "create",
                0,
                "Name",
                "expense",
                "cny",
            ),
        ] {
            let receipt = parse_account_payload("book-1", &invalid).unwrap_err();
            assert_eq!(receipt.result_code, "INVALID_PAYLOAD");
        }
    }

    #[test]
    fn account_payload_distinguishes_missing_null_and_present_parent() {
        let missing = account_mutation(
            "missing-parent",
            "book-1:child",
            "update",
            1,
            "Child",
            "expense",
            "CNY",
        );
        assert_eq!(
            parse_account_payload("book-1", &missing)
                .unwrap()
                .parent_account_id,
            None,
        );

        let mut null_parent = account_mutation(
            "null-parent",
            "book-1:child",
            "update",
            1,
            "Child",
            "expense",
            "CNY",
        );
        null_parent.payload["parentAccountId"] = serde_json::Value::Null;
        assert_eq!(
            parse_account_payload("book-1", &null_parent)
                .unwrap()
                .parent_account_id,
            Some(None),
        );

        let mut present_parent = account_mutation(
            "present-parent",
            "book-1:child",
            "update",
            1,
            "Child",
            "expense",
            "CNY",
        );
        present_parent.payload["parentAccountId"] = json!("book-1:root");
        assert_eq!(
            parse_account_payload("book-1", &present_parent)
                .unwrap()
                .parent_account_id,
            Some(Some("book-1:root".into())),
        );
    }

    #[tokio::test]
    async fn memory_categories_enforce_two_levels_and_compatible_updates() {
        let state = AppState::new(Config::for_test());
        {
            let mut store = state.store.write().await;
            store.accounts.insert(
                "book-1:root".into(),
                AccountRecord {
                    id: "book-1:root".into(),
                    book_id: "book-1".into(),
                    name: "Root".into(),
                    account_type: "expense".into(),
                    currency: "CNY".into(),
                    parent_account_id: None,
                    version: 1,
                },
            );
        }

        let mut child = account_mutation(
            "create-child",
            "book-1:child",
            "create",
            0,
            "Child",
            "expense",
            "CNY",
        );
        child.payload["parentAccountId"] = json!("book-1:root");
        let receipt = process_account_mutation_mem(&state, "book-1", &child).await;
        assert_eq!(receipt.status, "applied");
        assert_eq!(
            state
                .store
                .read()
                .await
                .accounts
                .get("book-1:child")
                .unwrap()
                .parent_account_id
                .as_deref(),
            Some("book-1:root"),
        );

        let mut grandchild = account_mutation(
            "create-grandchild",
            "book-1:grandchild",
            "create",
            0,
            "Grandchild",
            "expense",
            "CNY",
        );
        grandchild.payload["parentAccountId"] = json!("book-1:child");
        assert_eq!(
            process_account_mutation_mem(&state, "book-1", &grandchild)
                .await
                .result_code,
            "INVALID_CATEGORY_PARENT",
        );

        let mut cross_type = account_mutation(
            "cross-type",
            "book-1:cross-type",
            "create",
            0,
            "Cross Type",
            "income",
            "CNY",
        );
        cross_type.payload["parentAccountId"] = json!("book-1:root");
        assert_eq!(
            process_account_mutation_mem(&state, "book-1", &cross_type)
                .await
                .result_code,
            "INVALID_CATEGORY_PARENT",
        );

        let old_client_update = account_mutation(
            "old-client-update",
            "book-1:child",
            "update",
            1,
            "Renamed Child",
            "expense",
            "CNY",
        );
        assert_eq!(
            process_account_mutation_mem(&state, "book-1", &old_client_update)
                .await
                .status,
            "applied",
        );
        assert_eq!(
            state
                .store
                .read()
                .await
                .accounts
                .get("book-1:child")
                .unwrap()
                .parent_account_id
                .as_deref(),
            Some("book-1:root"),
        );

        let mut move_to_root = account_mutation(
            "move-to-root",
            "book-1:child",
            "update",
            2,
            "Renamed Child",
            "expense",
            "CNY",
        );
        move_to_root.payload["parentAccountId"] = serde_json::Value::Null;
        assert_eq!(
            process_account_mutation_mem(&state, "book-1", &move_to_root)
                .await
                .status,
            "applied",
        );
        assert!(state
            .store
            .read()
            .await
            .accounts
            .get("book-1:child")
            .unwrap()
            .parent_account_id
            .is_none());
    }

    #[tokio::test]
    async fn memory_account_updates_are_last_writer_wins_and_preserve_classification() {
        let state = AppState::new(Config::for_test());
        let create = account_mutation(
            "create",
            "book-1:category",
            "create",
            0,
            "Food",
            "expense",
            "CNY",
        );
        assert_eq!(
            process_account_mutation_mem(&state, "book-1", &create)
                .await
                .entity_version,
            Some(1)
        );

        let duplicate = account_mutation(
            "duplicate",
            "book-1:category",
            "create",
            0,
            "Food",
            "expense",
            "CNY",
        );
        let duplicate = process_account_mutation_mem(&state, "book-1", &duplicate).await;
        assert_eq!(duplicate.result_code, "LEDGER_VERSION_CONFLICT");
        assert_eq!(duplicate.entity_version, Some(1));

        let update = account_mutation(
            "update",
            "book-1:category",
            "update",
            999,
            "  Meals  ",
            "income",
            "USD",
        );
        let update = process_account_mutation_mem(&state, "book-1", &update).await;
        assert_eq!(update.status, "applied");
        assert_eq!(update.entity_version, Some(2));

        let second_update = account_mutation(
            "second-update",
            "book-1:category",
            "update",
            1,
            "Dining",
            "asset",
            "EUR",
        );
        let second_update = process_account_mutation_mem(&state, "book-1", &second_update).await;
        assert_eq!(second_update.status, "applied");
        assert_eq!(second_update.entity_version, Some(3));

        let missing = account_mutation(
            "missing",
            "book-1:missing",
            "update",
            0,
            "Missing",
            "expense",
            "CNY",
        );
        let missing = process_account_mutation_mem(&state, "book-1", &missing).await;
        assert_eq!(missing.result_code, "ACCOUNT_NOT_FOUND");

        let store = state.store.read().await;
        let account = store.accounts.get("book-1:category").unwrap();
        assert_eq!(account.name, "Dining");
        assert_eq!(account.account_type, "expense");
        assert_eq!(account.currency, "CNY");
        let change = store.changes.last().unwrap();
        assert_eq!(change.payload["accountType"], "expense");
        assert_eq!(change.payload["currency"], "CNY");
    }

    #[tokio::test]
    async fn memory_transaction_rejects_an_account_owned_by_another_book() {
        let state = AppState::new(Config::for_test());
        {
            let mut store = state.store.write().await;
            for (id, book_id) in [
                ("book-1:cash", "book-1"),
                ("book-2:foreign-expense", "book-2"),
            ] {
                store.accounts.insert(
                    id.into(),
                    AccountRecord {
                        id: id.into(),
                        book_id: book_id.into(),
                        name: "Account".into(),
                        account_type: "expense".into(),
                        currency: "CNY".into(),
                        parent_account_id: None,
                        version: 1,
                    },
                );
            }
        }
        let mutation = SyncMutationDto {
            mutation_id: "foreign-account".into(),
            entity_type: "transaction".into(),
            entity_id: "tx-1".into(),
            operation: "create".into(),
            base_version: 0,
            schema_version: 1,
            payload: json!({
                "entries": [
                    {"accountId": "book-2:foreign-expense", "amountMinor": "100", "currency": "CNY"},
                    {"accountId": "book-1:cash", "amountMinor": "-100", "currency": "CNY"}
                ]
            }),
        };

        let receipt = process_mutation_mem(&state, "book-1", &mutation).await;
        assert_eq!(receipt.status, "rejected");
        assert_eq!(receipt.result_code, "ACCOUNT_NOT_FOUND");
        assert!(state.store.read().await.transactions.is_empty());
    }

    #[tokio::test]
    async fn memory_transaction_update_without_occurred_at_preserves_existing_date() {
        let state = AppState::new(Config::for_test());
        {
            let mut store = state.store.write().await;
            for (id, account_type) in [("book-1:expense", "expense"), ("book-1:cash", "asset")] {
                store.accounts.insert(
                    id.into(),
                    AccountRecord {
                        id: id.into(),
                        book_id: "book-1".into(),
                        name: "Account".into(),
                        account_type: account_type.into(),
                        currency: "CNY".into(),
                        parent_account_id: None,
                        version: 1,
                    },
                );
            }
        }
        let entries = json!([
            {"accountId": "book-1:expense", "amountMinor": "100", "currency": "CNY"},
            {"accountId": "book-1:cash", "amountMinor": "-100", "currency": "CNY"}
        ]);
        let create = transaction_mutation(json!({
            "occurredAt": "2024-04-13T12:34:56+08:00",
            "description": "Original",
            "entries": entries,
        }));
        let create_receipt = process_mutation_mem(&state, "book-1", &create).await;
        assert_eq!(create_receipt.status, "applied");
        assert_eq!(create_receipt.entity_version, Some(1));

        let mut duplicate_create = transaction_mutation(create.payload.clone());
        duplicate_create.mutation_id = "transaction-date-duplicate-create".into();
        let duplicate_receipt = process_mutation_mem(&state, "book-1", &duplicate_create).await;
        assert_eq!(duplicate_receipt.status, "rejected");
        assert_eq!(duplicate_receipt.result_code, "LEDGER_VERSION_CONFLICT");
        assert_eq!(duplicate_receipt.entity_version, Some(1));

        let mut update = transaction_mutation(json!({
            "description": "Updated",
            "entries": entries,
        }));
        update.mutation_id = "transaction-date-update".into();
        update.operation = "update".into();

        let stale_receipt = process_mutation_mem(&state, "book-1", &update).await;
        assert_eq!(stale_receipt.status, "rejected");
        assert_eq!(stale_receipt.result_code, "LEDGER_VERSION_CONFLICT");
        assert_eq!(stale_receipt.entity_version, Some(1));

        update.base_version = 1;
        let update_receipt = process_mutation_mem(&state, "book-1", &update).await;
        assert_eq!(update_receipt.status, "applied");
        assert_eq!(update_receipt.entity_version, Some(2));

        let store = state.store.read().await;
        let transaction = store.transactions.get("tx-1").unwrap();
        assert_eq!(transaction.version, 2);
        assert_eq!(
            super::format_occurred_at(transaction.occurred_at),
            "2024-04-13T04:34:56Z"
        );
        assert_eq!(store.changes.last().unwrap().entity_version, 2);
        assert_eq!(
            store.changes.last().unwrap().payload["occurredAt"],
            "2024-04-13T04:34:56Z"
        );
    }
}
