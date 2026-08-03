use axum::Json;
use serde_json::json;

pub async fn live() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

pub async fn ready() -> Json<serde_json::Value> {
    Json(json!({ "status": "ready", "store": "memory" }))
}

pub async fn startup() -> Json<serde_json::Value> {
    Json(json!({ "status": "started" }))
}
