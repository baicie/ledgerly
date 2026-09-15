use std::env;
use std::path::PathBuf;

use ed25519_dalek::pkcs8::{EncodePrivateKey, EncodePublicKey};
use ed25519_dalek::SigningKey;
use jsonwebtoken::{DecodingKey, EncodingKey};
use sha2::{Digest, Sha256};

const DEFAULT_BACKUP_CAPACITY_WARN_BYTES: u64 = 20 * 1024 * 1024 * 1024;
const DEFAULT_BACKUP_CAPACITY_CRITICAL_BYTES: u64 = 50 * 1024 * 1024 * 1024;
const MAX_ATTACHMENT_BYTES: u64 = 20 * 1024 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectStoreBackend {
    Local,
    S3,
}

#[derive(Clone)]
pub struct Config {
    pub listen_addr: String,
    pub database_url: Option<String>,
    /// Legacy env name kept as seed material for Ed25519 when JWT_ED25519_SEED unset.
    pub jwt_secret: String,
    pub jwt_ed25519_seed: Option<String>,
    pub jwt_previous_ed25519_seed: Option<String>,
    pub object_store_dir: PathBuf,
    pub object_store_hmac_secret: String,
    pub object_store_hmac_previous_secret: Option<String>,
    pub object_store_public_base: String,
    pub object_storage_backend: ObjectStoreBackend,
    pub s3_endpoint: Option<String>,
    pub s3_region: String,
    pub s3_bucket: Option<String>,
    pub s3_access_key_id: Option<String>,
    pub s3_secret_access_key: Option<String>,
    pub s3_session_token: Option<String>,
    pub s3_prefix: Option<String>,
    pub s3_force_path_style: bool,
    pub s3_allow_http: bool,
    pub s3_public_endpoint: Option<String>,
    pub attachment_max_bytes: u64,
    pub attachment_pending_ttl_hours: u64,
    pub backup_dir: Option<PathBuf>,
    pub backup_offsite_dir: Option<PathBuf>,
    pub backup_keep: usize,
    pub backup_interval_hours: u64,
    pub backup_password: Option<String>,
    pub backup_password_previous: Option<String>,
    pub backup_capacity_warn_bytes: u64,
    pub backup_capacity_critical_bytes: u64,
    pub audit_retention_days: u64,
    pub recovery_drill_enabled: bool,
    pub recovery_drill_interval_hours: u64,
    pub recovery_drill_database_url: Option<String>,
    pub rate_limit_rps: u32,
    pub auth_rate_limit_rps: u32,
    pub cors_allowed_origins: Vec<String>,
    pub auth_cookie_secure: bool,
    pub otel_endpoint: Option<String>,
    pub is_production: bool,
    pub jwt_encoding_key: EncodingKey,
    pub jwt_decoding_key: DecodingKey,
    pub jwt_previous_decoding_key: Option<DecodingKey>,
}

const _: fn() = || {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<Config>();
};

