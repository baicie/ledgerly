use clap::{Parser, Subcommand};
use ledger_server::{Config, migrate, run_api};
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
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse()?))
        .json()
        .init();

    let cli = Cli::parse();
    let config = Config::from_env();

    match cli.command {
        Commands::Doctor => {
            println!("ledger-server doctor");
            println!("listen={}", config.listen_addr);
            println!("database_url_set={}", config.database_url.is_some());
            println!("mode=ok");
        }
        Commands::Migrate => {
            migrate(&config).await?;
            println!("migrate complete");
        }
        Commands::Api | Commands::All => {
            run_api(config).await?;
        }
        Commands::Worker => {
            tracing::info!("worker mode: idle (jobs table not polled in MVP stub)");
            tokio::signal::ctrl_c().await?;
        }
    }
    Ok(())
}
