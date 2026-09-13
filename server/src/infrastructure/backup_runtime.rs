use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

use anyhow::{bail, Context};
use sqlx::postgres::PgPoolOptions;
use time::OffsetDateTime;
use url::Url;
use uuid::Uuid;

use crate::config::Config;

use super::backup_bundle::{
    cleanup_backup_bundles, create_backup_bundle, find_latest_backup_bundle,
    replicate_backup_bundle, unpack_backup_bundle, verify_backup_bundle,
};
use super::backup_status::{
    duration_millis, evaluate_backup_readiness, rfc3339, BackupReadinessSnapshot, BackupRunOutcome,
    BackupRunStatus, BackupStatusStore, RecoveryDrillOutcome, RecoveryDrillStatus,
    RecoveryDrillStatusStore, RestoreRunOutcome, RestoreRunStatus, RestoreStatusStore,
};
use super::object_store::{
    backup_object_store, object_metadata_from_root, restore_object_store,
    verify_object_store_backup,
};
use super::postgres;

#[derive(Debug, Clone)]
pub struct BackupRunReport {
    pub run_id: String,
    pub bundle_path: PathBuf,
    pub file_count: usize,
    pub total_size_bytes: u64,
    pub duration_ms: u64,
    pub replicated: bool,
    pub local_retained: usize,
    pub offsite_retained: usize,
}

#[derive(Debug, Clone)]
pub struct RestoreRunReport {
    pub safety_backup_run_id: String,
    pub file_count: usize,
    pub object_count: usize,
    pub book_count: i64,
    pub transaction_count: i64,
    pub duration_ms: u64,
}

#[derive(Debug, Clone)]
pub struct RecoveryDrillReport {
    pub bundle_created_at: String,
    pub file_count: usize,
    pub object_count: usize,
    pub book_count: i64,
    pub transaction_count: i64,
    pub duration_ms: u64,
}

pub fn run_pg_dump(config: &Config, out: &Path) -> anyhow::Result<()> {
    let url = config
        .database_url
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL required"))?;
    let status = Command::new("pg_dump")
        .args(["--format=custom", "--file"])
        .arg(out)
        .arg(url)
        .status()?;
    if !status.success() {
        bail!("pg_dump failed");
    }
    Ok(())
}

pub fn run_pg_restore(config: &Config, from: &Path) -> anyhow::Result<()> {
    let url = config
        .database_url
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("DATABASE_URL required"))?;
    let status = Command::new("pg_restore")
        .args(["--clean", "--if-exists", "--no-owner", "--dbname", url])
        .arg(from)
        .status()?;
    if !status.success() {
        bail!("pg_restore failed");
    }
    Ok(())
}

pub async fn run_backup(config: &Config) -> anyhow::Result<BackupRunReport> {
    let backup_dir = config
        .backup_dir
        .as_deref()
        .context("BACKUP_DIR is required for backup runs")?;
    let started_at = OffsetDateTime::now_utc();
    let started = Instant::now();
    let run_id = Uuid::now_v7().to_string();
    let bundles_root = backup_dir.join("bundles");
    let work_dir = backup_dir.join("work").join(&run_id);
    let bundle_path = bundles_root.join(&run_id);
    let database_dump = work_dir.join("database.dump");
    let objects_backup = work_dir.join("objects");

    std::fs::create_dir_all(&work_dir)
        .with_context(|| format!("create backup work directory {}", work_dir.display()))?;
    std::fs::create_dir_all(&bundles_root)
        .with_context(|| format!("create backup bundle root {}", bundles_root.display()))?;

    let mut result = run_backup_steps(
        config,
        &database_dump,
        &objects_backup,
        &bundle_path,
        &bundles_root,
        &run_id,
    )
    .await;
    let _ = std::fs::remove_dir_all(&work_dir);
    let completed_at = OffsetDateTime::now_utc();
    let duration_ms = duration_millis(started.elapsed());
    if let Ok(report) = &mut result {
        report.duration_ms = duration_ms;
    }

    let status = match &result {
        Ok(report) => BackupRunStatus {
            outcome: BackupRunOutcome::Success,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            file_count: report.file_count,
            total_size_bytes: report.total_size_bytes,
            replicated: report.replicated,
            local_retained: report.local_retained,
            offsite_retained: report.offsite_retained,
            error_summary: None,
        },
        Err(error) => BackupRunStatus {
            outcome: BackupRunOutcome::Failed,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            file_count: 0,
            total_size_bytes: 0,
            replicated: false,
            local_retained: 0,
            offsite_retained: 0,
            error_summary: Some(truncate_error(&error.to_string())),
        },
    };
    let status_result = BackupStatusStore::new(backup_dir).write(&status);
    match (result, status_result) {
        (Ok(report), Ok(())) => Ok(report),
        (Ok(_), Err(error)) => Err(error),
        (Err(error), _) => Err(error),
    }
}

