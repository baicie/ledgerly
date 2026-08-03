use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::{app_router, migrate, AppState, Config};
use serde_json::json;
use tower::ServiceExt;

fn pg_url() -> Option<String> {
    std::env::var("DATABASE_URL").ok()
}

async fn json_body(res: axum::response::Response) -> serde_json::Value {
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn postgres_push_pull_persists() {
    let Some(url) = pg_url() else {
        eprintln!("skip postgres_push_pull_persists: DATABASE_URL unset");
        return;
    };

    let mut config = Config::for_test();
    config.database_url = Some(url);
    migrate(&config).await.expect("migrate");
    let state = AppState::new_async(config).await.expect("state");
    assert!(state.using_postgres());

    let app = app_router(state.clone());
    let email = format!("pg_{}@test.com", uuid::Uuid::now_v7());

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password":"password123","displayName":"PG"})
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
                    json!({"email": email, "password":"password123","deviceId":"dev_pg"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let login = json_body(res).await;
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let food = format!("{book_id}:acc_food");
    let cash = format!("{book_id}:acc_cash");

    let ready = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/health/ready")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let ready_body = json_body(ready).await;
    assert_eq!(ready_body["store"], "postgres");

    let mutation = json!({
        "deviceId": "dev_pg",
        "mutations": [{
            "mutationId": format!("mut_{}", uuid::Uuid::now_v7()),
            "entityType": "transaction",
            "entityId": format!("tx_{}", uuid::Uuid::now_v7()),
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "description": "PG lunch",
                "entries": [
                    {"accountId": food, "amountMinor": "1200", "currency": "CNY"},
                    {"accountId": cash, "amountMinor": "-1200", "currency": "CNY"}
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
        .oneshot(
            Request::builder()
                .uri(format!("/v1/books/{book_id}/sync/pull?cursor=0"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let pull = json_body(res).await;
    assert!(!pull["changes"].as_array().unwrap().is_empty());
}
