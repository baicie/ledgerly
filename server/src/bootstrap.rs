use std::net::SocketAddr;
use std::time::Duration;

use axum::{
    http::{header, HeaderValue, Method},
    Router,
};
use metrics_exporter_prometheus::PrometheusBuilder;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use uuid::Uuid;

use crate::config::Config;
use crate::infrastructure::{jobs, object_store, postgres, rate_limit};
use crate::metrics::{http_metrics_middleware, make_span_fn, register_metrics};
use crate::state::AppState;
use crate::transport::http::router;

pub async fn migrate(config: &Config) -> anyhow::Result<()> {
    let span = crate::obs::info_span!("app.migrate", domain = "app", phase = "migrate");
    let _guard = span.enter();
    let Some(pool) = postgres::connect(config).await? else {
        crate::obs::app_event("migrate", "skipped", "DATABASE_URL unset");
        return Ok(());
    };
    postgres::migrate(&pool).await?;
    crate::obs::app_event("migrate", "ok", "postgres migrations applied");
    Ok(())
}

pub async fn run_api(config: Config, with_worker: bool) -> anyhow::Result<()> {
    let span = crate::obs::info_span!("app.run_api", domain = "app", phase = "boot");
    let _guard = span.enter();
    init_otel(&config);
    let _ = object_store::ensure_dir(&config);

    // Register metric descriptors and build the Prometheus exporter.
    register_metrics();
    let metrics_handle = PrometheusBuilder::new()
        .install_recorder()
        .map_err(|e| anyhow::anyhow!("failed to install Prometheus recorder: {e}"))?;
    let handle = crate::metrics::MetricsHandle::new(metrics_handle);

    let mut state = AppState::new_async(config.clone()).await?;
    // Attach the Prometheus handle to app state so /metrics can serve it.
    state.metrics_handle = Some(handle);
    if let Some(pool) = &state.pool {
        postgres::migrate(pool).await?;
        crate::obs::app_event("boot", "ok", "postgres connected and migrated");
        let _ = jobs::enqueue(pool, "purge_expired_sessions", serde_json::json!({}), 0).await;
        let _ = jobs::enqueue(pool, "enqueue_recurring_scan", serde_json::json!({}), 0).await;
    } else {
        crate::obs::app_event("boot", "degraded", "running with in-memory store");
    }

    if with_worker {
        if let Some(pool) = state.pool.clone() {
            let worker_id = format!("worker-{}", Uuid::now_v7());
            tokio::spawn(async move {
                if let Err(_err) = jobs::run_worker(pool, worker_id).await {
                    // Structured error event is recorded in obs::error_event.
                    // The raw error is intentionally omitted: it may embed
                    // connection strings or query parameters.
                    crate::obs::error_event("job", "WORKER_EXITED");
                    crate::metrics::record_job_outcome("worker", "exited");
                }
            });
        } else {
            crate::obs::app_event("boot", "skipped", "worker requested but DATABASE_URL unset");
        }
    }

    let rate = rate_limit::RateLimitLayer::new(config.rate_limit_rps, config.auth_rate_limit_rps);
    let app = Router::new()
        .merge(router::app_router(state.clone()))
        .layer(rate)
        .layer(axum::middleware::from_fn(http_metrics_middleware))
        .layer(axum::middleware::from_fn(request_id_middleware))
        .layer(tower_http::trace::TraceLayer::new_for_http().make_span_with(make_span_fn()))
        .layer(cors_layer(&config)?)
        .layer(RequestBodyLimitLayer::new(8 * 1024 * 1024))
        .layer(TimeoutLayer::with_status_code(
            axum::http::StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(30),
        ))
        .layer(CatchPanicLayer::new());

    let addr: SocketAddr = config.listen_addr.parse()?;
    crate::obs::app_event("listen", "ok", &format!("{addr}"));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

/// Middleware that opens an `http.request` span for every request and
/// stamps `request_id` (either from the inbound `x-request-id` header
/// when present and well-formed, or freshly minted). The span stays
/// entered for the lifetime of the inner future, so every downstream
/// log line and the JSON error response body share the same correlation
/// ID. We deliberately run this before `TraceLayer` so HTTP-level spans
/// nest inside the request span rather than racing with it.
async fn request_id_middleware(
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    // Inbound `x-request-id` is treated as opaque user input:
    // anything longer than 64 chars is dropped because we never
    // expect legitimate clients to send long ids, and we never
    // want an attacker to inflate log line size.
    const MAX_INBOUND_ID_LEN: usize = 64;
    let header_id = req
        .headers()
        .get("x-request-id")
        .and_then(|v| v.to_str().ok())
        .filter(|s| {
            !s.is_empty()
                && s.len() <= MAX_INBOUND_ID_LEN
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        })
        .map(|s| s.to_string());
    let request_id = header_id.unwrap_or_else(|| format!("req_{}", Uuid::now_v7()));
    let method = req.method().as_str().to_string();
    let path = req.uri().path().to_string();
    let span = crate::obs::http_request_span(&request_id, &method, &path);
    let mut response = span.in_scope(|| async move { next.run(req).await }).await;
    if let Ok(value) = axum::http::HeaderValue::from_str(&request_id) {
        response.headers_mut().insert("x-request-id", value);
    }
    response
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
    crate::obs::app_event("backup", "ok", out);
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
    crate::obs::app_event("restore", "ok", from);
    Ok(())
}

fn init_otel(config: &Config) {
    if let Some(endpoint) = &config.otel_endpoint {
        crate::obs::app_event(
            "otel",
            "ok",
            &format!(
                "endpoint={endpoint} using tracing JSON export (OTLP collector optional)"
            ),
        );
        // Full OTLP pipeline kept minimal for MVP: rely on structured tracing logs.
        // When a collector is present, ship JSON logs or attach a future otlp layer.
    }
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    crate::obs::app_event("shutdown", "ok", "ctrl-c received");
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
