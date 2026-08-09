use std::time::Duration;

use sqlx::PgPool;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use uuid::Uuid;

/// Background job worker using PostgreSQL SKIP LOCKED.
pub async fn run_worker(pool: PgPool, worker_id: String) -> anyhow::Result<()> {
    tracing::info!(%worker_id, "job worker started");
    loop {
        let claimed = claim_jobs(&pool, &worker_id, 10).await?;
        if claimed.is_empty() {
            tokio::time::sleep(Duration::from_secs(2)).await;
            continue;
        }
        for job in claimed {
            if let Err(err) = execute_job(&pool, &job).await {
                tracing::error!(job_id = %job.id, error = %err, "job failed");
                let _ = fail_job(&pool, &job, &err.to_string()).await;
            } else {
                let _ = complete_job(&pool, &job.id).await;
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct JobRow {
    pub id: String,
    pub job_type: String,
    pub payload: serde_json::Value,
    pub attempts: i32,
    pub max_attempts: i32,
}

async fn claim_jobs(pool: &PgPool, worker_id: &str, limit: i64) -> anyhow::Result<Vec<JobRow>> {
    let mut tx = pool.begin().await?;
    let rows: Vec<(String, String, serde_json::Value, i32, i32)> = sqlx::query_as(
        "SELECT id, job_type, payload, attempts, max_attempts
         FROM jobs
         WHERE status = 'pending' AND run_at <= now()
         ORDER BY priority DESC, run_at, id
         FOR UPDATE SKIP LOCKED
         LIMIT $1",
    )
    .bind(limit)
    .fetch_all(&mut *tx)
    .await?;

    let mut out = Vec::new();
    for (id, job_type, payload, attempts, max_attempts) in rows {
        sqlx::query(
            "UPDATE jobs SET status='running', locked_by=$1, locked_at=now(), attempts=attempts+1
             WHERE id=$2",
        )
        .bind(worker_id)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
        out.push(JobRow {
            id,
            job_type,
            payload,
            attempts: attempts + 1,
            max_attempts,
        });
    }
    tx.commit().await?;
    Ok(out)
}

async fn execute_job(pool: &PgPool, job: &JobRow) -> anyhow::Result<()> {
    match job.job_type.as_str() {
        "purge_expired_sessions" => {
            sqlx::query(
                "UPDATE device_sessions SET revoked_at = now()
                 WHERE revoked_at IS NULL AND created_at < now() - interval '30 days'",
            )
            .execute(pool)
            .await?;
        }
        "compact_sync_log" => {
            sqlx::query(
                "DELETE FROM sync_changes
                 WHERE sequence < (SELECT COALESCE(MAX(sequence),0) - 100000 FROM sync_changes)",
            )
            .execute(pool)
            .await?;
        }
        "enqueue_recurring_scan" => {
            generate_due_recurring(pool).await?;
            // Keep scanning periodically.
            let _ = enqueue_at(
                pool,
                "enqueue_recurring_scan",
                serde_json::json!({}),
                0,
                "now() + interval '1 minute'",
            )
            .await;
        }
        other => {
            tracing::warn!(job_type = other, "unknown job type, marking done");
        }
    }
    Ok(())
}

/// Materialize due recurring rules as balanced ledger transactions + sync_changes.
async fn generate_due_recurring(pool: &PgPool) -> anyhow::Result<()> {
    let due: Vec<(String, String, String, serde_json::Value)> = sqlx::query_as(
        "SELECT id, book_id, name, payload FROM recurring_rules
         WHERE active = true AND next_run_at <= now()
         ORDER BY next_run_at, id
         LIMIT 50",
    )
    .fetch_all(pool)
    .await?;

    for (rule_id, book_id, name, payload) in due {
        let entries = payload
            .get("entries")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        if entries.len() < 2 {
            tracing::warn!(%rule_id, "recurring payload missing entries, skipping");
            sqlx::query(
                "UPDATE recurring_rules SET next_run_at = next_run_at + interval '1 month'
                 WHERE id=$1",
            )
            .bind(&rule_id)
            .execute(pool)
            .await?;
            continue;
        }

        let mut sum: i128 = 0;
        let mut parsed: Vec<(String, i64, String)> = Vec::new();
        for raw in &entries {
            let account_id = raw
                .get("accountId")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow::anyhow!("missing accountId"))?
                .to_string();
            let amount: i64 = match raw.get("amountMinor") {
                Some(serde_json::Value::String(s)) => s.parse()?,
                Some(serde_json::Value::Number(n)) => n
                    .as_i64()
                    .ok_or_else(|| anyhow::anyhow!("bad amountMinor"))?,
                _ => anyhow::bail!("missing amountMinor"),
            };
            let currency = raw
                .get("currency")
                .and_then(|v| v.as_str())
                .unwrap_or("CNY")
                .to_string();
            sum += amount as i128;
            parsed.push((account_id, amount, currency));
        }
        if sum != 0 {
            tracing::warn!(%rule_id, %sum, "unbalanced recurring payload, skipping");
            sqlx::query(
                "UPDATE recurring_rules SET next_run_at = next_run_at + interval '1 month'
                 WHERE id=$1",
            )
            .bind(&rule_id)
            .execute(pool)
            .await?;
            continue;
        }

        let tx_id = Uuid::now_v7().to_string();
        let commit_id = Uuid::now_v7().to_string();
        let occurred_at = OffsetDateTime::now_utc();
        let occurred_at_rfc3339 = occurred_at.format(&Rfc3339)?;
        let description = payload
            .get("description")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| name.clone());

        let mut db = pool.begin().await?;
        sqlx::query(
            "INSERT INTO transactions (id, book_id, description, occurred_at, version)
             VALUES ($1,$2,$3,$4,1)",
        )
        .bind(&tx_id)
        .bind(&book_id)
        .bind(&description)
        .bind(occurred_at)
        .execute(&mut *db)
        .await?;

        let mut entry_payload = Vec::new();
        for (idx, (account_id, amount, currency)) in parsed.iter().enumerate() {
            let entry_id = format!("{tx_id}-{idx}");
            sqlx::query(
                "INSERT INTO transaction_entries
                 (id, transaction_id, account_id, amount_minor, currency_code, entry_index)
                 VALUES ($1,$2,$3,$4,$5,$6)",
            )
            .bind(&entry_id)
            .bind(&tx_id)
            .bind(account_id)
            .bind(amount)
            .bind(currency)
            .bind(idx as i32)
            .execute(&mut *db)
            .await?;
            entry_payload.push(serde_json::json!({
                "accountId": account_id,
                "amountMinor": amount.to_string(),
                "currency": currency,
            }));
        }

        let change_payload = serde_json::json!({
            "description": description,
            "occurredAt": occurred_at_rfc3339,
            "entries": entry_payload,
            "recurringRuleId": rule_id,
        });
        sqlx::query(
            "INSERT INTO sync_changes
             (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
             VALUES ($1,$2,'transaction',$3,'upsert',1,$4)",
        )
        .bind(&book_id)
        .bind(&commit_id)
        .bind(&tx_id)
        .bind(&change_payload)
        .execute(&mut *db)
        .await?;

        sqlx::query(
            "UPDATE recurring_rules SET next_run_at = next_run_at + interval '1 month'
             WHERE id=$1",
        )
        .bind(&rule_id)
        .execute(&mut *db)
        .await?;
        db.commit().await?;
        tracing::info!(%rule_id, %tx_id, %book_id, "recurring transaction generated");
    }
    Ok(())
}

async fn complete_job(pool: &PgPool, id: &str) -> anyhow::Result<()> {
    sqlx::query(
        "UPDATE jobs SET status='completed', completed_at=now(), locked_by=NULL, locked_at=NULL
         WHERE id=$1",
    )
    .bind(id)
    .execute(pool)
    .await?;
    Ok(())
}

async fn fail_job(pool: &PgPool, job: &JobRow, error: &str) -> anyhow::Result<()> {
    let status = if job.attempts >= job.max_attempts {
        "dead"
    } else {
        "pending"
    };
    sqlx::query(
        "UPDATE jobs SET status=$1, last_error=$2, locked_by=NULL, locked_at=NULL,
            run_at = now() + (interval '1 second' * power(2, least(attempts, 8)))
         WHERE id=$3",
    )
    .bind(status)
    .bind(error)
    .bind(&job.id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn enqueue(
    pool: &PgPool,
    job_type: &str,
    payload: serde_json::Value,
    priority: i32,
) -> anyhow::Result<String> {
    enqueue_at(pool, job_type, payload, priority, "now()").await
}

async fn enqueue_at(
    pool: &PgPool,
    job_type: &str,
    payload: serde_json::Value,
    priority: i32,
    run_at_sql: &str,
) -> anyhow::Result<String> {
    let id = Uuid::now_v7().to_string();
    let sql = format!(
        "INSERT INTO jobs (id, job_type, payload, priority, run_at) VALUES ($1,$2,$3,$4, {run_at_sql})"
    );
    sqlx::query(&sql)
        .bind(&id)
        .bind(job_type)
        .bind(payload)
        .bind(priority)
        .execute(pool)
        .await?;
    Ok(id)
}
