use std::fs;
use std::path::{Path, PathBuf};

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::config::ObjectStoreBackend;
use ledger_server::infrastructure::object_store::{
    backup_object_store_for_config, complete_multipart_for_config, direct_url, get_object_bytes,
    list_object_keys, migrate_local_object_store_to_s3, multipart_part_upload_url_for_config,
    object_metadata_for_config, put_multipart_part_for_config, restore_object_store_for_config,
    sign_url, start_multipart_for_config, verify_object_store_backup, MULTIPART_PART_SIZE_BYTES,
};
use ledger_server::{app_router, AppState, Config};
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

static S3_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

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
    let _guard = S3_TEST_LOCK.lock().await;

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

    let direct_key = "books/book-a/direct-attachment";
    let direct_bytes = b"direct S3 attachment";
    let direct_upload_url = direct_url(&target, Method::PUT, direct_key, 600)
        .await
        .unwrap()
        .expect("direct S3 upload URL");
    let direct_put = reqwest::Client::new()
        .put(direct_upload_url)
        .body(direct_bytes.to_vec())
        .send()
        .await
        .unwrap();
    assert!(direct_put.status().is_success());
    let direct_download_url = direct_url(&target, Method::GET, direct_key, 600)
        .await
        .unwrap()
        .expect("direct S3 download URL");
    let direct_get = reqwest::Client::new()
        .get(direct_download_url)
        .send()
        .await
        .unwrap();
    assert!(direct_get.status().is_success());
    assert_eq!(direct_get.bytes().await.unwrap().as_ref(), direct_bytes);

    let backup_report = backup_object_store_for_config(&target, backup.path())
        .await
        .unwrap();
    assert_eq!(backup_report.object_count, 4);
    assert_eq!(
        backup_report.total_size_bytes,
        (first_bytes.len() + second_bytes.len() + http_bytes.len() + direct_bytes.len()) as u64
    );
    verify_object_store_backup(backup.path()).unwrap();

    let restored = s3_config(&restored_prefix);
    let restore_report = restore_object_store_for_config(&restored, backup.path())
        .await
        .unwrap();
    assert_eq!(restore_report.object_count, 4);
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
    assert_eq!(
        get_object_bytes(&restored, direct_key)
            .await
            .unwrap()
            .unwrap()
            .as_ref(),
        direct_bytes
    );

    let multipart_key = "books/book-a/multipart-attachment";
    let multipart_first = vec![0x41; MULTIPART_PART_SIZE_BYTES];
    let multipart_second = b"multipart tail".to_vec();
    let upload_id = start_multipart_for_config(&target, multipart_key)
        .await
        .unwrap()
        .expect("S3 multipart upload id");
    let first_part_url =
        multipart_part_upload_url_for_config(&target, multipart_key, Some(&upload_id), 1, 600)
            .await
            .unwrap()
            .expect("presigned multipart part URL");
    let first_part_response = reqwest::Client::new()
        .put(first_part_url)
        .body(multipart_first.clone())
        .send()
        .await
        .unwrap();
    assert!(first_part_response.status().is_success());
    let first_part = first_part_response
        .headers()
        .get("etag")
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();
    let second_part = put_multipart_part_for_config(
        &target,
        multipart_key,
        Some(&upload_id),
        1,
        multipart_second.clone().into(),
    )
    .await
    .unwrap();
    complete_multipart_for_config(
        &target,
        multipart_key,
        Some(&upload_id),
        &[first_part, second_part],
    )
    .await
    .unwrap();
    let multipart_download = get_object_bytes(&restored, multipart_key).await.unwrap();
    assert!(
        multipart_download.is_none(),
        "multipart object must remain in the source prefix"
    );
    let multipart_bytes = get_object_bytes(&target, multipart_key)
        .await
        .unwrap()
        .expect("multipart object");
    assert_eq!(
        &multipart_bytes[..MULTIPART_PART_SIZE_BYTES],
        multipart_first
    );
    assert_eq!(
        &multipart_bytes[MULTIPART_PART_SIZE_BYTES..],
        multipart_second
    );
}

