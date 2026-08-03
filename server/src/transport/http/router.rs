use axum::{Router, routing::get};

use crate::state::AppState;

use super::{auth, health, ledger, sync};

pub fn app_router(state: AppState) -> Router {
    Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .route("/health/startup", get(health::startup))
        .merge(auth::routes())
        .merge(ledger::routes())
        .merge(sync::routes())
        .with_state(state)
}
