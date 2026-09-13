use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Read, Write};
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
const BUNDLE_SCHEMA_VERSION: u32 = 2;
const BUNDLE_MIN_READABLE_SCHEMA_VERSION: u32 = 1;
const BUNDLE_MANIFEST_FILE: &str = "manifest.json";
const BUNDLE_PAYLOAD_DIR: &str = "payload";
const DATABASE_LOGICAL_PATH: &str = "database.dump";
const OBJECT_STORE_LOGICAL_PREFIX: &str = "object-store/";
const ARGON2_MEMORY_KIB: u32 = 19_456;
const ARGON2_ITERATIONS: u32 = 2;
const ARGON2_PARALLELISM: u32 = 1;
const ARGON2_KEY_BYTES: usize = 32;
const AES_GCM_NONCE_BYTES: usize = 12;
const AES_GCM_CHUNK_NONCE_PREFIX_BYTES: usize = 8;
const BUNDLE_CHUNK_SIZE_BYTES: usize = 1024 * 1024;
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BackupBundleCleanupReport {
    pub deleted_count: usize,
    pub kept_count: usize,
    pub freed_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackupBundleSummary {
    pub path: PathBuf,
    pub created_at: String,
    pub file_count: usize,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    chunk_size_bytes: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    chunk_count: Option<u32>,
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
            let payload_path = format!("{BUNDLE_PAYLOAD_DIR}/{index:08}.bin");
            let payload = write_bundle_payload(
                &source_path,
                &out_dir.join(&payload_path),
                key.as_ref(),
                &logical_path,
            )?;
            total_size_bytes += payload.size_bytes;
            files.push(BundleFile {
                logical_path,
                payload_path,
                size_bytes: payload.size_bytes,
                sha256: payload.sha256,
                stored_size_bytes: payload.stored_size_bytes,
                stored_sha256: payload.stored_sha256,
                nonce_base64: payload.nonce_base64,
                chunk_size_bytes: payload.chunk_size_bytes,
                chunk_count: payload.chunk_count,
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
    let manifest = read_manifest(bundle_dir)?;
    if manifest.schema_version >= 2 {
        let plaintext_verified = process_bundle_files_v2(bundle_dir, &manifest, password, None)?;
        return Ok(BackupBundleVerificationReport {
            file_count: manifest.file_count,
            total_size_bytes: manifest.total_size_bytes,
            encrypted: manifest.encrypted,
            plaintext_verified,
        });
    }
    let (manifest, files) = read_bundle_files_v1(bundle_dir, password)?;
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
    let manifest = read_manifest(bundle_dir)?;
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
        if manifest.schema_version >= 2 {
            process_bundle_files_v2(bundle_dir, &manifest, password, Some(&staging))?;
            fs::rename(&staging, out_dir).context("publish unpacked backup bundle")?;
            return Ok(BackupBundleReport {
                file_count: manifest.file_count,
                total_size_bytes: manifest.total_size_bytes,
                encrypted: manifest.encrypted,
            });
        }
        let (manifest, files) = read_bundle_files_v1(bundle_dir, password)?;
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

pub fn cleanup_backup_bundles(
    root: &Path,
    keep: usize,
) -> anyhow::Result<BackupBundleCleanupReport> {
    if keep == 0 {
        bail!("at least one backup bundle must be retained");
    }
    if !root.is_dir() {
        bail!("backup bundle root is not a directory: {}", root.display());
    }

    let mut bundles = Vec::new();
    for entry in
        fs::read_dir(root).with_context(|| format!("read backup bundle root {}", root.display()))?
    {
        let entry = entry.context("read backup bundle root entry")?;
        let file_type = entry.file_type().context("read backup bundle entry type")?;
        if !file_type.is_dir() || file_type.is_symlink() {
            continue;
        }
        let Ok(manifest) = read_manifest(&entry.path()) else {
            continue;
        };
        let Ok(created_at) = OffsetDateTime::parse(&manifest.created_at, &Rfc3339) else {
            continue;
        };
        bundles.push((created_at, entry.path(), directory_size(&entry.path())?));
    }
    bundles.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| right.1.cmp(&left.1)));
    let kept_count = bundles.len().min(keep);
    let mut deleted_count = 0_usize;
    let mut freed_bytes = 0_u64;
    for (_, path, size_bytes) in bundles.into_iter().skip(keep) {
        fs::remove_dir_all(&path)
            .with_context(|| format!("delete old backup bundle {}", path.display()))?;
        deleted_count += 1;
        freed_bytes += size_bytes;
    }
    Ok(BackupBundleCleanupReport {
        deleted_count,
        kept_count,
        freed_bytes,
    })
}

pub fn find_latest_backup_bundle(root: &Path) -> anyhow::Result<Option<BackupBundleSummary>> {
    if !root.is_dir() {
        return Ok(None);
    }
    let mut bundles = Vec::new();
    for entry in
        fs::read_dir(root).with_context(|| format!("read backup bundle root {}", root.display()))?
    {
        let entry = entry.context("read backup bundle root entry")?;
        let file_type = entry.file_type().context("read backup bundle entry type")?;
        if !file_type.is_dir() || file_type.is_symlink() {
            continue;
        }
        let Ok(manifest) = read_manifest(&entry.path()) else {
            continue;
        };
        let Ok(created_at) = OffsetDateTime::parse(&manifest.created_at, &Rfc3339) else {
            continue;
        };
        bundles.push((
            created_at,
            BackupBundleSummary {
                path: entry.path(),
                created_at: manifest.created_at,
                file_count: manifest.file_count,
            },
        ));
    }
    bundles.sort_by(|left, right| {
        right
            .0
            .cmp(&left.0)
            .then_with(|| right.1.path.cmp(&left.1.path))
    });
    Ok(bundles.into_iter().next().map(|(_, summary)| summary))
}

fn directory_size(root: &Path) -> anyhow::Result<u64> {
    let mut total = 0_u64;
    let mut stack = vec![root.to_path_buf()];
    while let Some(directory) = stack.pop() {
        for entry in fs::read_dir(&directory)
            .with_context(|| format!("read directory {}", directory.display()))?
        {
            let entry = entry.context("read directory entry")?;
            let file_type = entry.file_type().context("read directory entry type")?;
            if file_type.is_symlink() {
                bail!("backup bundle cleanup does not follow symlinks");
            }
            if file_type.is_dir() {
                stack.push(entry.path());
            } else if file_type.is_file() {
                total += entry.metadata().context("read bundle file metadata")?.len();
            }
        }
    }
    Ok(total)
}

fn read_bundle_files_v1(
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
    if manifest.schema_version < BUNDLE_MIN_READABLE_SCHEMA_VERSION
        || manifest.schema_version > BUNDLE_SCHEMA_VERSION
    {
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

struct PayloadWriteMetadata {
    size_bytes: u64,
    sha256: String,
    stored_size_bytes: u64,
    stored_sha256: String,
    nonce_base64: Option<String>,
    chunk_size_bytes: Option<u32>,
    chunk_count: Option<u32>,
}

fn write_bundle_payload(
    source_path: &Path,
    destination_path: &Path,
    key: Option<&[u8; 32]>,
    logical_path: &str,
) -> anyhow::Result<PayloadWriteMetadata> {
    let source =
        File::open(source_path).with_context(|| format!("open input {}", source_path.display()))?;
    let mut reader = BufReader::new(source);
    let destination = File::create(destination_path)
        .with_context(|| format!("create payload {}", destination_path.display()))?;
    let mut writer = BufWriter::new(destination);
    let mut plain_digest = Sha256::new();
    let mut stored_digest = Sha256::new();
    let mut plain_size = 0_u64;
    let mut stored_size = 0_u64;

    if let Some(key) = key {
        let mut nonce_prefix = [0_u8; AES_GCM_CHUNK_NONCE_PREFIX_BYTES];
        OsRng.fill_bytes(&mut nonce_prefix);
        let chunk_size = BUNDLE_CHUNK_SIZE_BYTES;
        let mut buffer = vec![0_u8; chunk_size];
        let mut chunk_count = 0_u32;
        loop {
            let read = read_filled(&mut reader, &mut buffer)?;
            if read == 0 {
                break;
            }
            let plaintext = &buffer[..read];
            let nonce = chunk_nonce(&nonce_prefix, chunk_count);
            let aad = chunk_aad(logical_path, chunk_count);
            let ciphertext = Aes256Gcm::new_from_slice(key)
                .expect("AES-256 key")
                .encrypt(
                    Nonce::from_slice(&nonce),
                    Payload {
                        msg: plaintext,
                        aad: &aad,
                    },
                )
                .map_err(|_| anyhow::anyhow!("encrypt backup bundle file"))?;
            let length = u32::try_from(ciphertext.len())
                .context("encrypted backup chunk exceeds frame size")?;
            writer
                .write_all(&length.to_be_bytes())
                .context("write encrypted backup frame length")?;
            writer
                .write_all(&ciphertext)
                .context("write encrypted backup frame")?;
            stored_digest.update(length.to_be_bytes());
            stored_digest.update(&ciphertext);
            plain_digest.update(plaintext);
            plain_size += read as u64;
            stored_size += 4 + ciphertext.len() as u64;
            chunk_count = chunk_count
                .checked_add(1)
                .context("backup chunk count overflow")?;
        }
        writer.flush().context("flush encrypted backup payload")?;
        return Ok(PayloadWriteMetadata {
            size_bytes: plain_size,
            sha256: hex::encode(plain_digest.finalize()),
            stored_size_bytes: stored_size,
            stored_sha256: hex::encode(stored_digest.finalize()),
            nonce_base64: Some(STANDARD.encode(nonce_prefix)),
            chunk_size_bytes: Some(chunk_size as u32),
            chunk_count: Some(chunk_count),
        });
    }

    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = reader.read(&mut buffer).context("read backup input")?;
        if read == 0 {
            break;
        }
        writer
            .write_all(&buffer[..read])
            .context("write plaintext backup payload")?;
        plain_digest.update(&buffer[..read]);
        stored_digest.update(&buffer[..read]);
        plain_size += read as u64;
        stored_size += read as u64;
    }
    writer.flush().context("flush plaintext backup payload")?;
    let sha256 = hex::encode(plain_digest.finalize());
    Ok(PayloadWriteMetadata {
        size_bytes: plain_size,
        sha256: sha256.clone(),
        stored_size_bytes: stored_size,
        stored_sha256: sha256,
        nonce_base64: None,
        chunk_size_bytes: None,
        chunk_count: None,
    })
}

fn process_bundle_files_v2(
    bundle_dir: &Path,
    manifest: &BackupBundleManifest,
    password: Option<&str>,
    output_dir: Option<&Path>,
) -> anyhow::Result<bool> {
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
    if manifest.encrypted && output_dir.is_some() && key.is_none() {
        bail!("backup bundle password is required");
    }

    let mut logical_paths = HashSet::new();
    let mut payload_paths = HashSet::new();
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
        let payload = File::open(bundle_dir.join(&payload_path))
            .with_context(|| format!("read bundle payload {}", file.payload_path))?;
        let mut reader = BufReader::new(payload);
        if let Some(output_dir) = output_dir {
            let output_path = output_dir.join(&logical_path);
            if let Some(parent) = output_path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("create unpack directory {}", parent.display()))?;
            }
            let output = File::create(&output_path)
                .with_context(|| format!("create unpacked file {}", output_path.display()))?;
            let mut writer = BufWriter::new(output);
            process_bundle_file_v2(
                &mut reader,
                key.as_ref(),
                manifest.encrypted,
                file,
                &logical_path,
                Some(&mut writer),
            )?;
            writer.flush().context("flush unpacked bundle file")?;
        } else {
            process_bundle_file_v2(
                &mut reader,
                key.as_ref(),
                manifest.encrypted,
                file,
                &logical_path,
                None,
            )?;
        }
        total_size_bytes += file.size_bytes;
    }
    if total_size_bytes != manifest.total_size_bytes {
        bail!("backup bundle total size mismatch");
    }
    Ok(!manifest.encrypted || key.is_some())
}

