use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::{AppState, Config, app_router};
use serde_json::json;
use tower::ServiceExt;

fn test_state() -> AppState {
    AppState::new(Config {
        listen_addr: "127.0.0.1:0".into(),
        database_url: None,
        jwt_secret: "test-secret".into(),
    })
}

async fn json_body(res: axum::response::Response) -> serde_json::Value {
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn health_live_ok() {
    let app = app_router(test_state());
    let res = app
        .oneshot(
            Request::builder()
                .uri("/health/live")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn register_login_and_sync_push_pull() {
    let state = test_state();
    let app = app_router(state.clone());

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"a@b.com","password":"password123","displayName":"A"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"a@b.com","password":"password123","deviceId":"dev1"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let login = json_body(res).await;
    assert!(login.get("accessToken").is_some());

    let book_id = {
        let store = state.store.read().await;
        store.books.values().next().unwrap().id.clone()
    };

    let mutation = json!({
        "deviceId": "dev1",
        "mutations": [{
            "mutationId": "mut_1",
            "entityType": "transaction",
            "entityId": "tx_1",
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "description": "Lunch",
                "entries": [
                    {"accountId": "acc_food", "amountMinor": "2500", "currency": "CNY"},
                    {"accountId": "acc_cash", "amountMinor": "-2500", "currency": "CNY"}
                ]
            }
        }]
    });

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let push = json_body(res).await;
    assert_eq!(push["receipts"][0]["status"], "applied");

    // Idempotent replay
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let push2 = json_body(res).await;
    assert_eq!(push2["receipts"][0]["status"], "applied");

    let res = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/sync/pull?cursor=0"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let pull = json_body(res).await;
    assert_eq!(pull["changes"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn unbalanced_mutation_rejected() {
    let state = test_state();
    let app = app_router(state.clone());
    let _ = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"c@d.com","password":"password123","displayName":"C"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let _ = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"c@d.com","password":"password123","deviceId":"dev2"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let book_id = {
        let store = state.store.read().await;
        store.books.values().next().unwrap().id.clone()
    };

    let mutation = json!({
        "deviceId": "dev2",
        "mutations": [{
            "mutationId": "mut_bad",
            "entityType": "transaction",
            "entityId": "tx_bad",
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "entries": [
                    {"accountId": "acc_food", "amountMinor": "100", "currency": "CNY"},
                    {"accountId": "acc_cash", "amountMinor": "-50", "currency": "CNY"}
                ]
            }
        }]
    });
    let res = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let body = json_body(res).await;
    assert_eq!(body["receipts"][0]["status"], "rejected");
    assert_eq!(body["receipts"][0]["resultCode"], "LEDGER_UNBALANCED");
}
