use std::path::{Path, PathBuf};
use std::time::Duration;

use ledger_server::{backup, migrate, restore, Config};
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use tokio::time::Instant;
use url::Url;
use uuid::Uuid;

const RESTORED_TABLES: &[&str] = &[
    "users",
    "device_sessions",
    "books",
    "book_members",
    "accounts",
    "transactions",
    "transaction_entries",
    "budgets",
    "recurring_rules",
    "attachments",
    "jobs",
    "sync_mutations",
    "sync_changes",
];

fn pg_url() -> Option<String> {
    std::env::var("DATABASE_URL").ok()
}

fn require_postgres() -> bool {
    std::env::var("REQUIRE_POSTGRES_TESTS").ok().as_deref() == Some("true")
}

fn database_url(base: &str, database: &str) -> String {
    let mut url = Url::parse(base).expect("valid DATABASE_URL");
    url.set_path(database);
    url.to_string()
}

fn temporary_database_name(prefix: &str) -> String {
    let id = Uuid::now_v7().simple().to_string();
    format!("ledgerly_{prefix}_{}", &id[..12])
}

fn dump_path() -> PathBuf {
    std::env::temp_dir().join(format!("ledgerly-backup-drill-{}.dump", Uuid::now_v7()))
}

async fn table_count(pool: &PgPool, table: &str) -> i64 {
    sqlx::query_scalar(&format!("SELECT COUNT(*) FROM {table}"))
        .fetch_one(pool)
        .await
        .unwrap_or_else(|error| panic!("count {table}: {error}"))
}

async fn snapshot_counts(pool: &PgPool) -> Vec<(&'static str, i64)> {
    let mut counts = Vec::with_capacity(RESTORED_TABLES.len());
    for table in RESTORED_TABLES {
        counts.push((*table, table_count(pool, table).await));
    }
    counts
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn postgres_backup_restore_drill_preserves_pre_backup_snapshot() {
    let Some(base_url) = pg_url() else {
        if require_postgres() {
            panic!("DATABASE_URL is required for PostgreSQL backup restore test");
        }
        eprintln!("skip postgres_backup_restore_drill: DATABASE_URL unset");
        return;
    };

    let admin = PgPoolOptions::new()
        .max_connections(2)
        .connect(&base_url)
        .await
        .expect("connect admin database");
    let can_create: bool = sqlx::query_scalar(
        "SELECT rolcreatedb OR rolsuper
         FROM pg_roles
         WHERE rolname = current_user",
    )
    .fetch_one(&admin)
    .await
    .expect("read role capabilities");
    if !can_create {
        if require_postgres() {
            panic!("PostgreSQL test role requires CREATEDB");
        }
        eprintln!("skip postgres_backup_restore_drill: role cannot create databases");
        return;
    }

    let source_database = temporary_database_name("drill_source");
    let target_database = temporary_database_name("drill_target");
    let source_url = database_url(&base_url, &source_database);
    let target_url = database_url(&base_url, &target_database);
    let dump = dump_path();

    for database in [&source_database, &target_database] {
        sqlx::query(&format!("CREATE DATABASE \"{database}\""))
            .execute(&admin)
            .await
            .unwrap_or_else(|error| panic!("create database {database}: {error}"));
    }

    let result = run_backup_restore_drill(&source_url, &target_url, &dump).await;

    let _ = tokio::fs::remove_file(&dump).await;
    for database in [&target_database, &source_database] {
        let _ = sqlx::query(&format!(
            "DROP DATABASE IF EXISTS \"{database}\" WITH (FORCE)"
        ))
        .execute(&admin)
        .await;
    }

    result.expect("PostgreSQL backup/restore drill");
}

async fn run_backup_restore_drill(
    source_url: &str,
    target_url: &str,
    dump: &Path,
) -> anyhow::Result<()> {
    let mut source_config = Config::for_test();
    source_config.database_url = Some(source_url.to_string());
    let mut target_config = Config::for_test();
    target_config.database_url = Some(target_url.to_string());

    migrate(&source_config).await?;
    let source = PgPoolOptions::new()
        .max_connections(4)
        .connect(source_url)
        .await?;

    let fixture = seed_source(&source).await?;
    // The server migration runner is idempotent SQL rather than a
    // version table. Run it once more after the book exists so the
    // snapshot includes the default categories a real deployed book has.
    migrate(&source_config).await?;
    let expected_counts = snapshot_counts(&source).await;

    let backup_started = Instant::now();
    backup(&source_config, dump.to_str().expect("dump path")).await?;
    let backup_elapsed = backup_started.elapsed();

    let post_backup_transaction_id = seed_post_backup_marker(&source, &fixture.book_id).await?;
    assert!(table_count(&source, "transactions").await > fixture.pre_backup_transaction_count);

    let recovery_started = Instant::now();
    restore(&target_config, dump.to_str().expect("dump path")).await?;
    migrate(&target_config).await?;
    let recovery_elapsed = recovery_started.elapsed();

    let target = PgPoolOptions::new()
        .max_connections(4)
        .connect(target_url)
        .await?;
    let restored_counts = snapshot_counts(&target).await;
    assert_eq!(restored_counts, expected_counts);

    let restored_description: Option<String> =
        sqlx::query_scalar("SELECT description FROM transactions WHERE id = $1")
            .bind(&fixture.pre_backup_transaction_id)
            .fetch_one(&target)
            .await?;
    assert_eq!(restored_description.as_deref(), Some("pre-backup marker"));

    let post_backup_exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM transactions WHERE id = $1)")
            .bind(&post_backup_transaction_id)
            .fetch_one(&target)
            .await?;
    assert!(
        !post_backup_exists,
        "restore must stop at the snapshot boundary"
    );

    let latest_index_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*)
         FROM pg_indexes
         WHERE schemaname = 'public'
           AND indexname = 'uq_transactions_auto_event'",
    )
    .fetch_one(&target)
    .await?;
    assert_eq!(
        latest_index_count, 1,
        "restored schema is missing the latest migration"
    );

    assert!(
        recovery_elapsed < Duration::from_secs(4 * 60 * 60),
        "recovery exceeded the four-hour RTO target: {recovery_elapsed:?}"
    );
    eprintln!(
        "postgres backup/restore drill passed: backup={backup_elapsed:?} recovery={recovery_elapsed:?}"
    );
    Ok(())
}

