use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
};
use ledger_contracts::{
    MutationReceiptDto, SyncChangeDto, SyncPullResponse, SyncPushRequest, SyncPushResponse,
};
use ledger_domain::{EntryDraft, validate_balanced};
use serde::Deserialize;
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{AppState, ChangeRecord, MutationReceipt, TxRecord};

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
    Path(book_id): Path<String>,
    Json(req): Json<SyncPushRequest>,
) -> Result<Json<SyncPushResponse>, ApiError> {
    let mut receipts = Vec::new();
    for mutation in req.mutations {
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

        let receipt = process_mutation(&state, &book_id, &mutation).await;
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

async fn process_mutation(
    state: &AppState,
    book_id: &str,
    mutation: &ledger_contracts::SyncMutationDto,
) -> MutationReceiptDto {
    if mutation.entity_type != "transaction" || mutation.operation != "create" {
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: "UNSUPPORTED_MUTATION".into(),
            entity_version: None,
        };
    }

    let entries = match mutation.payload.get("entries").and_then(|v| v.as_array()) {
        Some(arr) => arr,
        None => {
            return MutationReceiptDto {
                mutation_id: mutation.mutation_id.clone(),
                status: "rejected".into(),
                result_code: "INVALID_PAYLOAD".into(),
                entity_version: None,
            };
        }
    };

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

    if let Err(err) = validate_balanced(&drafts) {
        let code = if err == ledger_domain::DomainError::Unbalanced {
            "LEDGER_UNBALANCED"
        } else {
            "LEDGER_INVALID"
        };
        return MutationReceiptDto {
            mutation_id: mutation.mutation_id.clone(),
            status: "rejected".into(),
            result_code: code.into(),
            entity_version: None,
        };
    }

    let mut store = state.store.write().await;
    if let Some(existing) = store.transactions.get(&mutation.entity_id) {
        if existing.version != mutation.base_version && mutation.base_version != 0 {
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
        .map(|d| (d.account_id.clone(), d.amount_minor as i64, d.currency.clone()))
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
            entries: entry_tuples.clone(),
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
    Path(book_id): Path<String>,
    Query(q): Query<PullQuery>,
) -> Result<Json<SyncPullResponse>, ApiError> {
    let cursor = q.cursor.unwrap_or(0);
    let limit = q.limit.unwrap_or(500).min(1000);
    let store = state.store.read().await;
    let mut changes: Vec<_> = store
        .changes
        .iter()
        .filter(|c| c.book_id == book_id && c.sequence > cursor)
        .cloned()
        .collect();
    changes.sort_by_key(|c| c.sequence);

    // Keep commit atomic: do not split same commit_id across pages.
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
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
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
