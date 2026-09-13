use std::fs;
use std::path::{Path, PathBuf};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::infrastructure::backup_bundle::{create_backup_bundle, replicate_backup_bundle};
use ledger_server::infrastructure::backup_runtime::record_backup_metrics;
use ledger_server::infrastructure::backup_status::{
    BackupRunOutcome, BackupRunStatus, BackupStatusStore, RecoveryDrillOutcome,
    RecoveryDrillStatus, RecoveryDrillStatusStore, RestoreRunOutcome, RestoreRunStatus,
    RestoreStatusStore,
};
use ledger_server::infrastructure::object_store::backup_object_store;
use ledger_server::metrics::{register_metrics, MetricsHandle};
use ledger_server::{app_router, AppState, Config};
use metrics_exporter_prometheus::PrometheusBuilder;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tower::ServiceExt;
use uuid::Uuid;

struct TestDirectory {
    path: PathBuf,
}

impl TestDirectory {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!("ledgerly-backup-metrics-{}", Uuid::now_v7()));
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

fn timestamp(value: OffsetDateTime) -> String {
    value.format(&Rfc3339).unwrap()
}

fn metric_value(body: &str, name: &str, labels: &[(&str, &str)]) -> Option<f64> {
    body.lines().find_map(|line| {
        let mut fields = line.split_whitespace();
        let sample = fields.next()?;
        let value = fields.next()?.parse().ok()?;
        let name_matches = sample == name
            || sample
                .strip_prefix(name)
                .is_some_and(|suffix| suffix.starts_with('{'));
        let labels_match = labels.iter().all(|(key, value)| {
            let expected = format!("{key}=\"{value}\"");
            sample
                .split(['{', ',', '}'])
                .any(|label| label.trim() == expected)
        });
        (name_matches && labels_match).then_some(value)
    })
}

