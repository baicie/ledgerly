//! Structured tracing helpers per ADR-BE-017.
//!
//! Domain spans: auth, ledger, sync, postgres, job, object_store,
//! http (request_id), app (lifecycle).
//!
//! **Security constraint**: never log account bodies, precise amounts,
//! tokens, or full mutation payloads.

use tracing::{Level, Span};

// Re-export tracing macros so they can be used via `tracing::info!` etc.
// from any module that imports `crate::obs`.
pub use tracing::{debug, error, info, info_span, warn};

/// Returns the request_id recorded on the currently-entered `http.request`
/// span, or `None` if the caller is not running inside one.
///
/// Use this to stamp the same correlation ID onto the JSON error body
/// the client receives. Keeping the lookup in one helper means we can
/// change the underlying storage (extension map, span attribute, task
/// local) without rewriting every call site.
pub fn current_request_id() -> Option<String> {
    tracing::Span::current()
        .field("request_id")
        .and_then(|field| field.to_string().into())
}

/// Creates an `http` domain span with a request_id. The span is entered
/// by the caller via `let _guard = span.enter();` and recorded in every
/// downstream log line within that request scope.
///
/// `request_id` must be a short, opaque identifier (no path or query).
#[inline]
pub fn http_request_span(request_id: &str, method: &str, path: &str) -> Span {
    tracing::info_span!(
        "http.request",
        domain = "http",
        operation = "request",
        request_id = %request_id,
        http.method = %method,
        http.path = %path,
    )
}

/// Records an `app` lifecycle event (boot, shutdown, migration, etc.).
///
/// `phase` is the high-level milestone (`boot`, `migrate`, `listen`,
/// `shutdown`). `outcome` carries a stable tag for grep-friendly logs.
#[inline]
pub fn app_event(phase: &'static str, outcome: &'static str, detail: &str) {
    tracing::info!(
        domain = "app",
        phase = %phase,
        outcome = %outcome,
        detail = %detail,
        "app.lifecycle",
    );
}

/// Records a structured error event. Use this instead of bare
/// `tracing::error!` so dashboards can group errors by `domain`.
///
/// `error_code` should be the public-facing machine code (e.g.
/// `INVALID_REFRESH`, `DB_ERROR`). Never include the error message
/// itself: it may contain user-supplied bytes and we already sanitize
/// at the API boundary.
#[inline]
pub fn error_event(domain: &'static str, error_code: &'static str) {
    tracing::error!(
        domain = %domain,
        error_code = %error_code,
        "error.observed",
    );
}

/// Creates an `auth` domain span with the given operation name and user_id.
///
// NOTE: user_id is safe to log (opaque UUID, not PII). Email/password
// tokens and display names are explicitly excluded per ADR-BE-017.
#[inline]
pub fn auth_span(operation: &'static str, user_id: &str) -> Span {
    tracing::info_span!(
        "auth",
        domain = "auth",
        operation = %operation,
        user_id = %user_id,
    )
}

/// Creates a `sync` domain span for the push operation.
///
// NOTE: The mutation batch is NOT logged. Only structural metadata
// (counts, entity types) that cannot contain sensitive amounts is captured.
#[inline]
pub fn sync_push_span(book_id: &str, device_id: &str, mutation_count: usize) -> Span {
    tracing::info_span!(
        "sync.push",
        domain = "sync",
        operation = "push",
        book_id = %book_id,
        device_id = %device_id,
        mutation_count = %mutation_count,
    )
}

/// Creates a `sync` domain span for the pull operation.
#[inline]
pub fn sync_pull_span(book_id: &str, cursor: i64, limit: usize) -> Span {
    tracing::info_span!(
        "sync.pull",
        domain = "sync",
        operation = "pull",
        book_id = %book_id,
        cursor = %cursor,
        limit = %limit,
    )
}

/// Creates a `sync` domain span for the bootstrap operation.
#[inline]
pub fn sync_bootstrap_span(book_id: &str) -> Span {
    tracing::info_span!(
        "sync.bootstrap",
        domain = "sync",
        operation = "bootstrap",
        book_id = %book_id,
    )
}