fn process_bundle_file_v2(
    reader: &mut impl Read,
    key: Option<&[u8; 32]>,
    encrypted: bool,
    file: &BundleFile,
    logical_path: &str,
    mut writer: Option<&mut dyn Write>,
) -> anyhow::Result<()> {
    let mut stored_digest = Sha256::new();
    let mut plain_digest = Sha256::new();
    let mut stored_size = 0_u64;
    let mut plain_size = 0_u64;

    if encrypted {
        let chunk_size = file
            .chunk_size_bytes
            .context("encrypted bundle is missing chunk size")? as usize;
        let chunk_count = file
            .chunk_count
            .context("encrypted bundle is missing chunk count")?;
        let nonce_raw = file
            .nonce_base64
            .as_ref()
            .context("encrypted bundle file is missing nonce")?;
        let nonce_prefix = STANDARD.decode(nonce_raw).context("decode bundle nonce")?;
        if nonce_prefix.len() != AES_GCM_CHUNK_NONCE_PREFIX_BYTES {
            bail!("invalid bundle nonce length");
        }
        if chunk_size == 0 {
            bail!("invalid backup chunk size");
        }
        for index in 0..chunk_count {
            let mut length = [0_u8; 4];
            reader
                .read_exact(&mut length)
                .context("read encrypted backup frame length")?;
            stored_digest.update(length);
            stored_size += 4;
            let length = u32::from_be_bytes(length) as usize;
            if length < 16 {
                bail!("invalid encrypted backup frame length");
            }
            let plaintext_length = length - 16;
            if index + 1 < chunk_count && plaintext_length != chunk_size {
                bail!("non-final backup chunk has invalid length");
            }
            if plaintext_length > chunk_size {
                bail!("backup chunk exceeds configured size");
            }
            let mut ciphertext = vec![0_u8; length];
            reader
                .read_exact(&mut ciphertext)
                .context("read encrypted backup frame")?;
            stored_digest.update(&ciphertext);
            stored_size += length as u64;
            plain_size += plaintext_length as u64;
            if let Some(key) = key {
                let nonce = chunk_nonce_from_slice(&nonce_prefix, index)?;
                let aad = chunk_aad(logical_path, index);
                let plaintext = Aes256Gcm::new_from_slice(key)
                    .expect("AES-256 key")
                    .decrypt(
                        Nonce::from_slice(&nonce),
                        Payload {
                            msg: &ciphertext,
                            aad: &aad,
                        },
                    )
                    .map_err(|_| anyhow::anyhow!("invalid bundle password or corrupted payload"))?;
                if plaintext.len() != plaintext_length {
                    bail!("decrypted backup chunk length mismatch");
                }
                plain_digest.update(&plaintext);
                if let Some(writer) = writer.as_deref_mut() {
                    writer
                        .write_all(&plaintext)
                        .context("write decrypted backup chunk")?;
                }
            }
        }
        let mut trailing = [0_u8; 1];
        if reader
            .read(&mut trailing)
            .context("read backup payload end")?
            != 0
        {
            bail!("encrypted backup payload has trailing bytes");
        }
    } else {
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let read = reader.read(&mut buffer).context("read plaintext payload")?;
            if read == 0 {
                break;
            }
            plain_digest.update(&buffer[..read]);
            stored_digest.update(&buffer[..read]);
            plain_size += read as u64;
            stored_size += read as u64;
            if let Some(writer) = writer.as_deref_mut() {
                writer
                    .write_all(&buffer[..read])
                    .context("write plaintext payload")?;
            }
        }
    }

    if stored_size != file.stored_size_bytes
        || hex::encode(stored_digest.finalize()) != file.stored_sha256
    {
        bail!("stored payload integrity failed: {}", file.logical_path);
    }
    if plain_size != file.size_bytes {
        bail!("plaintext payload size failed: {}", file.logical_path);
    }
    if (!encrypted || key.is_some()) && hex::encode(plain_digest.finalize()) != file.sha256 {
        bail!("plaintext payload integrity failed: {}", file.logical_path);
    }
    Ok(())
}