pub fn backup_readiness(config: &Config) -> anyhow::Result<BackupReadinessSnapshot> {
    evaluate_backup_readiness(
        config.backup_dir.as_deref(),
        config.backup_interval_hours,
        OffsetDateTime::now_utc(),
    )
}

pub fn restore_status(config: &Config) -> anyhow::Result<Option<RestoreRunStatus>> {
    config
        .backup_dir
        .as_deref()
        .map(RestoreStatusStore::new)
        .map(|store| store.read())
        .transpose()
        .map(Option::flatten)
}

pub fn recovery_drill_status(config: &Config) -> anyhow::Result<Option<RecoveryDrillStatus>> {
    config
        .backup_dir
        .as_deref()
        .map(RecoveryDrillStatusStore::new)
        .map(|store| store.read())
        .transpose()
        .map(Option::flatten)
}

pub async fn run_recovery_drill(config: Config) -> anyhow::Result<RecoveryDrillReport> {
    let backup_dir = config
        .backup_dir
        .clone()
        .context("BACKUP_DIR is required for recovery drills")?;
    let started_at = OffsetDateTime::now_utc();
    let started = Instant::now();
    let work_dir = backup_dir
        .join("work")
        .join(format!("drill-{}", Uuid::now_v7()));
    let unpacked = work_dir.join("unpacked");
    let drill_objects = work_dir.join("objects");
    let offsite_root = config.backup_offsite_dir.clone();
    let password = config.backup_password.clone();
    let database_url = config
        .recovery_drill_database_url
        .clone()
        .or_else(|| config.database_url.clone());

    let mut bundle_created_at = String::new();
    let result = async {
        let local_bundle_root = backup_dir.join("bundles");
        let bundle_root = offsite_root.unwrap_or(local_bundle_root);
        let bundle = find_latest_backup_bundle(&bundle_root)?
            .context("no backup bundle available for recovery drill")?;
        let bundle_path = bundle.path;
        bundle_created_at = bundle.created_at.clone();
        let bundle_created = bundle.created_at;
        let bundle_file_count = bundle.file_count;
        let verification = verify_backup_bundle(&bundle_path, password.as_deref())?;
        if !verification.plaintext_verified {
            bail!("backup password is required for recovery drill");
        }

        std::fs::create_dir_all(&work_dir).with_context(|| {
            format!(
                "create recovery drill work directory {}",
                work_dir.display()
            )
        })?;
        unpack_backup_bundle(&bundle_path, &unpacked, password.as_deref())?;
        let object_backup = unpacked.join("object-store");
        let object_verification = verify_object_store_backup(&object_backup)?;
        let database_url = database_url
            .as_deref()
            .context("DATABASE_URL is required for recovery drill")?;
        let (admin, database_name, drill_url) = create_temporary_database(database_url).await?;
        let mut drill_config = config.clone();
        drill_config.database_url = Some(drill_url);
        drill_config.object_store_dir = drill_objects.clone();

        let steps = execute_recovery_drill(
            drill_config,
            unpacked.clone(),
            object_backup,
            object_verification.object_count,
        )
        .await;

        let drop_result = sqlx::query(&format!(
            "DROP DATABASE IF EXISTS \"{database_name}\" WITH (FORCE)"
        ))
        .execute(&admin)
        .await
        .context("drop temporary recovery drill database");
        let (object_count, book_count, transaction_count) = steps?;
        drop_result?;
        Ok::<RecoveryDrillReport, anyhow::Error>(RecoveryDrillReport {
            bundle_created_at: bundle_created,
            file_count: bundle_file_count,
            object_count,
            book_count,
            transaction_count,
            duration_ms: 0,
        })
    }
    .await;

    let _ = std::fs::remove_dir_all(&work_dir);
    let completed_at = OffsetDateTime::now_utc();
    let duration_ms = duration_millis(started.elapsed());
    let mut result = result;
    if let Ok(report) = &mut result {
        report.duration_ms = duration_ms;
    }
    let status = match &result {
        Ok(report) => RecoveryDrillStatus {
            outcome: RecoveryDrillOutcome::Success,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            bundle_created_at: report.bundle_created_at.clone(),
            file_count: report.file_count,
            object_count: report.object_count,
            book_count: report.book_count,
            transaction_count: report.transaction_count,
            error_summary: None,
        },
        Err(error) => RecoveryDrillStatus {
            outcome: RecoveryDrillOutcome::Failed,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            bundle_created_at,
            file_count: 0,
            object_count: 0,
            book_count: 0,
            transaction_count: 0,
            error_summary: Some(truncate_error(&error.to_string())),
        },
    };
    let status_result = RecoveryDrillStatusStore::new(&backup_dir).write(&status);
    match (result, status_result) {
        (Ok(report), Ok(())) => Ok(report),
        (Ok(_), Err(error)) => Err(error),
        (Err(error), _) => Err(error),
    }
}

