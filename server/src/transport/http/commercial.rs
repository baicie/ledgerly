use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Path, State},
    http::{HeaderMap, Method, StatusCode},
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::error::ApiError;
use crate::infrastructure::audit::{self, AuditEvent, AuditOutcome};
use crate::infrastructure::object_store::{self, MULTIPART_PART_SIZE_BYTES};
use crate::state::{AppState, AttachmentRecord, BudgetRecord, InviteRecord};
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
        .route("/v1/books/{book_id}/attachments", get(list_attachments))
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}",
            delete(delete_attachment),
        )
        .route(
            "/v1/books/{book_id}/recurring",
            post(create_recurring).get(list_recurring),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/complete",
            post(complete_attachment),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/parts/{part_number}",
            put(upload_multipart_part)
                .layer(DefaultBodyLimit::max(MULTIPART_PART_SIZE_BYTES + 1024)),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/parts/{part_number}/upload-url",
            post(multipart_part_upload_url),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/parts/{part_number}/complete",
            post(complete_multipart_part),
        )
        .route(
            "/v1/books/{book_id}/attachments/{attachment_id}/multipart",
            get(multipart_upload_status).delete(abort_multipart_upload),
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
    headers: HeaderMap,
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
    audit::record(
        &state,
        AuditEvent::user(&auth.user_id, "invite.create", AuditOutcome::Success)
            .target("invite", &id)
            .request_id(audit::request_id(&headers))
            .metadata(serde_json::json!({ "bookId": book_id, "role": role })),
    )
    .await;
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
               AND t.occurred_at >= date_trunc('month', now())
               AND t.occurred_at < date_trunc('month', now()) + interval '1 month'",
        )
        .bind(book_id)
        .bind(account_id)
        .fetch_one(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        return Ok(row.0);
    }
    let store = state.store.read().await;
    let now = OffsetDateTime::now_utc();
    let mut sum = 0i64;
    for tx in store.transactions.values() {
        if tx.book_id != book_id || tx.deleted || !is_same_month(tx.occurred_at, now) {
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
    let now = OffsetDateTime::now_utc();
    let mut budgets = Vec::new();
    for b in store.budgets.iter().filter(|b| b.book_id == book_id) {
        let spent = if let Some(ref cat) = b.category_account_id {
            let mut sum = 0i64;
            for tx in store.transactions.values() {
                if tx.book_id != book_id || tx.deleted || !is_same_month(tx.occurred_at, now) {
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

fn is_same_month(value: OffsetDateTime, reference: OffsetDateTime) -> bool {
    value.year() == reference.year() && value.month() == reference.month()
}

fn object_store_api_error(_: anyhow::Error) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "OBJECT_STORE_IO",
        "object storage unavailable",
    )
}

async fn mark_attachment_failed(state: &AppState, book_id: &str, attachment_id: &str) {
    if let Some(pool) = &state.pool {
        let _ = sqlx::query(
            "UPDATE attachments SET upload_status='failed'
             WHERE id=$1 AND book_id=$2",
        )
        .bind(attachment_id)
        .bind(book_id)
        .execute(pool)
        .await;
    } else if let Some(record) = state
        .store
        .write()
        .await
        .attachments
        .iter_mut()
        .find(|record| record.id == attachment_id && record.book_id == book_id)
    {
        record.upload_status = "failed".into();
    }
}

async fn audit_attachment_complete_failure(
    state: &AppState,
    user_id: &str,
    headers: &HeaderMap,
    book_id: &str,
    attachment_id: &str,
    reason: &'static str,
) {
    audit::record(
        state,
        AuditEvent::user(user_id, "attachment.complete", AuditOutcome::Failure)
            .target("attachment", attachment_id)
            .request_id(audit::request_id(headers))
            .metadata(serde_json::json!({
                "bookId": book_id,
                "reason": reason
            })),
    )
    .await;
}

#[allow(clippy::too_many_arguments)]
async fn reject_attachment_upload(
    state: &AppState,
    user_id: &str,
    headers: &HeaderMap,
    book_id: &str,
    attachment_id: &str,
    object_key: &str,
    multipart_upload_id: Option<&str>,
    reason: &'static str,
) -> ApiError {
    if let Some(upload_id) = multipart_upload_id {
        let _ =
            object_store::abort_multipart_for_config(&state.config, object_key, Some(upload_id))
                .await;
    }
    let _ = object_store::delete_object_for_config(&state.config, object_key).await;
    mark_attachment_failed(state, book_id, attachment_id).await;
    audit_attachment_complete_failure(state, user_id, headers, book_id, attachment_id, reason)
        .await;
    ApiError::new(
        StatusCode::UNPROCESSABLE_ENTITY,
        "UPLOAD_SIZE_MISMATCH",
        "uploaded attachment size does not match the upload session",
    )
}

#[derive(sqlx::FromRow)]
struct AttachmentCatalogRecord {
    id: String,
    transaction_id: Option<String>,
    file_name: Option<String>,
    object_key: String,
    content_hash: Option<String>,
    mime_type: Option<String>,
    size_bytes: Option<i64>,
    upload_status: String,
    created_at: OffsetDateTime,
}

#[derive(sqlx::FromRow)]
struct MultipartPartRow {
    object_key: String,
    multipart_upload_id: Option<String>,
    multipart_parts: serde_json::Value,
    size_bytes: Option<i64>,
    upload_mode: String,
    upload_status: String,
}

#[derive(sqlx::FromRow)]
struct MultipartPartStateRow {
    object_key: String,
    multipart_upload_id: Option<String>,
    size_bytes: Option<i64>,
    upload_mode: String,
    upload_status: String,
}

#[derive(sqlx::FromRow)]
struct CompleteAttachmentRow {
    object_key: String,
    size_bytes: Option<i64>,
    upload_mode: String,
    multipart_upload_id: Option<String>,
    multipart_parts: serde_json::Value,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AttachmentCatalogItem {
    id: String,
    transaction_id: Option<String>,
    file_name: String,
    object_key: String,
    content_hash: Option<String>,
    mime_type: String,
    size_bytes: Option<i64>,
    upload_status: String,
    created_at: String,
    download_url: Option<String>,
    download_mode: Option<String>,
}

async fn attachment_download_info(
    state: &AppState,
    upload_status: &str,
    object_key: &str,
) -> Result<(Option<String>, Option<String>), ApiError> {
    if upload_status != "ready" {
        return Ok((None, None));
    }
    match object_store::direct_url(&state.config, Method::GET, object_key, 3600)
        .await
        .map_err(object_store_api_error)?
    {
        Some(url) => Ok((Some(url), Some("direct".into()))),
        None => Ok((
            Some(object_store::sign_url(
                &state.config,
                "GET",
                object_key,
                3600,
            )),
            Some("proxy".into()),
        )),
    }
}

async fn list_attachments(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let mut records: Vec<AttachmentCatalogRecord> = if let Some(pool) = &state.pool {
        sqlx::query_as(
            "SELECT id, transaction_id, file_name, object_key, content_hash,
                    mime_type, size_bytes, upload_status, created_at
             FROM attachments
             WHERE book_id=$1
             ORDER BY created_at DESC, id DESC",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?
    } else {
        let store = state.store.read().await;
        store
            .attachments
            .iter()
            .filter(|record| record.book_id == book_id)
            .map(|record| AttachmentCatalogRecord {
                id: record.id.clone(),
                transaction_id: record.transaction_id.clone(),
                file_name: record.file_name.clone(),
                object_key: record.object_key.clone(),
                content_hash: record.content_hash.clone(),
                mime_type: record.mime_type.clone(),
                size_bytes: record.size_bytes,
                upload_status: record.upload_status.clone(),
                created_at: record.created_at,
            })
            .collect()
    };
    records.sort_by(|left, right| {
        right
            .created_at
            .cmp(&left.created_at)
            .then_with(|| right.id.cmp(&left.id))
    });

    let mut attachments = Vec::with_capacity(records.len());
    for record in records {
        let (download_url, download_mode) =
            attachment_download_info(&state, &record.upload_status, &record.object_key).await?;
        attachments.push(AttachmentCatalogItem {
            id: record.id,
            transaction_id: record.transaction_id,
            file_name: record.file_name.unwrap_or_else(|| "attachment".into()),
            object_key: record.object_key,
            content_hash: record.content_hash,
            mime_type: record
                .mime_type
                .unwrap_or_else(|| "application/octet-stream".into()),
            size_bytes: record.size_bytes,
            upload_status: record.upload_status,
            created_at: record
                .created_at
                .format(&Rfc3339)
                .unwrap_or_else(|_| record.created_at.to_string()),
            download_url,
            download_mode,
        });
    }
    Ok(Json(serde_json::json!({ "attachments": attachments })))
}

async fn delete_attachment(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path((book_id, attachment_id)): Path<(String, String)>,
) -> Result<StatusCode, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
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
        row.map(|row| row.0)
    } else {
        state
            .store
            .read()
            .await
            .attachments
            .iter()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
            .map(|record| record.object_key.clone())
    };
    let Some(object_key) = object_key else {
        return Err(ApiError::new(
            StatusCode::NOT_FOUND,
            "NOT_FOUND",
            "attachment missing",
        ));
    };
    object_store::delete_object_for_config(&state.config, &object_key)
        .await
        .map_err(object_store_api_error)?;
    if let Some(pool) = &state.pool {
        sqlx::query("DELETE FROM attachments WHERE id=$1 AND book_id=$2")
            .bind(&attachment_id)
            .bind(&book_id)
            .execute(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
    } else {
        state
            .store
            .write()
            .await
            .attachments
            .retain(|record| !(record.id == attachment_id && record.book_id == book_id));
    }
    audit::record(
        &state,
        AuditEvent::user(&auth.user_id, "attachment.delete", AuditOutcome::Success)
            .target("attachment", &attachment_id)
            .request_id(audit::request_id(&headers))
            .metadata(serde_json::json!({ "bookId": book_id })),
    )
    .await;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize)]
struct UploadSessionRequest {
    #[serde(rename = "transactionId")]
    transaction_id: Option<String>,
    #[serde(rename = "mimeType")]
    mime_type: Option<String>,
    #[serde(rename = "fileName")]
    file_name: Option<String>,
    size: Option<i64>,
}

fn normalize_attachment_file_name(value: Option<&str>) -> Result<Option<String>, ApiError> {
    let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let value = value.rsplit(['/', '\\']).next().unwrap_or(value);
    if value.len() > 255 {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_ATTACHMENT_FILE_NAME",
            "attachment file name must not exceed 255 bytes",
        ));
    }
    Ok(Some(value.to_string()))
}

fn should_use_multipart(config: &crate::config::Config, size: Option<i64>) -> bool {
    let Some(size) = size else {
        return false;
    };
    let threshold = match config.object_storage_backend {
        crate::config::ObjectStoreBackend::Local => 7 * 1024 * 1024,
        crate::config::ObjectStoreBackend::S3 => 64 * 1024 * 1024,
    };
    size > threshold
}

fn multipart_part_count(size_bytes: u64) -> usize {
    size_bytes.div_ceil(MULTIPART_PART_SIZE_BYTES as u64) as usize
}

fn multipart_part_length(size_bytes: u64, part_number: usize) -> Option<usize> {
    let total_parts = multipart_part_count(size_bytes);
    if part_number == 0 || part_number > total_parts {
        return None;
    }
    if part_number < total_parts {
        return Some(MULTIPART_PART_SIZE_BYTES);
    }
    Some((size_bytes - (total_parts - 1) as u64 * MULTIPART_PART_SIZE_BYTES as u64) as usize)
}

fn parse_multipart_parts(value: &serde_json::Value) -> Result<Vec<String>, ApiError> {
    let parts = value.as_array().ok_or_else(|| {
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "INVALID_MULTIPART_STATE",
            "multipart state is invalid",
        )
    })?;
    parts
        .iter()
        .map(|value| {
            value.as_str().map(str::to_string).ok_or_else(|| {
                ApiError::new(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "INVALID_MULTIPART_STATE",
                    "multipart state is invalid",
                )
            })
        })
        .collect()
}

fn update_multipart_part(
    value: &serde_json::Value,
    size_bytes: u64,
    part_number: usize,
    part_id: &str,
) -> Result<(serde_json::Value, usize, usize), ApiError> {
    let mut parts = parse_multipart_parts(value)?;
    let total_parts = multipart_part_count(size_bytes);
    if parts.len() > total_parts {
        return Err(ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "INVALID_MULTIPART_STATE",
            "multipart state is invalid",
        ));
    }
    parts.resize(total_parts, String::new());
    parts[part_number - 1] = part_id.to_string();
    let uploaded_parts = parts.iter().filter(|part| !part.is_empty()).count();
    let parts_json =
        serde_json::Value::Array(parts.into_iter().map(serde_json::Value::String).collect());
    Ok((parts_json, uploaded_parts, total_parts))
}

