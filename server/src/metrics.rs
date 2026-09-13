//! Prometheus metrics instrumentation.
//!
//! All metrics follow the naming convention: `<domain>_<name>_<unit>{}`
//! Labels are low-cardinality strings only (no IDs, amounts, or paths).
//!
//! Security: count values are never incremented from error payloads.

use axum::extract::Request;
use metrics::{
    counter, describe_counter, describe_gauge, describe_histogram, gauge, histogram, Unit,
};
use metrics_exporter_prometheus::PrometheusHandle;

/// Prometheus handle stored in app state for /metrics endpoint.
#[derive(Clone)]
pub struct MetricsHandle(pub PrometheusHandle);

impl MetricsHandle {
    pub fn new(handle: PrometheusHandle) -> Self {
        Self(handle)
    }
}

// ---------------------------------------------------------------------------
// Registration — call once at startup before any metric is recorded.
// ---------------------------------------------------------------------------

/// Registers all metric descriptors so Prometheus exporter knows about them.
/// Call this once before `build` or `init` on the PrometheusBuilder.
pub fn register_metrics() {
    describe_histogram!(
        "http_request_duration_seconds",
        Unit::Seconds,
        "End-to-end HTTP request latency, from Accept to last response byte."
    );
    describe_counter!(
        "http_requests_total",
        Unit::Count,
        "Total HTTP requests, labelled by method, route, and status class."
    );
    describe_counter!(
        "auth_errors_total",
        Unit::Count,
        "Authentication and authorization errors, labelled by error code."
    );
    describe_counter!(
        "job_outcomes_total",
        Unit::Count,
        "Background job outcomes (success / failure), labelled by job_type."
    );
    describe_counter!(
        "job_rules_skipped_total",
        Unit::Count,
        "Recurring rule skips due to invalid payload, labelled by error_code."
    );
    describe_counter!(
        "sync_push_mutations_total",
        Unit::Count,
        "Sync push mutations processed, labelled by outcome."
    );
    describe_counter!(
        "sync_pull_responses_total",
        Unit::Count,
        "Sync pull responses, labelled by outcome."
    );
    describe_gauge!(
        "postgres_pool_connections",
        Unit::Count,
        "Current PostgreSQL pool connection count."
    );
    describe_gauge!(
        "postgres_pool_min_connections",
        Unit::Count,
        "Minimum PostgreSQL pool connections configured."
    );
    describe_gauge!(
        "postgres_pool_max_connections",
        Unit::Count,
        "Maximum PostgreSQL pool connections configured."
    );
    describe_gauge!(
        "backup_state",
        Unit::Count,
        "Current backup readiness state, with exactly one state set to 1."
    );
    describe_gauge!(
        "backup_last_run_timestamp_seconds",
        Unit::Seconds,
        "Unix timestamp of the last backup run, labelled by outcome."
    );
    describe_gauge!(
        "backup_age_seconds",
        Unit::Seconds,
        "Age of the last completed backup run."
    );
    describe_gauge!(
        "backup_last_run_duration_seconds",
        Unit::Seconds,
        "Duration of the last completed backup run, labelled by outcome."
    );
    describe_gauge!(
        "backup_bundle_count",
        Unit::Count,
        "Number of valid retained backup bundles, labelled by location."
    );
    describe_gauge!(
        "backup_bundle_bytes",
        Unit::Bytes,
        "Stored payload and manifest bytes in valid retained bundles."
    );
    describe_gauge!(
        "backup_bundle_invalid",
        Unit::Count,
        "Number of invalid retained bundle directories, labelled by location."
    );
    describe_gauge!(
        "backup_replication_enabled",
        Unit::Count,
        "Whether offsite backup replication is configured."
    );
    describe_gauge!(
        "backup_capacity_limit_bytes",
        Unit::Bytes,
        "Configured backup capacity threshold, labelled by location and severity."
    );
    describe_gauge!(
        "backup_capacity_utilization_percent",
        Unit::Percent,
        "Backup storage usage as a percentage of the configured threshold."
    );
    describe_gauge!(
        "backup_recovery_drill_state",
        Unit::Count,
        "Current recovery drill state, with exactly one state set to 1."
    );
    describe_gauge!(
        "backup_recovery_drill_age_seconds",
        Unit::Seconds,
        "Age of the last completed recovery drill."
    );
    describe_gauge!(
        "backup_recovery_drill_last_run_timestamp_seconds",
        Unit::Seconds,
        "Unix timestamp of the last recovery drill, labelled by outcome."
    );
    describe_gauge!(
        "backup_recovery_drill_last_run_duration_seconds",
        Unit::Seconds,
        "Duration of the last recovery drill, labelled by outcome."
    );
    describe_gauge!(
        "backup_restore_state",
        Unit::Count,
        "Current one-command restore state, with exactly one state set to 1."
    );
    describe_gauge!(
        "backup_restore_age_seconds",
        Unit::Seconds,
        "Age of the last completed one-command restore."
    );
    describe_gauge!(
        "backup_restore_last_run_timestamp_seconds",
        Unit::Seconds,
        "Unix timestamp of the last one-command restore, labelled by outcome."
    );
    describe_gauge!(
        "backup_restore_last_run_duration_seconds",
        Unit::Seconds,
        "Duration of the last one-command restore, labelled by outcome."
    );
    describe_counter!(
        "backup_runs_total",
        Unit::Count,
        "Backup runs completed in this process, labelled by outcome."
    );
    describe_counter!(
        "backup_recovery_drill_runs_total",
        Unit::Count,
        "Recovery drills completed in this process, labelled by outcome."
    );
    describe_counter!(
        "backup_restore_runs_total",
        Unit::Count,
        "One-command restores completed in this process, labelled by outcome."
    );
    describe_counter!(
        "backup_cleanup_failures_total",
        Unit::Count,
        "Backup bundle retention cleanup failures, labelled by location."
    );
    describe_counter!(
        "backup_metrics_collection_errors_total",
        Unit::Count,
        "Backup metric collection failures, labelled by component."
    );
    describe_counter!(
        "object_store_operations_total",
        Unit::Count,
        "Object storage operations, labelled by backend, operation, and outcome."
    );
    describe_histogram!(
        "object_store_operation_duration_seconds",
        Unit::Seconds,
        "Object storage operation latency, labelled by backend and operation."
    );
}