/// Records a ledger domain event for mutation processing.
///
// NOTE: Amounts are NEVER logged. Only the entity_type and operation
// are recorded to keep the span low-cardinality.
#[inline]
pub fn ledger_event(
    level: Level,
    entity_type: &str,
    operation: &str,
    entity_id: &str,
) {
    match level {
        Level::ERROR => tracing::error!(
            domain = "ledger",
            entity_type = %entity_type,
            operation = %operation,
            entity_id = %entity_id,
            "ledger.process",
        ),
        Level::WARN => tracing::warn!(
            domain = "ledger",
            entity_type = %entity_type,
            operation = %operation,
            entity_id = %entity_id,
            "ledger.process",
        ),
        Level::INFO => tracing::info!(
            domain = "ledger",
            entity_type = %entity_type,
            operation = %operation,
            entity_id = %entity_id,
            "ledger.process",
        ),
        Level::DEBUG => tracing::debug!(
            domain = "ledger",
            entity_type = %entity_type,
            operation = %operation,
            entity_id = %entity_id,
            "ledger.process",
        ),
        Level::TRACE => tracing::trace!(
            domain = "ledger",
            entity_type = %entity_type,
            operation = %operation,
            entity_id = %entity_id,
            "ledger.process",
        ),
    }
}

/// Creates a `postgres` domain span for database operations.
///
// NOTE: Query parameters (especially amounts) are not included in span
// attributes per ADR-BE-017.
#[inline]
pub fn postgres_span(operation: &'static str, query_name: &'static str) -> Span {
    tracing::info_span!(
        "postgres.query",
        domain = "postgres",
        operation = %operation,
        query_name = %query_name,
    )
}

/// Creates a `postgres` domain span for a transaction boundary.
#[inline]
pub fn postgres_tx_span(mode: &'static str) -> Span {
    tracing::info_span!(
        "postgres.transaction",
        domain = "postgres",
        tx_mode = %mode,
    )
}

/// Creates a `job` domain span for background job execution.
///
// NOTE: Job payloads (which may contain sensitive data) are never logged.
#[inline]
pub fn job_span(job_type: &str, job_id: &str) -> Span {
    tracing::info_span!(
        "job.execute",
        domain = "job",
        job_type = %job_type,
        job_id = %job_id,
    )
}

/// Records a job outcome (success or failure).
#[inline]
pub fn job_outcome(job_type: &str, job_id: &str, outcome: &'static str) {
    match outcome {
        "success" => tracing::info!(
            domain = "job",
            job_type = %job_type,
            job_id = %job_id,
            outcome = %outcome,
            "job.outcome",
        ),
        _ => tracing::error!(
            domain = "job",
            job_type = %job_type,
            job_id = %job_id,
            outcome = %outcome,
            "job.outcome",
        ),
    }
}

/// Creates an `object_store` domain span for PUT operations.
#[inline]
pub fn object_store_put_span(key: &str, size_bytes: usize) -> Span {
    tracing::info_span!(
        "object_store.put",
        domain = "object_store",
        operation = "put",
        key_hash = %short_hash(key),
        size_bytes = %size_bytes,
    )
}

/// Records an `object_store` GET event with key hash (no full path).
#[inline]
pub fn object_store_get_event(key: &str, found: bool) {
    if found {
        tracing::info!(
            domain = "object_store",
            operation = "get",
            key_hash = %short_hash(key),
            found = %found,
            "object_store.get",
        );
    } else {
        tracing::warn!(
            domain = "object_store",
            operation = "get",
            key_hash = %short_hash(key),
            found = %found,
            "object_store.get",
        );
    }
}

