use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use anyhow::{bail, Context};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use uuid::Uuid;

use super::object_store::verify_object_store_backup;

const BUNDLE_KIND: &str = "ledgerly-server-backup-bundle";
const BUNDLE_SCHEMA_VERSION: u32 = 1;
const BUNDLE_MANIFEST_FILE: &str = "manifest.json";
const BUNDLE_PAYLOAD_DIR: &str = "payload";
const DATABASE_LOGICAL_PATH: &str = "database.dump";
const OBJECT_STORE_LOGICAL_PREFIX: &str = "object-store/";
const ARGON2_MEMORY_KIB: u32 = 19_456;
const ARGON2_ITERATIONS: u32 = 2;
const ARGON2_PARALLELISM: u32 = 1;
const ARGON2_KEY_BYTES: usize = 32;
const AES_GCM_NONCE_BYTES: usize = 12;
const ARGON2_SALT_BYTES: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BackupBundleReport {
    pub file_count: usize,
    pub total_size_bytes: u64,
    pub encrypted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BackupBundleVerificationReport {
    pub file_count: usize,
    pub total_size_bytes: u64,
    pub encrypted: bool,
    pub plaintext_verified: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BackupBundleManifest {
    kind: String,
    schema_version: u32,
    created_at: String,
    encrypted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    encryption: Option<BundleEncryption>,
    file_count: usize,
    total_size_bytes: u64,
    files: Vec<BundleFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BundleEncryption {
    cipher: String,
    kdf: String,
    salt_base64: String,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BundleFile {
    logical_path: String,
    payload_path: String,
    size_bytes: u64,
    sha256: String,
    stored_size_bytes: u64,
    stored_sha256: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    nonce_base64: Option<String>,
}

pub fn create_backup_bundle(
    database_dump: &Path,
    object_store_backup: &Path,
    out_dir: &Path,
    password: Option<&str>,
) -> anyhow::Result<BackupBundleReport> {
    if let Some(password) = password {
        if password.len() < 8 {
            bail!("backup bundle password must be at least 8 characters");
        }
    }
    if !database_dump.is_file() {
        bail!("database dump does not exist: {}", database_dump.display());
    }
    verify_object_store_backup(object_store_backup)?;
    require_empty_output_directory(out_dir)?;
    reject_overlapping_paths(database_dump, out_dir)?;
    reject_overlapping_paths(object_store_backup, out_dir)?;

    let result = (|| -> anyhow::Result<BackupBundleReport> {
        fs::create_dir_all(out_dir.join(BUNDLE_PAYLOAD_DIR))
            .context("create backup bundle payload directory")?;

        let mut inputs = vec![(
            DATABASE_LOGICAL_PATH.to_string(),
            database_dump.to_path_buf(),
        )];
        collect_files(
            object_store_backup,
            object_store_backup,
            OBJECT_STORE_LOGICAL_PREFIX,
            &mut inputs,
        )?;
        inputs.sort_by(|left, right| left.0.cmp(&right.0));

        let encryption = if password.is_some() {
            Some(create_encryption()?)
        } else {
            None
        };
        let key = encryption
            .as_ref()
            .zip(password)
            .map(|(encryption, password)| derive_key(password, encryption))
            .transpose()?;

        let mut files = Vec::with_capacity(inputs.len());
        let mut total_size_bytes = 0_u64;
        for (index, (logical_path, source_path)) in inputs.into_iter().enumerate() {
            let logical_path = validated_logical_path(&logical_path)?;
            let plaintext = fs::read(&source_path)
                .with_context(|| format!("read bundle input {}", source_path.display()))?;
            let size_bytes = plaintext.len() as u64;
            let sha256 = sha256_bytes(&plaintext);
            let payload_path = format!("{BUNDLE_PAYLOAD_DIR}/{index:08}.bin");
            let (stored, nonce_base64) = if let Some(key) = &key {
                let mut nonce = [0_u8; AES_GCM_NONCE_BYTES];
                OsRng.fill_bytes(&mut nonce);
                let ciphertext = Aes256Gcm::new_from_slice(key)
                    .expect("AES-256 key")
                    .encrypt(
                        Nonce::from_slice(&nonce),
                        Payload {
                            msg: plaintext.as_ref(),
                            aad: logical_path.as_bytes(),
                        },
                    )
                    .map_err(|_| anyhow::anyhow!("encrypt backup bundle file"))?;
                (ciphertext, Some(STANDARD.encode(nonce)))
            } else {
                (plaintext, None)
            };
            fs::write(out_dir.join(&payload_path), &stored)
                .with_context(|| format!("write bundle payload {payload_path}"))?;
            total_size_bytes += size_bytes;
            files.push(BundleFile {
                logical_path,
                payload_path,
                size_bytes,
                sha256,
                stored_size_bytes: stored.len() as u64,
                stored_sha256: sha256_bytes(&stored),
                nonce_base64,
            });
        }

        let manifest = BackupBundleManifest {
            kind: BUNDLE_KIND.into(),
            schema_version: BUNDLE_SCHEMA_VERSION,
            created_at: OffsetDateTime::now_utc()
                .format(&Rfc3339)
                .context("format backup bundle timestamp")?,
            encrypted: encryption.is_some(),
            encryption,
            file_count: files.len(),
            total_size_bytes,
            files,
        };
        write_manifest(out_dir, &manifest)?;
        Ok(BackupBundleReport {
            file_count: manifest.file_count,
            total_size_bytes: manifest.total_size_bytes,
            encrypted: manifest.encrypted,
        })
    })();

    if result.is_err() {
        let _ = fs::remove_dir_all(out_dir);
    }
    result
}

pub fn verify_backup_bundle(
    bundle_dir: &Path,
    password: Option<&str>,
) -> anyhow::Result<BackupBundleVerificationReport> {
    let (manifest, files) = read_bundle_files(bundle_dir, password)?;
    let plaintext_verified = !manifest.encrypted || password.is_some();
    Ok(BackupBundleVerificationReport {
        file_count: files.len(),
        total_size_bytes: manifest.total_size_bytes,
        encrypted: manifest.encrypted,
        plaintext_verified,
    })
}

pub fn unpack_backup_bundle(
    bundle_dir: &Path,
    out_dir: &Path,
    password: Option<&str>,
) -> anyhow::Result<BackupBundleReport> {
    if out_dir.exists() {
        bail!("backup bundle output directory must not exist");
    }
    let (manifest, files) = read_bundle_files(bundle_dir, password)?;
    if manifest.encrypted && password.is_none() {
        bail!("backup bundle password is required");
    }

    let parent = out_dir
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)
        .with_context(|| format!("create bundle output parent {}", parent.display()))?;
    let staging = parent.join(format!(".ledgerly-bundle-unpack-{}", Uuid::now_v7()));
    fs::create_dir_all(&staging).context("create bundle unpack staging directory")?;

    let result = (|| -> anyhow::Result<BackupBundleReport> {
        let mut total_size_bytes = 0_u64;
        for (file, contents) in manifest.files.iter().zip(files) {
            let path = staging.join(&file.logical_path);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("create unpack directory {}", parent.display()))?;
            }
            fs::write(&path, &contents)
                .with_context(|| format!("write unpacked file {}", file.logical_path))?;
            total_size_bytes += contents.len() as u64;
        }
        fs::rename(&staging, out_dir).context("publish unpacked backup bundle")?;
        Ok(BackupBundleReport {
            file_count: manifest.file_count,
            total_size_bytes,
            encrypted: manifest.encrypted,
        })
    })();

    if result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    result
}

pub fn replicate_backup_bundle(
    from_dir: &Path,
    to_dir: &Path,
) -> anyhow::Result<BackupBundleVerificationReport> {
    if to_dir.exists() {
        bail!("backup bundle replication target must not exist");
    }
    let verification = verify_backup_bundle(from_dir, None)?;
    let manifest = read_manifest(from_dir)?;
    let parent = to_dir
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)
        .with_context(|| format!("create replication parent {}", parent.display()))?;
    let staging = parent.join(format!(".ledgerly-bundle-replica-{}", Uuid::now_v7()));
    fs::create_dir_all(&staging).context("create bundle replica staging directory")?;

    let result = (|| -> anyhow::Result<BackupBundleVerificationReport> {
        fs::copy(
            from_dir.join(BUNDLE_MANIFEST_FILE),
            staging.join(BUNDLE_MANIFEST_FILE),
        )
        .context("copy bundle manifest")?;
        for file in &manifest.files {
            let payload_path = validated_relative_path(&file.payload_path)?;
            let destination = staging.join(&payload_path);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent).with_context(|| {
                    format!("create replica payload directory {}", parent.display())
                })?;
            }
            fs::copy(from_dir.join(&payload_path), &destination)
                .with_context(|| format!("replicate bundle payload {}", file.payload_path))?;
        }
        let replicated = verify_backup_bundle(&staging, None)?;
        if replicated.file_count != verification.file_count
            || replicated.total_size_bytes != verification.total_size_bytes
        {
            bail!("replicated backup bundle summary mismatch");
        }
        fs::rename(&staging, to_dir).context("publish backup bundle replica")?;
        Ok(replicated)
    })();

    if result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    result
}

