use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZoneConsent {
    pub zone_owner_id: String,
    pub consenter_id: String,
    pub status: String,
    pub created_at: String,
}

/// Insert a pending consent request (zone owner asks consenter to opt in).
pub async fn request_consent(
    pool: &DbPool,
    zone_owner_id: &str,
    consenter_id: &str,
) -> Result<ZoneConsent, sqlx::Error> {
    sqlx::query(
        "INSERT INTO zone_consents (zone_owner_id, consenter_id, status) VALUES (?, ?, 'pending')",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .execute(pool)
    .await?;

    let row = sqlx::query(
        "SELECT zone_owner_id, consenter_id, status, created_at FROM zone_consents \
         WHERE zone_owner_id = ? AND consenter_id = ?",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .fetch_one(pool)
    .await?;

    Ok(ZoneConsent {
        zone_owner_id: row.get("zone_owner_id"),
        consenter_id: row.get("consenter_id"),
        status: row.get("status"),
        created_at: row.get("created_at"),
    })
}

/// Consenter accepts — allow zone owner's zones to evaluate their location.
pub async fn accept_consent(
    pool: &DbPool,
    zone_owner_id: &str,
    consenter_id: &str,
) -> Result<(), sqlx::Error> {
    let result = sqlx::query(
        "UPDATE zone_consents SET status = 'accepted' \
         WHERE zone_owner_id = ? AND consenter_id = ? AND status = 'pending'",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }
    Ok(())
}

/// Consenter rejects the request.
pub async fn reject_consent(
    pool: &DbPool,
    zone_owner_id: &str,
    consenter_id: &str,
) -> Result<(), sqlx::Error> {
    let result = sqlx::query(
        "UPDATE zone_consents SET status = 'rejected' \
         WHERE zone_owner_id = ? AND consenter_id = ? AND status = 'pending'",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }
    Ok(())
}

/// Consenter revokes previously granted consent (delete the row).
pub async fn revoke_consent(
    pool: &DbPool,
    zone_owner_id: &str,
    consenter_id: &str,
) -> Result<(), sqlx::Error> {
    let result = sqlx::query(
        "DELETE FROM zone_consents WHERE zone_owner_id = ? AND consenter_id = ?",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }
    Ok(())
}

/// Get all users who have consented to the zone owner's zones (status = accepted).
pub async fn get_consents_for_owner(
    pool: &DbPool,
    zone_owner_id: &str,
) -> Result<Vec<ZoneConsent>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT zone_owner_id, consenter_id, status, created_at \
         FROM zone_consents WHERE zone_owner_id = ? AND status = 'accepted' \
         ORDER BY created_at DESC",
    )
    .bind(zone_owner_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ZoneConsent {
            zone_owner_id: r.get("zone_owner_id"),
            consenter_id: r.get("consenter_id"),
            status: r.get("status"),
            created_at: r.get("created_at"),
        })
        .collect())
}

/// Get pending consent requests addressed to this user (they are the consenter).
pub async fn get_consent_requests_for_user(
    pool: &DbPool,
    user_id: &str,
) -> Result<Vec<ZoneConsent>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT zone_owner_id, consenter_id, status, created_at \
         FROM zone_consents WHERE consenter_id = ? AND status = 'pending' \
         ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ZoneConsent {
            zone_owner_id: r.get("zone_owner_id"),
            consenter_id: r.get("consenter_id"),
            status: r.get("status"),
            created_at: r.get("created_at"),
        })
        .collect())
}

/// Check if a specific user has accepted consent for a zone owner.
pub async fn has_consent(
    pool: &DbPool,
    zone_owner_id: &str,
    consenter_id: &str,
) -> Result<bool, sqlx::Error> {
    let row = sqlx::query(
        "SELECT COUNT(*) as cnt FROM zone_consents \
         WHERE zone_owner_id = ? AND consenter_id = ? AND status = 'accepted'",
    )
    .bind(zone_owner_id)
    .bind(consenter_id)
    .fetch_one(pool)
    .await?;

    let count: i64 = row.get("cnt");
    Ok(count > 0)
}