struct DrillFixture {
    book_id: String,
    pre_backup_transaction_id: String,
    pre_backup_transaction_count: i64,
}

async fn seed_source(pool: &PgPool) -> anyhow::Result<DrillFixture> {
    let suffix = Uuid::now_v7().simple().to_string();
    let user_id = format!("user_{suffix}");
    let book_id = format!("book_{suffix}");
    let cash_id = format!("{book_id}:cash");
    let food_id = format!("{book_id}:food");
    let pre_transaction_id = format!("tx_pre_{suffix}");
    let recurring_id = format!("recurring_{suffix}");
    let attachment_id = format!("attachment_{suffix}");
    let job_id = format!("job_{suffix}");
    let sync_mutation_id = format!("mutation_{suffix}");
    let device_id = format!("device_{suffix}");

    sqlx::query(
        "INSERT INTO users (id, email, password_hash, display_name)
         VALUES ($1, $2, 'test-hash', 'Recovery Drill')",
    )
    .bind(&user_id)
    .bind(format!("{suffix}@drill.test"))
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO device_sessions
           (id, user_id, device_id, refresh_token_hash, device_name)
         VALUES ($1, $2, $3, $4, 'drill-device')",
    )
    .bind(format!("session_{suffix}"))
    .bind(&user_id)
    .bind(&device_id)
    .bind(format!("refresh_{suffix}"))
    .execute(pool)
    .await?;
    sqlx::query("INSERT INTO books (id, name, owner_id) VALUES ($1, $2, $3)")
        .bind(&book_id)
        .bind("Recovery Drill Book")
        .bind(&user_id)
        .execute(pool)
        .await?;
    sqlx::query(
        "INSERT INTO book_members (book_id, user_id, role)
         VALUES ($1, $2, 'owner')",
    )
    .bind(&book_id)
    .bind(&user_id)
    .execute(pool)
    .await?;
    for (account_id, name, account_type) in
        [(&cash_id, "Cash", "asset"), (&food_id, "Food", "expense")]
    {
        sqlx::query(
            "INSERT INTO accounts
               (id, book_id, name, account_type, currency_code)
             VALUES ($1, $2, $3, $4, 'CNY')",
        )
        .bind(account_id)
        .bind(&book_id)
        .bind(name)
        .bind(account_type)
        .execute(pool)
        .await?;
    }
    sqlx::query(
        "INSERT INTO transactions
           (id, book_id, description, occurred_at, source)
         VALUES ($1, $2, 'pre-backup marker', now(), 'manual')",
    )
    .bind(&pre_transaction_id)
    .bind(&book_id)
    .execute(pool)
    .await?;
    for (entry_id, account_id, amount_minor, entry_index) in [
        (
            format!("{pre_transaction_id}:food"),
            &food_id,
            1250_i64,
            0_i32,
        ),
        (
            format!("{pre_transaction_id}:cash"),
            &cash_id,
            -1250_i64,
            1_i32,
        ),
    ] {
        sqlx::query(
            "INSERT INTO transaction_entries
               (id, transaction_id, account_id, amount_minor, currency_code, entry_index)
             VALUES ($1, $2, $3, $4, 'CNY', $5)",
        )
        .bind(entry_id)
        .bind(&pre_transaction_id)
        .bind(account_id)
        .bind(amount_minor)
        .bind(entry_index)
        .execute(pool)
        .await?;
    }
    sqlx::query(
        "INSERT INTO budgets
           (id, book_id, name, category_account_id, amount_minor)
         VALUES ($1, $2, 'Recovery budget', $3, 50000)",
    )
    .bind(format!("budget_{suffix}"))
    .bind(&book_id)
    .bind(&food_id)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO recurring_rules
           (id, book_id, name, payload, next_run_at)
         VALUES ($1, $2, 'Recovery rent', '{\"kind\":\"expense\"}'::jsonb, now())",
    )
    .bind(&recurring_id)
    .bind(&book_id)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO attachments
           (id, book_id, transaction_id, object_key, content_hash, mime_type, size_bytes)
         VALUES ($1, $2, $3, $4, 'sha256-drill', 'application/octet-stream', 32)",
    )
    .bind(&attachment_id)
    .bind(&book_id)
    .bind(&pre_transaction_id)
    .bind(format!("objects/{attachment_id}"))
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO jobs (id, job_type, payload, status)
         VALUES ($1, 'recovery_drill', '{\"source\":\"test\"}'::jsonb, 'pending')",
    )
    .bind(&job_id)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO sync_mutations
           (book_id, device_id, mutation_id, status, result_code, entity_version, response_payload)
         VALUES ($1, $2, $3, 'applied', 'OK', 1, '{\"ok\":true}'::jsonb)",
    )
    .bind(&book_id)
    .bind(&device_id)
    .bind(&sync_mutation_id)
    .execute(pool)
    .await?;
    sqlx::query(
        "INSERT INTO sync_changes
           (book_id, commit_id, entity_type, entity_id, operation, entity_version, payload)
         VALUES ($1, $2, 'transaction', $3, 'upsert', 1, '{\"description\":\"pre-backup marker\"}'::jsonb)",
    )
    .bind(&book_id)
    .bind(format!("commit_{suffix}"))
    .bind(&pre_transaction_id)
    .execute(pool)
    .await?;

    let pre_backup_transaction_count = table_count(pool, "transactions").await;
    Ok(DrillFixture {
        book_id,
        pre_backup_transaction_id: pre_transaction_id,
        pre_backup_transaction_count,
    })
}

async fn seed_post_backup_marker(pool: &PgPool, book_id: &str) -> anyhow::Result<String> {
    let transaction_id = format!("tx_post_{}", Uuid::now_v7().simple());
    sqlx::query(
        "INSERT INTO transactions
           (id, book_id, description, occurred_at, source)
         VALUES ($1, $2, 'post-backup marker', now(), 'manual')",
    )
    .bind(&transaction_id)
    .bind(book_id)
    .execute(pool)
    .await?;
    Ok(transaction_id)
}
