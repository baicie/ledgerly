use std::net::SocketAddr;
use std::time::Duration;

use axum::{
    http::{header, HeaderValue, Method},
    Router,
};
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use crate::config::Config;
use crate::infrastructure::{jobs, object_store, postgres, rate_limit};
use crate::state::AppState;
use crate::transport::http::router;

pub async fn migrate(config: &Config) -> anyhow::Result<()> {
    let Some(pool) = postgres::connect(config).await? else {
        tracing::warn!("DATABASE_URL unset; migrate skipped (in-memory mode)");
        return Ok(());
    };
    postgres::migrate(&pool).await?;
    Ok(())
}

pub async fn run_api(config: Config, with_worker: bool) -> anyhow::Result<()> {
    init_otel(&config);
    let _ = object_store::ensure_dir(&config);

    let state = AppState::new_async(config.clone()).await?;
    if let Some(pool) = &state.pool {
        postgres::migrate(pool).await?;
        tracing::info!("postgres connected and migrated");
        let _ = jobs::enqueue(pool, "purge_expired_sessions", serde_json::json!({}), 0).await;
        let _ = jobs::enqueue(pool, "enqueue_recurring_scan", serde_json::json!({}), 0).await;
    } else {
        tracing::warn!("running with in-memory store");
    }

    if with_worker {
        if let Some(pool) = state.pool.clone() {
            let worker_id = format!("worker-{}", Uuid::now_v7());
            tokio::spawn(async move {
                if let Err(err) = jobs::run_worker(pool, worker_id).await {
                    tracing::error!(error = %err, "worker exited");
                }
            });
        } else {
            tracing::warn!("worker requested but DATABASE_URL unset");
        }
    }

    let rate = rate_limit::RateLimitLayer::new(config.rate_limit_rps, config.auth_rate_limit_rps);
    let app = Router::new()
        .merge(router::app_router(state.clone()))
        .layer(rate)
        .layer(TraceLayer::new_for_http())
        .layer(cors_layer(&config)?)
        .layer(RequestBodyLimitLayer::new(8 * 1024 * 1024))
        .layer(TimeoutLayer::with_status_code(
            axum::http::StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(30),
        ))
        .layer(CatchPanicLayer::new());

    let addr: SocketAddr = config.listen_addr.parse()?;
    tracing::info!(%addr, "listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

fn cors_layer(config: &Config) -> anyhow::Result<CorsLayer> {
    let origins = config
        .cors_allowed_origins
        .iter()
        .map(|origin| HeaderValue::from_str(origin))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(CorsLayer::new()
        .allow_origin(AllowOrigin::list(origins))
        .allow_credentials(true)
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PUT,
            Method::PATCH,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE]))
}

pub async fn run_worker_only(config: Config) -> anyhow::Result<()> {
    let Some(pool) = postgres::connect(&config).await? else {
        anyhow::bail!("DATABASE_URL required for worker mode");
    };
    postgres::migrate(&pool).await?;
    let worker_id = format!("worker-{}", Uuid::now_v7());
    jobs::run_worker(pool, worker_id).await
}

pub async fn backup(config: &Config, out: &str) -> anyhow::Result<()> {
    let url = config
        .database_url
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL required"))?;
    let status = std::process::Command::new("pg_dump")
        .args(["--format=custom", "--file", out, url])
        .status()?;
    if !status.success() {
        anyhow::bail!("pg_dump failed");
    }
    tracing::info!(out, "backup complete");
    Ok(())
}

pub async fn restore(config: &Config, from: &str) -> anyhow::Result<()> {
    let url = config
        .database_url
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL required"))?;
    let status = std::process::Command::new("pg_restore")
        .args([
            "--clean",
            "--if-exists",
            "--no-owner",
            "--dbname",
            url,
            from,
        ])
        .status()?;
    if !status.success() {
        anyhow::bail!("pg_restore failed");
    }
    tracing::info!(from, "restore complete");
    Ok(())
}

fn init_otel(config: &Config) {
    if let Some(endpoint) = &config.otel_endpoint {
        tracing::info!(
            %endpoint,
            "OTEL_EXPORTER_OTLP_ENDPOINT set; using tracing JSON export (OTLP collector optional)"
        );
        // Full OTLP pipeline kept minimal for MVP: rely on structured tracing logs.
        // When a collector is present, ship JSON logs or attach a future otlp layer.
    }
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutdown signal received");
}

#[cfg(test)]
mod tests {
    use axum::{body::Body, http::Request, routing::post, Router};
    use tower::ServiceExt;

    use super::{cors_layer, Config};

    async fn ok() {}

    #[tokio::test]
    async fn cors_allows_credentials_only_for_configured_origin() {
        let mut config = Config::for_test();
        config.cors_allowed_origins = vec!["https://app.ledgerly.example".into()];
        let app = Router::new()
            .route("/v1/auth/login", post(ok))
            .layer(cors_layer(&config).unwrap());

        let allowed = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/v1/auth/login")
                    .header("origin", "https://app.ledgerly.example")
                    .header("access-control-request-method", "POST")
                    .header("access-control-request-headers", "content-type")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            allowed.headers()["access-control-allow-origin"],
            "https://app.ledgerly.example"
        );
        assert_eq!(
            allowed.headers()["access-control-allow-credentials"],
            "true"
        );

        let denied = app
            .oneshot(
                Request::builder()
                    .method("OPTIONS")
                    .uri("/v1/auth/login")
                    .header("origin", "https://untrusted.example")
                    .header("access-control-request-method", "POST")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert!(denied
            .headers()
            .get("access-control-allow-origin")
            .is_none());
    }
}
