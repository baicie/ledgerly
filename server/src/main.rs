use std::path::Path;

use clap::{Parser, Subcommand};
use ledger_server::infrastructure::object_store;
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
    Restore {
        #[arg(long)]
        from: String,
        #[arg(long)]
        objects_from: Option<String>,
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
    }
    Ok(())
}
