use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiErrorBody {
    pub code: String,
    pub message: String,
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    #[serde(rename = "displayName")]
    pub display_name: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    #[serde(rename = "deviceId")]
    pub device_id: String,
    #[serde(rename = "deviceName")]
    pub device_name: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TokenResponse {
    #[serde(rename = "accessToken")]
    pub access_token: String,
    #[serde(rename = "refreshToken")]
    pub refresh_token: String,
    #[serde(rename = "tokenType")]
    pub token_type: String,
    #[serde(rename = "expiresIn")]
    pub expires_in: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateTransactionRequest {
    #[serde(rename = "bookId")]
    pub book_id: String,
    pub description: Option<String>,
    pub entries: Vec<EntryDto>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EntryDto {
    #[serde(rename = "accountId")]
    pub account_id: String,
    #[serde(rename = "amountMinor")]
    pub amount_minor: String,
    pub currency: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateTransactionResponse {
    #[serde(rename = "transactionId")]
    pub transaction_id: String,
    pub version: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncPushRequest {
    #[serde(rename = "deviceId")]
    pub device_id: String,
    pub mutations: Vec<SyncMutationDto>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncMutationDto {
    #[serde(rename = "mutationId")]
    pub mutation_id: String,
    #[serde(rename = "entityType")]
    pub entity_type: String,
    #[serde(rename = "entityId")]
    pub entity_id: String,
    pub operation: String,
    #[serde(rename = "baseVersion")]
    pub base_version: i64,
    #[serde(rename = "schemaVersion")]
    pub schema_version: i32,
    pub payload: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncPushResponse {
    pub receipts: Vec<MutationReceiptDto>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MutationReceiptDto {
    #[serde(rename = "mutationId")]
    pub mutation_id: String,
    pub status: String,
    #[serde(rename = "resultCode")]
    pub result_code: String,
    #[serde(rename = "entityVersion")]
    pub entity_version: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncPullResponse {
    #[serde(rename = "nextCursor")]
    pub next_cursor: String,
    #[serde(rename = "hasMore")]
    pub has_more: bool,
    pub changes: Vec<SyncChangeDto>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncChangeDto {
    pub sequence: String,
    #[serde(rename = "commitId")]
    pub commit_id: String,
    #[serde(rename = "entityType")]
    pub entity_type: String,
    #[serde(rename = "entityId")]
    pub entity_id: String,
    pub operation: String,
    pub version: i64,
    pub payload: serde_json::Value,
}