fn read_bundle_files(
    bundle_dir: &Path,
    password: Option<&str>,
) -> anyhow::Result<(BackupBundleManifest, Vec<Vec<u8>>)> {
    let manifest = read_manifest(bundle_dir)?;
    if manifest.encrypted && password.is_some() && password.map(str::len).unwrap_or(0) < 8 {
        bail!("backup bundle password must be at least 8 characters");
    }
    let key = if manifest.encrypted {
        password
            .zip(manifest.encryption.as_ref())
            .map(|(password, encryption)| derive_key(password, encryption))
            .transpose()?
    } else {
        None
    };

    let mut logical_paths = HashSet::new();
    let mut payload_paths = HashSet::new();
    let mut files = Vec::with_capacity(manifest.files.len());
    let mut total_size_bytes = 0_u64;
    for file in &manifest.files {
        let logical_path = validated_logical_path(&file.logical_path)?;
        let payload_path = validated_relative_path(&file.payload_path)?;
        if !logical_paths.insert(logical_path.clone()) {
            bail!("duplicate logical path in backup bundle");
        }
        if !payload_paths.insert(payload_path.clone()) {
            bail!("duplicate payload path in backup bundle");
        }
        let stored = fs::read(bundle_dir.join(&payload_path))
            .with_context(|| format!("read bundle payload {}", file.payload_path))?;
        if stored.len() as u64 != file.stored_size_bytes
            || sha256_bytes(&stored) != file.stored_sha256
        {
            bail!("stored payload integrity failed: {}", file.logical_path);
        }
        let plaintext = if manifest.encrypted {
            let Some(key) = &key else {
                total_size_bytes += file.size_bytes;
                files.push(stored);
                continue;
            };
            let nonce = file
                .nonce_base64
                .as_ref()
                .context("encrypted bundle file is missing nonce")?;
            let nonce = STANDARD.decode(nonce).context("decode bundle nonce")?;
            if nonce.len() != AES_GCM_NONCE_BYTES {
                bail!("invalid bundle nonce length");
            }
            Aes256Gcm::new_from_slice(key)
                .expect("AES-256 key")
                .decrypt(
                    Nonce::from_slice(&nonce),
                    Payload {
                        msg: stored.as_ref(),
                        aad: logical_path.as_bytes(),
                    },
                )
                .map_err(|_| anyhow::anyhow!("invalid bundle password or corrupted payload"))?
        } else {
            stored
        };
        if plaintext.len() as u64 != file.size_bytes || sha256_bytes(&plaintext) != file.sha256 {
            bail!("plaintext payload integrity failed: {}", file.logical_path);
        }
        total_size_bytes += file.size_bytes;
        files.push(plaintext);
    }
    if total_size_bytes != manifest.total_size_bytes {
        bail!("backup bundle total size mismatch");
    }
    Ok((manifest, files))
}

