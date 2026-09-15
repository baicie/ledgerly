use anyhow::Context;
use axum::http::HeaderMap;
use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::state::{AppState, AuditEventRecord};

type AuditRow = (
    String,
    OffsetDateTime,
    String,
    Option<String>,
    String,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    Value,
);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuditActor {
    User,
    System,
}

impl AuditActor {
    fn as_str(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::System => "system",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuditOutcome {
    Success,
    Failure,
    Denied,
}

impl AuditOutcome {
    fn as_str(self) -> &'static str {
        match self {
            Self::Success => "success",
            Self::Failure => "failure",
            Self::Denied => "denied",
        }
    }
}

pub struct AuditEvent<'a> {
    pub actor: AuditActor,
    pub actor_id: Option<&'a str>,
    pub action: &'a str,
    pub outcome: AuditOutcome,
    pub target_type: Option<&'a str>,
    pub target_id: Option<&'a str>,
    pub request_id: Option<&'a str>,
    pub metadata: Value,
}

impl<'a> AuditEvent<'a> {
    pub fn user(actor_id: &'a str, action: &'a str, outcome: AuditOutcome) -> Self {
        Self {
            actor: AuditActor::User,
            actor_id: Some(actor_id),
            action,
            outcome,
            target_type: None,
            target_id: None,
            request_id: None,
            metadata: serde_json::json!({}),
        }
    }

    pub fn system(action: &'a str, outcome: AuditOutcome) -> Self {
        Self {
            actor: AuditActor::System,
            actor_id: None,
            action,
            outcome,
            target_type: None,
            target_id: None,
            request_id: None,
            metadata: serde_json::json!({}),
        }
    }

    pub fn anonymous(action: &'a str, outcome: AuditOutcome) -> Self {
        Self {
            actor: AuditActor::User,
            actor_id: None,
            action,
            outcome,
            target_type: None,
            target_id: None,
            request_id: None,
            metadata: serde_json::json!({}),
        }
    }

    pub fn target(mut self, target_type: &'a str, target_id: &'a str) -> Self {
        self.target_type = Some(target_type);
        self.target_id = Some(target_id);
        self
    }

    pub fn request_id(mut self, request_id: Option<&'a str>) -> Self {
        self.request_id = request_id;
        self
    }

    pub fn metadata(mut self, metadata: Value) -> Self {
        self.metadata = metadata;
        self
    }
}

#[derive(Debug, Clone)]
pub struct AuditQuery {
    pub actor_id: Option<String>,
    pub action: Option<String>,
    pub outcome: Option<String>,
    pub before: Option<String>,
    pub limit: usize,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEventView {
    pub id: String,
    pub occurred_at: String,
    pub actor_type: String,
    pub actor_id: Option<String>,
    pub action: String,
    pub outcome: String,
    pub target_type: Option<String>,
    pub target_id: Option<String>,
    pub request_id: Option<String>,
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditPage {
    pub events: Vec<AuditEventView>,
    pub next_cursor: Option<String>,
}

pub fn request_id(headers: &HeaderMap) -> Option<&str> {
    headers
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.is_empty() && value.len() <= 64)
}

pub async fn record(state: &AppState, event: AuditEvent<'_>) {
    let result = if let Some(pool) = &state.pool {
        record_pool(pool, event).await
    } else {
        record_memory(state, event).await
    };
    if result.is_err() {
        crate::metrics::record_audit_write_failure();
        crate::obs::error_event("audit", "WRITE_FAILED");
    }
}

pub async fn record_on_pool(pool: &PgPool, event: AuditEvent<'_>) {
    if record_pool(pool, event).await.is_err() {
        crate::metrics::record_audit_write_failure();
        crate::obs::error_event("audit", "WRITE_FAILED");
    }
}

pub async fn record_pool(pool: &PgPool, event: AuditEvent<'_>) -> anyhow::Result<()> {
    let id = Uuid::now_v7().to_string();
    let metadata = bounded_metadata(event.metadata)?;
    sqlx::query(
        "INSERT INTO audit_events
         (id, actor_type, actor_id, action, outcome, target_type, target_id, request_id, metadata)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)",
    )
    .bind(&id)
    .bind(event.actor.as_str())
    .bind(event.actor_id)
    .bind(event.action)
    .bind(event.outcome.as_str())
    .bind(event.target_type)
    .bind(event.target_id)
    .bind(event.request_id)
    .bind(metadata)
    .execute(pool)
    .await
    .context("insert audit event")?;
    crate::metrics::record_audit_event(event.action, event.outcome.as_str());
    Ok(())
}

