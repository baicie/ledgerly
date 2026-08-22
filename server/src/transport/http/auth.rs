use argon2::Argon2;
use axum::{
    extract::{DefaultBodyLimit, State},
    http::{header, HeaderName, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use axum_extra::extract::cookie::{Cookie, CookieJar, SameSite};
use jsonwebtoken::{encode, Algorithm, Header};
use ledger_contracts::{LoginRequest, RegisterRequest, SessionMode, TokenResponse};
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
        .layer(DefaultBodyLimit::max(16 * 1024))
}

#[derive(Debug, Deserialize)]
struct RefreshRequest {
    #[serde(rename = "refreshToken")]
    refresh_token: Option<String>,
    #[serde(rename = "sessionMode")]
    session_mode: Option<SessionMode>,
}

const REFRESH_COOKIE_NAME: &str = "ledgerly_refresh";
const REFRESH_COOKIE_PATH: &str = "/v1/auth";
const MAX_EMAIL_LENGTH: usize = 254;
const MAX_PASSWORD_LENGTH: usize = 128;
const MAX_DISPLAY_NAME_LENGTH: usize = 80;
const MAX_DEVICE_ID_LENGTH: usize = 128;
type TokenResponseHeaders = [(HeaderName, &'static str); 2];

async fn logout(
    State(state): State<AppState>,
    jar: CookieJar,
    auth: AuthUser,
) -> Result<(CookieJar, StatusCode), ApiError> {
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
    Ok((clear_refresh_cookie(jar, &state), StatusCode::NO_CONTENT))
}

async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let req = validate_registration(req)?;
    let hash = hash_password(&req.password)?;
    let id = Uuid::now_v7().to_string();

    if let Some(pool) = &state.pool {
        let result = sqlx::query(
            "INSERT INTO users (id, email, password_hash, display_name)
             VALUES ($1,$2,$3,$4) ON CONFLICT (email) DO NOTHING",
        )
        .bind(&id)
        .bind(&req.email)
        .bind(&hash)
        .bind(&req.display_name)
        .execute(pool)
        .await
        .map_err(db_err)?;
        if result.rows_affected() == 0 {
            return Err(ApiError::new(
                StatusCode::CONFLICT,
                "EMAIL_TAKEN",
                "email already registered",
            ));
        }
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
    jar: CookieJar,
    Json(req): Json<LoginRequest>,
) -> Result<(CookieJar, TokenResponseHeaders, Json<TokenResponse>), ApiError> {
    let req = validate_login(req)?;
    let cookie_mode = uses_cookie_session(req.session_mode)?;
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
        tracing::error!(error = %e, "failed to resolve book during login");
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "BOOK_ERROR",
            "failed to resolve account book",
        )
    })?;
    let mut tokens = issue_tokens(&state, &user.id, &req.device_id).await?;
    tokens.book_id = Some(book_id);
    tokens.plan = Some(user_plan(&state, &user.id).await);
    let jar = if cookie_mode {
        let refresh = tokens.refresh_token.take().expect("issued refresh token");
        add_refresh_cookie(jar, &state, refresh)
    } else {
        jar
    };
    Ok((jar, token_response_headers(), Json(tokens)))
}

