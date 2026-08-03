use axum::{extract::State, Json};
use serde_json::json;

use crate::error::ApiError;
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