#[tokio::test]
async fn metrics_endpoint_exports_backup_health_and_capacity() {
    let directory = TestDirectory::new();
    let backup_dir = directory.path().join("backups");
    let object_store_dir = directory.path().join("objects");
    let object_backup = directory.path().join("object-backup");
    let database_dump = directory.path().join("database.dump");
    let local_bundle = backup_dir.join("bundles").join("local-run");
    let offsite_dir = directory.path().join("offsite");
    let offsite_bundle = offsite_dir.join("offsite-run");

    fs::create_dir_all(&object_store_dir).unwrap();
    let mut config = Config::for_test();
    config.object_store_dir = object_store_dir;
    backup_object_store(&config, &object_backup).unwrap();
    fs::write(&database_dump, b"database dump").unwrap();
    create_backup_bundle(&database_dump, &object_backup, &local_bundle, None).unwrap();
    replicate_backup_bundle(&local_bundle, &offsite_bundle).unwrap();

    let now = OffsetDateTime::now_utc();
    let completed_at = timestamp(now);
    BackupStatusStore::new(&backup_dir)
        .write(&BackupRunStatus {
            outcome: BackupRunOutcome::Success,
            started_at: timestamp(now - time::Duration::seconds(90)),
            completed_at: completed_at.clone(),
            duration_ms: 90_000,
            file_count: 2,
            total_size_bytes: 13,
            replicated: true,
            local_retained: 1,
            offsite_retained: 1,
            error_summary: None,
        })
        .unwrap();
    RecoveryDrillStatusStore::new(&backup_dir)
        .write(&RecoveryDrillStatus {
            outcome: RecoveryDrillOutcome::Success,
            started_at: timestamp(now - time::Duration::seconds(30)),
            completed_at: completed_at.clone(),
            duration_ms: 30_000,
            bundle_created_at: completed_at.clone(),
            file_count: 2,
            object_count: 0,
            book_count: 0,
            transaction_count: 0,
            error_summary: None,
        })
        .unwrap();
    RestoreStatusStore::new(&backup_dir)
        .write(&RestoreRunStatus {
            outcome: RestoreRunOutcome::Success,
            started_at: timestamp(now - time::Duration::seconds(45)),
            completed_at,
            duration_ms: 45_000,
            safety_backup_run_id: Some("safety-run".into()),
            file_count: 2,
            object_count: 0,
            book_count: 0,
            transaction_count: 0,
            error_summary: None,
        })
        .unwrap();

    config.backup_dir = Some(backup_dir);
    config.backup_offsite_dir = Some(offsite_dir);
    config.recovery_drill_enabled = true;
    config.backup_capacity_warn_bytes = 100 * 1024 * 1024;
    config.backup_capacity_critical_bytes = 200 * 1024 * 1024;

    register_metrics();
    let handle = PrometheusBuilder::new().install_recorder().unwrap();
    let disabled_handle = handle.clone();
    ledger_server::metrics::record_backup_run("success");
    ledger_server::metrics::record_recovery_drill_run("failure");
    ledger_server::metrics::record_restore_run("success");
    ledger_server::metrics::record_backup_cleanup_failure("local");
    ledger_server::metrics::record_postgres_pool_connections(4, 1, 8);
    let mut state = AppState::new(config);
    state.metrics_handle = Some(MetricsHandle::new(handle));
    let response = app_router(state)
        .oneshot(
            Request::builder()
                .uri("/metrics")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let body = String::from_utf8(bytes.to_vec()).unwrap();

    assert_eq!(
        metric_value(&body, "backup_state", &[("state", "ready")]),
        Some(1.0),
        "metrics body:\n{body}"
    );
    assert_eq!(
        metric_value(&body, "backup_recovery_drill_state", &[("state", "ready")]),
        Some(1.0)
    );
    assert_eq!(
        metric_value(&body, "backup_restore_state", &[("state", "ready")]),
        Some(1.0)
    );
    assert_eq!(
        metric_value(&body, "backup_bundle_count", &[("location", "local")]),
        Some(1.0)
    );
    assert_eq!(
        metric_value(&body, "backup_bundle_count", &[("location", "offsite")]),
        Some(1.0)
    );
    assert!(metric_value(&body, "backup_bundle_bytes", &[("location", "local")]).unwrap() > 0.0);
    assert_eq!(
        metric_value(&body, "backup_replication_enabled", &[]),
        Some(1.0)
    );
    assert!(
        metric_value(
            &body,
            "backup_capacity_utilization_percent",
            &[("location", "local"), ("severity", "warning")]
        )
        .unwrap()
            > 0.0
    );
    assert_eq!(
        metric_value(&body, "backup_runs_total", &[("outcome", "success")]),
        Some(1.0)
    );
    assert_eq!(
        metric_value(
            &body,
            "backup_recovery_drill_runs_total",
            &[("outcome", "failure")]
        ),
        Some(1.0)
    );
    assert_eq!(
        metric_value(
            &body,
            "backup_restore_runs_total",
            &[("outcome", "success")]
        ),
        Some(1.0)
    );
    assert_eq!(
        metric_value(
            &body,
            "backup_cleanup_failures_total",
            &[("location", "local")]
        ),
        Some(1.0)
    );
    assert_eq!(
        metric_value(&body, "postgres_pool_connections", &[("role", "current")]),
        Some(4.0)
    );

    record_backup_metrics(&Config::for_test());
    let disabled_body = disabled_handle.render();
    assert_eq!(
        metric_value(&disabled_body, "backup_state", &[("state", "disabled")]),
        Some(1.0)
    );
    assert_eq!(
        metric_value(
            &disabled_body,
            "backup_recovery_drill_state",
            &[("state", "disabled")]
        ),
        Some(1.0)
    );
    assert_eq!(
        metric_value(
            &disabled_body,
            "backup_restore_state",
            &[("state", "never_run")]
        ),
        Some(1.0)
    );
}
