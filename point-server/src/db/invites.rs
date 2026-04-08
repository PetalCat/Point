use serde::Serialize;
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Serialize)]
pub struct Invite {
    pub id: String,
    pub code: String,
    pub created_by: String,
    pub max_uses: i64,
    pub uses: i64,
}

pub async fn create_invite(
    pool: &DbPool,
    id: &str,
    code: &str,
    created_by: &str,
    max_uses: i32,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO invites (id, code, created_by, max_uses) VALUES (?, ?, ?, ?)")
        .bind(id)
        .bind(code)
        .bind(created_by)
        .bind(max_uses)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn use_invite(pool: &DbPool, code: &str) -> Result<(), sqlx::Error> {
    // Atomic check-and-increment: single statement prevents race conditions
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let result = sqlx::query(
        "UPDATE invites SET uses = uses + 1 \
         WHERE code = ? AND uses < max_uses \
         AND (expires_at IS NULL OR expires_at > ?)",
    )
    .bind(code)
    .bind(&now)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }
    Ok(())
}

pub async fn list_invites(pool: &DbPool, created_by: &str) -> Result<Vec<Invite>, sqlx::Error> {
    let rows =
        sqlx::query("SELECT id, code, created_by, max_uses, uses FROM invites WHERE created_by = ?")
            .bind(created_by)
            .fetch_all(pool)
            .await?;

    Ok(rows
        .into_iter()
        .map(|r| Invite {
            id: r.get("id"),
            code: r.get("code"),
            created_by: r.get("created_by"),
            max_uses: r.get("max_uses"),
            uses: r.get("uses"),
        })
        .collect())
}

pub async fn delete_invite(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    let result = sqlx::query("DELETE FROM invites WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }

    Ok(())
}
