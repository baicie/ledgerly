use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use time::{format_description::well_known::Rfc3339, Month, OffsetDateTime};
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::AppState;
use crate::transport::http::authz::{require_book_member, require_plan, AuthUser};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/v1/books/{book_id}/reports/summary", get(summary))
        .route("/v1/books/{book_id}/reports/trend", get(trend))
        .route("/v1/books/{book_id}/reports/budget", get(budget))
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
               AND t.occurred_at >= $2::timestamptz AND t.occurred_at < $3::timestamptz",
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

        let (income, expense, categories) =
            aggregate_entries(rows, &base, &rates);

        return Ok(Json(serde_json::json!({
            "plan": plan,
            "baseCurrency": base,
            "incomeMinor": income.to_string(),
            "expenseMinor": expense.to_string(),
            "netMinor": (income - expense).to_string(),
            "categories": categories,
        })));
    }

    // Memory mode: scan in-memory transactions.
    let store = state.store.read().await;
    let base = "CNY".to_string();
    let mut rows = Vec::new();
    for tx in store.transactions.values() {
        if tx.book_id != book_id || tx.deleted {
            continue;
        }
        for (account_id, amount, currency) in &tx.entries {
            if let Some(acc) = store.accounts.get(account_id) {
                rows.push((
                    acc.name.clone(),
                    acc.account_type.clone(),
                    *amount,
                    currency.clone(),
                ));
            }
        }
    }
    let (income, expense, categories) = aggregate_entries(rows, &base, &[]);
    Ok(Json(serde_json::json!({
        "plan": plan,
        "baseCurrency": base,
        "incomeMinor": income.to_string(),
        "expenseMinor": expense.to_string(),
        "netMinor": (income - expense).to_string(),
        "categories": categories,
    })))
}

// ---------------------------------------------------------------------------
// Trend endpoint
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct TrendQuery {
    /// Number of past months to include (default 6, max 24).
    months: Option<usize>,
}

async fn trend(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Query(q): Query<TrendQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let _plan = require_plan(&state, &auth.user_id, "plus").await?;
    let months = q.months.unwrap_or(6).min(24);

    if let Some(pool) = &state.pool {
        return trend_pg(pool, &book_id, months).await;
    }
    trend_mem(&state, &book_id, months).await
}

