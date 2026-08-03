use std::net::SocketAddr;
use std::time::Duration;

use axum::Router;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::CorsLayer;
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use crate::config::Config;
use crate::infrastructure::postgres;
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

pub async fn run_api(config: Config) -> anyhow::Result<()> {
    let state = AppState::new_async(config.clone()).await?;
    if let Some(pool) = &state.pool {
        postgres::migrate(pool).await?;
        tracing::info!("postgres connected and migrated");
    } else {
        tracing::warn!("running with in-memory store");
    }

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
