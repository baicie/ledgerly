use axum::{
    extract::{Query, State},
    http::StatusCode,
    routing::get,
    Json, Router,
};
use serde::Deserialize;

use crate::error::ApiError;
use crate::infrastructure::audit::{self, AuditQuery};
use crate::state::AppState;
use crate::transport::http::authz::AuthUser;

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/audit/events", get(list_events))
}

#[derive(Debug, Deserialize)]
struct AuditQueryParams {
    limit: Option<usize>,
    action: Option<String>,
    outcome: Option<String>,
    before: Option<String>,
}

async fn list_events(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<AuditQueryParams>,
) -> Result<Json<audit::AuditPage>, ApiError> {
    let page = audit::query(
        &state,
        AuditQuery {
            actor_id: Some(auth.user_id),
            action: params.action,
            outcome: params.outcome,
            before: params.before,
            limit: params.limit.unwrap_or(50),
        },
    )
    .await
    .map_err(|_| {
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "AUDIT_QUERY_ERROR",
            "audit query failed",
        )
    })?;
    Ok(Json(page))
}
