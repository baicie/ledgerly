use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::AppState;
use crate::transport::http::authz::{require_book_member, require_plan, AuthUser};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/v1/books/{book_id}/reports/summary", get(summary))
        .route(
            "/v1/books/{book_id}/transactions/{tx_id}/revisions",
            get(list_revisions),
        )
        .route("/v1/books/{book_id}/fx-rates", get(list_fx).put(upsert_fx))
}

#[derive(Debug, Deserialize)]
struct SummaryQuery {
    from: Option<String>,
    to: Option<String>,
}

async fn summary(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Query(q): Query<SummaryQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let plan = require_plan(&state, &auth.user_id, "plus").await?;

    let from = q.from.unwrap_or_else(|| "1970-01-01T00:00:00Z".into());
    let to = q.to.unwrap_or_else(|| "2100-01-01T00:00:00Z".into());

    if let Some(pool) = &state.pool {
        let base: String = sqlx::query_scalar("SELECT base_currency FROM books WHERE id=$1")
            .bind(&book_id)
            .fetch_one(pool)
            .await
            .unwrap_or_else(|_| "CNY".into());

        let rows: Vec<(String, String, i64, String)> = sqlx::query_as(
            "SELECT a.name, a.account_type, te.amount_minor, te.currency_code
             FROM transaction_entries te
             JOIN transactions t ON t.id = te.transaction_id
             JOIN accounts a ON a.id = te.account_id
             WHERE t.book_id=$1 AND t.deleted_at IS NULL
               AND t.created_at >= $2::timestamptz AND t.created_at < $3::timestamptz",
        )
        .bind(&book_id)
        .bind(&from)
        .bind(&to)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;

        let rates: Vec<(String, String, f64)> = sqlx::query_as(
            "SELECT base_currency, quote_currency, rate::float8 FROM fx_rates WHERE book_id=$1",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .unwrap_or_default();

        let mut income = 0i64;
        let mut expense = 0i64;
        let mut categories = Vec::new();
        let mut missing = Vec::new();

        for (name, ty, amount, currency) in rows {
            let converted = convert_amount(amount, &currency, &base, &rates, &mut missing);
            if ty == "income" && amount > 0 {
                income += converted;
            } else if ty == "expense" && amount > 0 {
                expense += converted;
                categories.push(serde_json::json!({
                    "name": name,
                    "amountMinor": converted.to_string(),
                    "currency": base,
                }));
            }
        }

        return Ok(Json(serde_json::json!({
            "plan": plan,
            "baseCurrency": base,
            "incomeMinor": income.to_string(),
            "expenseMinor": expense.to_string(),
            "netMinor": (income - expense).to_string(),
            "categories": categories,
            "missingRates": missing,
        })));
    }

    Ok(Json(serde_json::json!({
        "plan": plan,
        "baseCurrency": "CNY",
        "incomeMinor": "0",
        "expenseMinor": "0",
        "netMinor": "0",
        "categories": [],
        "missingRates": [],
    })))
}

fn convert_amount(
    amount: i64,
    currency: &str,
    base: &str,
    rates: &[(String, String, f64)],
    missing: &mut Vec<String>,
) -> i64 {
    if currency == base {
        return amount;
    }
    if let Some((_, _, rate)) = rates.iter().find(|(b, q, _)| b == base && q == currency) {
        // amount in quote -> base: amount / rate (rate = quote per 1 base)
        return ((amount as f64) / rate).round() as i64;
    }
    if let Some((_, _, rate)) = rates.iter().find(|(b, q, _)| b == currency && q == base) {
        return ((amount as f64) * rate).round() as i64;
    }
    let key = format!("{currency}->{base}");
    if !missing.contains(&key) {
        missing.push(key);
    }
    amount
}

async fn list_revisions(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((book_id, tx_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let rows: Vec<(String, i64, String, serde_json::Value, time::OffsetDateTime)> =
            sqlx::query_as(
                "SELECT id, version, operation, payload, created_at
                 FROM transaction_revisions
                 WHERE book_id=$1 AND transaction_id=$2
                 ORDER BY version DESC",
            )
            .bind(&book_id)
            .bind(&tx_id)
            .fetch_all(pool)
            .await
            .map_err(|e| {
                ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string())
            })?;
        return Ok(Json(serde_json::json!({
            "revisions": rows.iter().map(|(id, version, op, payload, at)| serde_json::json!({
                "id": id,
                "version": version,
                "operation": op,
                "payload": payload,
                "createdAt": at.to_string(),
            })).collect::<Vec<_>>()
        })));
    }
    let store = state.store.read().await;
    let revisions: Vec<_> = store
        .revisions
        .iter()
        .filter(|r| r.book_id == book_id && r.transaction_id == tx_id)
        .map(|r| {
            serde_json::json!({
                "id": r.id,
                "version": r.version,
                "operation": r.operation,
                "payload": r.payload,
            })
        })
        .collect();
    Ok(Json(serde_json::json!({ "revisions": revisions })))
}

#[derive(Debug, Deserialize)]
struct UpsertFxRequest {
    #[serde(rename = "baseCurrency")]
    base_currency: String,
    #[serde(rename = "quoteCurrency")]
    quote_currency: String,
    rate: f64,
}

async fn list_fx(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if let Some(pool) = &state.pool {
        let rows: Vec<(String, String, f64)> = sqlx::query_as(
            "SELECT base_currency, quote_currency, rate::float8 FROM fx_rates WHERE book_id=$1",
        )
        .bind(&book_id)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
        return Ok(Json(serde_json::json!({
            "rates": rows.iter().map(|(b,q,r)| serde_json::json!({
                "baseCurrency": b, "quoteCurrency": q, "rate": r
            })).collect::<Vec<_>>()
        })));
    }
    let store = state.store.read().await;
    let rates: Vec<_> = store
        .fx_rates
        .iter()
        .filter(|r| r.book_id == book_id)
        .map(|r| {
            serde_json::json!({
                "baseCurrency": r.base_currency,
                "quoteCurrency": r.quote_currency,
                "rate": r.rate,
            })
        })
        .collect();
    Ok(Json(serde_json::json!({ "rates": rates })))
}

async fn upsert_fx(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Json(req): Json<UpsertFxRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    if req.rate <= 0.0 {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_RATE",
            "rate must be > 0",
        ));
    }
    let id = Uuid::now_v7().to_string();
    if let Some(pool) = &state.pool {
        sqlx::query(
            "INSERT INTO fx_rates (id, book_id, base_currency, quote_currency, rate)
             VALUES ($1,$2,$3,$4,$5)
             ON CONFLICT (book_id, base_currency, quote_currency)
             DO UPDATE SET rate=$5, as_of=now()",
        )
        .bind(&id)
        .bind(&book_id)
        .bind(&req.base_currency)
        .bind(&req.quote_currency)
        .bind(req.rate)
        .execute(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;
    } else {
        let mut store = state.store.write().await;
        if let Some(existing) = store.fx_rates.iter_mut().find(|r| {
            r.book_id == book_id
                && r.base_currency == req.base_currency
                && r.quote_currency == req.quote_currency
        }) {
            existing.rate = req.rate;
        } else {
            store.fx_rates.push(crate::state::FxRateRecord {
                book_id: book_id.clone(),
                base_currency: req.base_currency.clone(),
                quote_currency: req.quote_currency.clone(),
                rate: req.rate,
            });
        }
    }
    Ok(Json(serde_json::json!({
        "baseCurrency": req.base_currency,
        "quoteCurrency": req.quote_currency,
        "rate": req.rate,
    })))
}
