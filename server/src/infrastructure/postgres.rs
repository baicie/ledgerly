use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;

use crate::config::Config;
use crate::error::ApiError;
use axum::http::StatusCode;

pub async fn connect(config: &Config) -> anyhow::Result<Option<PgPool>> {
    let Some(url) = &config.database_url else {
        return Ok(None);
    };
    let span = crate::obs::postgres_span("connect", "pg_pool_init");
    let _guard = span.enter();
    let pool = PgPoolOptions::new()
        .min_connections(1)
        .max_connections(8)
        .acquire_timeout(Duration::from_secs(3))
        .connect(url)
        .await?;
    crate::obs::postgres_pool_ready(1, 8);
    crate::metrics::record_postgres_pool_connections(8, 1, 8);
    Ok(Some(pool))
}

pub async fn migrate(pool: &PgPool) -> anyhow::Result<()> {
    let span = crate::obs::postgres_span("migrate", "apply_migrations");
    let _guard = span.enter();
    let mut connection = pool.acquire().await?;
    const MIGRATION_LOCK: &str = "SELECT pg_advisory_lock(704065788921)";
    const MIGRATION_UNLOCK: &str = "SELECT pg_advisory_unlock(704065788921)";
    sqlx::query(MIGRATION_LOCK)
        .execute(&mut *connection)
        .await?;

    let migration_result = async {
        for file in [
            include_str!("../../migrations/001_init.sql"),
            include_str!("../../migrations/002_jobs_commercial.sql"),
            include_str!("../../migrations/003_phase5plus.sql"),
            include_str!("../../migrations/004_auth_session_indexes.sql"),
            include_str!("../../migrations/005_category_hierarchy.sql"),
            include_str!("../../migrations/006_transaction_occurred_at.sql"),
            include_str!("../../migrations/007_multi_books.sql"),
            include_str!("../../migrations/008_transaction_source.sql"),
            include_str!("../../migrations/009_auto_ledger_fingerprint.sql"),
        ] {
            sqlx::raw_sql(file).execute(&mut *connection).await?;
        }
        Ok::<(), sqlx::Error>(())
    }
    .await;
    let unlock_result = sqlx::query(MIGRATION_UNLOCK)
        .execute(&mut *connection)
        .await;

    migration_result.and(unlock_result.map(|_| ()))?;
    crate::obs::postgres_migrations_applied();
    Ok(())
}

pub async fn ping(pool: &PgPool) -> Result<(), ApiError> {
    let span = crate::obs::postgres_span("ping", "pg_ping");
    let _guard = span.enter();
    sqlx::query("SELECT 1").execute(pool).await.map_err(|e| {
        ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "DB_UNAVAILABLE",
            e.to_string(),
        )
    })?;
    Ok(())
}
