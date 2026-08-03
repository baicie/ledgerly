use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

use crate::config::Config;
use crate::error::ApiError;
use axum::http::StatusCode;

pub async fn connect(config: &Config) -> anyhow::Result<Option<PgPool>> {
    let Some(url) = &config.database_url else {
        return Ok(None);
    };
    let pool = PgPoolOptions::new()
        .min_connections(1)
        .max_connections(8)
        .acquire_timeout(Duration::from_secs(3))
        .connect(url)
        .await?;
    Ok(Some(pool))
}

pub async fn migrate(pool: &PgPool) -> anyhow::Result<()> {
    let sql = include_str!("../../migrations/001_init.sql");
    sqlx::raw_sql(sql).execute(pool).await?;
    Ok(())
}

pub async fn ping(pool: &PgPool) -> Result<(), ApiError> {
    sqlx::query("SELECT 1")
        .execute(pool)
        .await
        .map_err(|e| {
            ApiError::new(
                StatusCode::SERVICE_UNAVAILABLE,
                "DB_UNAVAILABLE",
                e.to_string(),
            )
        })?;
    Ok(())
}
