use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value;
use sqlx::PgPool;
use tokio::sync::{Mutex, RwLock};
use uuid::Uuid;

use crate::config::Config;
use crate::infrastructure::postgres;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub store: Arc<RwLock<MemoryStore>>,
    pub memory_sync_lock: Arc<Mutex<()>>,
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
    pub budgets: Vec<BudgetRecord>,
    pub invites: Vec<InviteRecord>,
    pub subscriptions: HashMap<String, String>,
    pub fx_rates: Vec<FxRateRecord>,
    pub revisions: Vec<RevisionRecord>,
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
    pub deleted: bool,
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

#[derive(Clone)]
pub struct BudgetRecord {
    pub id: String,
    pub book_id: String,
    pub name: String,
    pub amount_minor: i64,
    pub currency: String,
    pub category_account_id: Option<String>,
}

#[derive(Clone)]
pub struct InviteRecord {
    pub id: String,
    pub book_id: String,
    pub email: String,
    pub role: String,
    pub token: String,
}

#[derive(Clone)]
pub struct FxRateRecord {
    pub book_id: String,
    pub base_currency: String,
    pub quote_currency: String,
    pub rate: f64,
}

#[derive(Clone)]
pub struct RevisionRecord {
    pub id: String,
    pub book_id: String,
    pub transaction_id: String,
    pub version: i64,
    pub operation: String,
    pub payload: Value,
}

pub fn scoped_account_id(book_id: &str, key: &str) -> String {
    format!("{book_id}:{key}")
}

impl AppState {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            store: Arc::new(RwLock::new(MemoryStore::default())),
            memory_sync_lock: Arc::new(Mutex::new(())),
            pool: None,
        }
    }

    pub async fn new_async(config: Config) -> anyhow::Result<Self> {
        let pool = postgres::connect(&config).await?;
        Ok(Self {
            config,
            store: Arc::new(RwLock::new(MemoryStore::default())),
            memory_sync_lock: Arc::new(Mutex::new(())),
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
        let book_id = Uuid::now_v7().to_string();
        store.books.insert(
            book_id.clone(),
            BookRecord {
                id: book_id.clone(),
                name: "Personal".into(),
                owner_id: user_id.to_string(),
            },
        );
        seed_accounts_mem(&mut store, &book_id);
        Ok(book_id)
    }
}

fn seed_accounts_mem(store: &mut MemoryStore, book_id: &str) {
    for (key, name, ty) in [
        ("acc_cash", "Cash", "asset"),
        ("acc_bank", "Bank", "asset"),
        ("acc_food", "Food", "expense"),
        ("acc_transport", "Transport", "expense"),
        ("acc_salary", "Salary", "income"),
    ] {
        let id = scoped_account_id(book_id, key);
        store.accounts.insert(
            id.clone(),
            AccountRecord {
                id,
                book_id: book_id.to_string(),
                name: name.into(),
                account_type: ty.into(),
                currency: "CNY".into(),
                version: 1,
            },
        );
    }
}

async fn ensure_demo_book_pg(pool: &PgPool, user_id: &str) -> anyhow::Result<String> {
    if let Some((id,)) = sqlx::query_as::<_, (String,)>(
        "SELECT b.id FROM books b
         JOIN book_members m ON m.book_id = b.id
         WHERE m.user_id = $1
         ORDER BY b.created_at
         LIMIT 1",
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?
    {
        return Ok(id);
    }

    let book_id = Uuid::now_v7().to_string();
    let mut tx = pool.begin().await?;
    sqlx::query("INSERT INTO books (id, name, owner_id) VALUES ($1, $2, $3)")
        .bind(&book_id)
        .bind("Personal")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO book_members (book_id, user_id, role) VALUES ($1, $2, 'owner')")
        .bind(&book_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    for (key, name, ty) in [
        ("acc_cash", "Cash", "asset"),
        ("acc_bank", "Bank", "asset"),
        ("acc_food", "Food", "expense"),
        ("acc_transport", "Transport", "expense"),
        ("acc_salary", "Salary", "income"),
    ] {
        let id = scoped_account_id(&book_id, key);
        sqlx::query(
            "INSERT INTO accounts (id, book_id, name, account_type, currency_code)
             VALUES ($1, $2, $3, $4, 'CNY')",
        )
        .bind(&id)
        .bind(&book_id)
        .bind(name)
        .bind(ty)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    // Seed default FX rates for demo.
    for (quote, rate) in [("USD", 0.14_f64), ("JPY", 21.5_f64)] {
        let _ = sqlx::query(
            "INSERT INTO fx_rates (id, book_id, base_currency, quote_currency, rate)
             VALUES ($1,$2,'CNY',$3,$4)
             ON CONFLICT (book_id, base_currency, quote_currency) DO NOTHING",
        )
        .bind(Uuid::now_v7().to_string())
        .bind(&book_id)
        .bind(quote)
        .bind(rate)
        .execute(pool)
        .await;
    }
    Ok(book_id)
}