async fn refresh(
    State(state): State<AppState>,
    jar: CookieJar,
    Json(req): Json<RefreshRequest>,
) -> Result<(CookieJar, TokenResponseHeaders, Json<TokenResponse>), RefreshError> {
    let cookie_mode = uses_cookie_session(req.session_mode).map_err(RefreshError::from)?;
    let refresh_token = if cookie_mode {
        if req.refresh_token.is_some() {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "MIXED_REFRESH_CREDENTIALS",
                "cookie sessions cannot include refreshToken",
            )
            .into());
        }
        match jar.get(REFRESH_COOKIE_NAME) {
            Some(cookie) => cookie.value().to_owned(),
            None => {
                return Err(RefreshError::from(refresh_error_response(
                    jar,
                    &state,
                    true,
                    ApiError::new(
                        StatusCode::UNAUTHORIZED,
                        "INVALID_REFRESH",
                        "refresh invalid",
                    ),
                )));
            }
        }
    } else {
        match req.refresh_token {
            Some(token) => token,
            None => {
                return Err(ApiError::new(
                    StatusCode::BAD_REQUEST,
                    "MISSING_REFRESH_CREDENTIAL",
                    "refreshToken or cookie session is required",
                )
                .into());
            }
        }
    };
    if !valid_refresh_token(&refresh_token) {
        return Err(RefreshError::from(refresh_error_response(
            jar,
            &state,
            cookie_mode,
            ApiError::new(
                StatusCode::UNAUTHORIZED,
                "INVALID_REFRESH",
                "refresh invalid",
            ),
        )));
    }
    let hash = hash_token(&refresh_token);
    let mut tokens = rotate_refresh_token(&state, &hash).await.map_err(|error| {
        RefreshError::from(refresh_error_response(
            jar.clone(),
            &state,
            cookie_mode,
            error,
        ))
    })?;
    let jar = finish_refresh(jar, &state, cookie_mode, &mut tokens);
    Ok((jar, token_response_headers(), Json(tokens)))
}

