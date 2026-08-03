use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts, StatusCode},
};
use jsonwebtoken::{decode, Algorithm, Validation};
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub session_id: String,
    pub device_id: String,
    pub token_version: i32,
    pub exp: usize,
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub user_id: String,
    pub session_id: String,
    pub device_id: String,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| {
                ApiError::new(
                    StatusCode::UNAUTHORIZED,
                    "UNAUTHORIZED",
                    "missing Authorization header",
                )
            })?;
        let token = header
            .strip_prefix("Bearer ")
            .or_else(|| header.strip_prefix("bearer "))
            .ok_or_else(|| {
                ApiError::new(
                    StatusCode::UNAUTHORIZED,
                    "UNAUTHORIZED",
                    "expected Bearer token",
                )
            })?;
        let claims = decode_access_token(state, token)?;
        ensure_session_active(state, &claims).await?;
        Ok(AuthUser {
            user_id: claims.sub,
            session_id: claims.session_id,
            device_id: claims.device_id,
        })
    }
}

async fn ensure_session_active(state: &AppState, claims: &Claims) -> Result<(), ApiError> {
    if let Some(pool) = &state.pool {
        let active: Option<(String,)> = sqlx::query_as(
            "SELECT id FROM device_sessions
             WHERE id=$1 AND user_id=$2 AND device_id=$3 AND revoked_at IS NULL",
        )
        .bind(&claims.session_id)
        .bind(&claims.sub)
        .bind(&claims.device_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        if active.is_some() {
            return Ok(());
        }
    } else {
        let store = state.store.read().await;
        if store
            .sessions
            .get(&claims.session_id)
            .is_some_and(|session| {
                !session.revoked
                    && session.user_id == claims.sub
                    && session.device_id == claims.device_id
            })
        {
            return Ok(());
        }
    }
    Err(ApiError::new(
        StatusCode::UNAUTHORIZED,
        "SESSION_REVOKED",
        "device session is revoked or missing",
    ))
}

pub fn decode_access_token(state: &AppState, token: &str) -> Result<Claims, ApiError> {
    let validation = Validation::new(Algorithm::EdDSA);
    decode::<Claims>(token, &state.config.jwt_decoding_key, &validation)
        .map(|data| data.claims)
        .map_err(|_| ApiError::new(StatusCode::UNAUTHORIZED, "UNAUTHORIZED", "invalid token"))
}

pub async fn require_book_member(
    state: &AppState,
    user_id: &str,
    book_id: &str,
) -> Result<(), ApiError> {
    if let Some(pool) = &state.pool {
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT book_id FROM book_members WHERE book_id=$1 AND user_id=$2
             UNION
             SELECT id FROM books WHERE id=$1 AND owner_id=$2
             LIMIT 1",
        )
        .bind(book_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        if row.is_none() {
            return Err(ApiError::new(
                StatusCode::FORBIDDEN,
                "BOOK_FORBIDDEN",
                "not a member of this book",
            ));
        }
        return Ok(());
    }

    let store = state.store.read().await;
    let allowed = store
        .books
        .get(book_id)
        .map(|b| b.owner_id == user_id)
        .unwrap_or(false);
    if !allowed {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "BOOK_FORBIDDEN",
            "not a member of this book",
        ));
    }
    Ok(())
}

pub async fn user_plan(state: &AppState, user_id: &str) -> String {
    if let Some(pool) = &state.pool {
        if let Ok(Some((plan,))) = sqlx::query_as::<_, (String,)>(
            "SELECT plan FROM subscriptions WHERE user_id=$1 AND status='active'",
        )
        .bind(user_id)
        .fetch_optional(pool)
        .await
        {
            return plan;
        }
        return "free".into();
    }
    let store = state.store.read().await;
    store
        .subscriptions
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| "free".into())
}

pub async fn require_plan(state: &AppState, user_id: &str, min: &str) -> Result<String, ApiError> {
    let plan = user_plan(state, user_id).await;
    let ok = match min {
        "plus" => plan == "plus" || plan == "family",
        "family" => plan == "family",
        _ => true,
    };
    if !ok {
        return Err(ApiError::new(
            StatusCode::PAYMENT_REQUIRED,
            "PLAN_REQUIRED",
            format!("requires {min} plan, current={plan}"),
        ));
    }
    Ok(plan)
}
