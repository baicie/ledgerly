use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::{app_router, AppState, Config};
use serde_json::json;
use tower::ServiceExt;

fn test_state() -> AppState {
    AppState::new(Config::for_test())
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
async fn object_store_signed_put_get() {
    let mut cfg = Config::for_test();
    cfg.object_store_public_base = "http://127.0.0.1:0".into();
    let _ = std::fs::create_dir_all(&cfg.object_store_dir);
    let state = AppState::new(cfg.clone());
    let app = app_router(state);

    let key = "books/demo/a1";
    let put_url = ledger_server::infrastructure::object_store::sign_url(&cfg, "PUT", key, 600);
    // Extract path+query from absolute URL for oneshot.
    let put_path = put_url.trim_start_matches(&cfg.object_store_public_base);
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(put_path)
                .body(Body::from(vec![1, 2, 3, 4]))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::NO_CONTENT);

    let get_url = ledger_server::infrastructure::object_store::sign_url(&cfg, "GET", key, 600);
    let get_path = get_url.trim_start_matches(&cfg.object_store_public_base);
    let res = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(get_path)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn sync_requires_auth() {
    let app = app_router(test_state());
    let res = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/books/book_x/sync/push")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"deviceId":"d","mutations":[]}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
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
                    json!({"email":"a@b.com","password":"password123","displayName":"A"})
                        .to_string(),
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
                    json!({"email":"a@b.com","password":"password123","deviceId":"dev1"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let login = json_body(res).await;
    assert!(login.get("accessToken").is_some());
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let food = format!("{book_id}:acc_food");
    let cash = format!("{book_id}:acc_cash");

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
                    {"accountId": food, "amountMinor": "2500", "currency": "CNY"},
                    {"accountId": cash, "amountMinor": "-2500", "currency": "CNY"}
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
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let push = json_body(res).await;
    assert_eq!(push["receipts"][0]["status"], "applied");

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let push2 = json_body(res).await;
    assert_eq!(push2["receipts"][0]["status"], "applied");

    let delete_mutation = json!({
        "deviceId": "dev1",
        "mutations": [{
            "mutationId": "mut_del",
            "entityType": "transaction",
            "entityId": "tx_1",
            "operation": "delete",
            "baseVersion": 1,
            "schemaVersion": 1,
            "payload": {"deleted": true}
        }]
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(delete_mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let del = json_body(res).await;
    assert_eq!(del["receipts"][0]["status"], "applied");

    // budget progress after expense (deleted so spent may be 0 — create fresh)
    let mut_budget = json!({
        "deviceId": "dev1",
        "mutations": [{
            "mutationId": "mut_food2",
            "entityType": "transaction",
            "entityId": "tx_food2",
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "description": "Dinner",
                "entries": [
                    {"accountId": food, "amountMinor": "800", "currency": "CNY"},
                    {"accountId": cash, "amountMinor": "-800", "currency": "CNY"}
                ]
            }
        }]
    });
    let _ = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(mut_budget.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/budgets"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "name": "Food",
                        "amountMinor": "5000",
                        "categoryAccountId": food
                    })
                    .to_string(),
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
                .uri(format!("/v1/books/{book_id}/budgets"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let budgets = json_body(res).await;
    assert_eq!(budgets["budgets"][0]["spentMinor"], "800");
    assert_eq!(budgets["budgets"][0]["remainingMinor"], "4200");

    let res = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/sync/pull?cursor=0"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let pull = json_body(res).await;
    assert!(pull["changes"].as_array().unwrap().len() >= 2);
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
                    json!({"email":"c@d.com","password":"password123","displayName":"C"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email":"c@d.com","password":"password123","deviceId":"dev2"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let login = json_body(res).await;
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let food = format!("{book_id}:acc_food");
    let cash = format!("{book_id}:acc_cash");

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
                    {"accountId": food, "amountMinor": "100", "currency": "CNY"},
                    {"accountId": cash, "amountMinor": "-50", "currency": "CNY"}
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
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let body = json_body(res).await;
    assert_eq!(body["receipts"][0]["status"], "rejected");
    assert_eq!(body["receipts"][0]["resultCode"], "LEDGER_UNBALANCED");
}

#[tokio::test]
async fn logout_revokes_access_token() {
    let app = app_router(test_state());
    let _ = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email":"logout@test.com",
                        "password":"password123",
                        "displayName":"Logout"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email":"logout@test.com",
                        "password":"password123",
                        "deviceId":"logout-device"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let login = json_body(res).await;
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap();

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::NO_CONTENT);

    let res = app
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/sync/pull?cursor=0"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}
