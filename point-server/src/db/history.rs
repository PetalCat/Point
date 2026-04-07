use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone)]
pub struct HistoryPoint {
    pub id: String,
    pub user_id: String,
    pub encrypted_blob: Vec<u8>,
    pub source_type: String,
    pub timestamp: i64,
}

/// Store a location history point (encrypted blob).
pub async fn store_history_point(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    encrypted_blob: &[u8],
    source_type: &str,
    timestamp: i64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO location_history (id, user_id, encrypted_blob, source_type, timestamp) \
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(user_id)
    .bind(encrypted_blob)
    .bind(source_type)
    .bind(timestamp)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get history points for a user since a given timestamp, up to a limit.
pub async fn get_history_for_user(
    pool: &DbPool,
    user_id: &str,
    since_timestamp: i64,
    limit: i64,
) -> Result<Vec<HistoryPoint>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, encrypted_blob, source_type, timestamp \
         FROM location_history \
         WHERE user_id = ? AND timestamp >= ? \
         ORDER BY timestamp ASC \
         LIMIT ?",
    )
    .bind(user_id)
    .bind(since_timestamp)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| HistoryPoint {
            id: r.get("id"),
            user_id: r.get("user_id"),
            encrypted_blob: r.get("encrypted_blob"),
            source_type: r.get("source_type"),
            timestamp: r.get("timestamp"),
        })
        .collect())
}

/// Delete all history for a user (account deletion).
pub async fn delete_history_for_user(pool: &DbPool, user_id: &str) -> Result<u64, sqlx::Error> {
    let result = sqlx::query("DELETE FROM location_history WHERE user_id = ?")
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected())
}

/// Delete history entries older than max_age_days. Returns the number of rows removed.
pub async fn cleanup_old_history(pool: &DbPool, max_age_days: i64) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        "DELETE FROM location_history WHERE datetime(created_at) < datetime('now', '-' || ? || ' days')",
    )
    .bind(max_age_days)
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}
