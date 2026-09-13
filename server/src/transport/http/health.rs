use axum::{extract::State, Json};
use serde_json::json;

use crate::error::ApiError;
use crate::infrastructure::backup_runtime;
use crate::infrastructure::postgres;
use crate::state::AppState;

pub async fn live() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

pub async fn ready(State(state): State<AppState>) -> Result<Json<serde_json::Value>, ApiError> {
    if let Some(pool) = &state.pool {
        postgres::ping(pool).await?;
        return Ok(Json(json!({ "status": "ready", "store": "postgres" })));
    }
    Ok(Json(json!({ "status": "ready", "store": "memory" })))
}

pub async fn startup() -> Json<serde_json::Value> {
    Json(json!({ "status": "started" }))
}

pub async fn backup(State(state): State<AppState>) -> Result<Json<serde_json::Value>, ApiError> {
    let snapshot = backup_runtime::backup_readiness(&state.config).map_err(|_| {
        ApiError::new(
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            "BACKUP_STATUS_ERROR",
            "backup status unavailable",
        )
    })?;
    let status = snapshot.readiness.as_str();
    let run = snapshot.status;
    Ok(Json(json!({
        "status": status,
        "intervalHours": state.config.backup_interval_hours,
        "ageSeconds": snapshot.age_seconds,
        "lastCompletedAt": run.as_ref().map(|status| status.completed_at.clone()),
        "fileCount": run.as_ref().map(|status| status.file_count),
        "totalSizeBytes": run.as_ref().map(|status| status.total_size_bytes),
        "replicated": run.as_ref().map(|status| status.replicated),
    })))
}