async fn rotate_refresh_token(state: &AppState, hash: &str) -> Result<TokenResponse, ApiError> {
    if let Some(pool) = &state.pool {
        let row: Option<(String, String, String, Option<time::OffsetDateTime>, bool)> =
            sqlx::query_as(
                "SELECT id, user_id, device_id, revoked_at,
                        created_at >= now() - interval '30 days' AS fresh
                 FROM device_sessions
             WHERE refresh_token_hash = $1",
            )
            .bind(hash)
            .fetch_optional(pool)
            .await
            .map_err(db_err)?;
        let (old_session_id, user_id, device_id, revoked_at, fresh) = row.ok_or_else(|| {
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
        if !fresh {
            sqlx::query(
                "UPDATE device_sessions SET revoked_at = now()
                 WHERE id = $1 AND revoked_at IS NULL",
            )
            .bind(&old_session_id)
            .execute(pool)
            .await
            .map_err(db_err)?;
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "INVALID_REFRESH",
                "refresh invalid",
            ));
        }

        let book_id = state.ensure_demo_book(&user_id).await.map_err(|e| {
            tracing::error!(error = %e, "failed to resolve book during token refresh");
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "BOOK_ERROR",
                "failed to resolve account book",
            )
        })?;
        let plan = user_plan(state, &user_id).await;
        let new_session_id = Uuid::now_v7().to_string();
        let refresh = random_token();
        let refresh_hash = hash_token(&refresh);
        let mut tokens =
            build_token_response(state, &user_id, &device_id, &new_session_id, refresh)?;
        let mut tx = pool.begin().await.map_err(db_err)?;
        let claimed = sqlx::query(
            "UPDATE device_sessions SET revoked_at = now()
             WHERE id = $1 AND revoked_at IS NULL
               AND created_at >= now() - interval '30 days'",
        )
        .bind(&old_session_id)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;
        if claimed.rows_affected() != 1 {
            tx.rollback().await.map_err(db_err)?;
            return Err(ApiError::new(
                StatusCode::UNAUTHORIZED,
                "REFRESH_REUSE",
                "refresh reuse detected",
            ));
        }
        sqlx::query(
            "INSERT INTO device_sessions (id, user_id, device_id, refresh_token_hash)
             VALUES ($1,$2,$3,$4)",
        )
        .bind(&new_session_id)
        .bind(&user_id)
        .bind(&device_id)
        .bind(&refresh_hash)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;
        sqlx::query(
            "INSERT INTO subscriptions (user_id, plan, status)
             VALUES ($1,'free','active') ON CONFLICT (user_id) DO NOTHING",
        )
        .bind(&user_id)
        .execute(&mut *tx)
        .await
        .map_err(db_err)?;
        tx.commit().await.map_err(db_err)?;
        tokens.book_id = Some(book_id);
        tokens.plan = Some(plan);
        return Ok(tokens);
    }

    let (user_id, device_id) = {
        let mut store = state.store.write().await;
        let session_id = store.refresh_to_session.remove(hash).ok_or_else(|| {
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
    let mut tokens = issue_tokens(state, &user_id, &device_id).await?;
    tokens.book_id = Some(book_id);
    tokens.plan = Some(user_plan(state, &user_id).await);
    Ok(tokens)
}

fn refresh_error_response(
    jar: CookieJar,
    state: &AppState,
    cookie_mode: bool,
    error: ApiError,
) -> Response {
    if cookie_mode && error.status == StatusCode::UNAUTHORIZED {
        return (clear_refresh_cookie(jar, state), error).into_response();
    }
    error.into_response()
}

struct RefreshError(Box<Response>);

impl IntoResponse for RefreshError {
    fn into_response(self) -> Response {
        *self.0
    }
}

impl From<ApiError> for RefreshError {
    fn from(error: ApiError) -> Self {
        Self(Box::new(error.into_response()))
    }
}

impl From<Response> for RefreshError {
    fn from(response: Response) -> Self {
        Self(Box::new(response))
    }
}

async fn issue_tokens(
    state: &AppState,
    user_id: &str,
    device_id: &str,
) -> Result<TokenResponse, ApiError> {
    let session_id = Uuid::now_v7().to_string();
    let refresh = random_token();
    let refresh_hash = hash_token(&refresh);
    let tokens = build_token_response(state, user_id, device_id, &session_id, refresh)?;

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

    Ok(tokens)
}

fn build_token_response(
    state: &AppState,
    user_id: &str,
    device_id: &str,
    session_id: &str,
    refresh: String,
) -> Result<TokenResponse, ApiError> {
    let exp = (time::OffsetDateTime::now_utc().unix_timestamp() + 900) as usize;
    let claims = Claims {
        sub: user_id.to_string(),
        session_id: session_id.to_string(),
        device_id: device_id.to_string(),
        token_version: 1,
        exp,
    };
    let header = Header::new(Algorithm::EdDSA);
    let access = encode(&header, &claims, &state.config.jwt_encoding_key).map_err(|e| {
        tracing::error!(error = %e, "failed to encode access token");
        ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "TOKEN_ERROR",
            "failed to issue access token",
        )
    })?;

    Ok(TokenResponse {
        access_token: access,
        refresh_token: Some(refresh),
        token_type: "Bearer".into(),
        expires_in: 900,
        book_id: None,
        plan: None,
    })
}

fn finish_refresh(
    jar: CookieJar,
    state: &AppState,
    cookie_mode: bool,
    tokens: &mut TokenResponse,
) -> CookieJar {
    if !cookie_mode {
        return jar;
    }
    let refresh = tokens.refresh_token.take().expect("issued refresh token");
    add_refresh_cookie(jar, state, refresh)
}

fn token_response_headers() -> TokenResponseHeaders {
    [
        (header::CACHE_CONTROL, "no-store"),
        (header::PRAGMA, "no-cache"),
    ]
}

fn add_refresh_cookie(jar: CookieJar, state: &AppState, value: String) -> CookieJar {
    jar.add(
        Cookie::build((REFRESH_COOKIE_NAME, value))
            .path(REFRESH_COOKIE_PATH)
            .http_only(true)
            .secure(state.config.auth_cookie_secure)
            .same_site(SameSite::Strict)
            .max_age(time::Duration::days(30))
            .build(),
    )
}

fn clear_refresh_cookie(jar: CookieJar, state: &AppState) -> CookieJar {
    jar.add(
        Cookie::build((REFRESH_COOKIE_NAME, ""))
            .path(REFRESH_COOKIE_PATH)
            .http_only(true)
            .secure(state.config.auth_cookie_secure)
            .same_site(SameSite::Strict)
            .max_age(time::Duration::ZERO)
            .expires(time::OffsetDateTime::UNIX_EPOCH)
            .build(),
    )
}

fn validate_registration(mut req: RegisterRequest) -> Result<RegisterRequest, ApiError> {
    req.email = normalize_email(&req.email)?;

    let password_length = req.password.chars().count();
    if !(8..=MAX_PASSWORD_LENGTH).contains(&password_length) {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "WEAK_PASSWORD",
            "password must contain between 8 and 128 characters",
        ));
    }

    req.display_name = req.display_name.trim().to_string();
    let display_name_length = req.display_name.chars().count();
    if !(1..=MAX_DISPLAY_NAME_LENGTH).contains(&display_name_length)
        || req.display_name.chars().any(char::is_control)
    {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_DISPLAY_NAME",
            "displayName must contain between 1 and 80 characters",
        ));
    }

    Ok(req)
}