async fn trend_pg(
    pool: &sqlx::PgPool,
    book_id: &str,
    months: usize,
) -> Result<Json<serde_json::Value>, ApiError> {
    let base: String = sqlx::query_scalar("SELECT base_currency FROM books WHERE id=$1")
        .bind(book_id)
        .fetch_one(pool)
        .await
        .unwrap_or_else(|_| "CNY".into());

    let rates: Vec<(String, String, f64)> = sqlx::query_as(
        "SELECT base_currency, quote_currency, rate::float8 FROM fx_rates WHERE book_id=$1",
    )
    .bind(book_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    // Compute start of each month going back `months` months.
    let now = OffsetDateTime::now_utc();
    let mut series = Vec::with_capacity(months);
    for i in 0..months {
        let month_date = subtract_months(now, i);
        let (from, to) = month_range(month_date.year(), month_date.month() as u8);
        let from_s = from.format(&Rfc3339).unwrap().to_string();
        let to_s = to.format(&Rfc3339).unwrap().to_string();

        let rows: Vec<(String, i64, String)> = sqlx::query_as(
            "SELECT a.account_type, te.amount_minor, te.currency_code
             FROM transaction_entries te
             JOIN transactions t ON t.id = te.transaction_id
             JOIN accounts a ON a.id = te.account_id
             WHERE t.book_id=$1 AND t.deleted_at IS NULL
               AND t.occurred_at >= $2::timestamptz AND t.occurred_at < $3::timestamptz",
        )
        .bind(book_id)
        .bind(&from_s)
        .bind(&to_s)
        .fetch_all(pool)
        .await
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;

        let mut income = 0i64;
        let mut expense = 0i64;
        for (account_type, amount, currency) in rows {
            let converted = convert_amount(amount, &currency, &base, &rates);
            if converted > 0 {
                if account_type == "income" {
                    income += converted;
                } else if account_type == "expense" {
                    expense += converted;
                }
            }
        }

        series.push(serde_json::json!({
            "month": format!("{:04}-{:02}", from.year(), from.month() as u8),
            "incomeMinor": income.to_string(),
            "expenseMinor": expense.to_string(),
            "netMinor": (income - expense).to_string(),
        }));
    }

    series.reverse(); // oldest first
    Ok(Json(serde_json::json!({ "series": series })))
}

async fn trend_mem(
    state: &AppState,
    book_id: &str,
    months: usize,
) -> Result<Json<serde_json::Value>, ApiError> {
    let store = state.store.read().await;
    // In memory mode we don't support FX conversion; base currency is CNY.
    let _base = "CNY".to_string();
    let now = OffsetDateTime::now_utc();
    let mut series = Vec::with_capacity(months);

    for i in 0..months {
        let month_date = subtract_months(now, i);
        let (from, to) = month_range(month_date.year(), month_date.month() as u8);
        let mut income = 0i64;
        let mut expense = 0i64;

        for tx in store.transactions.values() {
            if tx.book_id != book_id || tx.deleted {
                continue;
            }
            if tx.occurred_at < from || tx.occurred_at >= to {
                continue;
            }
            for (account_id, amount, _) in &tx.entries {
                if let Some(acc) = store.accounts.get(account_id) {
                    let a = *amount;
                    if a > 0 {
                        if acc.account_type == "income" {
                            income += a;
                        } else if acc.account_type == "expense" {
                            expense += a;
                        }
                    }
                }
            }
        }

        series.push(serde_json::json!({
            "month": format!("{:04}-{:02}", from.year(), from.month() as u8),
            "incomeMinor": income.to_string(),
            "expenseMinor": expense.to_string(),
            "netMinor": (income - expense).to_string(),
        }));
    }

    series.reverse();
    Ok(Json(serde_json::json!({ "series": series })))
}

// ---------------------------------------------------------------------------
// Budget endpoint
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct BudgetQuery {
    /// Month in YYYY-MM format (defaults to current month).
    month: Option<String>,
}

async fn budget(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(book_id): Path<String>,
    Query(q): Query<BudgetQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    require_book_member(&state, &auth.user_id, &book_id).await?;
    let _plan = require_plan(&state, &auth.user_id, "plus").await?;

    let (year, month) = parse_month(&q.month)?;
    let (from, to) = month_range(year, month);
    let from_s = from.format(&Rfc3339).unwrap().to_string();
    let to_s = to.format(&Rfc3339).unwrap().to_string();

    if let Some(pool) = &state.pool {
        return budget_pg(pool, &book_id, &from_s, &to_s, from).await;
    }
    budget_mem(&state, &book_id, from, to).await
}

async fn budget_pg(
    pool: &sqlx::PgPool,
    book_id: &str,
    from_s: &str,
    to_s: &str,
    month_start: OffsetDateTime,
) -> Result<Json<serde_json::Value>, ApiError> {
    let base: String = sqlx::query_scalar("SELECT base_currency FROM books WHERE id=$1")
        .bind(book_id)
        .fetch_one(pool)
        .await
        .unwrap_or_else(|_| "CNY".into());

    let rates: Vec<(String, String, f64)> = sqlx::query_as(
        "SELECT base_currency, quote_currency, rate::float8 FROM fx_rates WHERE book_id=$1",
    )
    .bind(book_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    // Fetch all budgets for this book.
    let budget_rows: Vec<(String, String, i64, String, Option<String>)> = sqlx::query_as(
        "SELECT id, name, amount_minor, currency_code, category_account_id
         FROM budgets WHERE book_id=$1",
    )
    .bind(book_id)
    .fetch_all(pool)
    .await
    .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, "DB_ERROR", e.to_string()))?;

    // For each budget, compute actual spending for the linked account in the period.
    let mut items = Vec::new();
    for (id, name, budget_amount, budget_currency, category_account_id) in budget_rows {
        let actual = if let Some(ref account_id) = category_account_id {
            // Sum entries for this specific account.
            let total: Option<i64> = sqlx::query_scalar(
                "SELECT COALESCE(SUM(te.amount_minor), 0)::bigint
                 FROM transaction_entries te
                 JOIN transactions t ON t.id = te.transaction_id
                 JOIN accounts a ON a.id = te.account_id
                 WHERE t.book_id=$1 AND t.deleted_at IS NULL
                   AND te.account_id = $2
                   AND t.occurred_at >= $3::timestamptz
                   AND t.occurred_at < $4::timestamptz
                   AND a.account_type = 'expense'",
            )
            .bind(book_id)
            .bind(account_id)
            .bind(from_s)
            .bind(to_s)
            .fetch_optional(pool)
            .await
            .unwrap_or(Some(0));
            total.unwrap_or(0)
        } else {
            0i64
        };

        // Convert budget to base currency.
        let budget_in_base =
            convert_amount(budget_amount, &budget_currency, &base, &rates);

        items.push(serde_json::json!({
            "id": id,
            "name": name,
            "budgetMinor": budget_in_base.to_string(),
            "actualMinor": actual.to_string(),
            "currency": base,
            "status": budget_status(actual, budget_in_base),
        }));
    }

    Ok(Json(serde_json::json!({
        "month": format!("{:04}-{:02}", month_start.year(), month_start.month() as u8),
        "baseCurrency": base,
        "items": items,
    })))
}

