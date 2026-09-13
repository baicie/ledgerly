use std::fs;
use std::path::{Path, PathBuf};

use anyhow::Context;
use serde::{Deserialize, Serialize};
use time::{format_description::well_known::Rfc3339, Duration as TimeDuration, OffsetDateTime};
use uuid::Uuid;

pub const BACKUP_STATUS_FILE: &str = "status.json";
pub const RESTORE_STATUS_FILE: &str = "restore-status.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BackupRunOutcome {
    Success,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RestoreRunOutcome {
    Success,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRunStatus {
    pub outcome: BackupRunOutcome,
    pub started_at: String,
    pub completed_at: String,
    pub duration_ms: u64,
    pub file_count: usize,
    pub total_size_bytes: u64,
    pub replicated: bool,
    pub local_retained: usize,
    pub offsite_retained: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_summary: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreRunStatus {
    pub outcome: RestoreRunOutcome,
    pub started_at: String,
    pub completed_at: String,
    pub duration_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub safety_backup_run_id: Option<String>,
    pub file_count: usize,
    pub object_count: usize,
    pub book_count: i64,
    pub transaction_count: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_summary: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackupReadiness {
    Disabled,
    NeverRun,
    Failed,
    Stale,
    Ready,
}

impl BackupReadiness {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::NeverRun => "never_run",
            Self::Failed => "failed",
            Self::Stale => "stale",
            Self::Ready => "ready",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackupReadinessSnapshot {
    pub readiness: BackupReadiness,
    pub status: Option<BackupRunStatus>,
    pub age_seconds: Option<i64>,
}

pub struct BackupStatusStore {
    path: PathBuf,
}

pub struct RestoreStatusStore {
    path: PathBuf,
}

impl BackupStatusStore {
    pub fn new(backup_dir: &Path) -> Self {
        Self {
            path: backup_dir.join(BACKUP_STATUS_FILE),
        }
    }

    pub fn read(&self) -> anyhow::Result<Option<BackupRunStatus>> {
        if !self.path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&self.path)
            .with_context(|| format!("read backup status {}", self.path.display()))?;
        let status = serde_json::from_slice(&bytes).context("decode persisted backup status")?;
        Ok(Some(status))
    }

    pub fn write(&self, status: &BackupRunStatus) -> anyhow::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create backup status directory {}", parent.display()))?;
        }
        let bytes = serde_json::to_vec_pretty(status).context("encode backup status")?;
        let temporary = self
            .path
            .with_file_name(format!("{BACKUP_STATUS_FILE}.tmp-{}", Uuid::now_v7()));
        fs::write(&temporary, bytes).context("write backup status")?;
        fs::rename(&temporary, &self.path).context("publish backup status")?;
        Ok(())
    }
}

impl RestoreStatusStore {
    pub fn new(backup_dir: &Path) -> Self {
        Self {
            path: backup_dir.join(RESTORE_STATUS_FILE),
        }
    }

    pub fn read(&self) -> anyhow::Result<Option<RestoreRunStatus>> {
        if !self.path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&self.path)
            .with_context(|| format!("read restore status {}", self.path.display()))?;
        let status = serde_json::from_slice(&bytes).context("decode persisted restore status")?;
        Ok(Some(status))
    }

    pub fn write(&self, status: &RestoreRunStatus) -> anyhow::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create restore status directory {}", parent.display()))?;
        }
        let bytes = serde_json::to_vec_pretty(status).context("encode restore status")?;
        let temporary = self
            .path
            .with_file_name(format!("{RESTORE_STATUS_FILE}.tmp-{}", Uuid::now_v7()));
        fs::write(&temporary, bytes).context("write restore status")?;
        fs::rename(&temporary, &self.path).context("publish restore status")?;
        Ok(())
    }
}

pub fn evaluate_backup_readiness(
    backup_dir: Option<&Path>,
    interval_hours: u64,
    now: OffsetDateTime,
) -> anyhow::Result<BackupReadinessSnapshot> {
    let Some(backup_dir) = backup_dir else {
        return Ok(BackupReadinessSnapshot {
            readiness: BackupReadiness::Disabled,
            status: None,
            age_seconds: None,
        });
    };
    let Some(status) = BackupStatusStore::new(backup_dir).read()? else {
        return Ok(BackupReadinessSnapshot {
            readiness: BackupReadiness::NeverRun,
            status: None,
            age_seconds: None,
        });
    };
    let completed_at = OffsetDateTime::parse(&status.completed_at, &Rfc3339)
        .context("parse backup completion time")?;
    let age = now - completed_at;
    let age_seconds = age.whole_seconds().max(0);
    let readiness = if status.outcome == BackupRunOutcome::Failed {
        BackupReadiness::Failed
    } else {
        let interval_seconds = (interval_hours as i64).saturating_mul(60 * 60);
        if age_seconds > interval_seconds {
            BackupReadiness::Stale
        } else {
            BackupReadiness::Ready
        }
    };
    Ok(BackupReadinessSnapshot {
        readiness,
        status: Some(status),
        age_seconds: Some(age_seconds),
    })
}

pub fn rfc3339(value: OffsetDateTime) -> anyhow::Result<String> {
    value.format(&Rfc3339).context("format RFC3339 timestamp")
}

pub fn duration_millis(duration: std::time::Duration) -> u64 {
    duration.as_millis().min(u64::MAX as u128) as u64
}

pub fn freshness_deadline(completed_at: OffsetDateTime, interval_hours: u64) -> OffsetDateTime {
    completed_at + TimeDuration::hours(interval_hours as i64)
}
