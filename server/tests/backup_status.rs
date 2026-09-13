use std::fs;
use std::path::{Path, PathBuf};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::app_router;
use ledger_server::infrastructure::backup_status::{
    evaluate_backup_readiness, BackupReadiness, BackupRunOutcome, BackupRunStatus,
    BackupStatusStore, RecoveryDrillOutcome, RecoveryDrillStatus, RecoveryDrillStatusStore,
    RestoreRunOutcome, RestoreRunStatus, RestoreStatusStore,
};
use ledger_server::{AppState, Config};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tower::ServiceExt;
use uuid::Uuid;

struct TestDirectory {
    path: PathBuf,
}

impl TestDirectory {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!("ledgerly-backup-status-{}", Uuid::now_v7()));
        fs::create_dir_all(&path).unwrap();
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn status(outcome: BackupRunOutcome, completed_at: OffsetDateTime) -> BackupRunStatus {
    BackupRunStatus {
        outcome,
        started_at: (completed_at - time::Duration::minutes(1))
            .format(&Rfc3339)
            .unwrap(),
        completed_at: completed_at.format(&Rfc3339).unwrap(),
        duration_ms: 1_000,
        file_count: 3,
        total_size_bytes: 1024,
        replicated: true,
        local_retained: 3,
        offsite_retained: 3,
        error_summary: None,
    }
}

#[test]
fn backup_readiness_tracks_success_failure_and_staleness() {
    let directory = TestDirectory::new();
    let store = BackupStatusStore::new(directory.path());
    let now = OffsetDateTime::parse("2026-09-14T12:00:00Z", &Rfc3339).unwrap();

    assert_eq!(
        evaluate_backup_readiness(None, 24, now).unwrap().readiness,
        BackupReadiness::Disabled
    );
    assert_eq!(
        evaluate_backup_readiness(Some(directory.path()), 24, now)
            .unwrap()
            .readiness,
        BackupReadiness::NeverRun
    );

    store
        .write(&status(
            BackupRunOutcome::Success,
            OffsetDateTime::parse("2026-09-14T10:00:00Z", &Rfc3339).unwrap(),
        ))
        .unwrap();
    assert_eq!(
        evaluate_backup_readiness(Some(directory.path()), 24, now)
            .unwrap()
            .readiness,
        BackupReadiness::Ready
    );

    store
        .write(&status(
            BackupRunOutcome::Success,
            OffsetDateTime::parse("2026-09-12T10:00:00Z", &Rfc3339).unwrap(),
        ))
        .unwrap();
    assert_eq!(
        evaluate_backup_readiness(Some(directory.path()), 24, now)
            .unwrap()
            .readiness,
        BackupReadiness::Stale
    );

    store
        .write(&status(
            BackupRunOutcome::Failed,
            OffsetDateTime::parse("2026-09-14T11:00:00Z", &Rfc3339).unwrap(),
        ))
        .unwrap();
    assert_eq!(
        evaluate_backup_readiness(Some(directory.path()), 24, now)
            .unwrap()
            .readiness,
        BackupReadiness::Failed
    );
}

#[tokio::test]
async fn backup_health_endpoint_is_disabled_without_backup_directory() {
    let app = app_router(AppState::new(Config::for_test()));
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health/backup")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "disabled");
}

#[tokio::test]
async fn backup_health_endpoint_reports_ready_without_sensitive_fields() {
    let directory = TestDirectory::new();
    BackupStatusStore::new(directory.path())
        .write(&status(
            BackupRunOutcome::Success,
            OffsetDateTime::now_utc(),
        ))
        .unwrap();
    RestoreStatusStore::new(directory.path())
        .write(&RestoreRunStatus {
            outcome: RestoreRunOutcome::Success,
            started_at: "2026-09-14T10:00:00Z".into(),
            completed_at: "2026-09-14T10:05:00Z".into(),
            duration_ms: 300_000,
            safety_backup_run_id: Some("safety-run".into()),
            file_count: 3,
            object_count: 1,
            book_count: 2,
            transaction_count: 4,
            error_summary: None,
        })
        .unwrap();
    RecoveryDrillStatusStore::new(directory.path())
        .write(&RecoveryDrillStatus {
            outcome: RecoveryDrillOutcome::Success,
            started_at: "2026-09-14T11:00:00Z".into(),
            completed_at: "2026-09-14T11:03:00Z".into(),
            duration_ms: 180_000,
            bundle_created_at: "2026-09-14T10:00:00Z".into(),
            file_count: 3,
            object_count: 1,
            book_count: 2,
            transaction_count: 4,
            error_summary: None,
        })
        .unwrap();
    let mut config = Config::for_test();
    config.backup_dir = Some(directory.path().to_path_buf());
    let app = app_router(AppState::new(config));

    let response = app
        .oneshot(
            Request::builder()
                .uri("/health/backup")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "ready");
    assert_eq!(body["fileCount"], 3);
    assert_eq!(body["lastRestore"]["outcome"], "success");
    assert_eq!(body["lastRestore"]["transactionCount"], 4);
    assert_eq!(body["lastRecoveryDrill"]["outcome"], "success");
    assert_eq!(body["lastRecoveryDrill"]["objectCount"], 1);
    assert!(body.get("errorSummary").is_none());
    assert!(body.get("bundlePath").is_none());
}
