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

/// Store a location history point (encrypted blob), bound to the audience it
/// was sent to so reads can be authorized per-audience (P1-10).
pub async fn store_history_point(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    encrypted_blob: &[u8],
    source_type: &str,
    timestamp: i64,
    recipient_type: &str,
    recipient_id: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO location_history (id, user_id, encrypted_blob, source_type, timestamp, recipient_type, recipient_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(user_id)
    .bind(encrypted_blob)
    .bind(source_type)
    .bind(timestamp)
    .bind(recipient_type)
    .bind(recipient_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Fetch the owner's own history (all audiences). Only the owner may use this.
pub async fn get_own_history(
    pool: &DbPool,
    user_id: &str,
    since_timestamp: i64,
    limit: i64,
) -> Result<Vec<HistoryPoint>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, encrypted_blob, source_type, timestamp \
         FROM location_history \
         WHERE user_id = ? AND timestamp >= ? \
         ORDER BY timestamp ASC LIMIT ?",
    )
    .bind(user_id)
    .bind(since_timestamp)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(row_to_point).collect())
}

/// Fetch history of `target` that `requester` is authorized to see — only rows
/// addressed directly to the requester, or to a group both share (P1-10).
/// Legacy rows with NULL audience are excluded for non-owners.
pub async fn get_history_for_audience(
    pool: &DbPool,
    target: &str,
    requester: &str,
    requester_group_ids: &[String],
    since_timestamp: i64,
    limit: i64,
) -> Result<Vec<HistoryPoint>, sqlx::Error> {
    // Build the group-id placeholder list dynamically.
    let group_placeholders = if requester_group_ids.is_empty() {
        "NULL".to_string()
    } else {
        requester_group_ids.iter().map(|_| "?").collect::<Vec<_>>().join(",")
    };

    let sql = format!(
        "SELECT id, user_id, encrypted_blob, source_type, timestamp \
         FROM location_history \
         WHERE user_id = ? AND timestamp >= ? AND ( \
             (recipient_type = 'user' AND recipient_id = ?) \
             OR (recipient_type = 'group' AND recipient_id IN ({group_placeholders})) \
         ) \
         ORDER BY timestamp ASC LIMIT ?"
    );

    let mut q = sqlx::query(&sql)
        .bind(target)
        .bind(since_timestamp)
        .bind(requester);
    for gid in requester_group_ids {
        q = q.bind(gid);
    }
    q = q.bind(limit);

    let rows = q.fetch_all(pool).await?;
    Ok(rows.into_iter().map(row_to_point).collect())
}

fn row_to_point(r: sqlx::sqlite::SqliteRow) -> HistoryPoint {
    HistoryPoint {
        id: r.get("id"),
        user_id: r.get("user_id"),
        encrypted_blob: r.get("encrypted_blob"),
        source_type: r.get("source_type"),
        timestamp: r.get("timestamp"),
    }
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
