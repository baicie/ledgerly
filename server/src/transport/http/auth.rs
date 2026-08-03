use argon2::Argon2;
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use jsonwebtoken::{encode, Algorithm, Header};
use ledger_contracts::{LoginRequest, RegisterRequest, TokenResponse};
use password_hash::rand_core::OsRng;
use password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use rand::RngCore;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{AppState, SessionRecord, UserRecord};
use crate::transport::http::authz::{user_plan, AuthUser, Claims};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/v1/auth/register", post(register))
        .route("/v1/auth/login", post(login))
        .route("/v1/auth/refresh", post(refresh))
        .route("/v1/auth/logout", post(logout))
}

#[derive(Debug, Deserialize)]
struct RefreshRequest {
    #[serde(rename = "refreshToken")]
    refresh_token: String,
}

async fn logout(State(state): State<AppState>, auth: AuthUser) -> Result<StatusCode, ApiError> {
    if let Some(pool) = &state.pool {
        sqlx::query(
            "UPDATE device_sessions SET revoked_at=now()
             WHERE id=$1 AND user_id=$2 AND device_id=$3",
        )
        .bind(&auth.session_id)
        .bind(&auth.user_id)
        .bind(&auth.device_id)
        .execute(pool)
        .await
        .map_err(db_err)?;
    } else {
        let mut store = state.store.write().await;
        if let Some(session) = store.sessions.get_mut(&auth.session_id) {
            session.revoked = true;
        }
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let hash = hash_password(&req.password)?;
    let id = Uuid::now_v7().to_string();

    if let Some(pool) = &state.pool {
        let exists: Option<(String,)> = sqlx::query_as("SELECT id FROM users WHERE email = $1")
            .bind(&req.email)
            .fetch_optional(pool)
            .await
            .map_err(db_err)?;
        if exists.is_some() {
            return Err(ApiError::new(
                StatusCode::CONFLICT,
                "EMAIL_TAKEN",
                "email already registered",
            ));
        }
        sqlx::query(
            "INSERT INTO users (id, email, password_hash, display_name) VALUES ($1,$2,$3,$4)",
        )
        .bind(&id)
        .bind(&req.email)
        .bind(&hash)
        .bind(&req.display_name)
        .execute(pool)
        .await
        .map_err(db_err)?;
        return Ok(Json(serde_json::json!({ "userId": id })));
    }

    let mut store = state.store.write().await;
    if store.users_by_email.contains_key(&req.email) {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "EMAIL_TAKEN",
            "email already registered",
        ));
    }
    store.users_by_email.insert(req.email.clone(), id.clone());
    store.users.insert(
        id.clone(),
        UserRecord {
            id: id.clone(),
            email: req.email,
            password_hash: hash,
            display_name: req.display_name,
        },
    );
    Ok(Json(serde_json::json!({ "userId": id })))
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    let user = if let Some(pool) = &state.pool {
        let row: Option<(String, String, String, String)> = sqlx::query_as(
            "SELECT id, email, password_hash, display_name FROM users WHERE email = $1",
        )
        .bind(&req.email)
        .fetch_optional(pool)
        .await
        .map_err(db_err)?;
        let (id, email, password_hash, display_name) = row.ok_or_else(|| {
            ApiError::new(StatusCode::UNAUTHORIZED, "INVALID_CREDENTIALS", "bad login")
        })?;
        UserRecord {
            id,
            email,
            password_hash,
            display_name,
        }
    } else {
        let store = state.store.read().await;
        let id = store
            .users_by_email
            .get(&req.email)
            .cloned()
            .ok_or_else(|| {
                ApiError::new(StatusCode::UNAUTHORIZED, "INVALID_CREDENTIALS", "bad login")
            })?;
        store.users.get(&id).cloned().ok_or_else(|| {
            ApiError::new(StatusCode::UNAUTHORIZED, "INVALID_CREDENTIALS", "bad login")
        })?
    };

    verify_password(&req.password, &user.password_hash)?;
    let book_id = state.ensure_demo_book(&user.id).await.map_err(|e| {
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "BOOK_ERROR",
            e.to_string(),
        )
    })?;
    let mut tokens = issue_tokens(&state, &user.id, &req.device_id).await?;
    tokens.book_id = Some(book_id);
    tokens.plan = Some(user_plan(&state, &user.id).await);
    Ok(Json(tokens))
}

