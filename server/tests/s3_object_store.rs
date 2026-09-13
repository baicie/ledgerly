use std::fs;
use std::path::{Path, PathBuf};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::config::ObjectStoreBackend;
use ledger_server::infrastructure::object_store::{
    backup_object_store_for_config, get_object_bytes, list_object_keys,
    migrate_local_object_store_to_s3, object_metadata_for_config, restore_object_store_for_config,
    sign_url, verify_object_store_backup,
};
use ledger_server::{app_router, AppState, Config};
use tower::ServiceExt;
use uuid::Uuid;

struct TestDirectory {
    path: PathBuf,
}

impl TestDirectory {
    fn new(prefix: &str) -> Self {
        let path = std::env::temp_dir().join(format!("ledgerly-{prefix}-{}", Uuid::now_v7()));
        fs::create_dir_all(&path).unwrap();
        Self { path }
    }

    fn unused(prefix: &str) -> Self {
        let path = std::env::temp_dir().join(format!("ledgerly-{prefix}-{}", Uuid::now_v7()));
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

fn s3_config(prefix: &str) -> Config {
    let mut config = Config::for_test();
    config.object_storage_backend = ObjectStoreBackend::S3;
    config.s3_endpoint =
        Some(std::env::var("S3_ENDPOINT").unwrap_or_else(|_| "http://127.0.0.1:9090".into()));
    config.s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into());
    config.s3_bucket = Some(std::env::var("S3_BUCKET").unwrap_or_else(|_| "ledgerly-test".into()));
    config.s3_access_key_id =
        Some(std::env::var("S3_ACCESS_KEY_ID").unwrap_or_else(|_| "foo".into()));
    config.s3_secret_access_key =
        Some(std::env::var("S3_SECRET_ACCESS_KEY").unwrap_or_else(|_| "bar".into()));
    config.s3_prefix = Some(prefix.into());
    config.s3_force_path_style = true;
    config.s3_allow_http = true;
    config
}

fn write_object(root: &Path, key: &str, bytes: &[u8]) {
    let path = root.join(key);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, bytes).unwrap();
}

#[tokio::test]
async fn s3_migration_backup_and_restore_round_trip() {
    if std::env::var("REQUIRE_S3_TESTS").ok().as_deref() != Some("true") {
        return;
    }

    let source = TestDirectory::new("s3-source");
    let backup = TestDirectory::unused("s3-backup");
    let run_id = Uuid::now_v7().simple().to_string();
    let target_prefix = format!("tests/{run_id}/target");
    let restored_prefix = format!("tests/{run_id}/restored");
    let first_key = "books/book-a/attachment-one";
    let second_key = "books/book-a/nested/attachment-two";
    let first_bytes = vec![0x31; 64 * 1024 + 17];
    let second_bytes = b"second s3 object".to_vec();
    write_object(source.path(), first_key, &first_bytes);
    write_object(source.path(), second_key, &second_bytes);

    let target = s3_config(&target_prefix);
    let dry_run = migrate_local_object_store_to_s3(&target, source.path(), true)
        .await
        .unwrap();
    assert!(dry_run.dry_run);
    assert_eq!(dry_run.scanned_objects, 2);
    assert_eq!(dry_run.uploaded_objects, 2);
    assert!(list_object_keys(&target).await.unwrap().is_empty());

    let migrated = migrate_local_object_store_to_s3(&target, source.path(), false)
        .await
        .unwrap();
    assert_eq!(migrated.scanned_objects, 2);
    assert_eq!(migrated.uploaded_objects, 2);
    assert_eq!(migrated.skipped_objects, 0);
    assert_eq!(
        migrated.uploaded_bytes,
        (first_bytes.len() + second_bytes.len()) as u64
    );

    let keys = list_object_keys(&target).await.unwrap();
    assert_eq!(keys, vec![first_key.to_string(), second_key.to_string()]);
    assert_eq!(
        get_object_bytes(&target, first_key)
            .await
            .unwrap()
            .unwrap()
            .as_ref(),
        first_bytes
    );
    assert_eq!(
        object_metadata_for_config(&target, second_key)
            .await
            .unwrap()
            .size_bytes,
        second_bytes.len() as u64
    );

    let app = app_router(AppState::new(target.clone()));
    let http_key = "books/book-a/http-attachment";
    let http_bytes = b"HTTP S3 attachment";
    let put_url = sign_url(&target, "PUT", http_key, 600);
    let put_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(put_url.trim_start_matches(&target.object_store_public_base))
                .body(Body::from(http_bytes.as_slice()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(put_response.status(), StatusCode::NO_CONTENT);

    let get_url = sign_url(&target, "GET", http_key, 600);
    let get_response = app
        .oneshot(
            Request::builder()
                .uri(get_url.trim_start_matches(&target.object_store_public_base))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_response.status(), StatusCode::OK);
    assert_eq!(
        get_response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .as_ref(),
        http_bytes
    );

    let backup_report = backup_object_store_for_config(&target, backup.path())
        .await
        .unwrap();
    assert_eq!(backup_report.object_count, 3);
    assert_eq!(
        backup_report.total_size_bytes,
        (first_bytes.len() + second_bytes.len() + http_bytes.len()) as u64
    );
    verify_object_store_backup(backup.path()).unwrap();

    let restored = s3_config(&restored_prefix);
    let restore_report = restore_object_store_for_config(&restored, backup.path())
        .await
        .unwrap();
    assert_eq!(restore_report.object_count, 3);
    assert_eq!(
        get_object_bytes(&restored, first_key)
            .await
            .unwrap()
            .unwrap()
            .as_ref(),
        first_bytes
    );
    assert_eq!(
        get_object_bytes(&restored, second_key)
            .await
            .unwrap()
            .unwrap(),
        second_bytes
    );
    assert_eq!(
        get_object_bytes(&restored, http_key)
            .await
            .unwrap()
            .unwrap()
            .as_ref(),
        http_bytes
    );
}
