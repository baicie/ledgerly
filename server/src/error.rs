use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
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
        let body = ApiErrorBody {
            code: self.code.to_string(),
            message: self.message,
            request_id: format!("req_{}", Uuid::now_v7()),
            details: self.details,
        };
        (self.status, Json(body)).into_response()
    }
}
