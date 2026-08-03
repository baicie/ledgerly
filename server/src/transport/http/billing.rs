use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use serde::Deserialize;

use crate::error::ApiError;
use crate::state::AppState;
use crate::transport::http::authz::AuthUser;

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/billing/dev-upgrade", post(dev_upgrade))
}

#[derive(Debug, Deserialize)]
struct DevUpgradeRequest {
    plan: String,
}

async fn dev_upgrade(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<DevUpgradeRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    if state.config.is_production {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "DISABLED",
            "dev-upgrade disabled in production",
        ));
    }
    let plan = match req.plan.as_str() {
        "free" | "plus" | "family" => req.plan.clone(),
        _ => {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "INVALID_PLAN",
                "plan must be free|plus|family",
            ))
        }
    };
    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO subscriptions (user_id, plan, status, updated_at)
             VALUES ($1,$2,'active', now())
             ON CONFLICT (user_id) DO UPDATE SET plan=$2, status='active', updated_at=now()",
        )
        .bind(&auth.user_id)
        .bind(&plan)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
    } else {
        let mut store = state.store.write().await;
        store
            .subscriptions
            .insert(auth.user_id.clone(), plan.clone());
    }
    Ok(Json(
        serde_json::json!({ "plan": plan, "status": "active" }),
    ))
}
