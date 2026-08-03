use std::env;
use std::path::PathBuf;

use ed25519_dalek::pkcs8::{EncodePrivateKey, EncodePublicKey};
use ed25519_dalek::SigningKey;
use jsonwebtoken::{DecodingKey, EncodingKey};
use sha2::{Digest, Sha256};

#[derive(Clone)]
pub struct Config {
    pub listen_addr: String,
    pub database_url: Option<String>,
    /// Legacy env name kept as seed material for Ed25519 when JWT_ED25519_SEED unset.
    pub jwt_secret: String,
    pub jwt_ed25519_seed: Option<String>,
    pub object_store_dir: PathBuf,
    pub object_store_hmac_secret: String,
    pub object_store_public_base: String,
    pub rate_limit_rps: u32,
    pub auth_rate_limit_rps: u32,
    pub cors_allowed_origins: Vec<String>,
    pub auth_cookie_secure: bool,
    pub otel_endpoint: Option<String>,
    pub is_production: bool,
    pub jwt_encoding_key: EncodingKey,
    pub jwt_decoding_key: DecodingKey,
}

impl std::fmt::Debug for Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Config")
            .field("listen_addr", &self.listen_addr)
            .field("database_url", &self.database_url.as_ref().map(|_| "***"))
            .field("object_store_dir", &self.object_store_dir)
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
        let config = Self {
            listen_addr: env::var("LEDGER_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            database_url: env::var("DATABASE_URL").ok(),
            jwt_secret,
            jwt_ed25519_seed,
            object_store_dir: PathBuf::from(
                env::var("OBJECT_STORE_DIR").unwrap_or_else(|_| "/tmp/ledgerly-objects".into()),
            ),
            object_store_hmac_secret: env::var("OBJECT_STORE_HMAC_SECRET")
                .unwrap_or_else(|_| "dev-object-hmac-secret".into()),
            object_store_public_base: env::var("OBJECT_STORE_PUBLIC_BASE")
                .unwrap_or_else(|_| "http://127.0.0.1:8080".into()),
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
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
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
            object_store_dir: std::env::temp_dir()
                .join(format!("ledgerly-test-{}", uuid::Uuid::now_v7())),
            object_store_hmac_secret: "test-hmac".into(),
            object_store_public_base: "http://127.0.0.1:0".into(),
            rate_limit_rps: 10_000,
            auth_rate_limit_rps: 10_000,
            cors_allowed_origins: Vec::new(),
            auth_cookie_secure: false,
            otel_endpoint: None,
            is_production: false,
            jwt_encoding_key: encoding,
            jwt_decoding_key: decoding,
        }
    }
}

fn parse_bool(name: &str, value: &str) -> anyhow::Result<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" | "1" => Ok(true),
        "false" | "0" => Ok(false),
        _ => anyhow::bail!("{name} must be true or false"),
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
    use super::{parse_origins, Config};

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
}
