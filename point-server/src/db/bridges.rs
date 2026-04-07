use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bridge {
    pub id: String,
    pub user_id: String,
    pub bridge_type: String,
    pub status: String,
    pub double_puppet: bool,
    pub last_heartbeat: Option<String>,
    pub error_message: Option<String>,
}

pub async fn get_bridge(pool: &DbPool, id: &str) -> Result<Option<Bridge>, sqlx::Error> {
    let row = sqlx::query("SELECT id, user_id, bridge_type, status, double_puppet, last_heartbeat, error_message FROM bridges WHERE id = ?")
        .bind(id).fetch_optional(pool).await?;
    Ok(row.map(|r| Bridge {
        id: r.get("id"),
        user_id: r.get("user_id"),
        bridge_type: r.get("bridge_type"),
        status: r.get("status"),
        double_puppet: r.get("double_puppet"),
        last_heartbeat: r.get("last_heartbeat"),
        error_message: r.get("error_message"),
    }))
}

pub async fn register_bridge(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    bridge_type: &str,
) -> Result<Bridge, sqlx::Error> {
    sqlx::query(
        "INSERT INTO bridges (id, user_id, bridge_type, status, last_heartbeat) \
         VALUES (?, ?, ?, 'connected', datetime('now')) \
         ON CONFLICT(id) DO UPDATE SET status = 'connected', last_heartbeat = datetime('now')",
    )
    .bind(id)
    .bind(user_id)
    .bind(bridge_type)
    .execute(pool)
    .await?;

    // Return the bridge we just upserted
    let row = sqlx::query(
        "SELECT id, user_id, bridge_type, status, double_puppet, last_heartbeat, error_message \
         FROM bridges WHERE id = ?",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    Ok(Bridge {
        id: row.get("id"),
        user_id: row.get("user_id"),
        bridge_type: row.get("bridge_type"),
        status: row.get("status"),
        double_puppet: row.get("double_puppet"),
        last_heartbeat: row.get("last_heartbeat"),
        error_message: row.get("error_message"),
    })
}

pub async fn update_heartbeat(
    pool: &DbPool,
    id: &str,
    status: &str,
    error_message: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE bridges SET status = ?, last_heartbeat = datetime('now'), error_message = ? \
         WHERE id = ?",
    )
    .bind(status)
    .bind(error_message)
    .bind(id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn list_user_bridges(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<Bridge>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, bridge_type, status, double_puppet, last_heartbeat, error_message \
         FROM bridges WHERE user_id = ?",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Bridge {
            id: r.get("id"),
            user_id: r.get("user_id"),
            bridge_type: r.get("bridge_type"),
            status: r.get("status"),
            double_puppet: r.get("double_puppet"),
            last_heartbeat: r.get("last_heartbeat"),
            error_message: r.get("error_message"),
        })
        .collect())
}

pub async fn disconnect_bridge(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE bridges SET status = 'disconnected' WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(())
}
