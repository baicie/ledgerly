use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::Router;
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

async fn post_json(app: &Router, uri: &str, body: serde_json::Value) -> axum::response::Response {
    app.clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap()
}

#[tokio::test]
async fn postgres_migrate_applies_auth_session_indexes() {
    let Some(url) = pg_url() else {
        if std::env::var("REQUIRE_POSTGRES_TESTS").ok().as_deref() == Some("true") {
            panic!("DATABASE_URL is required for PostgreSQL integration tests");
        }
        eprintln!("skip postgres_migrate_applies_auth_session_indexes: DATABASE_URL unset");
        return;
    };

    let mut config = Config::for_test();
    config.database_url = Some(url.clone());
    migrate(&config).await.expect("migrate");

    let pool = sqlx::PgPool::connect(&url).await.expect("connect");
    let indexes = sqlx::query_scalar::<_, String>(
        "SELECT indexname
         FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'device_sessions'",
    )
    .fetch_all(&pool)
    .await
    .expect("list device_sessions indexes");

    assert!(indexes
        .iter()
        .any(|name| name == "idx_device_sessions_refresh_token_hash"));
    assert!(indexes
        .iter()
        .any(|name| name == "idx_device_sessions_active_created_at"));
}

#[tokio::test]
async fn postgres_push_pull_persists() {
    let Some(url) = pg_url() else {
        if std::env::var("REQUIRE_POSTGRES_TESTS").ok().as_deref() == Some("true") {
            panic!("DATABASE_URL is required for PostgreSQL integration tests");
        }
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

#[tokio::test]
async fn postgres_refresh_rotation_is_atomic_and_expires_idle_tokens() {
    let Some(url) = pg_url() else {
        if std::env::var("REQUIRE_POSTGRES_TESTS").ok().as_deref() == Some("true") {
            panic!("DATABASE_URL is required for PostgreSQL integration tests");
        }
        eprintln!(
            "skip postgres_refresh_rotation_is_atomic_and_expires_idle_tokens: DATABASE_URL unset"
        );
        return;
    };

    let mut config = Config::for_test();
    config.database_url = Some(url);
    migrate(&config).await.expect("migrate");
    let state = AppState::new_async(config).await.expect("state");
    let app = app_router(state.clone());
    let email = format!("refresh_{}@test.com", uuid::Uuid::now_v7());
    assert_eq!(
        post_json(
            &app,
            "/v1/auth/register",
            json!({
                "email": email,
                "password": "password123",
                "displayName": "Refresh"
            }),
        )
        .await
        .status(),
        StatusCode::OK
    );

    let login = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": email,
            "password": "password123",
            "deviceId": "concurrent-refresh-device"
        }),
    )
    .await;
    assert_eq!(login.status(), StatusCode::OK);
    let refresh_token = json_body(login).await["refreshToken"]
        .as_str()
        .unwrap()
        .to_string();
    let refresh_request = || {
        post_json(
            &app,
            "/v1/auth/refresh",
            json!({"refreshToken": refresh_token}),
        )
    };

    let (first, second) = tokio::join!(refresh_request(), refresh_request());
    let statuses = [first.status(), second.status()];
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == StatusCode::OK)
            .count(),
        1
    );
    assert_eq!(
        statuses
            .iter()
            .filter(|status| **status == StatusCode::UNAUTHORIZED)
            .count(),
        1
    );

    let expired_login = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": email,
            "password": "password123",
            "deviceId": "expired-refresh-device"
        }),
    )
    .await;
    assert_eq!(expired_login.status(), StatusCode::OK);
    let expired_refresh = json_body(expired_login).await["refreshToken"]
        .as_str()
        .unwrap()
        .to_string();
    sqlx::query(
        "UPDATE device_sessions
         SET created_at = now() - interval '31 days'
         WHERE device_id = 'expired-refresh-device'",
    )
    .execute(state.pool.as_ref().unwrap())
    .await
    .unwrap();

    let expired_response = post_json(
        &app,
        "/v1/auth/refresh",
        json!({"refreshToken": expired_refresh}),
    )
    .await;
    assert_eq!(expired_response.status(), StatusCode::UNAUTHORIZED);
}
