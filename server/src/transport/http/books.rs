use axum::{extract::State, http::StatusCode, routing::get, Json, Router};
use serde::Deserialize;
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::{scoped_account_id, AppState, BookRecord};
use crate::transport::http::authz::AuthUser;

pub fn routes() -> Router<AppState> {
    Router::new().route("/v1/books", get(list_books).post(create_book))
}

#[derive(Debug, Deserialize)]
struct CreateBookRequest {
    name: String,
    #[serde(rename = "currencyCode", default = "default_currency")]
    currency_code: String,
}

fn default_currency() -> String {
    "CNY".into()
}

async fn list_books(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<serde_json::Value>, ApiError> {
    if let Some(pool) = &state.pool {
        let books: Vec<(String, String, String)> = sqlx::query_as(
            "SELECT b.id, b.name, 'owner'::text AS role
             FROM books b WHERE b.owner_id=$1
             UNION
             SELECT b.id, b.name, m.role
             FROM books b JOIN book_members m ON m.book_id=b.id
             WHERE m.user_id=$1 AND b.owner_id <> $1
             ORDER BY name",
        )
        .bind(&auth.user_id)
        .fetch_all(pool)
        .await
        .map_err(db_err)?;
        return Ok(Json(serde_json::json!({
            "books": books.iter().map(|(id, name, role)| serde_json::json!({
                "id": id, "name": name, "role": role
            })).collect::<Vec<_>>()
        })));
    }

    let store = state.store.read().await;
    let mut books: Vec<_> = store
        .books
        .values()
        .filter(|book| book.owner_id == auth.user_id)
        .map(|book| {
            serde_json::json!({
                "id": book.id, "name": book.name, "role": "owner"
            })
        })
        .collect();
    books.sort_by(|left, right| left["name"].as_str().cmp(&right["name"].as_str()));
    Ok(Json(serde_json::json!({ "books": books })))
}

async fn create_book(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateBookRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let name = req.name.trim();
    if name.is_empty() || name.chars().count() > 40 {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_BOOK_NAME",
            "book name must contain 1 to 40 characters",
        ));
    }
    if req.currency_code.len() != 3 || !req.currency_code.bytes().all(|b| b.is_ascii_uppercase()) {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_CURRENCY",
            "currencyCode must be an uppercase ISO currency code",
        ));
    }

    if let Some(pool) = &state.pool {
        let book_id = Uuid::now_v7().to_string();
        let mut tx = pool.begin().await.map_err(db_err)?;
        sqlx::query("INSERT INTO books (id, name, owner_id) VALUES ($1,$2,$3)")
            .bind(&book_id)
            .bind(name)
            .bind(&auth.user_id)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        sqlx::query("INSERT INTO book_members (book_id, user_id, role) VALUES ($1,$2,'owner')")
            .bind(&book_id)
            .bind(&auth.user_id)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        let defaults = [("acc_cash", "Cash", "asset"), ("acc_bank", "Bank", "asset")];
        for (key, account_name, account_type) in defaults {
            sqlx::query(
                "INSERT INTO accounts (id, book_id, name, account_type, currency_code)
                 VALUES ($1,$2,$3,$4,$5)",
            )
            .bind(scoped_account_id(&book_id, key))
            .bind(&book_id)
            .bind(account_name)
            .bind(account_type)
            .bind(&req.currency_code)
            .execute(&mut *tx)
            .await
            .map_err(db_err)?;
        }
        tx.commit().await.map_err(db_err)?;
        return Ok(Json(serde_json::json!({
            "id": book_id, "name": name, "currencyCode": req.currency_code, "role": "owner"
        })));
    }

    let book_id = Uuid::now_v7().to_string();
    let mut store = state.store.write().await;
    store.books.insert(
        book_id.clone(),
        BookRecord {
            id: book_id.clone(),
            name: name.into(),
            owner_id: auth.user_id.clone(),
        },
    );
    for (key, account_name, account_type) in
        [("acc_cash", "Cash", "asset"), ("acc_bank", "Bank", "asset")]
    {
        let id = scoped_account_id(&book_id, key);
        store.accounts.insert(
            id.clone(),
            crate::state::AccountRecord {
                id,
                book_id: book_id.clone(),
                name: account_name.into(),
                account_type: account_type.into(),
                currency: req.currency_code.clone(),
                parent_account_id: None,
                version: 1,
            },
        );
    }
    Ok(Json(serde_json::json!({
        "id": book_id, "name": name, "currencyCode": req.currency_code, "role": "owner"
    })))
}

fn db_err(error: sqlx::Error) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "DB_ERROR",
        error.to_string(),
    )
}