async fn budget_mem(
    state: &AppState,
    book_id: &str,
    from: OffsetDateTime,
    to: OffsetDateTime,
) -> Result<Json<serde_json::Value>, ApiError> {
    let store = state.store.read().await;
    let base = "CNY".to_string();

    // Memory budgets stored in changes (as upsert operations).
    // Rebuild budget map from changes.
    let mut budget_map: std::collections::BTreeMap<String, (String, i64)> =
        std::collections::BTreeMap::new(); // id -> (name, amount_minor)

    for change in store.changes.iter().filter(|c| c.book_id == book_id && c.entity_type == "budget") {
        if let Some(id) = change.payload.get("id").and_then(|v| v.as_str()) {
            let name = change
                .payload
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("Budget")
                .to_string();
            let amount: i64 = change
                .payload
                .get("amountMinor")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            budget_map.insert(id.to_string(), (name, amount));
        }
    }

    let mut items = Vec::new();
    for (id, (name, budget_amount)) in budget_map {
        let mut actual = 0i64;
        for tx in store.transactions.values() {
            if tx.book_id != book_id || tx.deleted {
                continue;
            }
            if tx.occurred_at < from || tx.occurred_at >= to {
                continue;
            }
            for (account_id, amount, _) in &tx.entries {
                if let Some(acc) = store.accounts.get(account_id) {
                    if acc.account_type == "expense" && *amount > 0 {
                        // In memory mode, we can't easily link a budget to an account.
                        // We sum all expense entries as a fallback.
                        actual += *amount;
                    }
                }
            }
        }

        items.push(serde_json::json!({
            "id": id,
            "name": name,
            "budgetMinor": budget_amount.to_string(),
            "actualMinor": actual.to_string(),
            "currency": base,
            "status": budget_status(actual, budget_amount),
        }));
    }

    Ok(Json(serde_json::json!({
        "month": format!("{:04}-{:02}", from.year(), from.month() as u8),
        "baseCurrency": base,
        "items": items,
    })))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Aggregates transaction entry rows into income / expense totals and a
/// per-category expense breakdown, all converted to `base` currency.
fn aggregate_entries(
    rows: Vec<(String, String, i64, String)>,
    base: &str,
    rates: &[(String, String, f64)],
) -> (i64, i64, Vec<serde_json::Value>) {
    let mut income = 0i64;
    let mut expense = 0i64;
    let mut category_map: std::collections::BTreeMap<String, i64> =
        std::collections::BTreeMap::new();

    for (name, account_type, amount, currency) in rows {
        let converted = convert_amount(amount, &currency, base, rates);
        if converted > 0 {
            if account_type == "income" {
                income += converted;
            } else if account_type == "expense" {
                expense += converted;
                *category_map.entry(name).or_default() += converted;
            }
        }
    }

    let categories: Vec<_> = category_map
        .into_iter()
        .map(|(name, amount)| {
            serde_json::json!({
                "name": name,
                "amountMinor": amount.to_string(),
                "currency": base,
            })
        })
        .collect();

    (income, expense, categories)
}

fn convert_amount(
    amount: i64,
    currency: &str,
    base: &str,
    rates: &[(String, String, f64)],
) -> i64 {
    if currency == base {
        return amount;
    }
    if let Some((_, _, rate)) = rates.iter().find(|(b, q, _)| b == base && q == currency) {
        return ((amount as f64) / rate).round() as i64;
    }
    if let Some((_, _, rate)) = rates.iter().find(|(b, q, _)| b == currency && q == base) {
        return ((amount as f64) * rate).round() as i64;
    }
    amount
}

/// Returns "over", "under", or "ok" based on actual vs budget.
fn budget_status(actual: i64, budget: i64) -> &'static str {
    if budget <= 0 {
        return "ok";
    }
    let ratio = actual as f64 / budget as f64;
    if ratio > 1.0 {
        "over"
    } else if ratio > 0.9 {
        "ok"
    } else {
        "under"
    }
}