async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    let hash = hash_token(&req.refresh_token);

    if let Some(pool) = &state.pool {
        let row: Option<(String, String, String, Option<time::OffsetDateTime>)> = sqlx::query_as(
            "SELECT id, user_id, device_id, revoked_at FROM device_sessions
             WHERE refresh_token_hash = $1",
        )
        .bind(&hash)
        .fetch_optional(pool)
        .await
        .map_err(db_err)?;
        let (session_id, user_id, device_id, revoked_at) = row.ok_or_else(|| {
            ApiError::new(
                StatusCode::UNAUTHORIZED,
                "INVALID_REFRESH",
                "refresh invalid",
            )
        })?;
        if revoked_at.is_some() {
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "REFRESH_REUSE",
                "refresh reuse detected",
            ));
        }
        sqlx::query("UPDATE device_sessions SET revoked_at = now() WHERE id = $1")
            .bind(&session_id)
            .execute(pool)
            .await
            .map_err(db_err)?;
        let book_id = state.ensure_demo_book(&user_id).await.map_err(|e| {
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "BOOK_ERROR",
                e.to_string(),
            )
        })?;
        let mut tokens = issue_tokens(&state, &user_id, &device_id).await?;
        tokens.book_id = Some(book_id);
        tokens.plan = Some(user_plan(&state, &user_id).await);
        return Ok(Json(tokens));
    }

    let (user_id, device_id) = {
        let mut store = state.store.write().await;
        let session_id = store.refresh_to_session.remove(&hash).ok_or_else(|| {
            ApiError::new(
                StatusCode::UNAUTHORIZED,
                "INVALID_REFRESH",
                "refresh invalid",
            )
        })?;
        let session = store.sessions.get_mut(&session_id).ok_or_else(|| {
            ApiError::new(
                StatusCode::UNAUTHORIZED,
                "INVALID_REFRESH",
                "refresh invalid",
            )
        })?;
        if session.revoked || session.refresh_hash != hash {
            session.revoked = true;
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "REFRESH_REUSE",
                "refresh reuse detected",
            ));
        }
        session.revoked = true;
        (session.user_id.clone(), session.device_id.clone())
    };
    let book_id = state.ensure_demo_book(&user_id).await.map_err(|e| {
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "BOOK_ERROR",
            e.to_string(),
        )
    })?;
    let mut tokens = issue_tokens(&state, &user_id, &device_id).await?;
    tokens.book_id = Some(book_id);
    tokens.plan = Some(user_plan(&state, &user_id).await);
    Ok(Json(tokens))
}

async fn issue_tokens(
    state: &AppState,
    user_id: &str,
    device_id: &str,
) -> Result<TokenResponse, ApiError> {
    let session_id = Uuid::now_v7().to_string();
    let refresh = random_token();
    let refresh_hash = hash_token(&refresh);

    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO device_sessions (id, user_id, device_id, refresh_token_hash)
             VALUES ($1,$2,$3,$4)",
        )
        .bind(&session_id)
        .bind(user_id)
        .bind(device_id)
        .bind(&refresh_hash)
        .execute(pool)
        .await
        .map_err(db_err)?;
        sqlx::query(
            "INSERT INTO subscriptions (user_id, plan, status)
             VALUES ($1,'free','active') ON CONFLICT (user_id) DO NOTHING",
        )
        .bind(user_id)
        .execute(pool)
        .await
        .map_err(db_err)?;
    } else {
        let mut store = state.store.write().await;
        store.sessions.insert(
            session_id.clone(),
            SessionRecord {
                id: session_id.clone(),
                user_id: user_id.to_string(),
                device_id: device_id.to_string(),
                refresh_hash: refresh_hash.clone(),
                revoked: false,
            },
        );
        store
            .refresh_to_session
            .insert(refresh_hash, session_id.clone());
        store
            .subscriptions
            .entry(user_id.to_string())
            .or_insert_with(|| "free".into());
    }

    let exp = (time::OffsetDateTime::now_utc().unix_timestamp() + 900) as usize;
    let claims = Claims {
        sub: user_id.to_string(),
        session_id,
        device_id: device_id.to_string(),
        token_version: 1,
        exp,
    };
    let header = Header::new(Algorithm::EdDSA);
    let access = encode(&header, &claims, &state.config.jwt_encoding_key).map_err(|e| {
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "TOKEN_ERROR",
            e.to_string(),
        )
    })?;

    Ok(TokenResponse {
        access_token: access,
        refresh_token: refresh,
        token_type: "Bearer".into(),
        expires_in: 900,
        book_id: None,
        plan: None,
    })
}

fn hash_password(password: &str) -> Result<String, ApiError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    Ok(argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| {
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "HASH_ERROR",
                e.to_string(),
            )
        })?
        .to_string())
}

fn verify_password(password: &str, hash: &str) -> Result<(), ApiError> {
    let parsed = PasswordHash::new(hash)
        .map_err(|_| ApiError::new(StatusCode::UNAUTHORIZED, "INVALID_CREDENTIALS", "bad login"))?;
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .map_err(|_| ApiError::new(StatusCode::UNAUTHORIZED, "INVALID_CREDENTIALS", "bad login"))
}

fn random_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

fn hash_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

fn db_err(e: sqlx::Error) -> ApiError {
    ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
}
