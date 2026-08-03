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
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{AppState, ChangeRecord, MutationReceipt, TxRecord};
use crate::transport::http::authz::{require_book_member, AuthUser};

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
            let receipt = process_mutation_pg(&state, &book_id, &mutation).await;
            sqlx::query(
                "INSERT INTO sync_mutations
                 (book_id, device_id, mutation_id, status, result_code, entity_version)
                 VALUES ($1,$2,$3,$4,$5,$6)",
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
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    let pool = state.pool.as_ref().unwrap();
    if mutation.operation == "delete" {
        return process_delete_pg(pool, book_id, mutation).await;
    }
    let drafts = match parse_entries(mutation) {
        Ok(d) => d,
        Err(r) => return r,
    };
    if let Some(r) = validate_or_reject(mutation, &drafts) {
        return r;
    }

    let existing: Option<(i64,)> =
        match sqlx::query_as("SELECT version FROM transactions WHERE id = $1 AND book_id = $2")
            .bind(&mutation.entity_id)
            .bind(book_id)
            .fetch_optional(pool)
            .await
        {
            Ok(v) => v,
            Err(_) => {
                return MutationReceiptDto {
                    mutation_id: mutation.mutation_id.clone(),
                    status: "rejected".into(),
                    result_code: "DB_ERROR".into(),
                    entity_version: None,
                };
            }
        };

    if let Some((version,)) = existing {
        if mutation.operation == "create" || mutation.base_version != version {
            return MutationReceiptDto {
                mutation_id: mutation.mutation_id.clone(),
                status: "rejected".into(),
                result_code: "LEDGER_VERSION_CONFLICT".into(),
                entity_version: Some(version),
            };
        }
    }

    let version = existing.map(|(v,)| v + 1).unwrap_or(1);
    let commit_id = Uuid::now_v7().to_string();
    let description = mutation
        .payload
        .get("description")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let Ok(mut tx) = pool.begin().await else {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "DB_ERROR".into(),
            entity_version: None,
        };
    };

    let write_ok = async {
        if existing.is_some() {
            sqlx::query(
                "UPDATE transactions SET description=$1, version=$2
                 WHERE id=$3 AND book_id=$4 AND version=$5",
            )
            .bind(&description)
            .bind(version)
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(mutation.base_version)
            .execute(&mut *tx)
            .await?;
            sqlx::query("DELETE FROM transaction_entries WHERE transaction_id=$1")
                .bind(&mutation.entity_id)
                .execute(&mut *tx)
                .await?;
        } else {
            sqlx::query(
                "INSERT INTO transactions (id, book_id, description, version)
                 VALUES ($1,$2,$3,$4)",
            )
            .bind(&mutation.entity_id)
            .bind(book_id)
            .bind(&description)
            .bind(version)
            .execute(&mut *tx)
            .await?;
        }

        for (idx, d) in drafts.iter().enumerate() {
            let entry_id = format!("{}-{idx}", mutation.entity_id);
            sqlx::query(
                "INSERT INTO transaction_entries
                 (id, transaction_id, account_id, amount_minor, currency_code, entry_index)
                 VALUES ($1,$2,$3,$4,$5,$6)",
            )
            .bind(&entry_id)
            .bind(&mutation.entity_id)
            .bind(&d.account_id)
            .bind(d.amount_minor as i64)
            .bind(&d.currency)
            .bind(idx as i32)
            .execute(&mut *tx)
            .await?;
        }

        sqlx::query(
            "INSERT INTO sync_changes
             (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
             VALUES ($1,$2,'transaction',$3,'upsert',$4,$5)",
        )
        .bind(book_id)
        .bind(&commit_id)
        .bind(&mutation.entity_id)
        .bind(version)
        .bind(&mutation.payload)
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
        .bind(&mutation.payload)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok::<(), sqlx::Error>(())
    }
    .await;

    if write_ok.is_err() {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "DB_ERROR".into(),
            entity_version: None,
        };
    }

    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(version),
    }
}

