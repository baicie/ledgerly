use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::post,
    Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::error::ApiError;
use crate::infrastructure::object_store;
use crate::state::{AppState, BudgetRecord, InviteRecord};
use crate::transport::http::authz::{require_book_member, require_plan, AuthUser};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/v1/books/{book_id}/invites",
            post(create_invite).get(list_invites),
        )
        .route(
            "/v1/books/{book_id}/budgets",
            post(create_budget).get(list_budgets),
        )
        .route(
            "/v1/books/{book_id}/attachments/upload-session",
            post(create_upload_session),
        )
        .route(
            "/v1/books/{book_id}/recurring",
            post(create_recurring).get(list_recurring),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/complete",
            post(complete_attachment),
        )
}

#[derive(Debug, Deserialize)]
struct CreateInviteRequest {
    email: String,
    role: Option<String>,
}

async fn create_invite(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<CreateInviteRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "family").await?;
    let id = Uuid::now_v7().to_string();
    let token = Uuid::now_v7().to_string();
    let role = req.role.unwrap_or_else(|| "editor".into());
    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO book_invites (id, book_id, email, role, token, created_by)
             VALUES ($1,$2,$3,$4,$5,$6)",
        )
        .bind(&id)
        .bind(&book_id)
        .bind(&req.email)
        .bind(&role)
        .bind(&token)
        .bind(&auth.user_id)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
    } else {
        let mut store = state.store.write().await;
        store.invites.push(InviteRecord {
            id: id.clone(),
            book_id: book_id.clone(),
            email: req.email.clone(),
            role: role.clone(),
            token: token.clone(),
        });
    }
    Ok(Json(serde_json::json!({
        "inviteId": id,
        "token": token,
        "email": req.email,
        "role": role,
    })))
}

async fn list_invites(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let rows: Vec<(String, String, String, String)> = sqlx::query_as(
            "SELECT id, email, role, token FROM book_invites WHERE book_id=$1 ORDER BY created_at DESC",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        return Ok(Json(serde_json::json!({
            "invites": rows.iter().map(|(id, email, role, token)| serde_json::json!({
                "id": id, "email": email, "role": role, "token": token
            })).collect::<Vec<_>>()
        })));
    }
    let store = state.store.read().await;
    let invites: Vec<_> = store
        .invites
        .iter()
        .filter(|i| i.book_id == book_id)
        .map(|i| {
            serde_json::json!({
                "id": i.id, "email": i.email, "role": i.role, "token": i.token
            })
        })
        .collect();
    Ok(Json(serde_json::json!({ "invites": invites })))
}

#[derive(Debug, Deserialize)]
struct CreateBudgetRequest {
    name: String,
    #[serde(rename = "amountMinor")]
    amount_minor: String,
    currency: Option<String>,
    #[serde(rename = "categoryAccountId")]
    category_account_id: Option<String>,
}

async fn create_budget(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<CreateBudgetRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let id = Uuid::now_v7().to_string();
    let amount: i64 = req
        .amount_minor
        .parse()
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_AMOUNT", "bad amountMinor"))?;
    let currency = req.currency.unwrap_or_else(|| "CNY".into());
    let category = req.category_account_id.clone();
    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO budgets (id, book_id, name, category_account_id, amount_minor, currency_code)
             VALUES ($1,$2,$3,$4,$5,$6)",
        )
        .bind(&id)
        .bind(&book_id)
        .bind(&req.name)
        .bind(&category)
        .bind(amount)
        .bind(&currency)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
    } else {
        let mut store = state.store.write().await;
        store.budgets.push(BudgetRecord {
            id: id.clone(),
            book_id: book_id.clone(),
            name: req.name.clone(),
            amount_minor: amount,
            currency: currency.clone(),
            category_account_id: category.clone(),
        });
    }
    Ok(Json(serde_json::json!({
        "budgetId": id,
        "name": req.name,
        "amountMinor": amount.to_string(),
        "currency": currency,
        "categoryAccountId": category,
        "spentMinor": "0",
        "remainingMinor": amount.to_string(),
    })))
}

