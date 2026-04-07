mod api;
mod config;
mod db;
mod error;
mod fcm;
mod federation_keys;
mod ws;

use clap::Parser;
use config::Config;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Config::parse();
    tracing::info!("Point server starting on {}", config.listen);

    let pool = db::init_pool(&config.database_url)
        .await
        .expect("Failed to connect to database");

    let jwt_secret = config
        .jwt_secret
        .clone()
        .unwrap_or_else(|| "dev-secret-change-me".to_string());

    let hub = ws::hub::Hub::new();
    let fcm = fcm::FcmService::load("firebase-admin.json");

    // Load or generate Ed25519 federation keypair
    let data_dir = config.database_url
        .strip_prefix("sqlite:")
        .and_then(|s| s.split('/').rev().nth(1).map(|_| {
            let path = std::path::Path::new(s.split('?').next().unwrap_or(s));
            path.parent().map(|p| p.to_string_lossy().to_string()).unwrap_or_else(|| "/data".to_string())
        }))
        .unwrap_or_else(|| "/data".to_string());
    let fed_keys = std::sync::Arc::new(federation_keys::FederationKeys::load_or_generate(&data_dir));
    tracing::info!("Federation public key: {}", fed_keys.public_key_hex);

    let state = api::AppState {
        pool: pool.clone(),
        config: config.clone(),
        jwt_secret,
        hub,
        fcm,
        federation_keys: fed_keys,
    };

    let cors = tower_http::cors::CorsLayer::very_permissive();
    let app = api::router(state).layer(cors);

    // Spawn TTL cleanup task that runs every 60 seconds
    let cleanup_pool = pool.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            match db::locations::cleanup_expired(&cleanup_pool).await {
                Ok(n) if n > 0 => tracing::info!(rows = n, "cleaned up expired location updates"),
                Err(e) => tracing::error!(error = %e, "location TTL cleanup failed"),
                _ => {}
            }
            match db::shares::cleanup_expired_temp_shares(&cleanup_pool).await {
                Ok(n) if n > 0 => tracing::info!(rows = n, "cleaned up expired temp shares"),
                Err(e) => tracing::error!(error = %e, "temp share TTL cleanup failed"),
                _ => {}
            }
            match db::history::cleanup_old_history(&cleanup_pool, 30).await {
                Ok(n) if n > 0 => tracing::info!(rows = n, "cleaned up old location history"),
                Err(e) => tracing::error!(error = %e, "location history cleanup failed"),
                _ => {}
            }
        }
    });

    let listener = tokio::net::TcpListener::bind(&config.listen)
        .await
        .expect("Failed to bind listener");

    tracing::info!("Server ready on {}", config.listen);
    axum::serve(listener, app).await.expect("Server error");
}
