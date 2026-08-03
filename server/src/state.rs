use std::collections::HashMap;
use std::sync::Arc;

use serde_json::Value;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub store: Arc<RwLock<MemoryStore>>,
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
        }
    }

    pub async fn ensure_demo_book(&self, user_id: &str) -> String {
        let mut store = self.store.write().await;
        if let Some(existing) = store.books.values().find(|b| b.owner_id == user_id) {
            return existing.id.clone();
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
        for (id, name, ty) in [
            ("acc_cash", "Cash", "asset"),
            ("acc_bank", "Bank", "asset"),
            ("acc_food", "Food", "expense"),
            ("acc_salary", "Salary", "income"),
        ] {
            let account_id = format!("{book_id}:{id}");
            store.accounts.insert(
                account_id.clone(),
                AccountRecord {
                    id: account_id,
                    book_id: book_id.clone(),
                    name: name.into(),
                    account_type: ty.into(),
                    currency: "CNY".into(),
                    version: 1,
                },
            );
        }
        book_id
    }
}