async fn month_spent_for_account(
    state: &AppState,
    book_id: &str,
    account_id: &str,
) -> Result<i64, ApiError> {
    if let Some(pool) = &state.pool {
        let row: (i64,) = sqlx::query_as(
            "SELECT COALESCE(SUM(te.amount_minor), 0)
             FROM transaction_entries te
             JOIN transactions t ON t.id = te.transaction_id
             WHERE t.book_id = $1
               AND te.account_id = $2
               AND t.deleted_at IS NULL
               AND t.created_at >= date_trunc('month', now())
               AND t.created_at < date_trunc('month', now()) + interval '1 month'",
        )
        .bind(book_id)
        .bind(account_id)
        .fetch_one(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        return Ok(row.0);
    }
    let store = state.store.read().await;
    let mut sum = 0i64;
    for tx in store.transactions.values() {
        if tx.book_id != book_id || tx.deleted {
            continue;
        }
        for (acc, amount, _) in &tx.entries {
            if acc == account_id {
                sum += amount;
            }
        }
    }
    Ok(sum)
}

async fn list_budgets(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let rows: Vec<(String, String, i64, String, Option<String>)> = sqlx::query_as(
            "SELECT id, name, amount_minor, currency_code, category_account_id
             FROM budgets WHERE book_id=$1 ORDER BY created_at DESC",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        let mut budgets = Vec::new();
        for (id, name, amount, currency, category) in rows {
            let spent = if let Some(ref cat) = category {
                month_spent_for_account(&state, &book_id, cat).await?
            } else {
                0
            };
            let remaining = amount - spent;
            budgets.push(serde_json::json!({
                "id": id,
                "name": name,
                "amountMinor": amount.to_string(),
                "currency": currency,
                "categoryAccountId": category,
                "spentMinor": spent.to_string(),
                "remainingMinor": remaining.to_string(),
            }));
        }
        return Ok(Json(serde_json::json!({ "budgets": budgets })));
    }
    let store = state.store.read().await;
    let mut budgets = Vec::new();
    for b in store.budgets.iter().filter(|b| b.book_id == book_id) {
        let spent = if let Some(ref cat) = b.category_account_id {
            let mut sum = 0i64;
            for tx in store.transactions.values() {
                if tx.book_id != book_id || tx.deleted {
                    continue;
                }
                for (acc, amount, _) in &tx.entries {
                    if acc == cat {
                        sum += amount;
                    }
                }
            }
            sum
        } else {
            0
        };
        budgets.push(serde_json::json!({
            "id": b.id,
            "name": b.name,
            "amountMinor": b.amount_minor.to_string(),
            "currency": b.currency,
            "categoryAccountId": b.category_account_id,
            "spentMinor": spent.to_string(),
            "remainingMinor": (b.amount_minor - spent).to_string(),
        }));
    }
    Ok(Json(serde_json::json!({ "budgets": budgets })))
}

#[derive(Debug, Deserialize)]
struct UploadSessionRequest {
    #[serde(rename = "transactionId")]
    transaction_id: Option<String>,
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
    size: Option<i64>,
}

async fn create_upload_session(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<UploadSessionRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let _ = object_store::ensure_dir(&state.config);
    let attachment_id = Uuid::now_v7().to_string();
    let object_key = format!("books/{book_id}/{attachment_id}");
    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO attachments
             (id, book_id, transaction_id, object_key, mime_type, size_bytes, upload_status, created_by)
             VALUES ($1,$2,$3,$4,$5,$6,'pending',$7)",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .bind(&req.transaction_id)
        .bind(&object_key)
        .bind(&req.mime_type)
        .bind(req.size)
        .bind(&auth.user_id)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
    }
    let upload_url = object_store::sign_url(&state.config, "PUT", &object_key, 600);
    let download_url = object_store::sign_url(&state.config, "GET", &object_key, 3600);
    Ok(Json(serde_json::json!({
        "attachmentId": attachment_id,
        "objectKey": object_key,
        "uploadUrl": upload_url,
        "downloadUrl": download_url,
        "expiresIn": 600,
    })))
}

async fn complete_attachment(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, attachment_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let object_key = if let Some(pool) = &state.pool {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT object_key FROM attachments WHERE id=$1 AND book_id=$2")
                .bind(&attachment_id)
                .bind(&book_id)
                .fetch_optional(pool)
                .await
                .map_err(|e| {
                    ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
                })?;
        row.map(|r| r.0).ok_or_else(|| {
            ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
        })?
    } else {
        format!("books/{book_id}/{attachment_id}")
    };
    if !object_store::object_exists(&state.config, &object_key) {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "UPLOAD_INCOMPLETE",
            "object not found on disk",
        ));
    }
    if let Some(pool) = &state.pool {
        sqlx::query("UPDATE attachments SET upload_status='ready' WHERE id=$1 AND book_id=$2")
            .bind(&attachment_id)
            .bind(&book_id)
            .execute(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        let _ = crate::infrastructure::jobs::enqueue(
            pool,
            "thumbnail_stub",
            serde_json::json!({ "attachmentId": attachment_id }),
            0,
        )
        .await;
    }
    let download_url = object_store::sign_url(&state.config, "GET", &object_key, 3600);
    Ok(Json(serde_json::json!({
        "attachmentId": attachment_id,
        "uploadStatus": "ready",
        "downloadUrl": download_url,
    })))
}

#[derive(Debug, Deserialize)]
struct CreateRecurringRequest {
    name: String,
    payload: serde_json::Value,
    /// When true, schedule for immediate worker pickup (tests / "run now").
    #[serde(rename = "runNow")]
    run_now: Option<bool>,
}

async fn create_recurring(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<CreateRecurringRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let id = Uuid::now_v7().to_string();
    if let Some(pool) = &state.pool {
        let run_now = req.run_now.unwrap_or(false);
        if run_now {
            sqlx::query(
                "INSERT INTO recurring_rules (id, book_id, name, payload, next_run_at)
                 VALUES ($1,$2,$3,$4, now())",
            )
            .bind(&id)
            .bind(&book_id)
            .bind(&req.name)
            .bind(&req.payload)
            .execute(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        } else {
            sqlx::query(
                "INSERT INTO recurring_rules (id, book_id, name, payload, next_run_at)
                 VALUES ($1,$2,$3,$4, now() + interval '1 day')",
            )
            .bind(&id)
            .bind(&book_id)
            .bind(&req.name)
            .bind(&req.payload)
            .execute(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        }
    }
    Ok(Json(
        serde_json::json!({ "recurringId": id, "name": req.name }),
    ))
}

async fn list_recurring(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let rows: Vec<(String, String, serde_json::Value, bool)> = sqlx::query_as(
            "SELECT id, name, payload, active FROM recurring_rules
             WHERE book_id=$1 ORDER BY created_at DESC",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        return Ok(Json(serde_json::json!({
            "rules": rows.iter().map(|(id, name, payload, active)| serde_json::json!({
                "id": id, "name": name, "payload": payload, "active": active
            })).collect::<Vec<_>>()
        })));
    }
    Ok(Json(serde_json::json!({ "rules": [] })))
}
