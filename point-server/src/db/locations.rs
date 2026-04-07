use sqlx::Row;

use super::DbPool;

/// Store an encrypted location update blob.
pub async fn store_location(
    pool: &DbPool,
    id: &str,
    sender_id: &str,
    recipient_type: &str,
    recipient_id: &str,
    encrypted_blob: &[u8],
    source_type: &str,
    timestamp: i64,
    ttl: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO location_updates (id, sender_id, recipient_type, recipient_id, encrypted_blob, source_type, timestamp, ttl) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(sender_id)
    .bind(recipient_type)
    .bind(recipient_id)
    .bind(encrypted_blob)
    .bind(source_type)
    .bind(timestamp)
    .bind(ttl)
    .execute(pool)
    .await?;

    Ok(())
}

/// Delete location updates whose TTL has expired. Returns the number of rows removed.
pub async fn cleanup_expired(pool: &DbPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        "DELETE FROM location_updates WHERE datetime(created_at, '+' || ttl || ' seconds') < datetime('now')",
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}

/// Get the most recent location update sent by a given user (for reconnect sync).
pub async fn get_latest_for_user(
    pool: &DbPool,
    sender_id: &str,
) -> Result<Option<LocationUpdate>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, sender_id, recipient_type, recipient_id, encrypted_blob, source_type, timestamp, ttl, created_at \
         FROM location_updates WHERE sender_id = ? ORDER BY created_at DESC LIMIT 1",
    )
    .bind(sender_id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| LocationUpdate {
        id: r.get("id"),
        sender_id: r.get("sender_id"),
        recipient_type: r.get("recipient_type"),
        recipient_id: r.get("recipient_id"),
        encrypted_blob: r.get("encrypted_blob"),
        source_type: r.get("source_type"),
        timestamp: r.get("timestamp"),
        ttl: r.get("ttl"),
        created_at: r.get("created_at"),
    }))
}

#[derive(Debug, Clone)]
pub struct LocationUpdate {
    pub id: String,
    pub sender_id: String,
    pub recipient_type: String,
    pub recipient_id: String,
    pub encrypted_blob: Vec<u8>,
    pub source_type: String,
    pub timestamp: i64,
    pub ttl: i64,
    pub created_at: String,
}
