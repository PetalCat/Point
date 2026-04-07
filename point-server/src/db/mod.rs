pub mod users;
pub mod groups;
pub mod group_invites;
pub mod history;
pub mod items;
pub mod places;
pub mod bridges;
pub mod invites;
pub mod locations;
pub mod shares;
pub mod zone_consents;
pub mod bridged_entities;
pub mod bridge_registry;
pub mod mls;

use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};

pub type DbPool = SqlitePool;

pub async fn init_pool(database_url: &str) -> Result<DbPool, sqlx::Error> {
    let pool = SqlitePoolOptions::new()
        .max_connections(20)
        .connect(database_url)
        .await?;

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await?;

    tracing::info!("Database connected and migrated");
    Ok(pool)
}
