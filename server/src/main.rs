use std::path::Path;

use clap::{Parser, Subcommand};
use ledger_server::infrastructure::{backup_bundle, backup_runtime, object_store};
use ledger_server::{backup, migrate, restore, run_api, run_worker_only, Config};
use tracing_subscriber::EnvFilter;

#[derive(Parser, Debug)]
#[command(name = "ledger-server")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    Api,
    Worker,
    All,
    Migrate,
    Doctor,
    Backup {
        #[arg(long)]
        out: String,
        #[arg(long)]
        objects_out: Option<String>,
    },
    BackupRun,
    BackupStatus,
    RestoreStatus,
    Restore {
        #[arg(long)]
        from: String,
        #[arg(long)]
        objects_from: Option<String>,
    },
    Bundle {
        #[command(subcommand)]
        command: BundleCommands,
    },
}

#[derive(Subcommand, Debug)]
enum BundleCommands {
    Create {
        #[arg(long)]
        database: String,
        #[arg(long)]
        objects: String,
        #[arg(long)]
        out: String,
        #[arg(long, env = "LEDGER_BACKUP_PASSWORD")]
        password: Option<String>,
    },
    Verify {
        #[arg(long)]
        from: String,
        #[arg(long, env = "LEDGER_BACKUP_PASSWORD")]
        password: Option<String>,
    },
    Unpack {
        #[arg(long)]
        from: String,
        #[arg(long)]
        to: String,
        #[arg(long, env = "LEDGER_BACKUP_PASSWORD")]
        password: Option<String>,
    },
    Replicate {
        #[arg(long)]
        from: String,
        #[arg(long)]
        to: String,
    },
    Cleanup {
        #[arg(long)]
        root: String,
        #[arg(long, default_value_t = 3)]
        keep: usize,
    },
    Restore {
        #[arg(long)]
        from: String,
        #[arg(long, env = "LEDGER_BACKUP_PASSWORD")]
        password: Option<String>,
        #[arg(long)]
        confirm: bool,
    },
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse()?))
        .json()
        .init();

    let cli = Cli::parse();
    let config = Config::from_env()?;

    match cli.command {
        Commands::Doctor => {
            println!("ledger-server doctor");
            println!("listen={}", config.listen_addr);
            println!("database_url_set={}", config.database_url.is_some());
            println!("object_store_dir={}", config.object_store_dir.display());
            println!("jwt=Ed25519");
            println!("mode=ok");
        }
        Commands::Migrate => {
            migrate(&config).await?;
            println!("migrate complete");
        }
        Commands::Api => run_api(config, false).await?,
        Commands::All => run_api(config, true).await?,
        Commands::Worker => run_worker_only(config).await?,
        Commands::Backup { out, objects_out } => {
            backup(&config, &out).await?;
            println!("backup written to {out}");
            if let Some(objects_out) = objects_out {
                let report = object_store::backup_object_store(&config, Path::new(&objects_out))?;
                println!(
                    "object store backup written to {objects_out} ({} objects, {} bytes)",
                    report.object_count, report.total_size_bytes
                );
            }
        }
        Commands::BackupRun => {
            let report = backup_runtime::run_backup(&config).await?;
            println!(
                "backup run {} complete: {} files, {} bytes, duration={} ms, replicated={}, local_retained={}, offsite_retained={}",
                report.run_id,
                report.file_count,
                report.total_size_bytes,
                report.duration_ms,
                report.replicated,
                report.local_retained,
                report.offsite_retained
            );
        }
        Commands::BackupStatus => {
            let snapshot = backup_runtime::backup_readiness(&config)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&serde_json::json!({
                    "status": snapshot.readiness.as_str(),
                    "ageSeconds": snapshot.age_seconds,
                    "lastCompletedAt": snapshot.status.as_ref().map(|status| status.completed_at.clone()),
                    "fileCount": snapshot.status.as_ref().map(|status| status.file_count),
                    "totalSizeBytes": snapshot.status.as_ref().map(|status| status.total_size_bytes),
                    "replicated": snapshot.status.as_ref().map(|status| status.replicated),
                }))?
            );
        }
        Commands::RestoreStatus => {
            let status = backup_runtime::restore_status(&config)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&serde_json::json!({
                    "status": status.as_ref().map(|value| match value.outcome {
                        ledger_server::infrastructure::backup_status::RestoreRunOutcome::Success => "success",
                        ledger_server::infrastructure::backup_status::RestoreRunOutcome::Failed => "failed",
                    }),
                    "completedAt": status.as_ref().map(|value| value.completed_at.clone()),
                    "durationMs": status.as_ref().map(|value| value.duration_ms),
                    "objectCount": status.as_ref().map(|value| value.object_count),
                    "bookCount": status.as_ref().map(|value| value.book_count),
                    "transactionCount": status.as_ref().map(|value| value.transaction_count),
                }))?
            );
        }
        Commands::Restore { from, objects_from } => {
            if let Some(objects_from) = objects_from {
                let report = object_store::restore_object_store(&config, Path::new(&objects_from))?;
                println!(
                    "object store restored from {objects_from} ({} objects, {} bytes)",
                    report.object_count, report.total_size_bytes
                );
            }
            restore(&config, &from).await?;
            println!("restore from {from} complete");
        }
        Commands::Bundle { command } => match command {
            BundleCommands::Create {
                database,
                objects,
                out,
                password,
            } => {
                let report = backup_bundle::create_backup_bundle(
                    Path::new(&database),
                    Path::new(&objects),
                    Path::new(&out),
                    password.as_deref(),
                )?;
                println!(
                    "backup bundle written to {out} ({} files, {} bytes, encrypted={})",
                    report.file_count, report.total_size_bytes, report.encrypted
                );
            }
            BundleCommands::Verify { from, password } => {
                let report =
                    backup_bundle::verify_backup_bundle(Path::new(&from), password.as_deref())?;
                println!(
                    "backup bundle verified: {} files, {} bytes, encrypted={}, plaintext_verified={}",
                    report.file_count,
                    report.total_size_bytes,
                    report.encrypted,
                    report.plaintext_verified
                );
            }
            BundleCommands::Unpack { from, to, password } => {
                let report = backup_bundle::unpack_backup_bundle(
                    Path::new(&from),
                    Path::new(&to),
                    password.as_deref(),
                )?;
                println!(
                    "backup bundle unpacked to {to} ({} files, {} bytes)",
                    report.file_count, report.total_size_bytes
                );
            }
            BundleCommands::Replicate { from, to } => {
                let report =
                    backup_bundle::replicate_backup_bundle(Path::new(&from), Path::new(&to))?;
                println!(
                    "backup bundle replicated to {to} ({} files, {} bytes)",
                    report.file_count, report.total_size_bytes
                );
            }
            BundleCommands::Cleanup { root, keep } => {
                let report = backup_bundle::cleanup_backup_bundles(Path::new(&root), keep)?;
                println!(
                    "backup bundle cleanup complete: deleted={}, kept={}, freed={} bytes",
                    report.deleted_count, report.kept_count, report.freed_bytes
                );
            }
            BundleCommands::Restore {
                from,
                password,
                confirm,
            } => {
                if !confirm {
                    anyhow::bail!("bundle restore is destructive; pass --confirm");
                }
                let report = backup_runtime::restore_backup_bundle(
                    &config,
                    Path::new(&from),
                    password.as_deref(),
                )
                .await?;
                println!(
                    "backup bundle restored: files={}, objects={}, books={}, transactions={}, duration={} ms, safety_backup={}",
                    report.file_count,
                    report.object_count,
                    report.book_count,
                    report.transaction_count,
                    report.duration_ms,
                    report.safety_backup_run_id
                );
            }
        },
    }
    Ok(())
}