fn normalize_multipart_part_id(value: &str) -> Result<String, ApiError> {
    let value = value.trim();
    if value.is_empty() || value.len() > 1024 || value.chars().any(char::is_control) {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MULTIPART_PART_ID",
            "multipart part id is invalid",
        ));
    }
    Ok(value.to_string())
}

async fn create_upload_session(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(book_id): Path<String>,
    Json(req): Json<UploadSessionRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let file_name = normalize_attachment_file_name(req.file_name.as_deref())?;
    if req.size.is_some_and(|size| size < 0) {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_ATTACHMENT_SIZE",
            "attachment size must not be negative",
        ));
    }
    if req
        .size
        .is_some_and(|size| size as u64 > state.config.attachment_max_bytes)
    {
        return Err(ApiError::new(
            StatusCode::PAYLOAD_TOO_LARGE,
            "ATTACHMENT_TOO_LARGE",
            "attachment exceeds configured maximum size",
        ));
    }
    let _ = object_store::ensure_dir(&state.config);
    let attachment_id = Uuid::now_v7().to_string();
    let object_key = format!("books/{book_id}/{attachment_id}");
    let multipart = should_use_multipart(&state.config, req.size);
    let multipart_upload_id = if multipart {
        object_store::start_multipart_for_config(&state.config, &object_key)
            .await
            .map_err(object_store_api_error)?
    } else {
        None
    };
    let upload_mode = if multipart { "multipart" } else { "single" };
    if let Some(pool) = &state.pool {
        let insert = sqlx::query(
            "INSERT INTO attachments
             (id, book_id, transaction_id, object_key, file_name, mime_type, size_bytes,
              upload_status, upload_mode, multipart_upload_id, created_by)
             VALUES ($1,$2,$3,$4,$5,$6,$7,'pending',$8,$9,$10)",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .bind(&req.transaction_id)
        .bind(&object_key)
        .bind(&file_name)
        .bind(&req.mime_type)
        .bind(req.size)
        .bind(upload_mode)
        .bind(&multipart_upload_id)
        .bind(&auth.user_id)
        .execute(pool)
        .await;
        if let Err(error) = insert {
            if multipart {
                let _ = object_store::abort_multipart_for_config(
                    &state.config,
                    &object_key,
                    multipart_upload_id.as_deref(),
                )
                .await;
            }
            return Err(ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "DB_ERROR",
                error.to_string(),
            ));
        }
    } else {
        state
            .store
            .write()
            .await
            .attachments
            .push(AttachmentRecord {
                id: attachment_id.clone(),
                book_id: book_id.clone(),
                transaction_id: req.transaction_id.clone(),
                file_name: file_name.clone(),
                object_key: object_key.clone(),
                content_hash: None,
                mime_type: req.mime_type.clone(),
                size_bytes: req.size,
                upload_status: "pending".into(),
                upload_mode: upload_mode.into(),
                multipart_upload_id: multipart_upload_id.clone(),
                multipart_parts: Vec::new(),
                created_by: Some(auth.user_id.clone()),
                created_at: OffsetDateTime::now_utc(),
            });
    }
    if multipart {
        audit::record(
            &state,
            AuditEvent::user(
                &auth.user_id,
                "attachment.upload_session",
                AuditOutcome::Success,
            )
            .target("attachment", &attachment_id)
            .request_id(audit::request_id(&headers))
            .metadata(serde_json::json!({
                "bookId": book_id,
                "uploadMode": upload_mode
            })),
        )
        .await;
        return Ok(Json(serde_json::json!({
            "attachmentId": attachment_id,
            "objectKey": object_key,
            "uploadUrl": null,
            "uploadMode": "multipart",
            "uploadHeaders": {},
            "downloadUrl": null,
            "downloadMode": null,
            "partSizeBytes": MULTIPART_PART_SIZE_BYTES,
            "expiresIn": 86400,
            "maxSizeBytes": state.config.attachment_max_bytes,
        })));
    }
    let direct_upload = object_store::direct_url(&state.config, Method::PUT, &object_key, 600)
        .await
        .map_err(object_store_api_error)?;
    let (upload_url, upload_mode) = match direct_upload {
        Some(url) => (url, "direct"),
        None => (
            object_store::sign_url(&state.config, "PUT", &object_key, 600),
            "proxy",
        ),
    };
    let direct_download = object_store::direct_url(&state.config, Method::GET, &object_key, 3600)
        .await
        .map_err(object_store_api_error)?;
    let (download_url, download_mode) = match direct_download {
        Some(url) => (url, "direct"),
        None => (
            object_store::sign_url(&state.config, "GET", &object_key, 3600),
            "proxy",
        ),
    };
    audit::record(
        &state,
        AuditEvent::user(
            &auth.user_id,
            "attachment.upload_session",
            AuditOutcome::Success,
        )
        .target("attachment", &attachment_id)
        .request_id(audit::request_id(&headers))
        .metadata(serde_json::json!({
            "bookId": book_id,
            "uploadMode": upload_mode
        })),
    )
    .await;
    Ok(Json(serde_json::json!({
        "attachmentId": attachment_id,
        "objectKey": object_key,
        "uploadUrl": upload_url,
        "uploadMode": upload_mode,
        "uploadHeaders": {},
        "downloadUrl": download_url,
        "downloadMode": download_mode,
        "expiresIn": 600,
        "maxSizeBytes": state.config.attachment_max_bytes,
    })))
}

