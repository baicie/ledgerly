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
    pub fn from_env() -> Self {
        let jwt_secret =
            env::var("JWT_SECRET").unwrap_or_else(|_| "dev-only-change-me-ledgerly-secret".into());
        let jwt_ed25519_seed = env::var("JWT_ED25519_SEED").ok();
        let (encoding, decoding) = build_ed25519_keys(&jwt_secret, jwt_ed25519_seed.as_deref());
        Self {
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
            otel_endpoint: env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok(),
            is_production: env::var("LEDGER_ENV").ok().as_deref() == Some("production"),
            jwt_encoding_key: encoding,
            jwt_decoding_key: decoding,
        }
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
            otel_endpoint: None,
            is_production: false,
            jwt_encoding_key: encoding,
            jwt_decoding_key: decoding,
        }
    }
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