fn read_manifest(bundle_dir: &Path) -> anyhow::Result<BackupBundleManifest> {
    let path = bundle_dir.join(BUNDLE_MANIFEST_FILE);
    let bytes =
        fs::read(&path).with_context(|| format!("read bundle manifest {}", path.display()))?;
    let manifest: BackupBundleManifest =
        serde_json::from_slice(&bytes).context("decode bundle manifest")?;
    if manifest.kind != BUNDLE_KIND {
        bail!("unexpected backup bundle kind: {}", manifest.kind);
    }
    if manifest.schema_version != BUNDLE_SCHEMA_VERSION {
        bail!(
            "unsupported backup bundle schema: {}",
            manifest.schema_version
        );
    }
    if manifest.file_count != manifest.files.len() {
        bail!("backup bundle count mismatch");
    }
    if manifest.encrypted != manifest.encryption.is_some() {
        bail!("backup bundle encryption metadata mismatch");
    }
    Ok(manifest)
}

fn write_manifest(out_dir: &Path, manifest: &BackupBundleManifest) -> anyhow::Result<()> {
    let bytes = serde_json::to_vec_pretty(manifest).context("encode bundle manifest")?;
    let temporary = out_dir.join(format!("{BUNDLE_MANIFEST_FILE}.tmp-{}", Uuid::now_v7()));
    fs::write(&temporary, bytes).context("write bundle manifest")?;
    fs::rename(&temporary, out_dir.join(BUNDLE_MANIFEST_FILE))
        .context("publish bundle manifest")?;
    Ok(())
}

