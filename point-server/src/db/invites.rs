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
    let row = sqlx::query(
        "SELECT id, max_uses, uses, expires_at FROM invites WHERE code = ?",
    )
    .bind(code)
    .fetch_optional(pool)
    .await?;

    let row = row.ok_or(sqlx::Error::RowNotFound)?;

    let max_uses: i32 = row.get("max_uses");
    let uses: i32 = row.get("uses");
    let expires_at: Option<String> = row.get("expires_at");
    let id: String = row.get("id");

    if uses >= max_uses {
        return Err(sqlx::Error::RowNotFound);
    }

    if let Some(exp) = expires_at {
        let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
        if now > exp {
            return Err(sqlx::Error::RowNotFound);
        }
    }

    sqlx::query("UPDATE invites SET uses = uses + 1 WHERE id = ?")
        .bind(&id)
        .execute(pool)
        .await?;

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
