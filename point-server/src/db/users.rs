use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub display_name: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub is_admin: bool,
    pub created_at: String,
}

pub async fn create_user(
    pool: &DbPool,
    id: &str,
    display_name: &str,
    password_hash: &str,
    is_admin: bool,
) -> Result<User, sqlx::Error> {
    sqlx::query(
        "INSERT INTO users (id, display_name, password_hash, is_admin) VALUES (?, ?, ?, ?)",
    )
    .bind(id)
    .bind(display_name)
    .bind(password_hash)
    .bind(is_admin)
    .execute(pool)
    .await?;

    get_user_by_id(pool, id)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_user_by_id(pool: &DbPool, id: &str) -> Result<Option<User>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, display_name, password_hash, is_admin, created_at FROM users WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| User {
        id: r.get("id"),
        display_name: r.get("display_name"),
        password_hash: r.get("password_hash"),
        is_admin: r.get("is_admin"),
        created_at: r.get("created_at"),
    }))
}

pub async fn count_users(pool: &DbPool) -> Result<i64, sqlx::Error> {
    let row = sqlx::query("SELECT COUNT(*) as cnt FROM users")
        .fetch_one(pool)
        .await?;
    Ok(row.get("cnt"))
}

pub async fn delete_user(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM users WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn update_password(pool: &DbPool, id: &str, new_hash: &str) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE users SET password_hash = ?, updated_at = datetime('now') WHERE id = ?")
        .bind(new_hash)
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn save_fcm_token(pool: &DbPool, user_id: &str, token: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO fcm_tokens (user_id, token) VALUES (?, ?) ON CONFLICT(user_id, token) DO UPDATE SET updated_at = datetime('now')"
    ).bind(user_id).bind(token).execute(pool).await?;
    Ok(())
}

pub async fn get_fcm_tokens(pool: &DbPool, user_id: &str) -> Result<Vec<String>, sqlx::Error> {
    let rows = sqlx::query("SELECT token FROM fcm_tokens WHERE user_id = ?")
        .bind(user_id).fetch_all(pool).await?;
    use sqlx::Row;
    Ok(rows.into_iter().map(|r| r.get("token")).collect())
}

pub async fn set_ghost_flag(pool: &DbPool, user_id: &str, ghosted: bool) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE users SET ghost_active = ? WHERE id = ?")
        .bind(ghosted).bind(user_id).execute(pool).await?;
    Ok(())
}

pub async fn is_ghost_active(pool: &DbPool, user_id: &str) -> Result<bool, sqlx::Error> {
    let row = sqlx::query("SELECT ghost_active FROM users WHERE id = ?")
        .bind(user_id).fetch_optional(pool).await?;
    use sqlx::Row;
    Ok(row.map(|r| r.get::<bool, _>("ghost_active")).unwrap_or(false))
}
