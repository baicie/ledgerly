use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context};
use axum::body::Bytes;
use axum::extract::{Path as AxumPath, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::put;
use axum::Router;
use futures_util::TryStreamExt;
use hmac::{Hmac, Mac};
use object_store::aws::AmazonS3Builder;
use object_store::path::Path as ObjectPath;
use object_store::{Error as ObjectStoreError, ObjectStore, ObjectStoreExt};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use uuid::Uuid;

use crate::config::{Config, ObjectStoreBackend};
use crate::error::ApiError;
use crate::state::AppState;

type HmacSha256 = Hmac<Sha256>;
type S3StoreCache = Mutex<HashMap<String, Arc<dyn ObjectStore>>>;

static S3_STORE_CACHE: OnceLock<S3StoreCache> = OnceLock::new();

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

#[derive(Clone)]
enum ObjectStoreClient {
    Local {
        root: PathBuf,
    },
    S3 {
        store: Arc<dyn ObjectStore>,
        prefix: Option<String>,
    },
}

impl ObjectStoreClient {
    fn from_config(config: &Config) -> anyhow::Result<Self> {
        match config.object_storage_backend {
            ObjectStoreBackend::Local => Ok(Self::Local {
                root: config.object_store_dir.clone(),
            }),
            ObjectStoreBackend::S3 => Ok(Self::S3 {
                store: cached_s3_store(config)?,
                prefix: config.s3_prefix.clone(),
            }),
        }
    }

    fn backend_label(&self) -> &'static str {
        match self {
            Self::Local { .. } => "local",
            Self::S3 { .. } => "s3",
        }
    }

    fn object_path(&self, object_key: &str) -> anyhow::Result<ObjectPath> {
        let key = validated_key(object_key)?;
        match self {
            Self::Local { .. } => Ok(ObjectPath::from(key)),
            Self::S3 { prefix, .. } => {
                let path = match prefix {
                    Some(prefix) => format!("{prefix}/{key}"),
                    None => key,
                };
                Ok(ObjectPath::from(path))
            }
        }
    }

    async fn put_bytes(&self, object_key: &str, bytes: &[u8]) -> anyhow::Result<()> {
        let started = Instant::now();
        let path = self.object_path(object_key);
        let result = match (self, path) {
            (Self::Local { root }, Ok(path)) => {
                let path = root.join(path.as_ref());
                async {
                    if let Some(parent) = path.parent() {
                        tokio::fs::create_dir_all(parent).await?;
                    }
                    tokio::fs::write(&path, bytes).await?;
                    Ok(())
                }
                .await
            }
            (Self::S3 { store, .. }, Ok(path)) => store
                .put(&path, Bytes::copy_from_slice(bytes).into())
                .await
                .map(|_| ())
                .map_err(Into::into),
            (_, Err(error)) => Err(error),
        };
        record_object_store_result(self.backend_label(), "put", started, result)
    }

    async fn get_bytes(&self, object_key: &str) -> anyhow::Result<Option<Bytes>> {
        let started = Instant::now();
        let path = self.object_path(object_key);
        let result = match (self, path) {
            (Self::Local { root }, Ok(path)) => {
                let path = root.join(path.as_ref());
                match tokio::fs::read(path).await {
                    Ok(bytes) => Ok(Some(Bytes::from(bytes))),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
                    Err(error) => Err(error.into()),
                }
            }
            (Self::S3 { store, .. }, Ok(path)) => match store.get(&path).await {
                Ok(result) => Ok(Some(result.bytes().await?)),
                Err(ObjectStoreError::NotFound { .. }) => Ok(None),
                Err(error) => Err(error.into()),
            },
            (_, Err(error)) => Err(error),
        };
        record_object_store_result(self.backend_label(), "get", started, result)
    }

    async fn object_exists(&self, object_key: &str) -> anyhow::Result<bool> {
        let started = Instant::now();
        let path = self.object_path(object_key);
        let result = match (self, path) {
            (Self::Local { root }, Ok(path)) => Ok(tokio::fs::metadata(root.join(path.as_ref()))
                .await
                .map(|metadata| metadata.is_file())
                .unwrap_or(false)),
            (Self::S3 { store, .. }, Ok(path)) => match store.head(&path).await {
                Ok(_) => Ok(true),
                Err(ObjectStoreError::NotFound { .. }) => Ok(false),
                Err(error) => Err(error.into()),
            },
            (_, Err(error)) => Err(error),
        };
        record_object_store_result(self.backend_label(), "head", started, result)
    }

    async fn object_metadata(&self, object_key: &str) -> anyhow::Result<StoredObjectMetadata> {
        let bytes = self
            .get_bytes(object_key)
            .await?
            .with_context(|| format!("object missing: {object_key}"))?;
        Ok(StoredObjectMetadata {
            key: validated_key(object_key)?,
            size_bytes: bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&bytes)),
        })
    }

    async fn list_keys(&self) -> anyhow::Result<Vec<String>> {
        let started = Instant::now();
        let result = match self {
            Self::Local { root } => {
                let mut files = Vec::new();
                if root.exists() {
                    collect_files(root, root, &mut files)?;
                }
                Ok(files.into_iter().map(|(key, _)| key).collect())
            }
            Self::S3 { store, prefix } => {
                let prefix_path = prefix.as_deref().map(ObjectPath::from);
                let mut stream = store.list(prefix_path.as_ref());
                let mut keys = Vec::new();
                while let Some(metadata) = stream.try_next().await? {
                    let key = metadata.location.to_string();
                    let key = match prefix {
                        Some(prefix) => key
                            .strip_prefix(&format!("{prefix}/"))
                            .map(str::to_string)
                            .unwrap_or_default(),
                        None => key,
                    };
                    if !key.is_empty() {
                        keys.push(validated_key(&key)?);
                    }
                }
                keys.sort();
                Ok(keys)
            }
        };
        record_object_store_result(self.backend_label(), "list", started, result)
    }

    async fn health_check(&self) -> anyhow::Result<()> {
        match self {
            Self::Local { root } => tokio::fs::create_dir_all(root)
                .await
                .context("create local object store root"),
            Self::S3 { store, prefix } => {
                let started = Instant::now();
                let prefix_path = prefix.as_deref().map(ObjectPath::from);
                let result = store
                    .list_with_delimiter(prefix_path.as_ref())
                    .await
                    .map(|_| ())
                    .map_err(Into::into);
                record_object_store_result("s3", "list", started, result)
            }
        }
    }
}

