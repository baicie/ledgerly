use std::net::SocketAddr;
use std::time::Duration;

use axum::Router;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::CorsLayer;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use crate::config::Config;
use crate::state::AppState;
use crate::transport::http::router;

pub async fn migrate(config: &Config) -> anyhow::Result<()> {
    let Some(url) = &config.database_url else {
        tracing::warn!("DATABASE_URL unset; migrate skipped (in-memory mode)");
        return Ok(());
    };
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(2)
        .connect(url)
        .await?;
    let sql = include_str!("../migrations/001_init.sql");
    sqlx::raw_sql(sql).execute(&pool).await?;
    Ok(())
}

pub async fn run_api(config: Config) -> anyhow::Result<()> {
    let state = AppState::new(config.clone());
    let app = Router::new()
        .merge(router::app_router(state.clone()))
        .layer(CatchPanicLayer::new())
        .layer(TimeoutLayer::with_status_code(
            axum::http::StatusCode::REQUEST_TIMEOUT,
            Duration::from_secs(30),
        ))
        .layer(RequestBodyLimitLayer::new(4 * 1024 * 1024))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    let addr: SocketAddr = config.listen_addr.parse()?;
    tracing::info!(%addr, "listening");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutdown signal received");
}
