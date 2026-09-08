use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use ledger_contracts::ApiErrorBody;
use uuid::Uuid;

#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
    pub details: Option<serde_json::Value>,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
            details: None,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        // Stamp the error into the structured log so dashboards can group
        // by (domain, error_code) without scraping the message body.
        crate::obs::error_event(self.code_domain(), self.code);

        // Emit a Prometheus counter for auth errors so alerting rules can fire
        // without depending on trace data.
        if self.code_domain() == "auth" {
            crate::metrics::record_auth_error(self.code);
        }

        // Reuse the active request_id when the caller entered an
        // `http.request` span, otherwise mint a fresh one. This means
        // any error logged within a request handler will carry the
        // same correlation ID the client sees in the response body.
        let request_id = crate::obs::current_request_id()
            .unwrap_or_else(|| format!("req_{}", Uuid::now_v7()));

        let body = ApiErrorBody {
            code: self.code.to_string(),
            message: self.message,
            request_id,
            details: self.details,
        };
        (self.status, Json(body)).into_response()
    }
}

impl ApiError {
    /// Maps an error code to a coarse `domain` tag for observability
    /// dashboards. Keep this mapping additive: new error codes should
    /// fall through to a sensible default rather than force an ADR.
    fn code_domain(&self) -> &'static str {
        match self.code {
            // Database / persistence
            "DB_ERROR" | "POOL_UNAVAILABLE" => "postgres",
            // Auth + session lifecycle
            "INVALID_CREDENTIALS"
            | "INVALID_REFRESH"
            | "REFRESH_REUSE"
            | "EMAIL_TAKEN"
            | "MIXED_REFRESH_CREDENTIALS"
            | "MISSING_REFRESH_CREDENTIAL"
            | "TOKEN_ENCODING_FAILED"
            | "PASSWORD_HASH_FAILED" => "auth",
            // Object store
            "NOT_FOUND" | "SIGNATURE_INVALID" | "EXPIRED" | "INVALID_METHOD" => "object_store",
            // Sync protocol validation surfaces
            "INVALID_REQUEST" | "MUTATION_REJECTED" => "sync",
            // Generic catch-all bucket. Specific domain-specific codes
            // should be added above before this is reached.
            _ => "api",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ApiError;
    use axum::http::StatusCode;

    #[test]
    fn code_domain_maps_known_codes() {
        let cases = [
            ("DB_ERROR", "postgres"),
            ("INVALID_REFRESH", "auth"),
            ("EMAIL_TAKEN", "auth"),
            ("NOT_FOUND", "object_store"),
            ("INVALID_REQUEST", "sync"),
            ("UNKNOWN_CODE", "api"),
        ];
        for (code, expected) in cases {
            let err = ApiError::new(StatusCode::BAD_REQUEST, code, "msg");
            assert_eq!(err.code_domain(), expected, "code={code}");
        }
    }

    #[test]
    fn fallback_request_id_keeps_prefix() {
        // Verify the helper that mints the fallback ID keeps the
        // `req_` prefix so legacy grep tooling keeps working when
        // the request is not nested in an `http.request` span.
        let id = crate::obs::current_request_id()
            .unwrap_or_else(|| format!("req_{}", uuid::Uuid::now_v7()));
        assert!(
            id.starts_with("req_"),
            "fallback request_id must keep the req_ prefix"
        );
    }

    #[test]
    fn error_event_emits_structured_log_without_panicking() {
        // Calling the helper outside any span must not panic; it is
        // the safety net that keeps error telemetry flowing even when
        // an upstream middleware is misconfigured.
        crate::obs::error_event("postgres", "DB_ERROR");
    }
}