fn cached_s3_store(config: &Config) -> anyhow::Result<Arc<dyn ObjectStore>> {
    let mut key_material = Sha256::new();
    for value in [
        config.s3_endpoint.as_deref().unwrap_or_default(),
        config.s3_region.as_str(),
        config.s3_bucket.as_deref().unwrap_or_default(),
        config.s3_access_key_id.as_deref().unwrap_or_default(),
        config.s3_secret_access_key.as_deref().unwrap_or_default(),
        config.s3_session_token.as_deref().unwrap_or_default(),
        if config.s3_force_path_style {
            "path-style"
        } else {
            "virtual-hosted"
        },
        if config.s3_allow_http {
            "allow-http"
        } else {
            "https-only"
        },
    ] {
        key_material.update(value.as_bytes());
        key_material.update(b"\n");
    }
    let cache_key = hex::encode(key_material.finalize());
    let cache = S3_STORE_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(store) = cache.lock().expect("S3 store cache").get(&cache_key) {
        return Ok(store.clone());
    }

    let bucket = config
        .s3_bucket
        .as_deref()
        .context("S3_BUCKET is required")?;
    let access_key_id = config
        .s3_access_key_id
        .as_deref()
        .context("S3_ACCESS_KEY_ID is required")?;
    let secret_access_key = config
        .s3_secret_access_key
        .as_deref()
        .context("S3_SECRET_ACCESS_KEY is required")?;
    let mut builder = AmazonS3Builder::new()
        .with_bucket_name(bucket)
        .with_region(&config.s3_region)
        .with_access_key_id(access_key_id)
        .with_secret_access_key(secret_access_key)
        .with_allow_http(config.s3_allow_http)
        .with_virtual_hosted_style_request(!config.s3_force_path_style);
    if let Some(endpoint) = config.s3_endpoint.as_deref() {
        builder = builder.with_endpoint(endpoint);
    }
    if let Some(token) = config.s3_session_token.as_deref() {
        builder = builder.with_token(token);
    }
    let store: Arc<dyn ObjectStore> =
        Arc::new(builder.build().context("configure S3 object store")?);
    cache
        .lock()
        .expect("S3 store cache")
        .insert(cache_key, store.clone());
    Ok(store)
}

fn record_object_store_result<T>(
    backend: &'static str,
    operation: &'static str,
    started: Instant,
    result: anyhow::Result<T>,
) -> anyhow::Result<T> {
    crate::metrics::record_object_store_operation(
        backend,
        operation,
        if result.is_ok() { "success" } else { "failure" },
        started.elapsed().as_secs_f64(),
    );
    result
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObjectStoreMigrationReport {
    pub scanned_objects: usize,
    pub uploaded_objects: usize,
    pub skipped_objects: usize,
    pub uploaded_bytes: u64,
    pub dry_run: bool,
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
    if config.object_storage_backend == ObjectStoreBackend::S3 {
        return Ok(());
    }
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
    validated_key(&key)
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_KEY", "bad object key"))?;
    let client = ObjectStoreClient::from_config(&state.config).map_err(object_store_api_err)?;
    client
        .put_bytes(&key, &body)
        .await
        .map_err(object_store_api_err)?;
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
    validated_key(&key)
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_KEY", "bad object key"))?;
    let client = ObjectStoreClient::from_config(&state.config).map_err(object_store_api_err)?;
    let bytes = client
        .get_bytes(&key)
        .await
        .map_err(object_store_api_err)?
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "NOT_FOUND", "object missing"))?;
    crate::obs::object_store_get_event(&key, true);
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        header::HeaderValue::from_static("application/octet-stream"),
    );
    Ok((StatusCode::OK, headers, bytes).into_response())
}