async fn process_mutation_mem(
    state: &AppState,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    if mutation.operation == "delete" {
        return process_delete_mem(state, book_id, mutation).await;
    }
    let drafts = match parse_entries(mutation) {
        Ok(d) => d,
        Err(r) => return r,
    };
    if let Some(r) = validate_or_reject(mutation, &drafts) {
        return r;
    }

    let mut store = state.store.write().await;
    if let Some(existing) = store.transactions.get(&mutation.entity_id) {
        if mutation.base_version != 0 && existing.version != mutation.base_version {
            return MutationReceiptDto {
                mutation_id: mutation.mutation_id.clone(),
                status: "rejected".into(),
                result_code: "LEDGER_VERSION_CONFLICT".into(),
                entity_version: Some(existing.version),
            };
        }
    }

    let version = 1;
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
        payload: mutation.payload.clone(),
    });

    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(version),
    }
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
        let rows: Vec<(i64, String, String, String, String, i64, serde_json::Value)> =
            sqlx::query_as(
                "SELECT sequence, commit_id, entity_type, entity_id, operation, entity_version, payload
                 FROM sync_changes
                 WHERE book_id=$1 AND sequence > $2
                 ORDER BY sequence ASC
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
        for (sequence, commit_id, entity_type, entity_id, operation, entity_version, payload) in
            rows
        {
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
            .map(|c| SyncChangeDto {
                sequence: c.sequence.to_string(),
                commit_id: c.commit_id,
                entity_type: c.entity_type,
                entity_id: c.entity_id,
                operation: c.operation,
                version: c.entity_version,
                payload: c.payload,
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
        let txs: Vec<(String, i64, Option<String>)> = sqlx::query_as(
            "SELECT id, version, description FROM transactions WHERE book_id=$1 AND deleted_at IS NULL",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(db_err)?;
        let mut out = Vec::new();
        for (id, version, description) in txs {
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
                "description": description,
                "entries": entries.iter().map(|(a,m,c)| serde_json::json!({
                    "accountId": a, "amountMinor": m.to_string(), "currency": c
                })).collect::<Vec<_>>(),
            }));
        }
        return Ok(Json(serde_json::json!({
            "bootstrapId": Uuid::now_v7().to_string(),
            "highWaterCursor": high.0.to_string(),
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
        .filter(|t| t.book_id == book_id)
        .cloned()
        .collect();
    Ok(Json(serde_json::json!({
        "bootstrapId": Uuid::now_v7().to_string(),
        "highWaterCursor": high_water.to_string(),
        "transactions": txs.iter().map(|t| serde_json::json!({
            "id": t.id,
            "version": t.version,
            "description": t.description,
            "entries": t.entries,
        })).collect::<Vec<_>>(),
    })))
}

async fn process_delete_pg(
    pool: &sqlx::PgPool,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    let existing: Option<(i64,)> =
        match sqlx::query_as("SELECT version FROM transactions WHERE id=$1 AND book_id=$2")
            .bind(&mutation.entity_id)
            .bind(book_id)
            .fetch_optional(pool)
            .await
        {
            Ok(v) => v,
            Err(_) => {
                return MutationReceiptDto {
                    mutation_id: mutation.mutation_id.clone(),
                    status: "rejected".into(),
                    result_code: "DB_ERROR".into(),
                    entity_version: None,
                };
            }
        };
    let Some((version,)) = existing else {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "NOT_FOUND".into(),
            entity_version: None,
        };
    };
    if mutation.base_version != 0 && mutation.base_version != version {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "LEDGER_VERSION_CONFLICT".into(),
            entity_version: Some(version),
        };
    }
    let new_version = version + 1;
    let commit_id = Uuid::now_v7().to_string();
    let Ok(mut tx) = pool.begin().await else {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "DB_ERROR".into(),
            entity_version: None,
        };
    };
    let ok = async {
        sqlx::query(
            "UPDATE transactions SET deleted_at=now(), version=$1
             WHERE id=$2 AND book_id=$3 AND version=$4",
        )
        .bind(new_version)
        .bind(&mutation.entity_id)
        .bind(book_id)
        .bind(version)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO sync_changes
             (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
             VALUES ($1,$2,'transaction',$3,'delete',$4,$5)",
        )
        .bind(book_id)
        .bind(&commit_id)
        .bind(&mutation.entity_id)
        .bind(new_version)
        .bind(&mutation.payload)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT INTO transaction_revisions
             (id, book_id, transaction_id, version, operation, payload)
             VALUES ($1,$2,$3,$4,'delete',$5)",
        )
        .bind(Uuid::now_v7().to_string())
        .bind(book_id)
        .bind(&mutation.entity_id)
        .bind(new_version)
        .bind(&mutation.payload)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok::<(), sqlx::Error>(())
    }
    .await;
    if ok.is_err() {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "DB_ERROR".into(),
            entity_version: None,
        };
    }
    MutationReceiptDto {
        mutation_id: mutation.mutation_id.clone(),
        status: "applied".into(),
        result_code: "OK".into(),
        entity_version: Some(new_version),
    }
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