async fn upload_multipart_part(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, attachment_id, part_number)): Path<(String, String, usize)>,
    body: Bytes,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    if body.is_empty() {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "EMPTY_MULTIPART_PART",
            "multipart part must not be empty",
        ));
    }

    if let Some(pool) = &state.pool {
        let mut tx = pool.begin().await.map_err(|e| {
            ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
        })?;
        let row: Option<MultipartPartRow> = sqlx::query_as(
            "SELECT object_key, multipart_upload_id, multipart_parts, size_bytes,
                    upload_mode, upload_status
             FROM attachments
             WHERE id=$1 AND book_id=$2
             FOR UPDATE",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        let MultipartPartRow {
            object_key,
            multipart_upload_id,
            multipart_parts,
            size_bytes,
            upload_mode,
            upload_status,
        } = row.ok_or_else(|| {
            ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
        })?;
        validate_multipart_part(
            &upload_mode,
            &upload_status,
            size_bytes,
            part_number,
            body.len(),
        )?;
        let part_id = object_store::put_multipart_part_for_config(
            &state.config,
            &object_key,
            multipart_upload_id.as_deref(),
            part_number - 1,
            body,
        )
        .await
        .map_err(object_store_api_error)?;
        let mut parts = parse_multipart_parts(&multipart_parts)?;
        let total_parts = multipart_part_count(size_bytes.unwrap_or_default() as u64);
        if parts.len() > total_parts {
            return Err(ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "INVALID_MULTIPART_STATE",
                "multipart state is invalid",
            ));
        }
        parts.resize(total_parts, String::new());
        parts[part_number - 1] = part_id.clone();
        let parts_json = serde_json::Value::Array(
            parts
                .iter()
                .cloned()
                .map(serde_json::Value::String)
                .collect(),
        );
        sqlx::query("UPDATE attachments SET multipart_parts=$3 WHERE id=$1 AND book_id=$2")
            .bind(&attachment_id)
            .bind(&book_id)
            .bind(&parts_json)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        tx.commit().await.map_err(|e| {
            ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
        })?;
        return Ok(Json(serde_json::json!({
            "partNumber": part_number,
            "partId": part_id,
            "uploadedParts": parts.iter().filter(|part| !part.is_empty()).count(),
            "totalParts": total_parts,
        })));
    }

    let (object_key, upload_id, size_bytes, upload_mode, upload_status) = {
        let store = state.store.read().await;
        let record = store
            .attachments
            .iter()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
            .ok_or_else(|| {
                ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
            })?;
        (
            record.object_key.clone(),
            record.multipart_upload_id.clone(),
            record.size_bytes.unwrap_or_default() as u64,
            record.upload_mode.clone(),
            record.upload_status.clone(),
        )
    };
    validate_multipart_part(
        &upload_mode,
        &upload_status,
        Some(size_bytes as i64),
        part_number,
        body.len(),
    )?;
    let part_id = object_store::put_multipart_part_for_config(
        &state.config,
        &object_key,
        upload_id.as_deref(),
        part_number - 1,
        body,
    )
    .await
    .map_err(object_store_api_error)?;
    let mut store = state.store.write().await;
    let record = store
        .attachments
        .iter_mut()
        .find(|record| record.id == attachment_id && record.book_id == book_id)
        .expect("multipart attachment exists");
    let total_parts = multipart_part_count(size_bytes);
    if record.multipart_parts.len() > total_parts {
        return Err(ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "INVALID_MULTIPART_STATE",
            "multipart state is invalid",
        ));
    }
    record.multipart_parts.resize(total_parts, String::new());
    record.multipart_parts[part_number - 1] = part_id.clone();
    let uploaded_parts = record
        .multipart_parts
        .iter()
        .filter(|part| !part.is_empty())
        .count();
    Ok(Json(serde_json::json!({
        "partNumber": part_number,
        "partId": part_id,
        "uploadedParts": uploaded_parts,
        "totalParts": total_parts,
    })))
}