async fn execute_recovery_drill(
    drill_config: Config,
    unpacked: PathBuf,
    object_backup: PathBuf,
    expected_object_count: usize,
) -> anyhow::Result<(usize, i64, i64)> {
    restore_object_store(&drill_config, &object_backup)?;
    run_pg_restore(&drill_config, &unpacked.join("database.dump"))?;
    let database_url = drill_config
        .database_url
        .clone()
        .context("temporary recovery drill database URL missing")?;
    let object_store_dir = drill_config.object_store_dir.clone();
    let pool = PgPoolOptions::new()
        .max_connections(8)
        .connect(&database_url)
        .await
        .context("temporary recovery drill database unavailable")?;
    postgres::migrate(&pool).await?;
    let (object_count, book_count, transaction_count) =
        verify_restored_state(object_store_dir, pool).await?;
    if object_count != expected_object_count {
        bail!("recovery drill attachment count mismatch");
    }
    Ok((object_count, book_count, transaction_count))
}

async fn create_temporary_database(
    database_url: &str,
) -> anyhow::Result<(sqlx::PgPool, String, String)> {
    let admin = PgPoolOptions::new()
        .max_connections(2)
        .connect(database_url)
        .await
        .context("connect recovery drill admin database")?;
    let can_create: bool = sqlx::query_scalar(
        "SELECT rolcreatedb OR rolsuper
         FROM pg_roles
         WHERE rolname = current_user",
    )
    .fetch_one(&admin)
    .await
    .context("read recovery drill role capabilities")?;
    if !can_create {
        bail!("recovery drill database role requires CREATEDB");
    }
    let database_name = format!(
        "ledgerly_drill_{}",
        &Uuid::now_v7().simple().to_string()[..12]
    );
    let mut drill_url = Url::parse(database_url).context("parse recovery drill database URL")?;
    sqlx::query(&format!("CREATE DATABASE \"{database_name}\""))
        .execute(&admin)
        .await
        .with_context(|| format!("create recovery drill database {database_name}"))?;
    drill_url.set_path(&database_name);
    Ok((admin, database_name, drill_url.to_string()))
}

pub async fn restore_backup_bundle(
    config: &Config,
    bundle_dir: &Path,
    password: Option<&str>,
) -> anyhow::Result<RestoreRunReport> {
    let backup_dir = config
        .backup_dir
        .as_deref()
        .context("BACKUP_DIR is required for bundle restore")?;
    let started_at = OffsetDateTime::now_utc();
    let started = Instant::now();
    let work_dir = backup_dir
        .join("work")
        .join(format!("restore-{}", Uuid::now_v7()));
    let unpacked = work_dir.join("unpacked");
    let (mut result, safety_backup_run_id) = async {
        let verification = match verify_backup_bundle(bundle_dir, password) {
            Ok(verification) => verification,
            Err(error) => return (Err(error), None),
        };
        if !verification.plaintext_verified {
            return (
                Err(anyhow::anyhow!("backup bundle password is required")),
                None,
            );
        }
        let safety = match run_backup(config).await {
            Ok(safety) => safety,
            Err(error) => return (Err(error), None),
        };
        let safety_id = safety.run_id;
        let restore_result = async {
            std::fs::create_dir_all(&work_dir)
                .with_context(|| format!("create restore work directory {}", work_dir.display()))?;
            let unpack = unpack_backup_bundle(bundle_dir, &unpacked, password)?;
            restore_steps(config, &unpacked, unpack.file_count, safety_id.clone()).await
        }
        .await;
        (restore_result, Some(safety_id))
    }
    .await;

    let _ = std::fs::remove_dir_all(&work_dir);
    let completed_at = OffsetDateTime::now_utc();
    let duration_ms = duration_millis(started.elapsed());
    if let Ok(report) = &mut result {
        report.duration_ms = duration_ms;
    }
    let status = match &result {
        Ok(report) => RestoreRunStatus {
            outcome: RestoreRunOutcome::Success,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            safety_backup_run_id: Some(report.safety_backup_run_id.clone()),
            file_count: report.file_count,
            object_count: report.object_count,
            book_count: report.book_count,
            transaction_count: report.transaction_count,
            error_summary: None,
        },
        Err(error) => RestoreRunStatus {
            outcome: RestoreRunOutcome::Failed,
            started_at: rfc3339(started_at)?,
            completed_at: rfc3339(completed_at)?,
            duration_ms,
            safety_backup_run_id,
            file_count: 0,
            object_count: 0,
            book_count: 0,
            transaction_count: 0,
            error_summary: Some(truncate_error(&error.to_string())),
        },
    };
    let status_result = RestoreStatusStore::new(backup_dir).write(&status);
    match (result, status_result) {
        (Ok(report), Ok(())) => Ok(report),
        (Ok(_), Err(error)) => Err(error),
        (Err(error), _) => Err(error),
    }
}

