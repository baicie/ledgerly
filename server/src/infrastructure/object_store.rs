use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context};
use axum::body::Bytes;
use axum::extract::{Path as AxumPath, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::put;
use axum::Router;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use uuid::Uuid;

use crate::config::Config;
use crate::error::ApiError;
use crate::state::AppState;

type HmacSha256 = Hmac<Sha256>;

const OBJECT_STORE_BACKUP_SCHEMA_VERSION: u32 = 1;
const OBJECT_STORE_BACKUP_KIND: &str = "ledgerly-object-store-backup";
const OBJECT_STORE_MANIFEST_FILE: &str = "manifest.json";
const OBJECT_STORE_OBJECTS_DIR: &str = "objects";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredObjectMetadata {
    pub key: String,
    pub size_bytes: u64,
    pub sha256: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObjectStoreBackupReport {
    pub object_count: usize,
    pub total_size_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObjectStoreRestoreReport {
    pub object_count: usize,
    pub total_size_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObjectStoreVerificationReport {
    pub object_count: usize,
    pub total_size_bytes: u64,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ObjectStoreBackupManifest {
    kind: String,
    schema_version: u32,
    created_at: String,
    object_count: usize,
    total_size_bytes: u64,
    objects: Vec<StoredObjectMetadata>,
}

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/object-store/{*key}", put(put_object).get(get_object))
}

#[derive(Debug, Deserialize)]
struct SignedQuery {
    expires: u64,
    sig: String,
    method: Option<String>,
}

pub fn ensure_dir(config: &Config) -> std::io::Result<()> {
    std::fs::create_dir_all(&config.object_store_dir)
}

pub fn sign_url(config: &Config, method: &str, object_key: &str, ttl_secs: u64) -> String {
    let expires = now_secs() + ttl_secs;
    let sig = sign(config, method, object_key, expires);
    format!(
        "{}/v1/object-store/{}?expires={expires}&sig={sig}&method={method}",
        config.object_store_public_base.trim_end_matches('/'),
        object_key.trim_start_matches('/'),
    )
}

fn sign(config: &Config, method: &str, object_key: &str, expires: u64) -> String {
    let mut mac =
        HmacSha256::new_from_slice(config.object_store_hmac_secret.as_bytes()).expect("hmac key");
    mac.update(method.as_bytes());
    mac.update(b"\n");
    mac.update(object_key.as_bytes());
    mac.update(b"\n");
    mac.update(expires.to_string().as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

fn verify(config: &Config, method: &str, object_key: &str, expires: u64, sig: &str) -> bool {
    if expires < now_secs() {
        return false;
    }
    let expected = sign(config, method, object_key, expires);
    expected.as_bytes().ct_eq(sig.as_bytes()).into()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn disk_path(config: &Config, object_key: &str) -> Result<PathBuf, ApiError> {
    validated_key(object_key)
        .map(|key| config.object_store_dir.join(key))
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_KEY", "bad object key"))
}

async fn put_object(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
    body: Bytes,
) -> Result<StatusCode, ApiError> {
    let span = crate::obs::object_store_put_span(&key, body.len());
    let _guard = span.enter();
    let method = q.method.as_deref().unwrap_or("PUT");
    if method != "PUT" || !verify(&state.config, "PUT", &key, q.expires, &q.sig) {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "BAD_SIGNATURE",
            "invalid or expired signature",
        ));
    }
    let path = disk_path(&state.config, &key)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(io_err)?;
    }
    std::fs::write(&path, &body).map_err(io_err)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn get_object(
    State(state): State<AppState>,
    AxumPath(key): AxumPath<String>,
    Query(q): Query<SignedQuery>,
) -> Result<Response, ApiError> {
    let method = q.method.as_deref().unwrap_or("GET");
    if method != "GET" || !verify(&state.config, "GET", &key, q.expires, &q.sig) {
        return Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "BAD_SIGNATURE",
            "invalid or expired signature",
        ));
    }
    let path = disk_path(&state.config, &key)?;
    let bytes = std::fs::read(&path)
        .map_err(|_| ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "object missing"))?;
    crate::obs::object_store_get_event(&key, true);
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        header::HeaderValue::from_static("application/octet-stream"),
    );
    Ok((StatusCode::OK, headers, bytes).into_response())
}

pub fn object_exists(config: &Config, object_key: &str) -> bool {
    disk_path(config, object_key)
        .map(|p| Path::new(&p).is_file())
        .unwrap_or(false)
}

pub fn object_metadata(config: &Config, object_key: &str) -> anyhow::Result<StoredObjectMetadata> {
    let path = disk_path_anyhow(&config.object_store_dir, object_key)?;
    metadata_for_path(object_key, &path)
}

pub fn object_metadata_from_root(
    object_store_dir: &Path,
    object_key: &str,
) -> anyhow::Result<StoredObjectMetadata> {
    let path = disk_path_anyhow(object_store_dir, object_key)?;
    metadata_for_path(object_key, &path)
}

pub fn verify_object_store_backup(
    from_dir: &Path,
) -> anyhow::Result<ObjectStoreVerificationReport> {
    let manifest = read_object_store_manifest(from_dir)?;
    let mut total_size_bytes = 0_u64;
    let mut seen = std::collections::HashSet::new();
    for object in &manifest.objects {
        let key = validated_key(&object.key)?;
        if !seen.insert(key.clone()) {
            bail!("duplicate object key in manifest: {key}");
        }
        let path = from_dir.join(OBJECT_STORE_OBJECTS_DIR).join(&key);
        let actual = metadata_for_path(&key, &path)?;
        if actual != *object {
            bail!("object backup metadata mismatch: {key}");
        }
        total_size_bytes += object.size_bytes;
    }
    if total_size_bytes != manifest.total_size_bytes {
        bail!("object store manifest total size mismatch");
    }
    Ok(ObjectStoreVerificationReport {
        object_count: manifest.object_count,
        total_size_bytes: manifest.total_size_bytes,
    })
}

pub fn backup_object_store(
    config: &Config,
    out_dir: &Path,
) -> anyhow::Result<ObjectStoreBackupReport> {
    if out_dir.exists() {
        let mut entries = fs::read_dir(out_dir)
            .with_context(|| format!("read backup directory {}", out_dir.display()))?;
        if entries.next().is_some() {
            bail!("object store backup output directory must be empty");
        }
    } else {
        fs::create_dir_all(out_dir)
            .with_context(|| format!("create backup directory {}", out_dir.display()))?;
    }
    let output_root = fs::canonicalize(out_dir).context("resolve object store backup directory")?;
    if let Ok(source_root) = fs::canonicalize(&config.object_store_dir) {
        if output_root.starts_with(&source_root) || source_root.starts_with(&output_root) {
            let _ = fs::remove_dir(out_dir);
            bail!("object store backup directory must be outside OBJECT_STORE_DIR");
        }
    }

    let objects_root = out_dir.join(OBJECT_STORE_OBJECTS_DIR);
    fs::create_dir_all(&objects_root).context("create object backup directory")?;
    let mut source_files = Vec::new();
    if config.object_store_dir.exists() {
        collect_files(
            &config.object_store_dir,
            &config.object_store_dir,
            &mut source_files,
        )?;
    }
    source_files.sort_by(|left, right| left.0.cmp(&right.0));

    let mut objects = Vec::with_capacity(source_files.len());
    let mut total_size_bytes = 0_u64;
    for (key, source_path) in source_files {
        let metadata = metadata_for_path(&key, &source_path)?;
        let destination = objects_root.join(&key);
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create object directory {}", parent.display()))?;
        }
        fs::copy(&source_path, &destination).with_context(|| {
            format!(
                "copy object {} to {}",
                source_path.display(),
                destination.display()
            )
        })?;
        let copied = metadata_for_path(&key, &destination)?;
        if copied != metadata {
            bail!("object changed while backing up: {key}");
        }
        total_size_bytes += metadata.size_bytes;
        objects.push(metadata);
    }

    let manifest = ObjectStoreBackupManifest {
        kind: OBJECT_STORE_BACKUP_KIND.into(),
        schema_version: OBJECT_STORE_BACKUP_SCHEMA_VERSION,
        created_at: OffsetDateTime::now_utc()
            .format(&Rfc3339)
            .context("format object store backup timestamp")?,
        object_count: objects.len(),
        total_size_bytes,
        objects,
    };
    let manifest_bytes =
        serde_json::to_vec_pretty(&manifest).context("encode object store manifest")?;
    let manifest_path = out_dir.join(OBJECT_STORE_MANIFEST_FILE);
    let temporary_manifest = out_dir.join(format!(
        "{OBJECT_STORE_MANIFEST_FILE}.tmp-{}",
        Uuid::now_v7()
    ));
    fs::write(&temporary_manifest, manifest_bytes).context("write object store manifest")?;
    fs::rename(&temporary_manifest, &manifest_path).context("publish object store manifest")?;

    Ok(ObjectStoreBackupReport {
        object_count: manifest.object_count,
        total_size_bytes: manifest.total_size_bytes,
    })
}