async fn multipart_part_upload_url(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, attachment_id, part_number)): Path<(String, String, usize)>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let row = load_multipart_part_state(&state, &book_id, &attachment_id).await?;
    let size_bytes = row.size_bytes.filter(|size| *size >= 0).ok_or_else(|| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MULTIPART_STATE",
            "multipart upload size is invalid",
        )
    })? as u64;
    validate_multipart_part_plan(
        &row.upload_mode,
        &row.upload_status,
        row.size_bytes,
        part_number,
    )?;
    let direct_url = object_store::multipart_part_upload_url_for_config(
        &state.config,
        &row.object_key,
        row.multipart_upload_id.as_deref(),
        part_number,
        600,
    )
    .await
    .map_err(object_store_api_error)?;
    let upload_mode = if direct_url.is_some() {
        "direct"
    } else {
        "proxy"
    };
    Ok(Json(serde_json::json!({
        "partNumber": part_number,
        "uploadMode": upload_mode,
        "uploadUrl": direct_url,
        "uploadHeaders": {},
        "expiresIn": 600,
        "totalParts": multipart_part_count(size_bytes),
    })))
}

#[derive(Debug, Deserialize)]
struct CompleteMultipartPartRequest {
    #[serde(rename = "partId")]
    part_id: String,
}

async fn complete_multipart_part(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, attachment_id, part_number)): Path<(String, String, usize)>,
    Json(req): Json<CompleteMultipartPartRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    if state.config.object_storage_backend != crate::config::ObjectStoreBackend::S3 {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "MULTIPART_DIRECT_UNAVAILABLE",
            "direct multipart upload is unavailable",
        ));
    }
    let part_id = normalize_multipart_part_id(&req.part_id)?;

    if let Some(pool) = &state.pool {
        let mut tx = pool.begin().await.map_err(|e| {
            ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
        })?;
        let row: Option<MultipartPartRow> = sqlx::query_as(
            "SELECT object_key, multipart_upload_id, multipart_parts, size_bytes,
                    upload_mode, upload_status
             FROM attachments
             WHERE id=$1 AND book_id=$2
             FOR UPDATE",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        let row = row.ok_or_else(|| {
            ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
        })?;
        validate_multipart_part_plan(
            &row.upload_mode,
            &row.upload_status,
            row.size_bytes,
            part_number,
        )?;
        let size_bytes = row.size_bytes.unwrap_or_default() as u64;
        let (parts_json, uploaded_parts, total_parts) =
            update_multipart_part(&row.multipart_parts, size_bytes, part_number, &part_id)?;
        sqlx::query("UPDATE attachments SET multipart_parts=$3 WHERE id=$1 AND book_id=$2")
            .bind(&attachment_id)
            .bind(&book_id)
            .bind(&parts_json)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        tx.commit().await.map_err(|e| {
            ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
        })?;
        return Ok(Json(serde_json::json!({
            "partNumber": part_number,
            "partId": part_id,
            "uploadedParts": uploaded_parts,
            "totalParts": total_parts,
        })));
    }

    let (size_bytes, upload_mode, upload_status, multipart_parts) = {
        let store = state.store.read().await;
        let record = store
            .attachments
            .iter()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
            .ok_or_else(|| {
                ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
            })?;
        (
            record.size_bytes,
            record.upload_mode.clone(),
            record.upload_status.clone(),
            serde_json::Value::Array(
                record
                    .multipart_parts
                    .iter()
                    .cloned()
                    .map(serde_json::Value::String)
                    .collect(),
            ),
        )
    };
    validate_multipart_part_plan(&upload_mode, &upload_status, size_bytes, part_number)?;
    let size_bytes = size_bytes.unwrap_or_default() as u64;
    let (parts_json, uploaded_parts, total_parts) =
        update_multipart_part(&multipart_parts, size_bytes, part_number, &part_id)?;
    let mut store = state.store.write().await;
    let record = store
        .attachments
        .iter_mut()
        .find(|record| record.id == attachment_id && record.book_id == book_id)
        .expect("multipart attachment exists");
    record.multipart_parts = parse_multipart_parts(&parts_json)?;
    Ok(Json(serde_json::json!({
        "partNumber": part_number,
        "partId": part_id,
        "uploadedParts": uploaded_parts,
        "totalParts": total_parts,
    })))
}

