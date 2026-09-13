use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

use anyhow::{bail, Context};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::config::Config;

use super::backup_bundle::{
    cleanup_backup_bundles, create_backup_bundle, replicate_backup_bundle, verify_backup_bundle,
};
use super::backup_status::{
    duration_millis, evaluate_backup_readiness, rfc3339, BackupReadinessSnapshot, BackupRunOutcome,
    BackupRunStatus, BackupStatusStore,
};
use super::object_store::backup_object_store;

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

pub async fn run_pg_dump(config: &Config, out: &Path) -> anyhow::Result<()> {
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

pub async fn run_pg_restore(config: &Config, from: &Path) -> anyhow::Result<()> {
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

    run_pg_dump(config, database_dump).await?;
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
