use axum::body::Body;
use axum::http::{
    header::{CACHE_CONTROL, PRAGMA, SET_COOKIE},
    Request, StatusCode,
};
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

async fn post_json(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
) -> axum::response::Response {
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

async fn register_user(app: &axum::Router, email: &str) -> axum::response::Response {
    post_json(
        app,
        "/v1/auth/register",
        json!({
            "email": email,
            "password": "password123",
            "displayName": "Session Test"
        }),
    )
    .await
}

fn response_cookie(res: &axum::response::Response) -> String {
    res.headers()
        .get(SET_COOKIE)
        .expect("set-cookie header")
        .to_str()
        .unwrap()
        .to_string()
}

fn cookie_pair(set_cookie: &str) -> &str {
    set_cookie.split(';').next().unwrap()
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
async fn registration_normalizes_identity_fields() {
    let state = test_state();
    let app = app_router(state.clone());

    let registered = post_json(
        &app,
        "/v1/auth/register",
        json!({
            "email": " Person@Example.COM ",
            "password": "password123",
            "displayName": "  Person  "
        }),
    )
    .await;
    assert_eq!(registered.status(), StatusCode::OK);

    {
        let store = state.store.read().await;
        let user_id = store.users_by_email.get("person@example.com").unwrap();
        let user = store.users.get(user_id).unwrap();
        assert_eq!(user.email, "person@example.com");
        assert_eq!(user.display_name, "Person");
    }

    let login = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": " PERSON@EXAMPLE.COM ",
            "password": "password123",
            "deviceId": "  device-1  "
        }),
    )
    .await;
    assert_eq!(login.status(), StatusCode::OK);

    let store = state.store.read().await;
    assert_eq!(
        store.sessions.values().next().unwrap().device_id,
        "device-1"
    );
}

#[tokio::test]
async fn registration_rejects_invalid_identity_fields_with_stable_codes() {
    let app = app_router(test_state());
    let cases = [
        (
            json!({
                "email": "not-an-email",
                "password": "password123",
                "displayName": "Person"
            }),
            "INVALID_EMAIL",
        ),
        (
            json!({
                "email": "person@example.com",
                "password": "short",
                "displayName": "Person"
            }),
            "WEAK_PASSWORD",
        ),
        (
            json!({
                "email": "person@example.com",
                "password": "p".repeat(129),
                "displayName": "Person"
            }),
            "WEAK_PASSWORD",
        ),
        (
            json!({
                "email": "person@example.com",
                "password": "password123",
                "displayName": " "
            }),
            "INVALID_DISPLAY_NAME",
        ),
        (
            json!({
                "email": "person@example.com",
                "password": "password123",
                "displayName": "n".repeat(81)
            }),
            "INVALID_DISPLAY_NAME",
        ),
    ];

    for (request, expected_code) in cases {
        let response = post_json(&app, "/v1/auth/register", request).await;
        assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
        let body = json_body(response).await;
        assert_eq!(body["code"], expected_code);
    }
}

#[tokio::test]
async fn login_rejects_invalid_device_ids() {
    let app = app_router(test_state());
    assert_eq!(
        register_user(&app, "device-validation@example.com")
            .await
            .status(),
        StatusCode::OK
    );

    for device_id in [String::new(), "d".repeat(129)] {
        let response = post_json(
            &app,
            "/v1/auth/login",
            json!({
                "email": "device-validation@example.com",
                "password": "password123",
                "deviceId": device_id
            }),
        )
        .await;
        assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
        let body = json_body(response).await;
        assert_eq!(body["code"], "INVALID_DEVICE_ID");
    }
}

#[tokio::test]
async fn login_rejects_oversized_password_before_verification() {
    let app = app_router(test_state());
    let response = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": "person@example.com",
            "password": "p".repeat(129),
            "deviceId": "device-1"
        }),
    )
    .await;

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let body = json_body(response).await;
    assert_eq!(body["code"], "INVALID_PASSWORD");
}

#[tokio::test]
async fn unsupported_session_modes_return_stable_errors() {
    let app = app_router(test_state());
    for (uri, body) in [
        (
            "/v1/auth/login",
            json!({
                "email": "person@example.com",
                "password": "password123",
                "deviceId": "device-1",
                "sessionMode": "unsupported"
            }),
        ),
        (
            "/v1/auth/refresh",
            json!({
                "sessionMode": "unsupported"
            }),
        ),
    ] {
        let response = post_json(&app, uri, body).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST, "{uri}");
        let response_body = json_body(response).await;
        assert_eq!(response_body["code"], "UNSUPPORTED_SESSION_MODE", "{uri}");
    }
}

