use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub listen_addr: String,
    pub database_url: Option<String>,
    pub jwt_secret: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            listen_addr: env::var("LEDGER_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            database_url: env::var("DATABASE_URL").ok(),
            jwt_secret: env::var("JWT_SECRET")
                .unwrap_or_else(|_| "dev-only-change-me-ledgerly-secret".into()),
        }
    }
}