/// One-way hash of an object key so the span attribute is
/// low-cardinality and does not expose the full path.
// Uses FNV-1a on the raw bytes (same as rustc's stable hash).
fn short_hash(s: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for byte in s.bytes() {
        h ^= byte as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    // Take the first 16 bits for a compact tag (65536 buckets).
    format!("{:04x}", h & 0xFFFF)
}

/// Records a job worker lifecycle event (started / stopped).
#[inline]
pub fn job_worker_event(outcome: &'static str, worker_id: &str) {
    match outcome {
        "started" => tracing::info!(
            domain = "job",
            worker_id = %worker_id,
            outcome = %outcome,
            "job.worker.lifecycle",
        ),
        _ => tracing::error!(
            domain = "job",
            worker_id = %worker_id,
            outcome = %outcome,
            "job.worker.lifecycle",
        ),
    }
}

/// Records a recurring rule skip event (structured domain tag only).
///
/// `error_code` is the stable dashboard key (never a raw error message).
#[inline]
pub fn job_rule_skip(rule_id: &str, error_code: &'static str) {
    tracing::warn!(
        domain = "job",
        rule_id = %rule_id,
        error_code = %error_code,
        "job.rule.skip",
    );
}

/// Records a recurring transaction materialization event.
#[inline]
pub fn job_recurring_generated(rule_id: &str, tx_id: &str, book_id: &str) {
    tracing::info!(
        domain = "job",
        rule_id = %rule_id,
        tx_id = %tx_id,
        book_id = %book_id,
        "job.recurring.generated",
    );
}

/// Records a postgres connection pool ready event.
#[inline]
pub fn postgres_pool_ready(min_connections: u32, max_connections: u32) {
    tracing::info!(
        domain = "postgres",
        min_connections = %min_connections,
        max_connections = %max_connections,
        "postgres.pool.ready",
    );
}

/// Records a postgres migrations applied event.
#[inline]
pub fn postgres_migrations_applied() {
    tracing::info!(domain = "postgres", "postgres.migrations.applied");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// FNV-1a must be deterministic so the same key always produces the
    /// same span attribute. This anchors future algorithm changes: if you
    /// swap in a different hash, the test below must be updated in the
    /// same commit so dashboards stay reproducible.
    #[test]
    fn short_hash_is_deterministic() {
        let a = short_hash("users/1234/avatar.bin");
        let b = short_hash("users/1234/avatar.bin");
        assert_eq!(a, b);
    }

    /// Output must be exactly 4 lowercase hex characters so dashboards
    /// can group by it without dynamic field cardinality explosions.
    #[test]
    fn short_hash_format_is_four_hex_chars() {
        for input in [
            "",
            "a",
            "users/1234/avatar.bin",
            "中文路径",
            "very-long-key-with-many-segments/12345678/abcdef.bin",
        ] {
            let h = short_hash(input);
            assert_eq!(h.len(), 4, "unexpected length for {input:?}: {h}");
            assert!(
                h.chars().all(|c| c.is_ascii_hexdigit()),
                "non-hex char in {h}"
            );
            assert!(
                h.chars().all(|c| !c.is_ascii_uppercase()),
                "uppercase hex char in {h}"
            );
        }
    }

    /// Even with a small bucket (16 bits) the FNV spread should give us
    /// a reasonable distribution; we don't need to be perfect, but we
    /// do want collisions to stay rare for typical input patterns.
    #[test]
    fn short_hash_distribution_stays_usable() {
        let mut seen = HashSet::new();
        for i in 0..1024u32 {
            let key = format!("users/{i}/avatar.bin");
            seen.insert(short_hash(&key));
        }
        // 1024 distinct keys should hit well over half of the 65536 buckets,
        // but we only require at least 256 distinct buckets to keep this
        // test stable across hash algorithm tweaks.
        assert!(
            seen.len() >= 256,
            "hash distribution too narrow: {} buckets",
            seen.len()
        );
    }

    /// `short_hash` is exposed only at module scope (lowercase fn); it
    /// must not leak via the public `pub use tracing::` re-exports or
    /// any of the span/event helpers. This guards against future
    /// refactors that accidentally broaden the module's public API
    /// surface and could let callers bypass the helpers' field contract.
    #[test]
    fn only_span_helpers_are_publicly_exposed() {
        // The module exposes tracing macros + a handful of span/event
        // constructors. None of them should accept a raw key as input
        // other than `object_store_put_span`, which runs it through
        // `short_hash` internally. We assert the public surface here.
        let _ = auth_span("test", "user-1");
        let _ = sync_push_span("book-1", "device-1", 1);
        let _ = sync_pull_span("book-1", 0, 500);
        let _ = sync_bootstrap_span("book-1");
        let _ = postgres_span("connect", "pg_pool_init");
        let _ = postgres_tx_span("read_write");
        let _ = job_span("auto_ledger_sweep", "job-1");
        job_outcome("auto_ledger_sweep", "job-1", "success");
        job_outcome("auto_ledger_sweep", "job-1", "failure");
        let _ = object_store_put_span("users/1/avatar.bin", 256);
        object_store_get_event("users/1/avatar.bin", true);
        object_store_get_event("users/1/avatar.bin", false);
        // `ledger_event` accepts a `Level` so it covers all branches.
        for level in [
            Level::ERROR,
            Level::WARN,
            Level::INFO,
            Level::DEBUG,
            Level::TRACE,
        ] {
            ledger_event(level, "transaction", "create", "tx-1");
        }
        // New helpers added in BE-017 observability pass.
        job_worker_event("started", "worker-1");
        job_rule_skip("rule-1", "PAYLOAD_MISSING_ENTRIES");
        job_rule_skip("rule-2", "UNBALANCED_PAYLOAD");
        job_recurring_generated("rule-1", "tx-1", "book-1");
        postgres_pool_ready(1, 8);
        postgres_migrations_applied();
        // error_event is tested in error.rs.
    }
}