async fn load_multipart_part_state(
    state: &AppState,
    book_id: &str,
    attachment_id: &str,
) -> Result<MultipartPartStateRow, ApiError> {
    if let Some(pool) = &state.pool {
        return sqlx::query_as(
            "SELECT object_key, multipart_upload_id, size_bytes, upload_mode, upload_status
             FROM attachments WHERE id=$1 AND book_id=$2",
        )
        .bind(attachment_id)
        .bind(book_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing"));
    }
    let store = state.store.read().await;
    store
        .attachments
        .iter()
        .find(|record| record.id == attachment_id && record.book_id == book_id)
        .map(|record| MultipartPartStateRow {
            object_key: record.object_key.clone(),
            multipart_upload_id: record.multipart_upload_id.clone(),
            size_bytes: record.size_bytes,
            upload_mode: record.upload_mode.clone(),
            upload_status: record.upload_status.clone(),
        })
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing"))
}

fn validate_multipart_part(
    upload_mode: &str,
    upload_status: &str,
    size_bytes: Option<i64>,
    part_number: usize,
    actual_length: usize,
) -> Result<(), ApiError> {
    let expected =
        validate_multipart_part_plan(upload_mode, upload_status, size_bytes, part_number)?;
    if actual_length != expected {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_MULTIPART_PART_SIZE",
            "multipart part size does not match the upload plan",
        ));
    }
    Ok(())
}