async fn restore_steps(
    config: &Config,
    unpacked: &Path,
    file_count: usize,
    safety_backup_run_id: String,
) -> anyhow::Result<RestoreRunReport> {
    let object_backup = unpacked.join("object-store");
    let database_dump = unpacked.join("database.dump");
    let object_verification = verify_object_store_backup(&object_backup)?;
    restore_object_store(config, &object_backup)?;
    run_pg_restore(config, &database_dump)?;
    let pool = postgres::connect(config)
        .await?
        .context("DATABASE_URL required for restore verification")?;
    postgres::migrate(&pool).await?;
    let (object_count, book_count, transaction_count) =
        verify_restored_state(config.object_store_dir.clone(), pool).await?;
    if object_count != object_verification.object_count {
        bail!("restored attachment count changed during verification");
    }
    Ok(RestoreRunReport {
        safety_backup_run_id,
        file_count,
        object_count,
        book_count,
        transaction_count,
        duration_ms: 0,
    })
}

async fn verify_restored_state(
    object_store_dir: PathBuf,
    pool: sqlx::PgPool,
) -> anyhow::Result<(usize, i64, i64)> {
    let latest_index_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)
         FROM pg_indexes
         WHERE schemaname = 'public'
           AND indexname = 'uq_transactions_auto_event'",
    )
    .fetch_one(&pool)
    .await?;
    if latest_index_count != 1 {
        bail!("restored schema is missing the latest migration");
    }
    let book_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM books")
        .fetch_one(&pool)
        .await?;
    let transaction_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM transactions")
        .fetch_one(&pool)
        .await?;
    let attachments: Vec<(String, Option<String>, Option<i64>)> =
        sqlx::query_as("SELECT object_key, content_hash, size_bytes FROM attachments")
            .fetch_all(&pool)
            .await?;
    for (object_key, expected_hash, expected_size) in &attachments {
        let actual = object_metadata_from_root(&object_store_dir, object_key.as_str())
            .with_context(|| format!("restored attachment missing: {object_key}"))?;
        if let Some(expected_size) = expected_size {
            if actual.size_bytes as i64 != *expected_size {
                bail!("restored attachment size mismatch: {object_key}");
            }
        }
        if let Some(expected_hash) = expected_hash {
            if actual.sha256 != *expected_hash {
                bail!("restored attachment hash mismatch: {object_key}");
            }
        }
    }
    Ok((attachments.len(), book_count, transaction_count))
}

async fn run_backup_steps(
    config: &Config,
    database_dump: &Path,
    objects_backup: &Path,
    bundle_path: &Path,
    bundles_root: &Path,
    run_id: &str,
) -> anyhow::Result<BackupRunReport> {
    let backup_dir = config
        .backup_dir
        .as_deref()
        .context("BACKUP_DIR is required")?;
    if let Some(offsite) = &config.backup_offsite_dir {
        if offsite == backup_dir {
            bail!("BACKUP_OFFSITE_DIR must differ from BACKUP_DIR");
        }
    }

    run_pg_dump(config, database_dump)?;
    backup_object_store(config, objects_backup)?;
    let bundle = create_backup_bundle(
        database_dump,
        objects_backup,
        bundle_path,
        config.backup_password.as_deref(),
    )?;
    let verification = verify_backup_bundle(bundle_path, config.backup_password.as_deref())?;
    if !verification.plaintext_verified {
        bail!("scheduled encrypted backup could not verify plaintext");
    }

    let mut replicated = false;
    let mut offsite_retained = 0;
    if let Some(offsite_root) = &config.backup_offsite_dir {
        std::fs::create_dir_all(offsite_root)
            .with_context(|| format!("create offsite backup root {}", offsite_root.display()))?;
        let offsite_bundle = offsite_root.join(run_id);
        replicate_backup_bundle(bundle_path, &offsite_bundle)?;
        offsite_retained = cleanup_backup_bundles(offsite_root, config.backup_keep)?.kept_count;
        replicated = true;
    }
    let local_retained = cleanup_backup_bundles(bundles_root, config.backup_keep)?.kept_count;

    Ok(BackupRunReport {
        run_id: run_id.to_string(),
        bundle_path: bundle_path.to_path_buf(),
        file_count: bundle.file_count,
        total_size_bytes: bundle.total_size_bytes,
        duration_ms: 0,
        replicated,
        local_retained,
        offsite_retained,
    })
}

fn truncate_error(error: &str) -> String {
    const MAX: usize = 500;
    let mut summary = error.replace(['\r', '\n'], " ");
    if summary.len() > MAX {
        summary.truncate(MAX);
        summary.push_str("...");
    }
    summary
}