impl std::fmt::Debug for Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Config")
            .field("listen_addr", &self.listen_addr)
            .field("database_url", &self.database_url.as_ref().map(|_| "***"))
            .field("object_store_dir", &self.object_store_dir)
            .field("object_storage_backend", &self.object_storage_backend)
            .field("rate_limit_rps", &self.rate_limit_rps)
            .field("is_production", &self.is_production)
            .finish_non_exhaustive()
    }
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let is_production = env::var("LEDGER_ENV").ok().as_deref() == Some("production");
        let jwt_secret =
            env::var("JWT_SECRET").unwrap_or_else(|_| "dev-only-change-me-ledgerly-secret".into());
        let jwt_ed25519_seed = env::var("JWT_ED25519_SEED").ok();
        let (encoding, decoding) = build_ed25519_keys(&jwt_secret, jwt_ed25519_seed.as_deref());
        let jwt_previous_ed25519_seed = env::var("JWT_ED25519_PREVIOUS_SEED")
            .ok()
            .filter(|seed| !seed.is_empty());
        let jwt_previous_decoding_key = jwt_previous_ed25519_seed
            .as_deref()
            .map(|seed| build_ed25519_keys(&jwt_secret, Some(seed)).1);
        let config = Self {
            listen_addr: env::var("LEDGER_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            database_url: env::var("DATABASE_URL").ok(),
            jwt_secret,
            jwt_ed25519_seed,
            jwt_previous_ed25519_seed,
            object_store_dir: PathBuf::from(
                env::var("OBJECT_STORE_DIR").unwrap_or_else(|_| "/tmp/ledgerly-objects".into()),
            ),
            object_store_hmac_secret: env::var("OBJECT_STORE_HMAC_SECRET")
                .unwrap_or_else(|_| "dev-object-hmac-secret".into()),
            object_store_hmac_previous_secret: env::var("OBJECT_STORE_HMAC_PREVIOUS_SECRET")
                .ok()
                .filter(|secret| !secret.is_empty()),
            object_store_public_base: env::var("OBJECT_STORE_PUBLIC_BASE")
                .unwrap_or_else(|_| "http://127.0.0.1:8080".into()),
            object_storage_backend: parse_object_store_backend(
                &env::var("OBJECT_STORE_BACKEND").unwrap_or_else(|_| "local".into()),
            )?,
            s3_endpoint: env::var("S3_ENDPOINT")
                .ok()
                .filter(|value| !value.is_empty()),
            s3_region: env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".into()),
            s3_bucket: env::var("S3_BUCKET").ok().filter(|value| !value.is_empty()),
            s3_access_key_id: env::var("S3_ACCESS_KEY_ID")
                .ok()
                .filter(|value| !value.is_empty()),
            s3_secret_access_key: env::var("S3_SECRET_ACCESS_KEY")
                .ok()
                .filter(|value| !value.is_empty()),
            s3_session_token: env::var("S3_SESSION_TOKEN")
                .ok()
                .filter(|value| !value.is_empty()),
            s3_prefix: env::var("S3_PREFIX").ok().filter(|value| !value.is_empty()),
            s3_force_path_style: env::var("S3_FORCE_PATH_STYLE")
                .ok()
                .map(|value| parse_bool("S3_FORCE_PATH_STYLE", &value))
                .transpose()?
                .unwrap_or(true),
            s3_allow_http: env::var("S3_ALLOW_HTTP")
                .ok()
                .map(|value| parse_bool("S3_ALLOW_HTTP", &value))
                .transpose()?
                .unwrap_or(false),
            s3_public_endpoint: env::var("S3_PUBLIC_ENDPOINT")
                .ok()
                .filter(|value| !value.is_empty()),
            attachment_max_bytes: parse_positive_u64_env(
                "ATTACHMENT_MAX_BYTES",
                100 * 1024 * 1024,
            )?,
            attachment_pending_ttl_hours: parse_positive_u64_env(
                "ATTACHMENT_PENDING_TTL_HOURS",
                24,
            )?,
            backup_dir: env::var("BACKUP_DIR").ok().map(PathBuf::from),
            backup_offsite_dir: env::var("BACKUP_OFFSITE_DIR").ok().map(PathBuf::from),
            backup_keep: env::var("BACKUP_KEEP")
                .ok()
                .and_then(|value| value.parse().ok())
                .filter(|keep| *keep > 0)
                .unwrap_or(3),
            backup_interval_hours: env::var("BACKUP_INTERVAL_HOURS")
                .ok()
                .and_then(|value| value.parse().ok())
                .filter(|hours| *hours > 0)
                .unwrap_or(24),
            backup_password: env::var("LEDGER_BACKUP_PASSWORD")
                .ok()
                .filter(|password| !password.is_empty()),
            backup_password_previous: env::var("LEDGER_BACKUP_PASSWORD_PREVIOUS")
                .ok()
                .filter(|password| !password.is_empty()),
            backup_capacity_warn_bytes: parse_positive_u64_env(
                "BACKUP_CAPACITY_WARN_BYTES",
                DEFAULT_BACKUP_CAPACITY_WARN_BYTES,
            )?,
            backup_capacity_critical_bytes: parse_positive_u64_env(
                "BACKUP_CAPACITY_CRITICAL_BYTES",
                DEFAULT_BACKUP_CAPACITY_CRITICAL_BYTES,
            )?,
            audit_retention_days: parse_positive_u64_env("AUDIT_RETENTION_DAYS", 365)?,
            recovery_drill_enabled: env::var("RECOVERY_DRILL_ENABLED")
                .ok()
                .map(|value| parse_bool("RECOVERY_DRILL_ENABLED", &value))
                .transpose()?
                .unwrap_or(false),
            recovery_drill_interval_hours: env::var("RECOVERY_DRILL_INTERVAL_HOURS")
                .ok()
                .and_then(|value| value.parse().ok())
                .filter(|hours| *hours > 0)
                .unwrap_or(720),
            recovery_drill_database_url: env::var("RECOVERY_DRILL_DATABASE_URL")
                .ok()
                .filter(|url| !url.is_empty()),
            rate_limit_rps: env::var("RATE_LIMIT_RPS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(100),
            auth_rate_limit_rps: env::var("AUTH_RATE_LIMIT_RPS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(20),
            cors_allowed_origins: parse_origins(
                &env::var("CORS_ALLOWED_ORIGINS").unwrap_or_default(),
            )?,
            auth_cookie_secure: env::var("AUTH_COOKIE_SECURE")
                .ok()
                .map(|value| parse_bool("AUTH_COOKIE_SECURE", &value))
                .transpose()?
                .unwrap_or(is_production),
            otel_endpoint: env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok(),
            is_production,
            jwt_encoding_key: encoding,
            jwt_decoding_key: decoding,
            jwt_previous_decoding_key,
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        if self.attachment_max_bytes > MAX_ATTACHMENT_BYTES {
            anyhow::bail!("ATTACHMENT_MAX_BYTES must not exceed 20 GiB");
        }
        if self.backup_capacity_warn_bytes == 0
            || self.backup_capacity_critical_bytes == 0
            || self.backup_capacity_critical_bytes < self.backup_capacity_warn_bytes
        {
            anyhow::bail!(
                "BACKUP_CAPACITY_CRITICAL_BYTES must be greater than or equal to \
                 BACKUP_CAPACITY_WARN_BYTES, and both values must be positive"
            );
        }
        if self.object_storage_backend == ObjectStoreBackend::S3 {
            self.validate_s3()?;
        }
        if !self.is_production {
            return Ok(());
        }
        if self.database_url.is_none() {
            anyhow::bail!("DATABASE_URL is required in production");
        }
        if self.jwt_secret == "dev-only-change-me-ledgerly-secret"
            || self.jwt_secret.contains("CHANGE_ME")
        {
            anyhow::bail!("JWT_SECRET must be replaced in production");
        }
        let Some(seed) = self.jwt_ed25519_seed.as_deref() else {
            anyhow::bail!("JWT_ED25519_SEED is required in production");
        };
        if seed.is_empty() || seed.contains("CHANGE_ME") {
            anyhow::bail!("JWT_ED25519_SEED must be replaced in production");
        }
        if self
            .jwt_previous_ed25519_seed
            .as_deref()
            .is_some_and(|seed| seed.contains("CHANGE_ME"))
        {
            anyhow::bail!("JWT_ED25519_PREVIOUS_SEED must be replaced in production");
        }
        if self.object_store_hmac_secret.is_empty()
            || self.object_store_hmac_secret.contains("CHANGE_ME")
            || self.object_store_hmac_secret == "dev-object-hmac-secret"
        {
            anyhow::bail!("OBJECT_STORE_HMAC_SECRET must be replaced in production");
        }
        if !self.auth_cookie_secure {
            anyhow::bail!("AUTH_COOKIE_SECURE must be true in production");
        }
        if self.cors_allowed_origins.is_empty() {
            anyhow::bail!("CORS_ALLOWED_ORIGINS requires at least one HTTPS origin in production");
        }
        if self
            .cors_allowed_origins
            .iter()
            .any(|origin| !origin.starts_with("https://"))
        {
            anyhow::bail!("CORS_ALLOWED_ORIGINS must contain only HTTPS origins in production");
        }
        if self.backup_dir.is_some() && self.backup_password.is_none() {
            anyhow::bail!("LEDGER_BACKUP_PASSWORD is required when BACKUP_DIR is configured");
        }
        if self.recovery_drill_enabled && self.backup_dir.is_none() {
            anyhow::bail!("BACKUP_DIR is required when RECOVERY_DRILL_ENABLED=true");
        }
        Ok(())
    }

    /// Test helper with fixed keys/dirs.
    pub fn for_test() -> Self {
        let jwt_secret = "test-secret".to_string();
        let (encoding, decoding) = build_ed25519_keys(&jwt_secret, Some("test-ed25519-seed"));
        Self {
            listen_addr: "127.0.0.1:0".into(),
            database_url: None,
            jwt_secret,
            jwt_ed25519_seed: Some("test-ed25519-seed".into()),
            jwt_previous_ed25519_seed: None,
            object_store_dir: std::env::temp_dir()
                .join(format!("ledgerly-test-{}", uuid::Uuid::now_v7())),
            object_store_hmac_secret: "test-hmac".into(),
            object_store_hmac_previous_secret: None,
            object_store_public_base: "http://127.0.0.1:0".into(),
            object_storage_backend: ObjectStoreBackend::Local,
            s3_endpoint: None,
            s3_region: "us-east-1".into(),
            s3_bucket: None,
            s3_access_key_id: None,
            s3_secret_access_key: None,
            s3_session_token: None,
            s3_prefix: None,
            s3_force_path_style: true,
            s3_allow_http: false,
            s3_public_endpoint: None,
            attachment_max_bytes: 100 * 1024 * 1024,
            attachment_pending_ttl_hours: 24,
            backup_dir: None,
            backup_offsite_dir: None,
            backup_keep: 3,
            backup_interval_hours: 24,
            backup_password: None,
            backup_password_previous: None,
            backup_capacity_warn_bytes: DEFAULT_BACKUP_CAPACITY_WARN_BYTES,
            backup_capacity_critical_bytes: DEFAULT_BACKUP_CAPACITY_CRITICAL_BYTES,
            audit_retention_days: 365,
            recovery_drill_enabled: false,
            recovery_drill_interval_hours: 720,
            recovery_drill_database_url: None,
            rate_limit_rps: 10_000,
            auth_rate_limit_rps: 10_000,
            cors_allowed_origins: Vec::new(),
            auth_cookie_secure: false,
            otel_endpoint: None,
            is_production: false,
            jwt_encoding_key: encoding,
            jwt_decoding_key: decoding,
            jwt_previous_decoding_key: None,
        }
    }

    pub fn for_test_with_jwt_seed(seed: &str) -> Self {
        let mut config = Self::for_test();
        let (encoding, decoding) = build_ed25519_keys(&config.jwt_secret, Some(seed));
        config.jwt_ed25519_seed = Some(seed.to_string());
        config.jwt_encoding_key = encoding;
        config.jwt_decoding_key = decoding;
        config
    }

    fn validate_s3(&self) -> anyhow::Result<()> {
        if self.s3_bucket.as_deref().unwrap_or_default().is_empty() {
            anyhow::bail!("S3_BUCKET is required when OBJECT_STORE_BACKEND=s3");
        }
        if self
            .s3_access_key_id
            .as_deref()
            .unwrap_or_default()
            .is_empty()
            || self
                .s3_secret_access_key
                .as_deref()
                .unwrap_or_default()
                .is_empty()
        {
            anyhow::bail!(
                "S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY are required when OBJECT_STORE_BACKEND=s3"
            );
        }
        if let Some(prefix) = self.s3_prefix.as_deref() {
            if prefix.trim().is_empty()
                || prefix.starts_with('/')
                || prefix.ends_with('/')
                || prefix
                    .split('/')
                    .any(|segment| segment.is_empty() || segment == "." || segment == "..")
            {
                anyhow::bail!("S3_PREFIX must be a non-empty relative object prefix");
            }
        }
        if let Some(endpoint) = self.s3_endpoint.as_deref() {
            let url = url::Url::parse(endpoint)
                .map_err(|_| anyhow::anyhow!("S3_ENDPOINT must be a valid URL"))?;
            if !matches!(url.scheme(), "http" | "https")
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
                || url.query().is_some()
                || url.fragment().is_some()
            {
                anyhow::bail!("S3_ENDPOINT must be an HTTP(S) URL without credentials or query");
            }
            if url.scheme() == "http" && !self.s3_allow_http {
                anyhow::bail!("S3_ALLOW_HTTP=true is required for an HTTP S3 endpoint");
            }
        }
        if let Some(endpoint) = self.s3_public_endpoint.as_deref() {
            let url = url::Url::parse(endpoint)
                .map_err(|_| anyhow::anyhow!("S3_PUBLIC_ENDPOINT must be a valid URL"))?;
            if !matches!(url.scheme(), "http" | "https")
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
                || url.query().is_some()
                || url.fragment().is_some()
            {
                anyhow::bail!(
                    "S3_PUBLIC_ENDPOINT must be an HTTP(S) URL without credentials or query"
                );
            }
            if url.scheme() == "http" && !self.s3_allow_http {
                anyhow::bail!("S3_ALLOW_HTTP=true is required for an HTTP public S3 endpoint");
            }
        }
        Ok(())
    }
}

fn parse_bool(name: &str, value: &str) -> anyhow::Result<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" => Ok(true),
        "false" | "0" => Ok(false),
        _ => anyhow::bail!("{name} must be true or false"),
    }
}

