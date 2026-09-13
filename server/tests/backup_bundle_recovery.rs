use std::fs;
use std::path::{Path, PathBuf};

use ledger_server::infrastructure::backup_bundle::{
    cleanup_backup_bundles, create_backup_bundle, replicate_backup_bundle, unpack_backup_bundle,
    verify_backup_bundle,
};
use ledger_server::infrastructure::object_store::backup_object_store;
use ledger_server::Config;
use sha2::{Digest, Sha256};
use uuid::Uuid;

struct TestDirectory {
    path: PathBuf,
}

impl TestDirectory {
    fn new(prefix: &str) -> Self {
        let path = std::env::temp_dir().join(format!("ledgerly-{prefix}-{}", Uuid::now_v7()));
        fs::create_dir_all(&path).expect("create test directory");
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

#[test]
fn plaintext_bundle_verifies_replicates_and_unpacks() {
    let fixture = BundleFixture::new("bundle-plaintext");
    let database_dump = fixture.database_dump.path().join("database.dump");
    fs::write(&database_dump, b"postgres custom dump bytes").expect("write database dump");
    write_object(
        fixture._object_source.path(),
        "books/book-a/attachment",
        b"attachment bytes",
    );
    backup_object_store(&fixture.source_config, fixture.object_backup.path())
        .expect("back up objects");

    let created = create_backup_bundle(
        &database_dump,
        fixture.object_backup.path(),
        fixture.bundle.path(),
        None,
    )
    .expect("create bundle");
    assert_eq!(created.file_count, 3);
    assert!(!created.encrypted);

    let verified =
        verify_backup_bundle(fixture.bundle.path(), None).expect("verify plaintext bundle");
    assert!(verified.plaintext_verified);
    assert_eq!(verified.file_count, created.file_count);

    let replicated = replicate_backup_bundle(fixture.bundle.path(), fixture.replica.path())
        .expect("replicate bundle");
    assert_eq!(replicated.file_count, created.file_count);
    verify_backup_bundle(fixture.replica.path(), None).expect("verify replica");

    let unpacked = unpack_backup_bundle(fixture.replica.path(), fixture.unpacked.path(), None)
        .expect("unpack bundle");
    assert_eq!(unpacked.file_count, created.file_count);
    assert_eq!(
        fs::read(fixture.unpacked.path().join("database.dump")).unwrap(),
        b"postgres custom dump bytes"
    );
    assert_eq!(
        fs::read(
            fixture
                .unpacked
                .path()
                .join("object-store/objects/books/book-a/attachment")
        )
        .unwrap(),
        b"attachment bytes"
    );
}

#[test]
fn encrypted_bundle_requires_password_and_detects_corruption() {
    let fixture = BundleFixture::new("bundle-encrypted");
    let database_dump = fixture.database_dump.path().join("database.dump");
    fs::write(&database_dump, b"encrypted database dump").expect("write database dump");
    let attachment_bytes = vec![0x5a; 1024 * 1024 + 123];
    write_object(
        fixture._object_source.path(),
        "books/book-a/attachment",
        &attachment_bytes,
    );
    backup_object_store(&fixture.source_config, fixture.object_backup.path())
        .expect("back up objects");

    create_backup_bundle(
        &database_dump,
        fixture.object_backup.path(),
        fixture.bundle.path(),
        Some("password123"),
    )
    .expect("create encrypted bundle");

    let locked = verify_backup_bundle(fixture.bundle.path(), None).expect("verify ciphertext");
    assert!(locked.encrypted);
    assert!(!locked.plaintext_verified);
    assert!(verify_backup_bundle(fixture.bundle.path(), Some("wrong-password")).is_err());

    let verified =
        verify_backup_bundle(fixture.bundle.path(), Some("password123")).expect("verify plaintext");
    assert!(verified.plaintext_verified);
    unpack_backup_bundle(
        fixture.bundle.path(),
        fixture.unpacked.path(),
        Some("password123"),
    )
    .expect("unpack encrypted bundle");
    assert_eq!(
        fs::read(fixture.unpacked.path().join("database.dump")).unwrap(),
        b"encrypted database dump"
    );
    assert_eq!(
        fs::read(
            fixture
                .unpacked
                .path()
                .join("object-store/objects/books/book-a/attachment")
        )
        .unwrap(),
        attachment_bytes
    );

    fs::write(
        fixture.bundle.path().join("payload/00000000.bin"),
        b"corrupted",
    )
    .expect("corrupt bundle payload");
    assert!(verify_backup_bundle(fixture.bundle.path(), Some("password123")).is_err());
}

#[test]
fn schema_v1_plaintext_bundle_remains_readable() {
    let fixture = BundleFixture::new("bundle-v1");
    let payload = b"legacy v1 bundle payload";
    let bundle = fixture.bundle.path();
    fs::create_dir_all(bundle.join("payload")).expect("create v1 payload directory");
    fs::write(bundle.join("payload/00000000.bin"), payload).expect("write v1 payload");
    let sha256 = hex::encode(Sha256::digest(payload));
    let manifest = serde_json::json!({
        "kind": "ledgerly-server-backup-bundle",
        "schemaVersion": 1,
        "createdAt": "2026-01-01T00:00:00Z",
        "encrypted": false,
        "fileCount": 1,
        "totalSizeBytes": payload.len(),
        "files": [{
            "logicalPath": "database.dump",
            "payloadPath": "payload/00000000.bin",
            "sizeBytes": payload.len(),
            "sha256": sha256,
            "storedSizeBytes": payload.len(),
            "storedSha256": sha256
        }]
    });
    fs::write(
        bundle.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    )
    .expect("write v1 manifest");

    let verified = verify_backup_bundle(bundle, None).expect("verify v1 bundle");
    assert!(verified.plaintext_verified);
    unpack_backup_bundle(bundle, fixture.unpacked.path(), None).expect("unpack v1 bundle");
    assert_eq!(
        fs::read(fixture.unpacked.path().join("database.dump")).unwrap(),
        payload
    );
}

#[test]
fn cleanup_keeps_newest_bundles_only() {
    let fixture = BundleFixture::new("bundle-cleanup");
    let database_dump = fixture.database_dump.path().join("database.dump");
    fs::write(&database_dump, b"cleanup database dump").expect("write database dump");
    write_object(
        fixture._object_source.path(),
        "books/book-a/attachment",
        b"cleanup attachment",
    );
    backup_object_store(&fixture.source_config, fixture.object_backup.path())
        .expect("back up objects");

    let root = TestDirectory::new("bundle-cleanup-root");
    for (name, created_at) in [
        ("oldest", "2026-01-01T00:00:00Z"),
        ("middle", "2026-02-01T00:00:00Z"),
        ("newest", "2026-03-01T00:00:00Z"),
    ] {
        let bundle = root.path().join(name);
        create_backup_bundle(&database_dump, fixture.object_backup.path(), &bundle, None)
            .expect("create cleanup bundle");
        set_bundle_created_at(&bundle, created_at);
    }

    let report = cleanup_backup_bundles(root.path(), 1).expect("cleanup bundles");

    assert_eq!(report.deleted_count, 2);
    assert_eq!(report.kept_count, 1);
    assert!(report.freed_bytes > 0);
    assert!(!root.path().join("oldest").exists());
    assert!(!root.path().join("middle").exists());
    assert!(root.path().join("newest").exists());
}

struct BundleFixture {
    source_config: Config,
    _object_source: TestDirectory,
    object_backup: TestDirectory,
    database_dump: TestDirectory,
    bundle: TestDirectory,
    replica: TestDirectory,
    unpacked: TestDirectory,
}

impl BundleFixture {
    fn new(prefix: &str) -> Self {
        let object_source = TestDirectory::new(&format!("{prefix}-objects"));
        let object_backup = TestDirectory::unused(&format!("{prefix}-object-backup"));
        let database_dump = TestDirectory::new(&format!("{prefix}-database"));
        let bundle = TestDirectory::unused(&format!("{prefix}-bundle"));
        let replica = TestDirectory::unused(&format!("{prefix}-replica"));
        let unpacked = TestDirectory::unused(&format!("{prefix}-unpacked"));
        let mut source_config = Config::for_test();
        source_config.object_store_dir = object_source.path().to_path_buf();
        Self {
            source_config,
            _object_source: object_source,
            object_backup,
            database_dump,
            bundle,
            replica,
            unpacked,
        }
    }
}

fn write_object(root: &Path, key: &str, bytes: &[u8]) {
    let path = root.join(key);
    fs::create_dir_all(path.parent().unwrap()).expect("create object parent");
    fs::write(path, bytes).expect("write object");
}

fn set_bundle_created_at(bundle: &Path, created_at: &str) {
    let manifest_path = bundle.join("manifest.json");
    let mut manifest: serde_json::Value =
        serde_json::from_slice(&fs::read(&manifest_path).unwrap()).unwrap();
    manifest["createdAt"] = serde_json::Value::String(created_at.to_string());
    fs::write(manifest_path, serde_json::to_vec_pretty(&manifest).unwrap()).unwrap();
}