fn validate_multipart_part_plan(
    upload_mode: &str,
    upload_status: &str,
    size_bytes: Option<i64>,
    part_number: usize,
) -> Result<usize, ApiError> {
    if upload_mode != "multipart" || upload_status != "pending" {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "MULTIPART_NOT_PENDING",
            "attachment is not pending multipart upload",
        ));
    }
    let size_bytes = size_bytes.filter(|size| *size >= 0).ok_or_else(|| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MULTIPART_STATE",
            "multipart upload size is invalid",
        )
    })? as u64;
    let expected = multipart_part_length(size_bytes, part_number).ok_or_else(|| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MULTIPART_PART",
            "multipart part number is out of range",
        )
    })?;
    Ok(expected)
}

async fn multipart_upload_status(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, attachment_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let row = if let Some(pool) = &state.pool {
        let row: Option<(String, String, Option<i64>, serde_json::Value, String)> = sqlx::query_as(
            "SELECT upload_status, upload_mode, size_bytes, multipart_parts, object_key
             FROM attachments WHERE id=$1 AND book_id=$2",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        row
    } else {
        let store = state.store.read().await;
        store
            .attachments
            .iter()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
            .map(|record| {
                (
                    record.upload_status.clone(),
                    record.upload_mode.clone(),
                    record.size_bytes,
                    serde_json::Value::Array(
                        record
                            .multipart_parts
                            .iter()
                            .cloned()
                            .map(serde_json::Value::String)
                            .collect(),
                    ),
                    record.object_key.clone(),
                )
            })
    };
    let Some((upload_status, upload_mode, size_bytes, multipart_parts, object_key)) = row else {
        return Err(ApiError::new(
            StatusCode::NOT_FOUND,
            "NOT_FOUND",
            "attachment missing",
        ));
    };
    if upload_mode != "multipart" {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "MULTIPART_NOT_PENDING",
            "attachment is not a multipart upload",
        ));
    }
    let size_bytes = size_bytes.filter(|size| *size >= 0).ok_or_else(|| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MULTIPART_STATE",
            "multipart upload size is invalid",
        )
    })? as u64;
    let total_parts = multipart_part_count(size_bytes);
    let parts = parse_multipart_parts(&multipart_parts)?;
    let uploaded_part_numbers = parts
        .iter()
        .enumerate()
        .filter(|(_, part_id)| !part_id.is_empty())
        .map(|(index, _)| index + 1)
        .collect::<Vec<_>>();
    Ok(Json(serde_json::json!({
        "attachmentId": attachment_id,
        "objectKey": object_key,
        "uploadStatus": upload_status,
        "uploadMode": upload_mode,
        "partSizeBytes": MULTIPART_PART_SIZE_BYTES,
        "totalParts": total_parts,
        "uploadedPartNumbers": uploaded_part_numbers,
    })))
}

