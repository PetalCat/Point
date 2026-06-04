use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

/// A saved visibility audience (Focus-style mode).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisibilityMode {
    pub id: String,
    pub user_id: String,
    pub name: String,
    pub icon: String,
    /// Group IDs included in this audience.
    pub group_ids: Vec<String>,
    /// Individual user IDs included in this audience.
    pub user_ids: Vec<String>,
    pub created_at: String,
}

fn row_to_mode(r: sqlx::sqlite::SqliteRow) -> VisibilityMode {
    let group_ids: Vec<String> =
        serde_json::from_str(&r.get::<String, _>("group_ids")).unwrap_or_default();
    let user_ids: Vec<String> =
        serde_json::from_str(&r.get::<String, _>("user_ids")).unwrap_or_default();
    VisibilityMode {
        id: r.get("id"),
        user_id: r.get("user_id"),
        name: r.get("name"),
        icon: r.get("icon"),
        group_ids,
        user_ids,
        created_at: r.get("created_at"),
    }
}

pub async fn list_modes(pool: &DbPool, user_id: &str) -> Result<Vec<VisibilityMode>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, name, icon, group_ids, user_ids, created_at \
         FROM visibility_modes WHERE user_id = ? ORDER BY created_at ASC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(row_to_mode).collect())
}

pub async fn get_mode(pool: &DbPool, id: &str) -> Result<Option<VisibilityMode>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, user_id, name, icon, group_ids, user_ids, created_at \
         FROM visibility_modes WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(row_to_mode))
}

#[allow(clippy::too_many_arguments)]
pub async fn create_mode(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    name: &str,
    icon: &str,
    group_ids: &[String],
    user_ids: &[String],
) -> Result<VisibilityMode, sqlx::Error> {
    sqlx::query(
        "INSERT INTO visibility_modes (id, user_id, name, icon, group_ids, user_ids) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(user_id)
    .bind(name)
    .bind(icon)
    .bind(serde_json::to_string(group_ids).unwrap_or_else(|_| "[]".into()))
    .bind(serde_json::to_string(user_ids).unwrap_or_else(|_| "[]".into()))
    .execute(pool)
    .await?;
    get_mode(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

#[allow(clippy::too_many_arguments)]
pub async fn update_mode(
    pool: &DbPool,
    id: &str,
    user_id: &str,
    name: &str,
    icon: &str,
    group_ids: &[String],
    user_ids: &[String],
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE visibility_modes SET name = ?, icon = ?, group_ids = ?, user_ids = ? \
         WHERE id = ? AND user_id = ?",
    )
    .bind(name)
    .bind(icon)
    .bind(serde_json::to_string(group_ids).unwrap_or_else(|_| "[]".into()))
    .bind(serde_json::to_string(user_ids).unwrap_or_else(|_| "[]".into()))
    .bind(id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_mode(pool: &DbPool, id: &str, user_id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM visibility_modes WHERE id = ? AND user_id = ?")
        .bind(id)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// The user's currently-applied mode ID (None = Custom).
pub async fn get_active_mode(pool: &DbPool, user_id: &str) -> Result<Option<String>, sqlx::Error> {
    let row = sqlx::query("SELECT active_mode_id FROM users WHERE id = ?")
        .bind(user_id)
        .fetch_optional(pool)
        .await?;
    Ok(row.and_then(|r| r.get::<Option<String>, _>("active_mode_id")))
}

pub async fn set_active_mode(
    pool: &DbPool,
    user_id: &str,
    mode_id: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE users SET active_mode_id = ? WHERE id = ?")
        .bind(mode_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}
