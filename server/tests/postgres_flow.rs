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

#[tokio::test]
async fn postgres_concurrent_updates_use_cas() {
    let Some(url) = pg_url() else {
        eprintln!("skip postgres_concurrent_updates_use_cas: DATABASE_URL unset");
        return;
    };

    let mut config = Config::for_test();
    config.database_url = Some(url);
    migrate(&config).await.expect("migrate");
    let state = AppState::new_async(config).await.expect("state");
    let app = app_router(state);
    let email = format!("cas_{}@test.com", uuid::Uuid::now_v7());

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password":"password123","displayName":"CAS"})
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
                    json!({
                        "email": email,
                        "password":"password123",
                        "deviceId":"dev_cas"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let login = json_body(res).await;
    let token = login["accessToken"].as_str().unwrap().to_string();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let food = format!("{book_id}:acc_food");
    let cash = format!("{book_id}:acc_cash");
    let tx_id = format!("tx_{}", uuid::Uuid::now_v7());

    let initial = json!({
        "deviceId": "dev_cas",
        "mutations": [{
            "mutationId": format!("mut_{}", uuid::Uuid::now_v7()),
            "entityType": "transaction",
            "entityId": tx_id,
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "description": "initial",
                "entries": [
                    {"accountId": food, "amountMinor": "100", "currency": "CNY"},
                    {"accountId": cash, "amountMinor": "-100", "currency": "CNY"}
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
                .body(Body::from(initial.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(json_body(res).await["receipts"][0]["status"], "applied");

    let update = |mutation_id: String, description: &str| {
        json!({
            "deviceId": "dev_cas",
            "mutations": [{
                "mutationId": mutation_id,
                "entityType": "transaction",
                "entityId": tx_id,
                "operation": "update",
                "baseVersion": 1,
                "schemaVersion": 1,
                "payload": {
                    "description": description,
                    "entries": [
                        {"accountId": food, "amountMinor": "100", "currency": "CNY"},
                        {"accountId": cash, "amountMinor": "-100", "currency": "CNY"}
                    ]
                }
            }]
        })
    };
    let request = |body: serde_json::Value| {
        app.clone().oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
    };
    let (res_a, res_b) = tokio::join!(
        request(update(format!("mut_{}", uuid::Uuid::now_v7()), "A")),
        request(update(format!("mut_{}", uuid::Uuid::now_v7()), "B")),
    );
    let a = json_body(res_a.unwrap()).await;
    let b = json_body(res_b.unwrap()).await;
    let statuses = [
        a["receipts"][0]["status"].as_str().unwrap(),
        b["receipts"][0]["status"].as_str().unwrap(),
    ];
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == "applied")
            .count(),
        1
    );
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == "rejected")
            .count(),
        1
    );
    let conflict = if a["receipts"][0]["status"] == "rejected" {
        &a
    } else {
        &b
    };
    assert_eq!(
        conflict["receipts"][0]["resultCode"],
        "LEDGER_VERSION_CONFLICT"
    );
}