async fn abort_multipart_upload(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path((book_id, attachment_id)): Path<(String, String)>,
) -> Result<StatusCode, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let row = if let Some(pool) = &state.pool {
        let row: Option<(String, String, Option<String>, String)> = sqlx::query_as(
            "SELECT object_key, upload_mode, multipart_upload_id, upload_status
             FROM attachments WHERE id=$1 AND book_id=$2",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        row
    } else {
        let store = state.store.read().await;
        store
            .attachments
            .iter()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
            .map(|record| {
                (
                    record.object_key.clone(),
                    record.upload_mode.clone(),
                    record.multipart_upload_id.clone(),
                    record.upload_status.clone(),
                )
            })
    };
    let Some((object_key, upload_mode, upload_id, upload_status)) = row else {
        return Err(ApiError::new(
            StatusCode::NOT_FOUND,
            "NOT_FOUND",
            "attachment missing",
        ));
    };
    if upload_mode != "multipart" || upload_status != "pending" {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "MULTIPART_NOT_PENDING",
            "attachment is not pending multipart upload",
        ));
    }
    object_store::abort_multipart_for_config(&state.config, &object_key, upload_id.as_deref())
        .await
        .map_err(object_store_api_error)?;
    if let Some(pool) = &state.pool {
        sqlx::query("DELETE FROM attachments WHERE id=$1 AND book_id=$2")
            .bind(&attachment_id)
            .bind(&book_id)
            .execute(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
    } else {
        state
            .store
            .write()
            .await
            .attachments
            .retain(|record| !(record.id == attachment_id && record.book_id == book_id));
    }
    audit::record(
        &state,
        AuditEvent::user(
            &auth.user_id,
            "attachment.multipart_abort",
            AuditOutcome::Success,
        )
        .target("attachment", &attachment_id)
        .request_id(audit::request_id(&headers))
        .metadata(serde_json::json!({ "bookId": book_id })),
    )
    .await;
    Ok(StatusCode::NO_CONTENT)
}

