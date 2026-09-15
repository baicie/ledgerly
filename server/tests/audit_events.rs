use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use ledger_server::{app_router, AppState, Config};
use serde_json::json;
use tower::ServiceExt;

#[tokio::test]
async fn auth_events_are_recorded_and_scoped_to_the_user() {
    let app = app_router(AppState::new(Config::for_test()));
    let register = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .header("x-request-id", "register-request")
                .body(Body::from(
                    json!({
                        "email": "audit@example.com",
                        "password": "password123",
                        "displayName": "Audit User"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(register.status(), StatusCode::OK);

    let login = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .header("x-request-id", "login-request")
                .body(Body::from(
                    json!({
                        "email": "audit@example.com",
                        "password": "password123",
                        "deviceId": "device-audit"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(login.status(), StatusCode::OK);
    let login_body = login.into_body().collect().await.unwrap().to_bytes();
    let login_json: serde_json::Value = serde_json::from_slice(&login_body).unwrap();
    let access_token = login_json["accessToken"].as_str().unwrap();

    let events = app
        .oneshot(
            Request::builder()
                .uri("/v1/audit/events?limit=10")
                .header("authorization", format!("Bearer {access_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(events.status(), StatusCode::OK);
    let body = events.into_body().collect().await.unwrap().to_bytes();
    let page: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let actions: Vec<_> = page["events"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|event| event["action"].as_str())
        .collect();

    assert!(actions.contains(&"auth.register"));
    assert!(actions.contains(&"auth.login"));
    assert!(page["events"]
        .as_array()
        .unwrap()
        .iter()
        .any(|event| event["requestId"] == "login-request"));
}