fn read_filled(reader: &mut impl Read, buffer: &mut [u8]) -> anyhow::Result<usize> {
    let mut total = 0;
    while total < buffer.len() {
        let read = reader.read(&mut buffer[total..])?;
        if read == 0 {
            break;
        }
        total += read;
    }
    Ok(total)
}

fn chunk_nonce(prefix: &[u8; AES_GCM_CHUNK_NONCE_PREFIX_BYTES], index: u32) -> [u8; 12] {
    let mut nonce = [0_u8; AES_GCM_NONCE_BYTES];
    nonce[..AES_GCM_CHUNK_NONCE_PREFIX_BYTES].copy_from_slice(prefix);
    nonce[AES_GCM_CHUNK_NONCE_PREFIX_BYTES..].copy_from_slice(&index.to_be_bytes());
    nonce
}

fn chunk_nonce_from_slice(prefix: &[u8], index: u32) -> anyhow::Result<[u8; AES_GCM_NONCE_BYTES]> {
    if prefix.len() != AES_GCM_CHUNK_NONCE_PREFIX_BYTES {
        bail!("invalid bundle nonce prefix");
    }
    let mut prefix_bytes = [0_u8; AES_GCM_CHUNK_NONCE_PREFIX_BYTES];
    prefix_bytes.copy_from_slice(prefix);
    Ok(chunk_nonce(&prefix_bytes, index))
}

fn chunk_aad(logical_path: &str, index: u32) -> Vec<u8> {
    let mut aad = Vec::with_capacity(logical_path.len() + 1 + 4);
    aad.extend_from_slice(logical_path.as_bytes());
    aad.push(0);
    aad.extend_from_slice(&index.to_be_bytes());
    aad
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