async fn complete_attachment(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path((book_id, attachment_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    require_plan(&state, &auth.user_id, "plus").await?;
    let (object_key, expected_size, upload_mode, multipart_upload_id, multipart_parts) =
        if let Some(pool) = &state.pool {
            let row: Option<CompleteAttachmentRow> = sqlx::query_as(
                "SELECT object_key, size_bytes, upload_mode, multipart_upload_id, multipart_parts
             FROM attachments WHERE id=$1 AND book_id=$2",
            )
            .bind(&attachment_id)
            .bind(&book_id)
            .fetch_optional(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
            row.map(|row| {
                (
                    row.object_key,
                    row.size_bytes,
                    row.upload_mode,
                    row.multipart_upload_id,
                    row.multipart_parts,
                )
            })
            .ok_or_else(|| {
                ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
            })?
        } else {
            let store = state.store.read().await;
            let record = store
                .attachments
                .iter()
                .find(|record| record.id == attachment_id && record.book_id == book_id)
                .ok_or_else(|| {
                    ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "attachment missing")
                })?;
            (
                record.object_key.clone(),
                record.size_bytes,
                record.upload_mode.clone(),
                record.multipart_upload_id.clone(),
                serde_json::Value::Array(
                    record
                        .multipart_parts
                        .iter()
                        .cloned()
                        .map(serde_json::Value::String)
                        .collect(),
                ),
            )
        };
    if upload_mode == "multipart" {
        let size_bytes = expected_size.ok_or_else(|| {
            ApiError::new(
                StatusCode::BAD_REQUEST,
                "INVALID_MULTIPART_STATE",
                "multipart upload size is missing",
            )
        })?;
        if size_bytes < 0 {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "INVALID_MULTIPART_STATE",
                "multipart upload size is invalid",
            ));
        }
        let expected_parts = multipart_part_count(size_bytes as u64);
        let part_ids = parse_multipart_parts(&multipart_parts)?;
        if part_ids.len() != expected_parts || part_ids.iter().any(String::is_empty) {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "MULTIPART_INCOMPLETE",
                "not all multipart parts have been uploaded",
            ));
        }
        if let Err(error) = object_store::complete_multipart_for_config(
            &state.config,
            &object_key,
            multipart_upload_id.as_deref(),
            &part_ids,
        )
        .await
        {
            audit_attachment_complete_failure(
                &state,
                &auth.user_id,
                &headers,
                &book_id,
                &attachment_id,
                "multipart_complete_failed",
            )
            .await;
            return Err(object_store_api_error(error));
        }
    }
    let actual_size = match object_store::object_size_for_config(&state.config, &object_key).await {
        Ok(size) => size,
        Err(error) => {
            audit_attachment_complete_failure(
                &state,
                &auth.user_id,
                &headers,
                &book_id,
                &attachment_id,
                "storage_unavailable",
            )
            .await;
            return Err(object_store_api_error(error));
        }
    };
    let Some(actual_size) = actual_size else {
        audit_attachment_complete_failure(
            &state,
            &auth.user_id,
            &headers,
            &book_id,
            &attachment_id,
            "upload_incomplete",
        )
        .await;
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "UPLOAD_INCOMPLETE",
            "object not found in object storage",
        ));
    };
    if actual_size > state.config.attachment_max_bytes
        || expected_size.is_some_and(|size| size < 0 || size as u64 != actual_size)
    {
        return Err(reject_attachment_upload(
            &state,
            &auth.user_id,
            &headers,
            &book_id,
            &attachment_id,
            &object_key,
            multipart_upload_id.as_deref(),
            "size_mismatch",
        )
        .await);
    }
    let metadata = match object_store::object_metadata_for_config(&state.config, &object_key).await
    {
        Ok(metadata) => metadata,
        Err(error) => {
            audit_attachment_complete_failure(
                &state,
                &auth.user_id,
                &headers,
                &book_id,
                &attachment_id,
                "verification_failed",
            )
            .await;
            return Err(object_store_api_error(error));
        }
    };
    if metadata.size_bytes != actual_size {
        return Err(reject_attachment_upload(
            &state,
            &auth.user_id,
            &headers,
            &book_id,
            &attachment_id,
            &object_key,
            multipart_upload_id.as_deref(),
            "size_changed_during_verification",
        )
        .await);
    }
    if let Some(pool) = &state.pool {
        sqlx::query(
            "UPDATE attachments
             SET upload_status='ready', size_bytes=$3, content_hash=$4,
                 multipart_upload_id=NULL, multipart_parts='[]'::jsonb
             WHERE id=$1 AND book_id=$2",
        )
        .bind(&attachment_id)
        .bind(&book_id)
        .bind(metadata.size_bytes as i64)
        .bind(&metadata.sha256)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        let _ = crate::infrastructure::jobs::enqueue(
            pool,
            "thumbnail_stub",
            serde_json::json!({ "attachmentId": attachment_id }),
            0,
        )
        .await;
    } else {
        let mut store = state.store.write().await;
        if let Some(record) = store
            .attachments
            .iter_mut()
            .find(|record| record.id == attachment_id && record.book_id == book_id)
        {
            record.upload_status = "ready".into();
            record.size_bytes = Some(metadata.size_bytes as i64);
            record.content_hash = Some(metadata.sha256.clone());
            record.multipart_upload_id = None;
            record.multipart_parts.clear();
        }
    }
    let download_url = match object_store::direct_url(&state.config, Method::GET, &object_key, 3600)
        .await
        .map_err(object_store_api_error)?
    {
        Some(url) => url,
        None => object_store::sign_url(&state.config, "GET", &object_key, 3600),
    };
    audit::record(
        &state,
        AuditEvent::user(&auth.user_id, "attachment.complete", AuditOutcome::Success)
            .target("attachment", &attachment_id)
            .request_id(audit::request_id(&headers))
            .metadata(serde_json::json!({ "bookId": book_id })),
    )
    .await;
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