async fn record_memory(state: &AppState, event: AuditEvent<'_>) -> anyhow::Result<()> {
    let record = AuditEventRecord {
        id: Uuid::now_v7().to_string(),
        occurred_at: OffsetDateTime::now_utc(),
        actor_type: event.actor.as_str().into(),
        actor_id: event.actor_id.map(str::to_string),
        action: event.action.into(),
        outcome: event.outcome.as_str().into(),
        target_type: event.target_type.map(str::to_string),
        target_id: event.target_id.map(str::to_string),
        request_id: event.request_id.map(str::to_string),
        metadata: bounded_metadata(event.metadata)?,
    };
    let mut store = state.store.write().await;
    store.audit_events.push(record);
    if store.audit_events.len() > 1_000 {
        let drain = store.audit_events.len() - 1_000;
        store.audit_events.drain(..drain);
    }
    crate::metrics::record_audit_event(event.action, event.outcome.as_str());
    Ok(())
}

pub async fn query(state: &AppState, query: AuditQuery) -> anyhow::Result<AuditPage> {
    let limit = query.limit.clamp(1, 200);
    if let Some(pool) = &state.pool {
        let rows: Vec<AuditRow> = sqlx::query_as(
            "SELECT id, occurred_at, actor_type, actor_id, action, outcome,
                    target_type, target_id, request_id, metadata
             FROM audit_events
             WHERE ($1::text IS NULL OR actor_id = $1)
               AND ($2::text IS NULL OR action = $2)
               AND ($3::text IS NULL OR outcome = $3)
               AND ($4::text IS NULL OR id < $4)
             ORDER BY id DESC
             LIMIT $5",
        )
        .bind(query.actor_id.as_deref())
        .bind(query.action.as_deref())
        .bind(query.outcome.as_deref())
        .bind(query.before.as_deref())
        .bind((limit + 1) as i64)
        .fetch_all(pool)
        .await
        .context("query audit events")?;
        return Ok(page_from_rows(rows, limit));
    }

    let store = state.store.read().await;
    let mut events: Vec<_> = store
        .audit_events
        .iter()
        .filter(|event| {
            query
                .actor_id
                .as_deref()
                .is_none_or(|actor_id| event.actor_id.as_deref() == Some(actor_id))
                && query
                    .action
                    .as_deref()
                    .is_none_or(|action| event.action == action)
                && query
                    .outcome
                    .as_deref()
                    .is_none_or(|outcome| event.outcome == outcome)
                && query
                    .before
                    .as_deref()
                    .is_none_or(|before| event.id.as_str() < before)
        })
        .cloned()
        .collect();
    events.sort_by(|left, right| right.id.cmp(&left.id));
    events.truncate(limit + 1);
    let rows = events
        .into_iter()
        .map(|event| {
            (
                event.id,
                event.occurred_at,
                event.actor_type,
                event.actor_id,
                event.action,
                event.outcome,
                event.target_type,
                event.target_id,
                event.request_id,
                event.metadata,
            )
        })
        .collect();
    Ok(page_from_rows(rows, limit))
}

fn page_from_rows(mut rows: Vec<AuditRow>, limit: usize) -> AuditPage {
    let has_more = rows.len() > limit;
    rows.truncate(limit);
    let next_cursor = has_more
        .then(|| rows.last().map(|row| row.0.clone()))
        .flatten();
    let events = rows
        .into_iter()
        .map(|row| AuditEventView {
            id: row.0,
            occurred_at: row
                .1
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
            actor_type: row.2,
            actor_id: row.3,
            action: row.4,
            outcome: row.5,
            target_type: row.6,
            target_id: row.7,
            request_id: row.8,
            metadata: row.9,
        })
        .collect();
    AuditPage {
        events,
        next_cursor,
    }
}

fn bounded_metadata(metadata: Value) -> anyhow::Result<Value> {
    let bytes = serde_json::to_vec(&metadata).context("encode audit metadata")?;
    if bytes.len() > 4_096 {
        anyhow::bail!("audit metadata exceeds 4096 bytes");
    }
    Ok(metadata)
}

#[cfg(test)]
mod tests {
    use super::bounded_metadata;

    #[test]
    fn audit_metadata_is_limited_to_four_kib() {
        let oversized = serde_json::json!({ "value": "a".repeat(5_000) });
        assert!(bounded_metadata(oversized).is_err());
    }
}