pub fn object_exists(config: &Config, object_key: &str) -> bool {
    if config.object_storage_backend != ObjectStoreBackend::Local {
        return false;
    }
    disk_path(config, object_key)
        .map(|p| Path::new(&p).is_file())
        .unwrap_or(false)
}

pub fn object_metadata(config: &Config, object_key: &str) -> anyhow::Result<StoredObjectMetadata> {
    if config.object_storage_backend != ObjectStoreBackend::Local {
        bail!("object_metadata requires the local object store backend");
    }
    let path = disk_path_anyhow(&config.object_store_dir, object_key)?;
    metadata_for_path(object_key, &path)
}

pub async fn object_exists_for_config(config: &Config, object_key: &str) -> anyhow::Result<bool> {
    ObjectStoreClient::from_config(config)?
        .object_exists(object_key)
        .await
}

pub async fn put_object_bytes(
    config: &Config,
    object_key: &str,
    bytes: &[u8],
) -> anyhow::Result<()> {
    ObjectStoreClient::from_config(config)?
        .put_bytes(object_key, bytes)
        .await
}

pub async fn get_object_bytes(config: &Config, object_key: &str) -> anyhow::Result<Option<Bytes>> {
    ObjectStoreClient::from_config(config)?
        .get_bytes(object_key)
        .await
}

pub async fn list_object_keys(config: &Config) -> anyhow::Result<Vec<String>> {
    ObjectStoreClient::from_config(config)?.list_keys().await
}

pub async fn object_metadata_for_config(
    config: &Config,
    object_key: &str,
) -> anyhow::Result<StoredObjectMetadata> {
    ObjectStoreClient::from_config(config)?
        .object_metadata(object_key)
        .await
}