fn parse_positive_u64_env(name: &str, default: u64) -> anyhow::Result<u64> {
    let Ok(value) = env::var(name) else {
        return Ok(default);
    };
    let value = value
        .trim()
        .parse::<u64>()
        .map_err(|_| anyhow::anyhow!("{name} must be a positive integer"))?;
    if value == 0 {
        anyhow::bail!("{name} must be greater than zero");
    }
    Ok(value)
}

fn parse_object_store_backend(value: &str) -> anyhow::Result<ObjectStoreBackend> {
    match value.trim().to_ascii_lowercase().as_str() {
        "local" => Ok(ObjectStoreBackend::Local),
        "s3" => Ok(ObjectStoreBackend::S3),
        _ => anyhow::bail!("OBJECT_STORE_BACKEND must be local or s3"),
    }
}

fn parse_origins(value: &str) -> anyhow::Result<Vec<String>> {
    value
        .split(',')
        .map(str::trim)
        .filter(|origin| !origin.is_empty())
        .map(|origin| {
            let url = url::Url::parse(origin)
                .map_err(|_| anyhow::anyhow!("invalid CORS origin: {origin}"))?;
            if !matches!(url.scheme(), "http" | "https")
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
                || url.query().is_some()
                || url.fragment().is_some()
                || url.path() != "/"
            {
                anyhow::bail!("CORS origin must be an HTTP(S) origin without path: {origin}");
            }
            Ok(url.origin().ascii_serialization())
        })
        .collect()
}