pub fn restore_object_store(
    config: &Config,
    from_dir: &Path,
) -> anyhow::Result<ObjectStoreRestoreReport> {
    let manifest = read_object_store_manifest(from_dir)?;

    let target = &config.object_store_dir;
    if target.exists() && !target.is_dir() {
        bail!("object store target is not a directory");
    }
    let parent = target
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)
        .with_context(|| format!("create object store parent {}", parent.display()))?;
    let staging = parent.join(format!(".ledgerly-objects-restore-{}", Uuid::now_v7()));
    fs::create_dir_all(&staging).context("create object restore staging directory")?;

    let restore_result = (|| -> anyhow::Result<ObjectStoreRestoreReport> {
        let mut total_size_bytes = 0_u64;
        let mut seen = std::collections::HashSet::new();
        for object in &manifest.objects {
            let key = validated_key(&object.key)?;
            if !seen.insert(key.clone()) {
                bail!("duplicate object key in manifest: {key}");
            }
            let source = from_dir.join(OBJECT_STORE_OBJECTS_DIR).join(&key);
            let source_metadata = metadata_for_path(&key, &source)?;
            if source_metadata != *object {
                bail!("object backup metadata mismatch: {key}");
            }
            let destination = staging.join(&key);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("create restore directory {}", parent.display()))?;
            }
            fs::copy(&source, &destination).with_context(|| format!("restore object {key}"))?;
            let restored = metadata_for_path(&key, &destination)?;
            if restored != *object {
                bail!("restored object metadata mismatch: {key}");
            }
            total_size_bytes += object.size_bytes;
        }
        if total_size_bytes != manifest.total_size_bytes {
            bail!("object store manifest total size mismatch");
        }

        let previous = parent.join(format!(".ledgerly-objects-previous-{}", Uuid::now_v7()));
        let had_target = target.exists();
        if had_target {
            fs::rename(target, &previous)
                .with_context(|| format!("move current object store to {}", previous.display()))?;
        }
        if let Err(error) = fs::rename(&staging, target) {
            if had_target {
                let _ = fs::rename(&previous, target);
            }
            return Err(error).context("publish restored object store");
        }
        if had_target {
            fs::remove_dir_all(&previous)
                .with_context(|| format!("remove previous object store {}", previous.display()))?;
        }
        Ok(ObjectStoreRestoreReport {
            object_count: manifest.object_count,
            total_size_bytes: manifest.total_size_bytes,
        })
    })();

    if restore_result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    restore_result
}