/// Parses a "YYYY-MM" month string into (year, month).
fn parse_month(s: &Option<String>) -> Result<(i32, u8), ApiError> {
    let s = s.as_deref().unwrap_or("current");
    if s == "current" {
        let now = OffsetDateTime::now_utc();
        return Ok((now.year(), now.month() as u8));
    }
    let parts: Vec<_> = s.split('-').collect();
    if parts.len() != 2 {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MONTH",
            "month must be in YYYY-MM format",
        ));
    }
    let year: i32 = parts[0]
        .parse()
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_MONTH", "invalid year"))?;
    let month: u8 = parts[1]
        .parse()
        .map_err(|_| ApiError::new(StatusCode::BAD_REQUEST, "INVALID_MONTH", "invalid month"))?;
    if !(1..=12).contains(&month) {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "INVALID_MONTH",
            "month must be 01-12",
        ));
    }
    Ok((year, month))
}

/// Returns the start (inclusive) and end (exclusive) of a month in UTC.
fn month_range(year: i32, month: u8) -> (OffsetDateTime, OffsetDateTime) {
    // First day of month at 00:00 UTC.
    let start = time::Date::from_calendar_date(year, Month::try_from(month).unwrap(), 1)
        .unwrap()
        .midnight()
        .assume_utc();

    // First day of next month.
    let (next_year, next_month) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    let end = time::Date::from_calendar_date(next_year, Month::try_from(next_month).unwrap(), 1)
        .unwrap()
        .midnight()
        .assume_utc();

    (start, end)
}

/// Subtracts `n` months from a date, staying at the start of the resulting month.
fn subtract_months(date: OffsetDateTime, n: usize) -> OffsetDateTime {
    let mut year = date.year();
    let mut month = date.month() as i32;
    for _ in 0..n {
        if month == 1 {
            month = 12;
            year -= 1;
        } else {
            month -= 1;
        }
    }
    time::Date::from_calendar_date(year, Month::try_from(month as u8).unwrap(), 1)
        .unwrap()
        .midnight()
        .assume_utc()
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

#[cfg(test)]
mod tests {
    use super::*;
    use time::Month;

    #[test]
    fn month_range_january() {
        let (start, end) = month_range(2024, 1);
        assert_eq!(start.year(), 2024);
        assert_eq!(start.month(), Month::January);
        assert_eq!(end.year(), 2024);
        assert_eq!(end.month(), Month::February);
    }

    #[test]
    fn month_range_december_wraps_year() {
        let (start, end) = month_range(2024, 12);
        assert_eq!(start.year(), 2024);
        assert_eq!(start.month(), Month::December);
        assert_eq!(end.year(), 2025);
        assert_eq!(end.month(), Month::January);
    }

    #[test]
    fn parse_month_accepts_valid_format() {
        let (y, m) = parse_month(&Some("2024-06".into())).unwrap();
        assert_eq!(y, 2024);
        assert_eq!(m, 6);
    }

    #[test]
    fn parse_month_rejects_invalid_format() {
        assert!(parse_month(&Some("2024".into())).is_err());
        assert!(parse_month(&Some("2024-13".into())).is_err());
        assert!(parse_month(&Some("2024-00".into())).is_err());
        assert!(parse_month(&Some("junk".into())).is_err());
    }

    #[test]
    fn budget_status_over_under_ok() {
        // Over budget (>100%)
        assert_eq!(budget_status(110, 100), "over");
        // Just over (>=90% <= 100%)
        assert_eq!(budget_status(95, 100), "ok");
        // Under budget (<90%)
        assert_eq!(budget_status(80, 100), "under");
        // Zero budget
        assert_eq!(budget_status(50, 0), "ok");
    }

    #[test]
    fn aggregate_entries_sums_correctly() {
        let rows = vec![
            ("Salary".into(), "income".into(), 5000i64, "CNY".into()),
            ("Food".into(), "expense".into(), 2000i64, "CNY".into()),
            ("Transport".into(), "expense".into(), 500i64, "CNY".into()),
            // Negative income (reversal) should be ignored
            ("Salary".into(), "income".into(), -100i64, "CNY".into()),
        ];
        let (income, expense, categories) = aggregate_entries(rows, "CNY", &[]);
        assert_eq!(income, 5000);
        assert_eq!(expense, 2500);
        assert_eq!(categories.len(), 2);
    }

    #[test]
    fn subtract_months_goes_back_correctly() {
        let date = time::Date::from_calendar_date(2024, time::Month::March, 15)
            .unwrap()
            .midnight()
            .assume_utc();
        let result = subtract_months(date, 2);
        assert_eq!(result.year(), 2024);
        assert_eq!(result.month(), Month::January);
    }

    #[test]
    fn subtract_months_wraps_year() {
        let date = time::Date::from_calendar_date(2024, time::Month::February, 10)
            .unwrap()
            .midnight()
            .assume_utc();
        let result = subtract_months(date, 3);
        assert_eq!(result.year(), 2023);
        assert_eq!(result.month(), Month::November);
    }
}