fn create_encryption() -> anyhow::Result<BundleEncryption> {
    let mut salt = [0_u8; ARGON2_SALT_BYTES];
    OsRng.fill_bytes(&mut salt);
    Ok(BundleEncryption {
        cipher: "aes-256-gcm".into(),
        kdf: "argon2id".into(),
        salt_base64: STANDARD.encode(salt),
        memory_kib: ARGON2_MEMORY_KIB,
        iterations: ARGON2_ITERATIONS,
        parallelism: ARGON2_PARALLELISM,
    })
}

fn derive_key(password: &str, encryption: &BundleEncryption) -> anyhow::Result<[u8; 32]> {
    if encryption.cipher != "aes-256-gcm" || encryption.kdf != "argon2id" {
        bail!("unsupported backup bundle encryption");
    }
    let salt = STANDARD
        .decode(&encryption.salt_base64)
        .context("decode Argon2 salt")?;
    if salt.len() < 8 {
        bail!("invalid backup bundle salt");
    }
    let params = Params::new(
        encryption.memory_kib,
        encryption.iterations,
        encryption.parallelism,
        Some(ARGON2_KEY_BYTES),
    )
    .map_err(|error| anyhow::anyhow!("invalid Argon2 parameters: {error}"))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut key = [0_u8; ARGON2_KEY_BYTES];
    argon2
        .hash_password_into(password.as_bytes(), &salt, &mut key)
        .map_err(|error| anyhow::anyhow!("derive backup bundle key: {error}"))?;
    Ok(key)
}

fn collect_files(
    root: &Path,
    current: &Path,
    logical_prefix: &str,
    files: &mut Vec<(String, PathBuf)>,
) -> anyhow::Result<()> {
    for entry in
        fs::read_dir(current).with_context(|| format!("read bundle input {}", current.display()))?
    {
        let entry = entry.context("read bundle input entry")?;
        let file_type = entry.file_type().context("read bundle input type")?;
        let path = entry.path();
        if file_type.is_symlink() {
            bail!("bundle input does not follow symlinks: {}", path.display());
        }
        if file_type.is_dir() {
            collect_files(root, &path, logical_prefix, files)?;
        } else if file_type.is_file() {
            let relative = path
                .strip_prefix(root)
                .context("bundle input escaped root")?;
            let relative = relative
                .components()
                .map(|component| component.as_os_str().to_string_lossy())
                .collect::<Vec<_>>()
                .join("/");
            files.push((format!("{logical_prefix}{relative}"), path));
        }
    }
    Ok(())
}

fn validated_logical_path(path: &str) -> anyhow::Result<String> {
    let path = validated_relative_path(path)?;
    if path != DATABASE_LOGICAL_PATH && !path.starts_with(OBJECT_STORE_LOGICAL_PREFIX) {
        bail!("invalid bundle logical path: {path}");
    }
    Ok(path)
}

fn validated_relative_path(path: &str) -> anyhow::Result<String> {
    if path.is_empty()
        || path.contains('\\')
        || Path::new(path).is_absolute()
        || path
            .split('/')
            .any(|segment| segment.is_empty() || segment == "." || segment == "..")
    {
        bail!("invalid bundle path: {path}");
    }
    Ok(path.to_string())
}

fn require_empty_output_directory(path: &Path) -> anyhow::Result<()> {
    if path.exists() {
        let mut entries = fs::read_dir(path)
            .with_context(|| format!("read output directory {}", path.display()))?;
        if entries.next().is_some() {
            bail!("backup bundle output directory must be empty");
        }
    } else {
        fs::create_dir_all(path)
            .with_context(|| format!("create output directory {}", path.display()))?;
    }
    Ok(())
}

fn reject_overlapping_paths(source: &Path, output: &Path) -> anyhow::Result<()> {
    let source = fs::canonicalize(source)
        .with_context(|| format!("resolve source path {}", source.display()))?;
    let output = fs::canonicalize(output)
        .with_context(|| format!("resolve output path {}", output.display()))?;
    if source.starts_with(&output) || output.starts_with(&source) {
        bail!("backup bundle output must be outside its input paths");
    }
    Ok(())
}

fn sha256_bytes(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}
