use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::body::Bytes;
use axum::extract::{Path as AxumPath, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::put;
use axum::Router;
use hmac::{Hmac, Mac};
use serde::Deserialize;
use sha2::Sha256;
use subtle::ConstantTimeEq;

use crate::config::Config;
use crate::error::ApiError;
use crate::state::AppState;

type HmacSha256 = Hmac<Sha256>;

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/object-store/{*key}", put(put_object).get(get_object))
}

#[derive(Debug, Deserialize)]
struct SignedQuery {
    expires: u64,
    sig: String,
    method: Option<String>,
}

pub fn ensure_dir(config: &Config) -> std::io::Result<()> {
    std::fs::create_dir_all(&config.object_store_dir)
}

pub fn sign_url(config: &Config, method: &str, object_key: &str, ttl_secs: u64) -> String {
    let expires = now_secs() + ttl_secs;
    let sig = sign(config, method, object_key, expires);
    format!(
        "{}/v1/object-store/{}?expires={expires}&sig={sig}&method={method}",
        config.object_store_public_base.trim_end_matches('/'),
        object_key.trim_start_matches('/'),
    )
}

fn sign(config: &Config, method: &str, object_key: &str, expires: u64) -> String {
    let mut mac =
        HmacSha256::new_from_slice(config.object_store_hmac_secret.as_bytes()).expect("hmac key");
    mac.update(method.as_bytes());
    mac.update(b"\n");
    mac.update(object_key.as_bytes());
    mac.update(b"\n");
    mac.update(expires.to_string().as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

fn verify(config: &Config, method: &str, object_key: &str, expires: u64, sig: &str) -> bool {
    if expires < now_secs() {
        return false;
    }
    let expected = sign(config, method, object_key, expires);
    expected.as_bytes().ct_eq(sig.as_bytes()).into()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn disk_path(config: &Config, object_key: &str) -> Result<PathBuf, ApiError> {
    let key = object_key.trim_start_matches('/');
    if key.is_empty() || key.contains("..") {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_KEY",
            "bad object key",
        ));
    }
    Ok(config.object_store_dir.join(key))
}

async fn put_object(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
    body: Bytes,
) -> Result<StatusCode, ApiError> {
    let method = q.method.as_deref().unwrap_or("PUT");
    if method != "PUT" || !verify(&state.config, "PUT", &key, q.expires, &q.sig) {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "BAD_SIGNATURE",
            "invalid or expired signature",
        ));
    }
    let path = disk_path(&state.config, &key)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(io_err)?;
    }
    std::fs::write(&path, &body).map_err(io_err)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn get_object(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
) -> Result<Response, ApiError> {
    let method = q.method.as_deref().unwrap_or("GET");
    if method != "GET" || !verify(&state.config, "GET", &key, q.expires, &q.sig) {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "BAD_SIGNATURE",
            "invalid or expired signature",
        ));
    }
    let path = disk_path(&state.config, &key)?;
    let bytes = std::fs::read(&path)
        .map_err(|_| ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "object missing"))?;
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        header::HeaderValue::from_static("application/octet-stream"),
    );
    Ok((StatusCode::OK, headers, bytes).into_response())
}

pub fn object_exists(config: &Config, object_key: &str) -> bool {
    disk_path(config, object_key)
        .map(|p| Path::new(&p).is_file())
        .unwrap_or(false)
}

fn io_err(e: std::io::Error) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "OBJECT_STORE_IO",
        e.to_string(),
    )
}