fn build_ed25519_keys(jwt_secret: &str, seed_override: Option<&str>) -> (EncodingKey, DecodingKey) {
    let material = seed_override.unwrap_or(jwt_secret);
    let mut hasher = Sha256::new();
    hasher.update(material.as_bytes());
    let digest = hasher.finalize();
    let mut seed = [0u8; 32];
    seed.copy_from_slice(&digest[..32]);
    let signing = SigningKey::from_bytes(&seed);
    let verifying = signing.verifying_key();
    let private_pem = signing
        .to_pkcs8_pem(Default::default())
        .expect("ed25519 pkcs8 pem")
        .to_string();
    let public_pem = verifying
        .to_public_key_pem(Default::default())
        .expect("ed25519 public pem");
    let encoding = EncodingKey::from_ed_pem(private_pem.as_bytes()).expect("encoding key");
    let decoding = DecodingKey::from_ed_pem(public_pem.as_bytes()).expect("decoding key");
    (encoding, decoding)
}

#[cfg(test)]
mod tests {
    use super::{parse_origins, Config, ObjectStoreBackend};

    #[test]
    fn cors_origins_are_normalized_and_reject_paths() {
        assert_eq!(
            parse_origins("https://app.example:8443, http://localhost:3000").unwrap(),
            vec![
                "https://app.example:8443".to_string(),
                "http://localhost:3000".to_string()
            ]
        );
        assert!(parse_origins("https://app.example/auth").is_err());
        assert!(parse_origins("https://user@app.example").is_err());
    }