// ---------------------------------------------------------------------------
// Metric accessors — call these at instrumentation sites.
// ---------------------------------------------------------------------------

/// Maps a dynamic error_code string to a static label. If the input is
/// already known we use that label; otherwise we collapse it to "OTHER"
/// to keep label cardinality bounded. This is the standard Prometheus
/// pattern for high-cardinality fields.
fn static_label(known: &[&'static str], value: &str) -> &'static str {
    if let Some(&hit) = known.iter().find(|&&k| k == value) {
        return hit;
    }
    "OTHER"
}

/// Known auth error codes — keep in sync with `crate::error::ApiError` codes.
static AUTH_ERROR_CODES: &[&str] = &[
    "AUTH_INVALID_CREDENTIALS",
    "AUTH_EMAIL_TAKEN",
    "AUTH_DEVICE_REQUIRED",
    "AUTH_TOKEN_INVALID",
    "AUTH_TOKEN_EXPIRED",
    "AUTH_REFRESH_REUSED",
    "AUTH_RATE_LIMITED",
    "AUTH_PAYLOAD_TOO_LARGE",
    "AUTH_PAYLOAD_INVALID",
    "AUTH_DISPLAY_NAME_INVALID",
    "AUTH_PASSWORD_TOO_WEAK",
    "AUTH_UNSUPPORTED_SESSION_MODE",
    "AUTH_INTERNAL",
];

/// Known job types.
static JOB_TYPES: &[&str] = &[
    "purge_expired_sessions",
    "enqueue_recurring_scan",
    "generate_due_recurring",
    "auto_ledger_sweep",
    "backup_bundle",
    "recovery_drill",
    "worker",
];

/// Records an authentication/authorization error.
pub fn record_auth_error(error_code: &str) {
    let label = static_label(AUTH_ERROR_CODES, error_code);
    counter!("auth_errors_total", "error_code" => label).increment(1);
}

/// Records a background job outcome.
pub fn record_job_outcome(job_type: &str, outcome: &'static str) {
    let label = static_label(JOB_TYPES, job_type);
    counter!("job_outcomes_total", "job_type" => label, "outcome" => outcome).increment(1);
}

/// Records a recurring rule skip.
pub fn record_job_rule_skip(error_code: &'static str) {
    counter!("job_rules_skipped_total", "error_code" => error_code).increment(1);
}

/// Records a recurring transaction materialization.
pub fn record_job_recurring_generated() {
    counter!("job_recurring_generated_total").increment(1);
}

/// Records a sync push mutation result.
pub fn record_sync_push(outcome: &'static str) {
    counter!("sync_push_mutations_total", "outcome" => outcome).increment(1);
}

/// Records a sync pull response result.
pub fn record_sync_pull(outcome: &'static str) {
    counter!("sync_pull_responses_total", "outcome" => outcome).increment(1);
}

/// Records PostgreSQL pool connection count (called periodically or on events).
pub fn record_postgres_pool_connections(current: u32, min: u32, max: u32) {
    gauge!("postgres_pool_connections", "role" => "current").set(current as f64);
    gauge!("postgres_pool_min_connections", "role" => "config").set(min as f64);
    gauge!("postgres_pool_max_connections", "role" => "config").set(max as f64);
}

static BACKUP_STATES: &[&str] = &["disabled", "never_run", "failed", "stale", "ready"];
static RUN_OUTCOMES: &[&str] = &["success", "failure"];
static STORAGE_LOCATIONS: &[&str] = &["local", "offsite"];
static CAPACITY_SEVERITIES: &[&str] = &["warning", "critical"];
static METRIC_COMPONENTS: &[&str] = &[
    "backup_status",
    "recovery_drill_status",
    "restore_status",
    "storage",
];
static OBJECT_STORE_BACKENDS: &[&str] = &["local", "s3"];
static OBJECT_STORE_OPERATIONS: &[&str] =
    &["put", "get", "head", "list", "backup", "restore", "migrate"];

pub fn record_backup_status(
    state: &str,
    outcome: Option<&str>,
    timestamp_seconds: Option<f64>,
    duration_seconds: Option<f64>,
    age_seconds: Option<f64>,
) {
    record_run_status(
        "backup_state",
        "backup_last_run_timestamp_seconds",
        "backup_last_run_duration_seconds",
        "backup_age_seconds",
        state,
        outcome,
        timestamp_seconds,
        duration_seconds,
        age_seconds,
    );
}

pub fn record_recovery_drill_status(
    state: &str,
    outcome: Option<&str>,
    timestamp_seconds: Option<f64>,
    duration_seconds: Option<f64>,
    age_seconds: Option<f64>,
) {
    record_run_status(
        "backup_recovery_drill_state",
        "backup_recovery_drill_last_run_timestamp_seconds",
        "backup_recovery_drill_last_run_duration_seconds",
        "backup_recovery_drill_age_seconds",
        state,
        outcome,
        timestamp_seconds,
        duration_seconds,
        age_seconds,
    );
}

pub fn record_restore_status(
    state: &str,
    outcome: Option<&str>,
    timestamp_seconds: Option<f64>,
    duration_seconds: Option<f64>,
    age_seconds: Option<f64>,
) {
    record_run_status(
        "backup_restore_state",
        "backup_restore_last_run_timestamp_seconds",
        "backup_restore_last_run_duration_seconds",
        "backup_restore_age_seconds",
        state,
        outcome,
        timestamp_seconds,
        duration_seconds,
        age_seconds,
    );
}

#[allow(clippy::too_many_arguments)]
fn record_run_status(
    state_metric: &'static str,
    timestamp_metric: &'static str,
    duration_metric: &'static str,
    age_metric: &'static str,
    state: &str,
    outcome: Option<&str>,
    timestamp_seconds: Option<f64>,
    duration_seconds: Option<f64>,
    age_seconds: Option<f64>,
) {
    let state = static_label(BACKUP_STATES, state);
    for candidate in BACKUP_STATES {
        gauge!(state_metric, "state" => *candidate).set(if *candidate == state {
            1.0
        } else {
            0.0
        });
    }

    let outcome = outcome.map(|value| static_label(RUN_OUTCOMES, value));
    for candidate in RUN_OUTCOMES {
        gauge!(timestamp_metric, "outcome" => *candidate).set(if outcome == Some(*candidate) {
            timestamp_seconds.unwrap_or_default()
        } else {
            0.0
        });
        gauge!(duration_metric, "outcome" => *candidate).set(if outcome == Some(*candidate) {
            duration_seconds.unwrap_or_default()
        } else {
            0.0
        });
    }
    gauge!(age_metric).set(age_seconds.unwrap_or_default());
}

pub fn record_backup_storage(
    location: &'static str,
    bundle_count: usize,
    total_bytes: u64,
    invalid_count: usize,
) {
    let location = static_label(STORAGE_LOCATIONS, location);
    gauge!("backup_bundle_count", "location" => location).set(bundle_count as f64);
    gauge!("backup_bundle_bytes", "location" => location).set(total_bytes as f64);
    gauge!("backup_bundle_invalid", "location" => location).set(invalid_count as f64);
}

pub fn record_backup_capacity(
    location: &'static str,
    used_bytes: u64,
    warn_bytes: u64,
    critical_bytes: u64,
) {
    let location = static_label(STORAGE_LOCATIONS, location);
    for (severity, limit_bytes) in [("warning", warn_bytes), ("critical", critical_bytes)] {
        let severity = static_label(CAPACITY_SEVERITIES, severity);
        gauge!(
            "backup_capacity_limit_bytes",
            "location" => location,
            "severity" => severity
        )
        .set(limit_bytes as f64);
        gauge!(
            "backup_capacity_utilization_percent",
            "location" => location,
            "severity" => severity
        )
        .set(used_bytes as f64 / limit_bytes.max(1) as f64 * 100.0);
    }
}

pub fn record_replication_enabled(enabled: bool) {
    gauge!("backup_replication_enabled").set(if enabled { 1.0 } else { 0.0 });
}

pub fn record_backup_run(outcome: &'static str) {
    let outcome = static_label(RUN_OUTCOMES, outcome);
    counter!("backup_runs_total", "outcome" => outcome).increment(1);
}

pub fn record_recovery_drill_run(outcome: &'static str) {
    let outcome = static_label(RUN_OUTCOMES, outcome);
    counter!("backup_recovery_drill_runs_total", "outcome" => outcome).increment(1);
}

pub fn record_restore_run(outcome: &'static str) {
    let outcome = static_label(RUN_OUTCOMES, outcome);
    counter!("backup_restore_runs_total", "outcome" => outcome).increment(1);
}

pub fn record_backup_cleanup_failure(location: &'static str) {
    let location = static_label(STORAGE_LOCATIONS, location);
    counter!("backup_cleanup_failures_total", "location" => location).increment(1);
}

pub fn record_backup_metrics_collection_error(component: &'static str) {
    let component = static_label(METRIC_COMPONENTS, component);
    counter!("backup_metrics_collection_errors_total", "component" => component).increment(1);
}

pub fn record_object_store_operation(
    backend: &'static str,
    operation: &'static str,
    outcome: &'static str,
    duration_seconds: f64,
) {
    let backend = static_label(OBJECT_STORE_BACKENDS, backend);
    let operation = static_label(OBJECT_STORE_OPERATIONS, operation);
    let outcome = static_label(RUN_OUTCOMES, outcome);
    counter!(
        "object_store_operations_total",
        "backend" => backend,
        "operation" => operation,
        "outcome" => outcome
    )
    .increment(1);
    histogram!(
        "object_store_operation_duration_seconds",
        "backend" => backend,
        "operation" => operation
    )
    .record(duration_seconds);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

fn status_class(status: u16) -> &'static str {
    match status {
        100..=199 => "1xx",
        200..=299 => "2xx",
        300..=399 => "3xx",
        400..=499 => "4xx",
        500..=599 => "5xx",
        _ => "unknown",
    }
}

// ---------------------------------------------------------------------------
// Axum middleware for HTTP metrics
// ---------------------------------------------------------------------------

/// Allowed HTTP route patterns. Anything not in this list is collapsed to
/// "OTHER" so an attacker hitting unknown paths cannot blow up label
/// cardinality.
static HTTP_ROUTES: &[&str] = &[
    "/health/live",
    "/health/ready",
    "/health/startup",
    "/metrics",
    "/v1/auth/register",
    "/v1/auth/login",
    "/v1/auth/refresh",
    "/v1/auth/logout",
    "/v1/auth/me",
    "/v1/books",
    "/v1/transactions",
    "/v1/sync/push",
    "/v1/sync/pull",
    "/v1/sync/bootstrap",
    "/v1/reports/monthly",
    "/v1/billing/dev-upgrade",
    "/v1/commercial/upgrade",
    "/v1/object_store/sign",
];

/// Records `http_request_duration_seconds` and `http_requests_total` for every
/// HTTP request. Route labels come from axum's `MatchedPath` extension
/// (filtered through the known-routes list to keep cardinality bounded).
///
/// This runs as Axum middleware so it has full access to both the Request
/// (for method/route) and the Response (for status code).
///
/// Security: request bodies are never accessed; only metadata is recorded.
pub async fn http_metrics_middleware(
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let start = std::time::Instant::now();

    // Extract route from MatchedPath (set by axum routing).
    let method = request.method().as_str().to_owned();
    let matched_route = request
        .extensions()
        .get::<axum::extract::MatchedPath>()
        .map(|m| m.as_str().to_owned())
        .unwrap_or_else(|| "unknown".to_owned());

    // Collapse unknown routes to "OTHER" to bound label cardinality.
    let route: &'static str = if HTTP_ROUTES.iter().any(|r| *r == matched_route) {
        // SAFETY: matched_route equals one of HTTP_ROUTES, so this lifetime
        // extension is sound (the static slice outlives this function).
        // We look up the matching static str directly to avoid relying on
        // transmute; the lookup guarantees the returned reference is 'static.
        HTTP_ROUTES
            .iter()
            .find(|r| **r == matched_route)
            .copied()
            .unwrap()
    } else {
        "OTHER"
    };

    let response = next.run(request).await;

    let elapsed = start.elapsed().as_secs_f64();
    let status = response.status().as_u16();
    let status_class = status_class(status);

    counter!("http_requests_total",
        "method" => method.clone(),
        "route" => route,
        "status_class" => status_class)
    .increment(1);
    histogram!("http_request_duration_seconds",
        "route" => route,
        "method" => method,
        "status_class" => status_class)
    .record(elapsed);

    response
}

/// Returns the default HTTP trace layer that creates one tracing span per
/// request. Structured fields (domain, http.method, http.route) match
/// the Prometheus metrics emitted by `http_metrics_middleware` so
/// dashboards can correlate trace spans with metrics.
///
/// Security: request bodies are never logged.
///
/// Implementation note: returning a typed `TraceLayer` here requires
/// working around tower-http's high-arity generics. We instead expose
/// `make_span_fn` and let `bootstrap.rs` wrap it with `TraceLayer::new_for_http`.
pub fn make_span_fn() -> impl Fn(&Request) -> tracing::Span + Clone + Send + Sync + 'static {
    |request: &Request| {
        let route = request
            .extensions()
            .get::<axum::extract::MatchedPath>()
            .map(|m| m.as_str().to_owned())
            .unwrap_or_else(|| "unknown".to_owned());

        tracing::info_span!(
            "http_request",
            domain = "http",
            operation = "request",
            http.method = %request.method(),
            http.route = %route,
            otel.name = %format!("{} {}", request.method(), route),
            otel.kind = "server",
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_class_groups_correctly() {
        assert_eq!(status_class(200), "2xx");
        assert_eq!(status_class(201), "2xx");
        assert_eq!(status_class(404), "4xx");
        assert_eq!(status_class(500), "5xx");
        assert_eq!(status_class(301), "3xx");
        assert_eq!(status_class(101), "1xx");
        assert_eq!(status_class(600), "unknown");
    }
}
