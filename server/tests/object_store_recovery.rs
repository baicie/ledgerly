use std::fs;
use std::path::{Path, PathBuf};

use ledger_server::infrastructure::object_store::{
    backup_object_store, object_metadata, restore_object_store,
};
use ledger_server::Config;
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
fn object_store_backup_restore_preserves_snapshot_and_hashes() {
    let source_dir = TestDirectory::new("objects-source");
    let target_dir = TestDirectory::new("objects-target");
    let backup_dir = TestDirectory::new("objects-backup");
    fs::remove_dir(backup_dir.path()).expect("remove pre-created backup directory");

    let mut source = Config::for_test();
    source.object_store_dir = source_dir.path().to_path_buf();
    let first_key = "books/book-a/attachment-one";
    let second_key = "books/book-a/nested/attachment-two";
    let first_bytes = b"first attachment bytes";
    let second_bytes = b"second attachment bytes";
    write_object(source.object_store_dir.as_path(), first_key, first_bytes);
    write_object(source.object_store_dir.as_path(), second_key, second_bytes);

    let first_metadata = object_metadata(&source, first_key).expect("first metadata");
    let backup = backup_object_store(&source, backup_dir.path()).expect("back up object store");
    assert_eq!(backup.object_count, 2);
    assert_eq!(
        backup.total_size_bytes,
        (first_bytes.len() + second_bytes.len()) as u64
    );

    write_object(
        source.object_store_dir.as_path(),
        "books/book-a/post-backup",
        b"must not be restored",
    );

    let mut target = Config::for_test();
    target.object_store_dir = target_dir.path().join("restored-objects");
    let restored = restore_object_store(&target, backup_dir.path()).expect("restore objects");
    assert_eq!(restored.object_count, backup.object_count);
    assert_eq!(restored.total_size_bytes, backup.total_size_bytes);
    assert_eq!(
        fs::read(target.object_store_dir.join(first_key)).unwrap(),
        first_bytes
    );
    assert_eq!(
        fs::read(target.object_store_dir.join(second_key)).unwrap(),
        second_bytes
    );
    assert!(!target
        .object_store_dir
        .join("books/book-a/post-backup")
        .exists());
    assert_eq!(object_metadata(&target, first_key).unwrap(), first_metadata);
}

#[test]
fn corrupted_object_backup_does_not_replace_existing_store() {
    let source_dir = TestDirectory::new("objects-corrupt-source");
    let target_dir = TestDirectory::new("objects-corrupt-target");
    let backup_dir = TestDirectory::new("objects-corrupt-backup");
    fs::remove_dir(backup_dir.path()).expect("remove pre-created backup directory");

    let mut source = Config::for_test();
    source.object_store_dir = source_dir.path().to_path_buf();
    write_object(
        source.object_store_dir.as_path(),
        "books/book-a/attachment",
        b"original",
    );
    backup_object_store(&source, backup_dir.path()).expect("back up object store");
    fs::write(
        backup_dir.path().join("objects/books/book-a/attachment"),
        b"corrupted",
    )
    .expect("corrupt backup object");

    let mut target = Config::for_test();
    target.object_store_dir = target_dir.path().to_path_buf();
    write_object(
        target.object_store_dir.as_path(),
        "books/book-a/existing",
        b"existing target",
    );

    let result = restore_object_store(&target, backup_dir.path());

    assert!(result.is_err());
    assert_eq!(
        fs::read(target.object_store_dir.join("books/book-a/existing")).unwrap(),
        b"existing target"
    );
}

fn write_object(root: &Path, key: &str, bytes: &[u8]) {
    let path = root.join(key);
    fs::create_dir_all(path.parent().unwrap()).expect("create object parent");
    fs::write(path, bytes).expect("write object");
}