#[tokio::test]
async fn auth_payloads_over_16_kib_are_rejected() {
    let app = app_router(test_state());
    let response = post_json(
        &app,
        "/v1/auth/register",
        json!({
            "email": "person@example.com",
            "password": "password123",
            "displayName": "x".repeat(17 * 1024)
        }),
    )
    .await;

    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
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
    assert_eq!(res.headers().get(CACHE_CONTROL).unwrap(), "no-store");
    assert_eq!(res.headers().get(PRAGMA).unwrap(), "no-cache");
    let login = json_body(res).await;
    assert!(login.get("accessToken").is_some());
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let food = format!("{book_id}:acc_food");
    let cash = format!("{book_id}:acc_cash");

    let custom_category = format!("{book_id}:category_coffee");
    let category_and_transaction = json!({
        "deviceId": "dev1",
        "mutations": [
            {
                "mutationId": "mut_category_create",
                "entityType": "account",
                "entityId": custom_category,
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "name": "Coffee",
                    "accountType": "expense",
                    "currency": "CNY"
                }
            },
            {
                "mutationId": "mut_category_transaction",
                "entityType": "transaction",
                "entityId": "tx_category_coffee",
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "description": "Coffee beans",
                    "entries": [
                        {"accountId": custom_category, "amountMinor": "8800", "currency": "CNY"},
                        {"accountId": cash, "amountMinor": "-8800", "currency": "CNY"}
                    ]
                }
            }
        ]
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(category_and_transaction.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let category_push = json_body(res).await;
    assert_eq!(category_push["receipts"][0]["status"], "applied");
    assert_eq!(category_push["receipts"][1]["status"], "applied");

    let rename_category = json!({
        "deviceId": "dev1",
        "mutations": [{
            "mutationId": "mut_category_rename",
            "entityType": "account",
            "entityId": custom_category,
            "operation": "update",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "name": "  Coffee & Tea  ",
                "accountType": "income",
                "currency": "USD"
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
                .body(Body::from(rename_category.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let category_rename = json_body(res).await;
    assert_eq!(category_rename["receipts"][0]["status"], "applied");
    assert_eq!(category_rename["receipts"][0]["entityVersion"], 2);

    let idempotent_rename = json!({
        "deviceId": "dev1",
        "mutations": [{
            "mutationId": "mut_category_idempotent_rename",
            "entityType": "account",
            "entityId": custom_category,
            "operation": "update",
            "baseVersion": 1,
            "schemaVersion": 1,
            "payload": {
                "name": "Coffee Final",
                "accountType": "expense",
                "currency": "CNY"
            }
        }]
    });
    let request = || {
        app.clone().oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(idempotent_rename.to_string()))
                .unwrap(),
        )
    };
    let (first, retry) = tokio::join!(request(), request());
    for response in [first.unwrap(), retry.unwrap()] {
        let receipt = json_body(response).await;
        assert_eq!(receipt["receipts"][0]["status"], "applied");
        assert_eq!(receipt["receipts"][0]["entityVersion"], 3);
    }

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
        .clone()
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
    assert!(pull["changes"].as_array().unwrap().iter().any(|change| {
        change["entityType"] == "account"
            && change["entityId"] == format!("{book_id}:category_coffee")
            && change["version"] == 3
            && change["payload"]["name"] == "Coffee Final"
            && change["payload"]["accountType"] == "expense"
            && change["payload"]["currency"] == "CNY"
    }));

    let res = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/bootstrap"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let bootstrap = json_body(res).await;
    assert!(bootstrap["accounts"]
        .as_array()
        .unwrap()
        .iter()
        .any(|account| {
            account["id"] == format!("{book_id}:category_coffee")
                && account["version"] == 3
                && account["name"] == "Coffee Final"
                && account["accountType"] == "expense"
                && account["currency"] == "CNY"
        }));
}

#[tokio::test]
async fn transaction_rejects_a_missing_account() {
    let state = test_state();
    let app = app_router(state.clone());
    assert_eq!(
        register_user(&app, "account-owner@example.com")
            .await
            .status(),
        StatusCode::OK
    );
    let login = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": "account-owner@example.com",
            "password": "password123",
            "deviceId": "account-owner-device"
        }),
    )
    .await;
    let login = json_body(login).await;
    let token = login["accessToken"].as_str().unwrap();
    let book_id = login["bookId"].as_str().unwrap();

    let mutation = json!({
        "deviceId": "account-owner-device",
        "mutations": [{
            "mutationId": "mut_missing_account",
            "entityType": "transaction",
            "entityId": "tx_missing_account",
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "entries": [
                    {"accountId": format!("{book_id}:missing"), "amountMinor": "100", "currency": "CNY"},
                    {"accountId": format!("{book_id}:acc_cash"), "amountMinor": "-100", "currency": "CNY"}
                ]
            }
        }]
    });
    let response = app
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
    let body = json_body(response).await;
    assert_eq!(body["receipts"][0]["status"], "rejected");
    assert_eq!(body["receipts"][0]["resultCode"], "ACCOUNT_NOT_FOUND");
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

#[tokio::test]
async fn native_refresh_token_rotates_and_rejects_reuse() {
    let app = app_router(test_state());
    let registered = register_user(&app, "native-session@test.com").await;
    assert_eq!(registered.status(), StatusCode::OK);

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": "native-session@test.com",
                        "password": "password123",
                        "deviceId": "native-device"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let login = json_body(res).await;
    let first_refresh = login["refreshToken"].as_str().unwrap().to_string();

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"refreshToken": first_refresh}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let refresh = json_body(res).await;
    assert_ne!(refresh["refreshToken"], first_refresh);

    let res = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"refreshToken": first_refresh}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn cookie_session_rotates_without_exposing_refresh_token_and_logout_clears_it() {
    let mut config = Config::for_test();
    config.auth_cookie_secure = true;
    let app = app_router(AppState::new(config));
    let registered = register_user(&app, "web-session@test.com").await;
    assert_eq!(registered.status(), StatusCode::OK);

    let login_res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": "web-session@test.com",
                        "password": "password123",
                        "deviceId": "web-device",
                        "sessionMode": "cookie"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(login_res.status(), StatusCode::OK);
    let login_cookie = response_cookie(&login_res);
    assert!(login_cookie.starts_with("ledgerly_refresh="));
    assert!(login_cookie.contains("HttpOnly"));
    assert!(login_cookie.contains("Secure"));
    assert!(login_cookie.contains("SameSite=Strict"));
    assert!(login_cookie.contains("Path=/v1/auth"));
    assert!(!login_cookie.contains("Domain="));
    let login = json_body(login_res).await;
    assert!(login.get("refreshToken").is_none());

    let refresh_res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("content-type", "application/json")
                .header("cookie", cookie_pair(&login_cookie))
                .body(Body::from(json!({"sessionMode": "cookie"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(refresh_res.status(), StatusCode::OK);
    assert_eq!(
        refresh_res.headers().get(CACHE_CONTROL).unwrap(),
        "no-store"
    );
    assert_eq!(refresh_res.headers().get(PRAGMA).unwrap(), "no-cache");
    let rotated_cookie = response_cookie(&refresh_res);
    assert_ne!(cookie_pair(&rotated_cookie), cookie_pair(&login_cookie));
    let refresh = json_body(refresh_res).await;
    assert!(refresh.get("refreshToken").is_none());
    let access_token = refresh["accessToken"].as_str().unwrap();

    let stale_res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("content-type", "application/json")
                .header("cookie", cookie_pair(&login_cookie))
                .body(Body::from(json!({"sessionMode": "cookie"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(stale_res.status(), StatusCode::UNAUTHORIZED);
    let stale_cookie = response_cookie(&stale_res);
    assert!(stale_cookie.contains("Max-Age=0"));

    let logout_res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("authorization", format!("Bearer {access_token}"))
                .header("cookie", cookie_pair(&rotated_cookie))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(logout_res.status(), StatusCode::NO_CONTENT);
    let cleared_cookie = response_cookie(&logout_res);
    assert!(cleared_cookie.starts_with("ledgerly_refresh="));
    assert!(cleared_cookie.contains("Max-Age=0"));

    let after_logout = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("content-type", "application/json")
                .header("cookie", cookie_pair(&rotated_cookie))
                .body(Body::from(json!({"sessionMode": "cookie"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(after_logout.status(), StatusCode::UNAUTHORIZED);
}