#[tokio::test]
async fn upload_session_uses_direct_s3_url_and_completes() {
    if std::env::var("REQUIRE_S3_TESTS").ok().as_deref() != Some("true") {
        return;
    }
    let _guard = S3_TEST_LOCK.lock().await;

    let prefix = format!("tests/{}/api", Uuid::now_v7().simple());
    let config = s3_config(&prefix);
    let app = app_router(AppState::new(config));
    let email = format!("s3-{}@example.com", Uuid::now_v7().simple());

    let register = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password123",
                        "displayName": "S3 Direct"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(register.status(), StatusCode::OK);

    let login = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password123",
                        "deviceId": "s3-direct-device"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let login: serde_json::Value =
        serde_json::from_slice(&login.into_body().collect().await.unwrap().to_bytes()).unwrap();
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap();

    let upgrade = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/billing/dev-upgrade")
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "plan": "plus" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(upgrade.status(), StatusCode::OK);

    let bytes = b"direct API upload";
    let session = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/attachments/upload-session"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "fileName": "receipt.txt",
                        "mimeType": "text/plain",
                        "size": bytes.len()
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(session.status(), StatusCode::OK);
    let session: serde_json::Value =
        serde_json::from_slice(&session.into_body().collect().await.unwrap().to_bytes()).unwrap();
    assert_eq!(session["uploadMode"], "direct");
    assert_eq!(session["downloadMode"], "direct");
    assert_eq!(session["maxSizeBytes"], 100 * 1024 * 1024);

    let put = reqwest::Client::new()
        .put(session["uploadUrl"].as_str().unwrap())
        .body(bytes.to_vec())
        .send()
        .await
        .unwrap();
    assert!(put.status().is_success());

    let complete = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/books/{book_id}/attachments/{}/complete",
                    session["attachmentId"].as_str().unwrap()
                ))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(complete.status(), StatusCode::OK);

    let list = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/attachments"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list.status(), StatusCode::OK);
    let list: serde_json::Value =
        serde_json::from_slice(&list.into_body().collect().await.unwrap().to_bytes()).unwrap();
    assert_eq!(list["attachments"].as_array().unwrap().len(), 1);
    assert_eq!(list["attachments"][0]["fileName"], "receipt.txt");
    assert_eq!(list["attachments"][0]["uploadStatus"], "ready");
    assert_eq!(list["attachments"][0]["downloadMode"], "direct");

    let mismatch = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/attachments/upload-session"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "fileName": "mismatch.txt",
                        "mimeType": "text/plain",
                        "size": bytes.len() + 1
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(mismatch.status(), StatusCode::OK);
    let mismatch: serde_json::Value =
        serde_json::from_slice(&mismatch.into_body().collect().await.unwrap().to_bytes()).unwrap();

    let put = reqwest::Client::new()
        .put(mismatch["uploadUrl"].as_str().unwrap())
        .body(bytes.to_vec())
        .send()
        .await
        .unwrap();
    assert!(put.status().is_success());

    let complete = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/books/{book_id}/attachments/{}/complete",
                    mismatch["attachmentId"].as_str().unwrap()
                ))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(complete.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let list = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/attachments"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let list: serde_json::Value =
        serde_json::from_slice(&list.into_body().collect().await.unwrap().to_bytes()).unwrap();
    let attachments = list["attachments"].as_array().unwrap();
    assert_eq!(attachments.len(), 2);
    assert_eq!(
        attachments
            .iter()
            .filter(|item| item["uploadStatus"] == "ready")
            .count(),
        1
    );
    assert_eq!(
        attachments
            .iter()
            .filter(|item| item["uploadStatus"] == "failed")
            .count(),
        1
    );

    let delete = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/books/{book_id}/attachments/{}",
                    session["attachmentId"].as_str().unwrap()
                ))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(delete.status(), StatusCode::NO_CONTENT);

    let deleted = reqwest::Client::new()
        .get(mismatch["downloadUrl"].as_str().unwrap())
        .send()
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NOT_FOUND);

    let list = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/attachments"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let list: serde_json::Value =
        serde_json::from_slice(&list.into_body().collect().await.unwrap().to_bytes()).unwrap();
    assert_eq!(list["attachments"].as_array().unwrap().len(), 1);
    assert_eq!(list["attachments"][0]["uploadStatus"], "failed");
}
