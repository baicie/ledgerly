use axum::{routing::get, Router};

use crate::infrastructure::object_store;
use crate::state::AppState;

use super::{auth, billing, books, commercial, health, ledger, reports, sync};

pub fn app_router(state: AppState) -> Router {
    Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .route("/health/startup", get(health::startup))
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
