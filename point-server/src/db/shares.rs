use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareRequest {
    pub id: String,
    pub from_user_id: String,
    pub to_user_id: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserShare {
    pub other_user_id: String,
    pub created_at: String,
}

pub async fn create_request(
    pool: &DbPool,
    id: &str,
    from_user_id: &str,
    to_user_id: &str,
) -> Result<ShareRequest, sqlx::Error> {
    sqlx::query(
        "INSERT INTO share_requests (id, from_user_id, to_user_id) VALUES (?, ?, ?)",
    )
    .bind(id)
    .bind(from_user_id)
    .bind(to_user_id)
    .execute(pool)
    .await?;

    let row = sqlx::query(
        "SELECT id, from_user_id, to_user_id, status, created_at FROM share_requests WHERE id = ?",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    Ok(ShareRequest {
        id: row.get("id"),
        from_user_id: row.get("from_user_id"),
        to_user_id: row.get("to_user_id"),
        status: row.get("status"),
        created_at: row.get("created_at"),
    })
}

pub async fn get_pending_requests_for_user(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<ShareRequest>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, from_user_id, to_user_id, status, created_at \
         FROM share_requests WHERE to_user_id = ? AND status = 'pending' \
         ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ShareRequest {
            id: r.get("id"),
            from_user_id: r.get("from_user_id"),
            to_user_id: r.get("to_user_id"),
            status: r.get("status"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn get_outgoing_requests(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<ShareRequest>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, from_user_id, to_user_id, status, created_at \
         FROM share_requests WHERE from_user_id = ? AND status = 'pending' \
         ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ShareRequest {
            id: r.get("id"),
            from_user_id: r.get("from_user_id"),
            to_user_id: r.get("to_user_id"),
            status: r.get("status"),
            created_at: r.get("created_at"),
        })
        .collect())
}

/// Accept a share request. Only the recipient (to_user_id) can accept.
/// Creates a user_shares entry with the smaller ID as user_a.
pub async fn accept_request(
    pool: &DbPool,
    request_id: &str,
    user_id: &str,
) -> Result<(), sqlx::Error> {
    // Fetch the request and verify the user is the recipient
    let row = sqlx::query(
        "SELECT from_user_id, to_user_id FROM share_requests WHERE id = ? AND to_user_id = ? AND status = 'pending'",
    )
    .bind(request_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    let row = row.ok_or(sqlx::Error::RowNotFound)?;
    let from_user_id: String = row.get("from_user_id");
    let to_user_id: String = row.get("to_user_id");

    // Update status
    sqlx::query(
        "UPDATE share_requests SET status = 'accepted', updated_at = datetime('now') WHERE id = ?",
    )
    .bind(request_id)
    .execute(pool)
    .await?;

    // Create user_shares entry with smaller ID as user_a
    let (user_a, user_b) = if from_user_id < to_user_id {
        (from_user_id, to_user_id)
    } else {
        (to_user_id, from_user_id)
    };

    sqlx::query(
        "INSERT OR IGNORE INTO user_shares (user_a, user_b) VALUES (?, ?)",
    )
    .bind(&user_a)
    .bind(&user_b)
    .execute(pool)
    .await?;

    Ok(())
}

/// Reject a share request. Only the recipient (to_user_id) can reject.
pub async fn reject_request(
    pool: &DbPool,
    request_id: &str,
    user_id: &str,
) -> Result<(), sqlx::Error> {
    let result = sqlx::query(
        "UPDATE share_requests SET status = 'rejected', updated_at = datetime('now') \
         WHERE id = ? AND to_user_id = ? AND status = 'pending'",
    )
    .bind(request_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }

    Ok(())
}

/// Get all active shares for a user, returning the other user's ID.
pub async fn get_shares_for_user(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<UserShare>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT \
           CASE WHEN user_a = ? THEN user_b ELSE user_a END AS other_user_id, \
           created_at \
         FROM user_shares \
         WHERE user_a = ? OR user_b = ? \
         ORDER BY created_at DESC",
    )
    .bind(user_id)
    .bind(user_id)
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| UserShare {
            other_user_id: r.get("other_user_id"),
            created_at: r.get("created_at"),
        })
        .collect())
}

/// Remove an active share between two users.
pub async fn remove_share(
    pool: &DbPool,
    user_id: &str,
    other_user_id: &str,
) -> Result<(), sqlx::Error> {
    let (user_a, user_b) = if user_id < other_user_id {
        (user_id, other_user_id)
    } else {
        (other_user_id, user_id)
    };

    let result = sqlx::query("DELETE FROM user_shares WHERE user_a = ? AND user_b = ?")
        .bind(user_a)
        .bind(user_b)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }

    Ok(())
}

// ==================== TEMPORARY SHARES ====================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempShare {
    pub id: String,
    pub from_user_id: String,
    pub to_user_id: Option<String>,
    pub link_token: Option<String>,
    pub precision: String,
    pub expires_at: String,
    pub created_at: String,
}

pub async fn create_temp_share(
    pool: &DbPool,
    id: &str,
    from_user_id: &str,
    to_user_id: Option<&str>,
    link_token: Option<&str>,
    precision: &str,
    expires_at: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO temporary_shares (id, from_user_id, to_user_id, link_token, precision, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(from_user_id)
    .bind(to_user_id)
    .bind(link_token)
    .bind(precision)
    .bind(expires_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn get_active_temp_shares(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<TempShare>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, from_user_id, to_user_id, link_token, precision, expires_at, created_at \
         FROM temporary_shares WHERE from_user_id = ? AND expires_at > datetime('now')",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| TempShare {
            id: r.get("id"),
            from_user_id: r.get("from_user_id"),
            to_user_id: r.get("to_user_id"),
            link_token: r.get("link_token"),
            precision: r.get("precision"),
            expires_at: r.get("expires_at"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn get_temp_shares_for_recipient(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<TempShare>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, from_user_id, to_user_id, link_token, precision, expires_at, created_at \
         FROM temporary_shares WHERE to_user_id = ? AND expires_at > datetime('now')",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| TempShare {
            id: r.get("id"),
            from_user_id: r.get("from_user_id"),
            to_user_id: r.get("to_user_id"),
            link_token: r.get("link_token"),
            precision: r.get("precision"),
            expires_at: r.get("expires_at"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn delete_temp_share(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM temporary_shares WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn cleanup_expired_temp_shares(pool: &DbPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query("DELETE FROM temporary_shares WHERE expires_at <= datetime('now')")
        .execute(pool)
        .await?;
    Ok(result.rows_affected())
}

/// Check if two users have an active share.
pub async fn are_sharing(
    pool: &DbPool,
    user_a: &str,
    user_b: &str,
) -> Result<bool, sqlx::Error> {
    let (a, b) = if user_a < user_b {
        (user_a, user_b)
    } else {
        (user_b, user_a)
    };

    let row = sqlx::query("SELECT COUNT(*) as cnt FROM user_shares WHERE user_a = ? AND user_b = ?")
        .bind(a)
        .bind(b)
        .fetch_one(pool)
        .await?;

    let count: i64 = row.get("cnt");
    Ok(count > 0)
}