    #[test]
    fn production_validation_rejects_default_secrets() {
        let mut config = Config::for_test();
        config.is_production = true;
        config.database_url = Some("postgres://ledgerly:test@db/ledgerly".into());
        config.jwt_secret = "dev-only-change-me-ledgerly-secret".into();
        config.object_store_hmac_secret = "dev-object-hmac-secret".into();

        assert!(config.validate().is_err());
    }

    #[test]
    fn production_validation_accepts_explicit_secrets() {
        let mut config = Config::for_test();
        config.is_production = true;
        config.database_url = Some("postgres://ledgerly:test@db/ledgerly".into());
        config.jwt_secret = "a-long-random-jwt-secret".into();
        config.jwt_ed25519_seed = Some("a-long-random-ed25519-seed".into());
        config.object_store_hmac_secret = "a-long-random-hmac-secret".into();
        config.cors_allowed_origins = vec!["https://app.ledgerly.example".into()];
        config.auth_cookie_secure = true;

        assert!(config.validate().is_ok());
    }

    #[test]
    fn production_validation_rejects_insecure_cookie_origin() {
        let mut config = Config::for_test();
        config.is_production = true;
        config.database_url = Some("postgres://ledgerly:test@db/ledgerly".into());
        config.jwt_secret = "a-long-random-jwt-secret".into();
        config.jwt_ed25519_seed = Some("a-long-random-ed25519-seed".into());
        config.object_store_hmac_secret = "a-long-random-hmac-secret".into();
        config.cors_allowed_origins = vec!["http://app.ledgerly.example".into()];
        config.auth_cookie_secure = false;

        assert!(config.validate().is_err());
    }