fn validate_login(mut req: LoginRequest) -> Result<LoginRequest, ApiError> {
    req.email = normalize_email(&req.email)?;
    req.device_id = req.device_id.trim().to_string();

    if req.password.chars().count() > MAX_PASSWORD_LENGTH {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_PASSWORD",
            "password must not exceed 128 characters",
        ));
    }

    let device_id_length = req.device_id.chars().count();
    if !(1..=MAX_DEVICE_ID_LENGTH).contains(&device_id_length)
        || req.device_id.chars().any(char::is_control)
    {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_DEVICE_ID",
            "deviceId must contain between 1 and 128 characters",
        ));
    }

    Ok(req)
}

fn uses_cookie_session(mode: Option<SessionMode>) -> Result<bool, ApiError> {
    match mode {
        None => Ok(false),
        Some(SessionMode::Cookie) => Ok(true),
        Some(SessionMode::Unsupported) => Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "UNSUPPORTED_SESSION_MODE",
            "sessionMode is unsupported",
        )),
    }
}

fn normalize_email(value: &str) -> Result<String, ApiError> {
    let email = value.trim().to_ascii_lowercase();
    if !valid_email(&email) {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_EMAIL",
            "email format is invalid",
        ));
    }
    Ok(email)
}

fn valid_email(email: &str) -> bool {
    if email.is_empty() || email.len() > MAX_EMAIL_LENGTH || !email.is_ascii() {
        return false;
    }

    let mut parts = email.split('@');
    let (Some(local), Some(domain), None) = (parts.next(), parts.next(), parts.next()) else {
        return false;
    };
    if local.is_empty()
        || local.len() > 64
        || local.starts_with('.')
        || local.ends_with('.')
        || local.contains("..")
        || !local.bytes().all(valid_email_local_byte)
        || !domain.contains('.')
    {
        return false;
    }

    domain.split('.').all(|label| {
        !label.is_empty()
            && label.len() <= 63
            && !label.starts_with('-')
            && !label.ends_with('-')
            && label
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
    })
}

fn valid_email_local_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric()
        || matches!(
            byte,
            b'!' | b'#'
                | b'$'
                | b'%'
                | b'&'
                | b'\''
                | b'*'
                | b'+'
                | b'-'
                | b'/'
                | b'='
                | b'?'
                | b'^'
                | b'_'
                | b'`'
                | b'{'
                | b'|'
                | b'}'
                | b'~'
                | b'.'
        )
}

fn hash_password(password: &str) -> Result<String, ApiError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    Ok(argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| {
            tracing::error!(error = %e, "failed to hash password");
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "HASH_ERROR",
                "failed to secure password",
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

fn valid_refresh_token(token: &str) -> bool {
    token.len() == 64 && token.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn db_err(e: sqlx::Error) -> ApiError {
    tracing::error!(error = %e, "database operation failed");
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "DB_ERROR",
        "database operation failed",
    )
}
