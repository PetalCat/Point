use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub bridge_id: Option<String>,
    pub capabilities: String,
    pub last_seen: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemShare {
    pub target_type: String,
    pub target_id: String,
    pub precision: String,
}

pub async fn create_item(
    pool: &DbPool,
    id: &str,
    owner_id: &str,
    name: &str,
    tracker_type: &str,
    source_id: Option<&str>,
    bridge_id: Option<&str>,
) -> Result<Item, sqlx::Error> {
    sqlx::query(
        "INSERT INTO items (id, owner_id, name, tracker_type, source_id, bridge_id) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(owner_id)
    .bind(name)
    .bind(tracker_type)
    .bind(source_id)
    .bind(bridge_id)
    .execute(pool)
    .await?;

    get_item(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_item(pool: &DbPool, id: &str) -> Result<Option<Item>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, owner_id, name, tracker_type, source_id, bridge_id, capabilities, last_seen \
         FROM items WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| Item {
        id: r.get("id"),
        owner_id: r.get("owner_id"),
        name: r.get("name"),
        tracker_type: r.get("tracker_type"),
        source_id: r.get("source_id"),
        bridge_id: r.get("bridge_id"),
        capabilities: r.get("capabilities"),
        last_seen: r.get("last_seen"),
    }))
}

pub async fn list_user_items(pool: &DbPool, user_id: &str) -> Result<Vec<Item>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT DISTINCT i.id, i.owner_id, i.name, i.tracker_type, i.source_id, \
         i.bridge_id, i.capabilities, i.last_seen \
         FROM items i \
         LEFT JOIN item_shares s ON i.id = s.item_id \
         LEFT JOIN group_members gm ON s.target_type = 'group' AND s.target_id = gm.group_id \
         WHERE i.owner_id = ? \
            OR (s.target_type = 'user' AND s.target_id = ?) \
            OR (s.target_type = 'group' AND gm.user_id = ?)",
    )
    .bind(user_id)
    .bind(user_id)
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Item {
            id: r.get("id"),
            owner_id: r.get("owner_id"),
            name: r.get("name"),
            tracker_type: r.get("tracker_type"),
            source_id: r.get("source_id"),
            bridge_id: r.get("bridge_id"),
            capabilities: r.get("capabilities"),
            last_seen: r.get("last_seen"),
        })
        .collect())
}

pub async fn share_item(
    pool: &DbPool,
    item_id: &str,
    target_type: &str,
    target_id: &str,
    precision: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO item_shares (item_id, target_type, target_id, precision) \
         VALUES (?, ?, ?, ?)",
    )
    .bind(item_id)
    .bind(target_type)
    .bind(target_id)
    .bind(precision)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn unshare_item(
    pool: &DbPool,
    item_id: &str,
    target_type: &str,
    target_id: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "DELETE FROM item_shares WHERE item_id = ? AND target_type = ? AND target_id = ?",
    )
    .bind(item_id)
    .bind(target_type)
    .bind(target_id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn get_item_shares(
    pool: &DbPool,
    item_id: &str,
) -> Result<Vec<ItemShare>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT target_type, target_id, precision FROM item_shares WHERE item_id = ?",
    )
    .bind(item_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| ItemShare {
            target_type: r.get("target_type"),
            target_id: r.get("target_id"),
            precision: r.get("precision"),
        })
        .collect())
}

pub async fn delete_item(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM items WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(())
}