fn read_object_store_manifest(from_dir: &Path) -> anyhow::Result<ObjectStoreBackupManifest> {
    let manifest_path = from_dir.join(OBJECT_STORE_MANIFEST_FILE);
    let manifest_bytes = fs::read(&manifest_path)
        .with_context(|| format!("read object store manifest {}", manifest_path.display()))?;
    let manifest: ObjectStoreBackupManifest =
        serde_json::from_slice(&manifest_bytes).context("decode object store manifest")?;
    if manifest.kind != OBJECT_STORE_BACKUP_KIND {
        bail!("unexpected object store backup kind: {}", manifest.kind);
    }
    if manifest.schema_version != OBJECT_STORE_BACKUP_SCHEMA_VERSION {
        bail!(
            "unsupported object store backup schema: {}",
            manifest.schema_version
        );
    }
    if manifest.object_count != manifest.objects.len() {
        bail!("object store manifest count mismatch");
    }
    Ok(manifest)
}

fn collect_files(
    root: &Path,
    current: &Path,
    files: &mut Vec<(String, PathBuf)>,
) -> anyhow::Result<()> {
    for entry in fs::read_dir(current)
        .with_context(|| format!("read object directory {}", current.display()))?
    {
        let entry = entry.context("read object directory entry")?;
        let file_type = entry.file_type().context("read object file type")?;
        let path = entry.path();
        if file_type.is_symlink() {
            bail!(
                "object store backup does not follow symlinks: {}",
                path.display()
            );
        }
        if file_type.is_dir() {
            collect_files(root, &path, files)?;
        } else if file_type.is_file() {
            let relative = path
                .strip_prefix(root)
                .context("object path escaped backup root")?;
            let key = relative
                .components()
                .map(|component| component.as_os_str().to_string_lossy())
                .collect::<Vec<_>>()
                .join("/");
            let key = validated_key(&key)?;
            files.push((key.to_string(), path));
        }
    }
    Ok(())
}

fn metadata_for_path(key: &str, path: &Path) -> anyhow::Result<StoredObjectMetadata> {
    let file = File::open(path).with_context(|| format!("open object {}", path.display()))?;
    let size_bytes = file.metadata().context("read object metadata")?.len();
    let mut reader = file;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = reader.read(&mut buffer).context("read object bytes")?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(StoredObjectMetadata {
        key: key.to_string(),
        size_bytes,
        sha256: hex::encode(digest.finalize()),
    })
}

fn validated_key(object_key: &str) -> anyhow::Result<String> {
    let key = object_key.trim_start_matches('/');
    if key.is_empty()
        || key.contains('\\')
        || Path::new(key).is_absolute()
        || key
            .split('/')
            .any(|segment| segment.is_empty() || segment == "." || segment == "..")
    {
        bail!("invalid object key: {object_key}");
    }
    Ok(key.to_string())
}

fn disk_path_anyhow(root: &Path, object_key: &str) -> anyhow::Result<PathBuf> {
    let key = validated_key(object_key)?;
    Ok(root.join(key))
}

fn io_err(e: std::io::Error) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "OBJECT_STORE_IO",
        e.to_string(),
    )
}
