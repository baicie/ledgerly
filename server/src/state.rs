use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value;
use sqlx::PgPool;
use tokio::sync::RwLock;

use crate::config::Config;
use crate::infrastructure::postgres;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub store: Arc<RwLock<MemoryStore>>,
    pub pool: Option<PgPool>,
}

#[derive(Default)]
pub struct MemoryStore {
    pub users: HashMap<String, UserRecord>,
    pub users_by_email: HashMap<String, String>,
    pub sessions: HashMap<String, SessionRecord>,
    pub refresh_to_session: HashMap<String, String>,
    pub books: HashMap<String, BookRecord>,
    pub accounts: HashMap<String, AccountRecord>,
    pub transactions: HashMap<String, TxRecord>,
    pub mutations: HashMap<(String, String, String), MutationReceipt>,
    pub changes: Vec<ChangeRecord>,
}

#[derive(Clone)]
pub struct UserRecord {
    pub id: String,
    pub email: String,
    pub password_hash: String,
    pub display_name: String,
}

#[derive(Clone)]
pub struct SessionRecord {
    pub id: String,
    pub user_id: String,
    pub device_id: String,
    pub refresh_hash: String,
    pub revoked: bool,
}

#[derive(Clone)]
pub struct BookRecord {
    pub id: String,
    pub name: String,
    pub owner_id: String,
}

#[derive(Clone)]
pub struct AccountRecord {
    pub id: String,
    pub book_id: String,
    pub name: String,
    pub account_type: String,
    pub currency: String,
    pub version: i64,
}

#[derive(Clone)]
pub struct TxRecord {
    pub id: String,
    pub book_id: String,
    pub description: Option<String>,
    pub version: i64,
    pub entries: Vec<(String, i64, String)>,
}

#[derive(Clone)]
pub struct MutationReceipt {
    pub status: String,
    pub result_code: String,
    pub entity_version: Option<i64>,
}

#[derive(Clone)]
pub struct ChangeRecord {
    pub sequence: i64,
    pub book_id: String,
    pub commit_id: String,
    pub entity_type: String,
    pub entity_id: String,
    pub operation: String,
    pub entity_version: i64,
    pub payload: Value,
}

impl AppState {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            store: Arc::new(RwLock::new(MemoryStore::default())),
            pool: None,
        }
    }

    pub async fn new_async(config: Config) -> anyhow::Result<Self> {
        let pool = postgres::connect(&config).await?;
        Ok(Self {
            config,
            store: Arc::new(RwLock::new(MemoryStore::default())),
            pool,
        })
    }

    pub fn using_postgres(&self) -> bool {
        self.pool.is_some()
    }

    pub async fn ensure_demo_book(&self, user_id: &str) -> anyhow::Result<String> {
        if let Some(pool) = &self.pool {
            return ensure_demo_book_pg(pool, user_id).await;
        }
        let mut store = self.store.write().await;
        if let Some(existing) = store.books.values().find(|b| b.owner_id == user_id) {
            return Ok(existing.id.clone());
        }
        let book_id = "book_default".to_string();
        store.books.insert(
            book_id.clone(),
            BookRecord {
                id: book_id.clone(),
                name: "Personal".into(),
                owner_id: user_id.to_string(),
            },
        );
        for (id, name, ty) in [
            ("acc_cash", "Cash", "asset"),
            ("acc_bank", "Bank", "asset"),
            ("acc_food", "Food", "expense"),
            ("acc_transport", "Transport", "expense"),
            ("acc_salary", "Salary", "income"),
        ] {
            store.accounts.insert(
                id.to_string(),
                AccountRecord {
                    id: id.to_string(),
                    book_id: book_id.clone(),
                    name: name.into(),
                    account_type: ty.into(),
                    currency: "CNY".into(),
                    version: 1,
                },
            );
        }
        Ok(book_id)
    }
}

async fn ensure_demo_book_pg(pool: &PgPool, user_id: &str) -> anyhow::Result<String> {
    // MVP: single shared demo book so client seed account ids (acc_cash, ...) stay global.
    const BOOK_ID: &str = "book_default";

    let existing: Option<(String,)> =
        sqlx::query_as("SELECT id FROM books WHERE id = $1")
            .bind(BOOK_ID)
            .fetch_optional(pool)
            .await?;

    if existing.is_none() {
        let mut tx = pool.begin().await?;
        sqlx::query("INSERT INTO books (id, name, owner_id) VALUES ($1, $2, $3)")
            .bind(BOOK_ID)
            .bind("Personal")
            .bind(user_id)
            .execute(&mut *tx)
            .await?;
        for (id, name, ty) in [
            ("acc_cash", "Cash", "asset"),
            ("acc_bank", "Bank", "asset"),
            ("acc_food", "Food", "expense"),
            ("acc_transport", "Transport", "expense"),
            ("acc_salary", "Salary", "income"),
        ] {
            sqlx::query(
                "INSERT INTO accounts (id, book_id, name, account_type, currency_code)
                 VALUES ($1, $2, $3, $4, 'CNY')
                 ON CONFLICT (id) DO NOTHING",
            )
            .bind(id)
            .bind(BOOK_ID)
            .bind(name)
            .bind(ty)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
    }

    sqlx::query(
        "INSERT INTO book_members (book_id, user_id, role) VALUES ($1, $2, 'owner')
         ON CONFLICT (book_id, user_id) DO NOTHING",
    )
    .bind(BOOK_ID)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(BOOK_ID.to_string())
}
