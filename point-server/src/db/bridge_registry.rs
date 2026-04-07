use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeType {
    pub id: String,
    pub bridge_type: String,
    pub display_name: String,
    pub description: String,
    pub icon: String,
    pub supports_people: bool,
    pub supports_items: bool,
    pub supports_double_puppet: bool,
}

fn row_to_bridge_type(r: sqlx::sqlite::SqliteRow) -> BridgeType {
    BridgeType {
        id: r.get("id"),
        bridge_type: r.get("bridge_type"),
        display_name: r.get("display_name"),
        description: r.get("description"),
        icon: r.get("icon"),
        supports_people: r.get("supports_people"),
        supports_items: r.get("supports_items"),
        supports_double_puppet: r.get("supports_double_puppet"),
    }
}

pub async fn list_bridge_types(pool: &DbPool) -> Result<Vec<BridgeType>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, bridge_type, display_name, description, icon, \
         supports_people, supports_items, supports_double_puppet \
         FROM bridge_registry ORDER BY display_name",
    )
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(row_to_bridge_type).collect())
}

pub async fn get_bridge_type(
    pool: &DbPool,
    bridge_type: &str,
) -> Result<Option<BridgeType>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, bridge_type, display_name, description, icon, \
         supports_people, supports_items, supports_double_puppet \
         FROM bridge_registry WHERE bridge_type = ?",
    )
    .bind(bridge_type)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(row_to_bridge_type))
}