pub async fn health_check(config: &Config) -> anyhow::Result<()> {
    ObjectStoreClient::from_config(config)?.health_check().await
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
    if config.object_storage_backend != ObjectStoreBackend::Local {
        bail!("backup_object_store requires the local object store backend");
    }
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
    if config.object_storage_backend != ObjectStoreBackend::Local {
        bail!("restore_object_store requires the local object store backend");
    }
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

pub async fn backup_object_store_for_config(
    config: &Config,
    out_dir: &Path,
) -> anyhow::Result<ObjectStoreBackupReport> {
    match config.object_storage_backend {
        ObjectStoreBackend::Local => backup_object_store(config, out_dir),
        ObjectStoreBackend::S3 => {
            let started = Instant::now();
            let result = backup_s3_object_store(config, out_dir).await;
            crate::metrics::record_object_store_operation(
                "s3",
                "backup",
                if result.is_ok() { "success" } else { "failure" },
                started.elapsed().as_secs_f64(),
            );
            result
        }
    }
}

pub async fn restore_object_store_for_config(
    config: &Config,
    from_dir: &Path,
) -> anyhow::Result<ObjectStoreRestoreReport> {
    match config.object_storage_backend {
        ObjectStoreBackend::Local => restore_object_store(config, from_dir),
        ObjectStoreBackend::S3 => {
            let started = Instant::now();
            let result = restore_s3_object_store(config, from_dir).await;
            crate::metrics::record_object_store_operation(
                "s3",
                "restore",
                if result.is_ok() { "success" } else { "failure" },
                started.elapsed().as_secs_f64(),
            );
            result
        }
    }
}

pub async fn migrate_local_object_store_to_s3(
    config: &Config,
    source_dir: &Path,
    dry_run: bool,
) -> anyhow::Result<ObjectStoreMigrationReport> {
    if config.object_storage_backend != ObjectStoreBackend::S3 {
        bail!("OBJECT_STORE_BACKEND=s3 is required for object store migration");
    }
    if !source_dir.is_dir() {
        bail!("local object store source is not a directory");
    }

    let started = Instant::now();
    let result = async {
        let client = ObjectStoreClient::from_config(config)?;
        if !dry_run {
            client.health_check().await?;
        }

        let mut files = Vec::new();
        collect_files(source_dir, source_dir, &mut files)?;
        files.sort_by(|left, right| left.0.cmp(&right.0));

        let mut scanned_objects = 0_usize;
        let mut uploaded_objects = 0_usize;
        let mut skipped_objects = 0_usize;
        let mut uploaded_bytes = 0_u64;
        for (key, source_path) in files {
            scanned_objects += 1;
            let local = metadata_for_path(&key, &source_path)?;
            if dry_run {
                uploaded_objects += 1;
                uploaded_bytes = uploaded_bytes.saturating_add(local.size_bytes);
                continue;
            }
            if client.object_exists(&key).await? {
                let remote = client.object_metadata(&key).await?;
                if remote == local {
                    skipped_objects += 1;
                    continue;
                }
            }
            let bytes = tokio::fs::read(&source_path)
                .await
                .with_context(|| format!("read local object {}", source_path.display()))?;
            client.put_bytes(&key, &bytes).await?;
            let copied = client.object_metadata(&key).await?;
            if copied != local {
                bail!("migrated object metadata mismatch: {key}");
            }
            uploaded_objects += 1;
            uploaded_bytes = uploaded_bytes.saturating_add(local.size_bytes);
        }

        Ok(ObjectStoreMigrationReport {
            scanned_objects,
            uploaded_objects,
            skipped_objects,
            uploaded_bytes,
            dry_run,
        })
    }
    .await;
    crate::metrics::record_object_store_operation(
        "s3",
        "migrate",
        if result.is_ok() { "success" } else { "failure" },
        started.elapsed().as_secs_f64(),
    );
    result
}

async fn backup_s3_object_store(
    config: &Config,
    out_dir: &Path,
) -> anyhow::Result<ObjectStoreBackupReport> {
    let client = ObjectStoreClient::from_config(config)?;
    prepare_object_backup_output(out_dir)?;
    let objects_root = out_dir.join(OBJECT_STORE_OBJECTS_DIR);
    tokio::fs::create_dir_all(&objects_root)
        .await
        .context("create object backup directory")?;

    let keys = client.list_keys().await?;
    let mut objects = Vec::with_capacity(keys.len());
    let mut total_size_bytes = 0_u64;
    for key in keys {
        let bytes = client
            .get_bytes(&key)
            .await?
            .with_context(|| format!("object disappeared during backup: {key}"))?;
        let metadata = StoredObjectMetadata {
            key: key.clone(),
            size_bytes: bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&bytes)),
        };
        let destination = objects_root.join(&key);
        if let Some(parent) = destination.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .with_context(|| format!("create object directory {}", parent.display()))?;
        }
        tokio::fs::write(&destination, &bytes)
            .await
            .with_context(|| format!("write backup object {}", destination.display()))?;
        total_size_bytes = total_size_bytes.saturating_add(metadata.size_bytes);
        objects.push(metadata);
    }

    write_object_store_manifest(out_dir, objects, total_size_bytes).await
}

async fn restore_s3_object_store(
    config: &Config,
    from_dir: &Path,
) -> anyhow::Result<ObjectStoreRestoreReport> {
    let verification = verify_object_store_backup(from_dir)?;
    let manifest = read_object_store_manifest(from_dir)?;
    let client = ObjectStoreClient::from_config(config)?;
    for object in &manifest.objects {
        let source = from_dir.join(OBJECT_STORE_OBJECTS_DIR).join(&object.key);
        let bytes = tokio::fs::read(&source)
            .await
            .with_context(|| format!("read backup object {}", source.display()))?;
        client.put_bytes(&object.key, &bytes).await?;
        let restored = client.object_metadata(&object.key).await?;
        if restored != *object {
            bail!("restored S3 object metadata mismatch: {}", object.key);
        }
    }
    Ok(ObjectStoreRestoreReport {
        object_count: verification.object_count,
        total_size_bytes: verification.total_size_bytes,
    })
}

fn prepare_object_backup_output(out_dir: &Path) -> anyhow::Result<()> {
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
    Ok(())
}

async fn write_object_store_manifest(
    out_dir: &Path,
    objects: Vec<StoredObjectMetadata>,
    total_size_bytes: u64,
) -> anyhow::Result<ObjectStoreBackupReport> {
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
    let bytes = serde_json::to_vec_pretty(&manifest).context("encode object store manifest")?;
    let manifest_path = out_dir.join(OBJECT_STORE_MANIFEST_FILE);
    let temporary = out_dir.join(format!(
        "{OBJECT_STORE_MANIFEST_FILE}.tmp-{}",
        Uuid::now_v7()
    ));
    tokio::fs::write(&temporary, bytes)
        .await
        .context("write object store manifest")?;
    tokio::fs::rename(&temporary, &manifest_path)
        .await
        .context("publish object store manifest")?;
    Ok(ObjectStoreBackupReport {
        object_count: manifest.object_count,
        total_size_bytes: manifest.total_size_bytes,
    })
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

fn object_store_api_err(_: anyhow::Error) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "OBJECT_STORE_IO",
        "object store unavailable",
    )
}