    #[test]
    fn production_validation_requires_backup_password() {
        let mut config = Config::for_test();
        config.is_production = true;
        config.database_url = Some("postgres://ledgerly:test@db/ledgerly".into());
        config.jwt_secret = "a-long-random-jwt-secret".into();
        config.jwt_ed25519_seed = Some("a-long-random-ed25519-seed".into());
        config.object_store_hmac_secret = "a-long-random-hmac-secret".into();
        config.cors_allowed_origins = vec!["https://app.ledgerly.example".into()];
        config.auth_cookie_secure = true;
        config.backup_dir = Some(std::path::PathBuf::from("/var/lib/ledgerly-backups"));

        assert!(config.validate().is_err());
    }

    #[test]
    fn backup_capacity_thresholds_must_be_ordered() {
        let mut config = Config::for_test();
        config.backup_capacity_warn_bytes = 2_000;
        config.backup_capacity_critical_bytes = 1_000;

        assert!(config.validate().is_err());
    }

    #[test]
    fn s3_storage_requires_credentials_bucket_and_http_opt_in() {
        let mut config = Config::for_test();
        config.object_storage_backend = ObjectStoreBackend::S3;
        assert!(config.validate().is_err());

        config.s3_bucket = Some("ledgerly".into());
        config.s3_access_key_id = Some("test-access".into());
        config.s3_secret_access_key = Some("test-secret".into());
        config.s3_endpoint = Some("http://127.0.0.1:9000".into());
        assert!(config.validate().is_err());

        config.s3_allow_http = true;
        config.s3_prefix = Some("production/ledgerly".into());
        assert!(config.validate().is_ok());
    }

    #[test]
    fn s3_prefix_rejects_path_traversal() {
        let mut config = Config::for_test();
        config.object_storage_backend = ObjectStoreBackend::S3;
        config.s3_bucket = Some("ledgerly".into());
        config.s3_access_key_id = Some("test-access".into());
        config.s3_secret_access_key = Some("test-secret".into());
        config.s3_prefix = Some("../objects".into());

        assert!(config.validate().is_err());
    }

    #[test]
    fn s3_public_endpoint_requires_clean_http_url() {
        let mut config = Config::for_test();
        config.object_storage_backend = ObjectStoreBackend::S3;
        config.s3_bucket = Some("ledgerly".into());
        config.s3_access_key_id = Some("test-access".into());
        config.s3_secret_access_key = Some("test-secret".into());
        config.s3_public_endpoint = Some("https://objects.example.com?token=secret".into());

        assert!(config.validate().is_err());

        config.s3_public_endpoint = Some("https://objects.example.com".into());
        assert!(config.validate().is_ok());

        config.s3_public_endpoint = Some("http://127.0.0.1:9000".into());
        assert!(config.validate().is_err());
    }

    #[test]
    fn attachment_max_bytes_stays_within_multipart_limit() {
        let mut config = Config::for_test();
        config.attachment_max_bytes = 20 * 1024 * 1024 * 1024 + 1;

        assert!(config.validate().is_err());

        config.attachment_max_bytes = 20 * 1024 * 1024 * 1024;
        assert!(config.validate().is_ok());
    }
}
