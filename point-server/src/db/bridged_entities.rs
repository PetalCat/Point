use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgedEntity {
    pub id: String,
    pub address: String,
    pub entity_type: String,
    pub display_name: String,
    pub bridge_owner_id: String,
    pub bridge_type: String,
    pub bridge_id: Option<String>,
    pub source_id: Option<String>,
    pub tracker_type: Option<String>,
    pub capabilities: String,
    pub last_seen: Option<String>,
    pub created_at: String,
}

fn row_to_entity(r: sqlx::sqlite::SqliteRow) -> BridgedEntity {
    BridgedEntity {
        id: r.get("id"),
        address: r.get("address"),
        entity_type: r.get("entity_type"),
        display_name: r.get("display_name"),
        bridge_owner_id: r.get("bridge_owner_id"),
        bridge_type: r.get("bridge_type"),
        bridge_id: r.get("bridge_id"),
        source_id: r.get("source_id"),
        tracker_type: r.get("tracker_type"),
        capabilities: r.get("capabilities"),
        last_seen: r.get("last_seen"),
        created_at: r.get("created_at"),
    }
}

pub fn generate_address(id: &str, bridge_type: &str, domain: &str) -> String {
    let short_id = &id[..8];
    format!("{}:{}@{}", short_id, bridge_type, domain)
}

pub async fn create_entity(
    pool: &DbPool,
    id: &str,
    address: &str,
    entity_type: &str,
    display_name: &str,
    bridge_owner_id: &str,
    bridge_type: &str,
    source_id: Option<&str>,
    tracker_type: Option<&str>,
) -> Result<BridgedEntity, sqlx::Error> {
    sqlx::query(
        "INSERT INTO bridged_entities (id, address, entity_type, display_name, bridge_owner_id, bridge_type, source_id, tracker_type) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(address)
    .bind(entity_type)
    .bind(display_name)
    .bind(bridge_owner_id)
    .bind(bridge_type)
    .bind(source_id)
    .bind(tracker_type)
    .execute(pool)
    .await?;

    get_entity(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_entity(pool: &DbPool, id: &str) -> Result<Option<BridgedEntity>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, address, entity_type, display_name, bridge_owner_id, bridge_type, \
         bridge_id, source_id, tracker_type, capabilities, last_seen, created_at \
         FROM bridged_entities WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(row_to_entity))
}

pub async fn get_entity_by_address(
    pool: &DbPool,
    address: &str,
) -> Result<Option<BridgedEntity>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, address, entity_type, display_name, bridge_owner_id, bridge_type, \
         bridge_id, source_id, tracker_type, capabilities, last_seen, created_at \
         FROM bridged_entities WHERE address = ?",
    )
    .bind(address)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(row_to_entity))
}

pub async fn list_entities_for_owner(
    pool: &DbPool,
    owner_id: &str,
) -> Result<Vec<BridgedEntity>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, address, entity_type, display_name, bridge_owner_id, bridge_type, \
         bridge_id, source_id, tracker_type, capabilities, last_seen, created_at \
         FROM bridged_entities WHERE bridge_owner_id = ?",
    )
    .bind(owner_id)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(row_to_entity).collect())
}

pub async fn list_entities_for_bridge(
    pool: &DbPool,
    bridge_id: &str,
) -> Result<Vec<BridgedEntity>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, address, entity_type, display_name, bridge_owner_id, bridge_type, \
         bridge_id, source_id, tracker_type, capabilities, last_seen, created_at \
         FROM bridged_entities WHERE bridge_id = ?",
    )
    .bind(bridge_id)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(row_to_entity).collect())
}

pub async fn update_entity_location(
    pool: &DbPool,
    id: &str,
    location_blob: &[u8],
    timestamp: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE bridged_entities SET last_location = ?, last_seen = ?, updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(location_blob)
    .bind(timestamp)
    .bind(id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn confirm_entity(
    pool: &DbPool,
    id: &str,
    bridge_id: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE bridged_entities SET bridge_id = ?, updated_at = datetime('now') WHERE id = ?",
    )
    .bind(bridge_id)
    .bind(id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn delete_entity(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM bridged_entities WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(())
}
