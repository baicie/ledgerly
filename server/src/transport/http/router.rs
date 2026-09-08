use axum::{routing::get, Router};

use crate::infrastructure::object_store;
use crate::state::AppState;

use super::{auth, billing, books, commercial, health, ledger, reports, sync};

pub fn app_router(state: AppState) -> Router {
    Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .route("/health/startup", get(health::startup))
        .route("/metrics", get(metrics_handler))
        .merge(auth::routes())
        .merge(books::routes())
        .merge(ledger::routes())
        .merge(sync::routes())
        .merge(commercial::routes())
        .merge(reports::routes())
        .merge(billing::routes())
        .merge(object_store::routes())
        .with_state(state)
}

/// Exposes the Prometheus `/metrics` endpoint.
async fn metrics_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Result<axum::response::Response, axum::http::StatusCode> {
    let handle = state
        .metrics_handle
        .as_ref()
        .ok_or(axum::http::StatusCode::SERVICE_UNAVAILABLE)?;
    let body = handle.0.render();
    Ok(axum::response::Response::builder()
        .header(axum::http::header::CONTENT_TYPE, "text/plain; version=0.0.4")
        .body(axum::body::Body::from(body))
        .unwrap())
}
