use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyPackageRow {
    pub id: String,
    pub user_id: String,
    pub key_package: Vec<u8>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MlsMessage {
    pub id: String,
    pub recipient_id: String,
    pub message_type: String,
    pub group_id: String,
    pub sender_id: String,
    pub payload: Vec<u8>,
    pub processed: bool,
    pub created_at: String,
}

pub async fn store_key_package(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    key_package: &[u8],
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO key_packages (id, user_id, key_package) VALUES (?, ?, ?)")
        .bind(id)
        .bind(user_id)
        .bind(key_package)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_key_packages(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<KeyPackageRow>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, key_package, created_at FROM key_packages WHERE user_id = ? ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| KeyPackageRow {
            id: r.get("id"),
            user_id: r.get("user_id"),
            key_package: r.get("key_package"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn delete_key_package(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM key_packages WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn store_mls_message(
    pool: &DbPool,
    id: &str,
    recipient_id: &str,
    message_type: &str,
    group_id: &str,
    sender_id: &str,
    payload: &[u8],
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO mls_messages (id, recipient_id, message_type, group_id, sender_id, payload) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(recipient_id)
    .bind(message_type)
    .bind(group_id)
    .bind(sender_id)
    .bind(payload)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_pending_messages(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<MlsMessage>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, recipient_id, message_type, group_id, sender_id, payload, processed, created_at \
         FROM mls_messages WHERE recipient_id = ? AND processed = FALSE \
         ORDER BY created_at ASC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| MlsMessage {
            id: r.get("id"),
            recipient_id: r.get("recipient_id"),
            message_type: r.get("message_type"),
            group_id: r.get("group_id"),
            sender_id: r.get("sender_id"),
            payload: r.get("payload"),
            processed: r.get("processed"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn mark_message_processed(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    let result = sqlx::query("UPDATE mls_messages SET processed = TRUE WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }

    Ok(())
}
