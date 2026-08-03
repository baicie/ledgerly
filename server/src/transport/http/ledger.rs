use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use ledger_contracts::{CreateTransactionRequest, CreateTransactionResponse};
use ledger_domain::{validate_balanced, EntryDraft};
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{AppState, ChangeRecord, TxRecord};
use crate::transport::http::authz::{require_book_member, AuthUser};

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/transactions", post(create_transaction))
}

async fn create_transaction(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateTransactionRequest>,
) -> Result<Json<CreateTransactionResponse>, ApiError> {
    require_book_member(&state, &auth.user_id, &req.book_id).await?;
    let drafts: Vec<EntryDraft> = req
        .entries
        .iter()
        .map(|e| {
            let amount_minor = e.amount_minor.parse::<i128>().map_err(|_| {
                ApiError::new(StatusCode::BAD_REQUEST, "INVALID_AMOUNT", "bad amountMinor")
            })?;
            Ok(EntryDraft {
                account_id: e.account_id.clone(),
                amount_minor,
                currency: e.currency.clone(),
            })
        })
        .collect::<Result<_, ApiError>>()?;

    validate_balanced(&drafts).map_err(|err| match err {
        ledger_domain::DomainError::Unbalanced => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "LEDGER_UNBALANCED",
            "entries do not sum to zero",
        ),
        other => ApiError::new(StatusCode::BAD_REQUEST, "LEDGER_INVALID", other.to_string()),
    })?;

    let tx_id = Uuid::now_v7().to_string();
    let commit_id = Uuid::now_v7().to_string();
    let entries: Vec<(String, i64, String)> = drafts
        .iter()
        .map(|d| {
            (
                d.account_id.clone(),
                d.amount_minor as i64,
                d.currency.clone(),
            )
        })
        .collect();

    {
        let mut store = state.store.write().await;
        if !store.books.contains_key(&req.book_id) {
            return Err(ApiError::new(
                StatusCode::NOT_FOUND,
                "BOOK_NOT_FOUND",
                "book missing",
            ));
        }
        store.transactions.insert(
            tx_id.clone(),
            TxRecord {
                id: tx_id.clone(),
                book_id: req.book_id.clone(),
                description: req.description.clone(),
                version: 1,
                deleted: false,
                entries: entries.clone(),
            },
        );
        let sequence = (store.changes.len() as i64) + 1;
        store.changes.push(ChangeRecord {
            sequence,
            book_id: req.book_id.clone(),
            commit_id,
            entity_type: "transaction".into(),
            entity_id: tx_id.clone(),
            operation: "upsert".into(),
            entity_version: 1,
            payload: serde_json::json!({
                "description": req.description,
                "entries": entries,
            }),
        });
    }

    Ok(Json(CreateTransactionResponse {
        transaction_id: tx_id,
        version: 1,
    }))
}
