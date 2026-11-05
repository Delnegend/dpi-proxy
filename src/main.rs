mod bypass;
mod proxy;

use std::error::Error;
use std::io;
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use bypass::BypassConfig;
use dotenv::{EnvLoader, EnvMap};
use tokio::net::TcpListener;

struct Options {
    address: String,
    port: u16,
    bypass: BypassConfig,
}

fn setting<T: FromStr>(env: &EnvMap, name: &str, default: &str) -> Result<T, io::Error> {
    let value = env.get(name).map_or(default, String::as_str);
    value.parse().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("invalid {name}: {value}"),
        )
    })
}

fn load_config() -> Result<Options, Box<dyn Error>> {
    let env = EnvLoader::new().required(false).load()?;
    let seconds: f64 = setting(&env, "DPI_PROXY_TIMEOUT_SECS", "3")?;
    let timeout = Duration::try_from_secs_f64(seconds).map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid DPI_PROXY_TIMEOUT_SECS",
        )
    })?;
    Ok(Options {
        address: env
            .get("DPI_PROXY_HOST")
            .cloned()
            .unwrap_or_else(|| String::from("127.0.0.1")),
        port: setting(&env, "DPI_PROXY_PORT", "1080")?,
        bypass: BypassConfig {
            split_sni: setting(&env, "DPI_PROXY_SPLIT_SNI", "true")?,
            retry_on_reset: setting(&env, "DPI_PROXY_RETRY_ON_RESET", "true")?,
            timeout: Some(timeout),
        },
    })
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    if std::env::args_os().nth(1).is_some() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "command-line arguments are not supported; use environment variables",
        )
        .into());
    }
    let options = load_config()?;
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut interrupt = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    let listener = TcpListener::bind((options.address.as_str(), options.port)).await?;
    eprintln!("dpi-proxy listening on {}", listener.local_addr()?);
    tokio::select! {
        result = proxy::serve(listener, Arc::new(options.bypass)) => result?,
        _ = terminate.recv() => {}
        _ = interrupt.recv() => {}
    }
    Ok(())
}
