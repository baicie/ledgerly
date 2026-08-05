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
    let cash = format!("{book_id}:acc_cash");
    let food = format!("{book_id}:acc_food");
    let custom_category = format!("{book_id}:category_pg_lunch");

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
        "mutations": [
            {
                "mutationId": format!("mut_account_{}", uuid::Uuid::now_v7()),
                "entityType": "account",
                "entityId": custom_category,
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "name": "PG Lunch",
                    "accountType": "expense",
                    "currency": "CNY",
                    "parentAccountId": food
                }
            },
            {
                "mutationId": format!("mut_tx_{}", uuid::Uuid::now_v7()),
                "entityType": "transaction",
                "entityId": format!("tx_{}", uuid::Uuid::now_v7()),
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "description": "PG lunch",
                    "entries": [
                        {"accountId": custom_category, "amountMinor": "1200", "currency": "CNY"},
                        {"accountId": cash, "amountMinor": "-1200", "currency": "CNY"}
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
                .body(Body::from(mutation.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let push = json_body(res).await;
    assert_eq!(push["receipts"][0]["status"], "applied");
    assert_eq!(push["receipts"][1]["status"], "applied");

    let rename = json!({
        "deviceId": "dev_pg",
        "mutations": [{
            "mutationId": format!("mut_rename_{}", uuid::Uuid::now_v7()),
            "entityType": "account",
            "entityId": custom_category,
            "operation": "update",
            "baseVersion": 999,
            "schemaVersion": 1,
            "payload": {
                "name": "  PG Meals  ",
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
                .body(Body::from(rename.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let rename = json_body(res).await;
    assert_eq!(rename["receipts"][0]["status"], "applied");
    assert_eq!(rename["receipts"][0]["entityVersion"], 2);

    let idempotent_rename = json!({
        "deviceId": "dev_pg",
        "mutations": [{
            "mutationId": format!("mut_idempotent_{}", uuid::Uuid::now_v7()),
            "entityType": "account",
            "entityId": custom_category,
            "operation": "update",
            "baseVersion": 1,
            "schemaVersion": 1,
            "payload": {
                "name": "PG Meals Final",
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

    let missing_account = json!({
        "deviceId": "dev_pg",
        "mutations": [{
            "mutationId": format!("mut_missing_{}", uuid::Uuid::now_v7()),
            "entityType": "transaction",
            "entityId": format!("tx_missing_{}", uuid::Uuid::now_v7()),
            "operation": "create",
            "baseVersion": 0,
            "schemaVersion": 1,
            "payload": {
                "entries": [
                    {"accountId": format!("{book_id}:missing"), "amountMinor": "100", "currency": "CNY"},
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
                .body(Body::from(missing_account.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let missing = json_body(res).await;
    assert_eq!(missing["receipts"][0]["status"], "rejected");
    assert_eq!(missing["receipts"][0]["resultCode"], "ACCOUNT_NOT_FOUND");

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
    let pull = json_body(res).await;
    assert!(!pull["changes"].as_array().unwrap().is_empty());
    assert!(pull["changes"].as_array().unwrap().iter().any(|change| {
        change["entityType"] == "account"
            && change["entityId"] == custom_category
            && change["version"] == 3
            && change["payload"]["name"] == "PG Meals Final"
            && change["payload"]["accountType"] == "expense"
            && change["payload"]["currency"] == "CNY"
            && change["payload"]["parentAccountId"] == food
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
            account["id"] == custom_category
                && account["version"] == 3
                && account["name"] == "PG Meals Final"
                && account["accountType"] == "expense"
                && account["currency"] == "CNY"
                && account["parentAccountId"] == food
        }));
}

#[tokio::test]
async fn postgres_concurrent_category_moves_preserve_two_level_hierarchy() {
    let Some(url) = pg_url() else {
        if std::env::var("REQUIRE_POSTGRES_TESTS").ok().as_deref() == Some("true") {
            panic!("DATABASE_URL is required for PostgreSQL integration tests");
        }
        eprintln!(
            "skip postgres_concurrent_category_moves_preserve_two_level_hierarchy: DATABASE_URL unset"
        );
        return;
    };

    let mut config = Config::for_test();
    config.database_url = Some(url);
    migrate(&config).await.expect("migrate");
    let state = AppState::new_async(config).await.expect("state");
    let app = app_router(state.clone());
    let email = format!("category_race_{}@test.com", uuid::Uuid::now_v7());

    let register = post_json(
        &app,
        "/v1/auth/register",
        json!({
            "email": email,
            "password": "password123",
            "displayName": "Category Race"
        }),
    )
    .await;
    assert_eq!(register.status(), StatusCode::OK);

    let login = post_json(
        &app,
        "/v1/auth/login",
        json!({
            "email": email,
            "password": "password123",
            "deviceId": "category-race-login"
        }),
    )
    .await;
    assert_eq!(login.status(), StatusCode::OK);
    let login = json_body(login).await;
    let token = login["accessToken"].as_str().unwrap().to_string();
    let book_id = login["bookId"].as_str().unwrap().to_string();
    let run_suffix = uuid::Uuid::now_v7().simple().to_string();
    let category_a = format!("{book_id}:category_hierarchy_race_a");
    let category_b = format!("{book_id}:category_hierarchy_race_b");
    let category_a_name = "Hierarchy Race A";
    let category_b_name = "Hierarchy Race B";

    let create_roots = json!({
        "deviceId": "category-race-setup",
        "mutations": [
            {
                "mutationId": format!("mut_{}", uuid::Uuid::now_v7()),
                "entityType": "account",
                "entityId": category_a,
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "name": category_a_name,
                    "accountType": "expense",
                    "currency": "CNY"
                }
            },
            {
                "mutationId": format!("mut_{}", uuid::Uuid::now_v7()),
                "entityType": "account",
                "entityId": category_b,
                "operation": "create",
                "baseVersion": 0,
                "schemaVersion": 1,
                "payload": {
                    "name": category_b_name,
                    "accountType": "expense",
                    "currency": "CNY"
                }
            }
        ]
    });
    let create_response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/books/{book_id}/sync/push"))
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(create_roots.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let create_response = json_body(create_response).await;
    assert!(create_response["receipts"]
        .as_array()
        .unwrap()
        .iter()
        .all(|receipt| receipt["status"] == "applied"));

    let pool = state.pool.as_ref().unwrap();
    const TEST_GATE_LOCK_NAMESPACE: i32 = 0x4C54_0001;
    const ACCOUNT_HIERARCHY_LOCK_NAMESPACE: i32 = 0x4C41_0002;
    let gate_lock_key = format!("category-hierarchy-race-gate:{run_suffix}");
    let hierarchy_lock_key = format!("{book_id}:account-hierarchy");
    let trigger_name = format!("category_hierarchy_race_{run_suffix}");
    let function_name = format!("category_hierarchy_gate_{run_suffix}");
    let install_gate = format!(
        "CREATE FUNCTION {function_name}()
         RETURNS trigger AS $$
         BEGIN
             PERFORM pg_advisory_xact_lock(
                 {TEST_GATE_LOCK_NAMESPACE},
                 hashtext('{gate_lock_key}')
             );
             RETURN NEW;
         END;
         $$ LANGUAGE plpgsql;
         CREATE TRIGGER {trigger_name}
         BEFORE UPDATE OF parent_account_id ON accounts
         FOR EACH ROW
         WHEN (NEW.id IN ('{category_a}', '{category_b}'))
         EXECUTE FUNCTION {function_name}();"
    );
    sqlx::raw_sql(&install_gate)
        .execute(pool)
        .await
        .expect("install hierarchy race gate");

    let mut gate_tx = pool.begin().await.expect("begin hierarchy race gate");
    sqlx::query("SELECT pg_advisory_xact_lock($1, hashtext($2))")
        .bind(TEST_GATE_LOCK_NAMESPACE)
        .bind(&gate_lock_key)
        .execute(&mut *gate_tx)
        .await
        .expect("close hierarchy race gate");

    let move_category = |device_id: &str, entity_id: &str, name: &str, parent_account_id: &str| {
        json!({
            "deviceId": device_id,
            "mutations": [{
                "mutationId": format!("mut_{}", uuid::Uuid::now_v7()),
                "entityType": "account",
                "entityId": entity_id,
                "operation": "update",
                "baseVersion": 1,
                "schemaVersion": 1,
                "payload": {
                    "name": name,
                    "accountType": "expense",
                    "currency": "CNY",
                    "parentAccountId": parent_account_id
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
    let (move_a, move_b, coordination) = tokio::join!(
        request(move_category(
            "category-race-a",
            &category_a,
            category_a_name,
            &category_b,
        )),
        request(move_category(
            "category-race-b",
            &category_b,
            category_b_name,
            &category_a,
        )),
        async {
            let deadline = tokio::time::Instant::now() + tokio::time::Duration::from_secs(10);
            let observation: Result<(i64, i64), String> = loop {
                let waiters: Result<(i64, i64), sqlx::Error> = sqlx::query_as(
                    "SELECT
                         COUNT(*) FILTER (
                             WHERE NOT granted
                               AND classid::bigint = $1::bigint
                               AND objid::bigint =
                                   (hashtext($2)::bigint & 4294967295)
                         )::bigint,
                         COUNT(*) FILTER (
                             WHERE NOT granted
                               AND classid::bigint = $3::bigint
                               AND objid::bigint =
                                   (hashtext($4)::bigint & 4294967295)
                         )::bigint
                     FROM pg_locks
                     WHERE locktype = 'advisory' AND objsubid = 2",
                )
                .bind(TEST_GATE_LOCK_NAMESPACE)
                .bind(&gate_lock_key)
                .bind(ACCOUNT_HIERARCHY_LOCK_NAMESPACE)
                .bind(&hierarchy_lock_key)
                .fetch_one(pool)
                .await;
                let (gate_waiters, hierarchy_waiters) = match waiters {
                    Ok(waiters) => waiters,
                    Err(error) => break Err(format!("observe hierarchy race locks: {error}")),
                };
                if gate_waiters >= 2 || (gate_waiters >= 1 && hierarchy_waiters >= 1) {
                    break Ok((gate_waiters, hierarchy_waiters));
                }
                if tokio::time::Instant::now() >= deadline {
                    break Err(format!(
                        "timed out observing hierarchy race locks: \
                         gate_waiters={gate_waiters}, hierarchy_waiters={hierarchy_waiters}"
                    ));
                }
                tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
            };
            gate_tx
                .rollback()
                .await
                .map_err(|error| format!("open hierarchy race gate: {error}"))?;
            observation
        },
    );

    let remove_gate = format!(
        "DROP TRIGGER IF EXISTS {trigger_name} ON accounts;
         DROP FUNCTION IF EXISTS {function_name}();"
    );
    sqlx::raw_sql(&remove_gate)
        .execute(pool)
        .await
        .expect("remove hierarchy race gate");

    coordination.expect("coordinate concurrent category moves");
    let move_a = json_body(move_a.unwrap()).await;
    let move_b = json_body(move_b.unwrap()).await;
    let receipts = [&move_a["receipts"][0], &move_b["receipts"][0]];
    assert_eq!(
        receipts
            .iter()
            .filter(|receipt| receipt["status"] == "applied")
            .count(),
        1
    );
    assert_eq!(
        receipts
            .iter()
            .filter(|receipt| {
                receipt["status"] == "rejected"
                    && receipt["resultCode"] == "INVALID_CATEGORY_PARENT"
            })
            .count(),
        1
    );

    let parents: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT id, parent_account_id
         FROM accounts
         WHERE id = ANY($1)
         ORDER BY id",
    )
    .bind(vec![category_a.clone(), category_b.clone()])
    .fetch_all(pool)
    .await
    .expect("read category hierarchy after concurrent moves");
    assert_eq!(
        parents
            .iter()
            .filter(|(_, parent_account_id)| parent_account_id.is_some())
            .count(),
        1
    );
    let child_parent_id = parents
        .iter()
        .find_map(|(_, parent_account_id)| parent_account_id.as_deref())
        .unwrap();
    assert!(parents
        .iter()
        .any(|(id, parent_account_id)| id == child_parent_id && parent_account_id.is_none()));
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
