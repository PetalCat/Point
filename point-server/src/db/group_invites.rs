use serde::Serialize;
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Serialize)]
pub struct GroupInvite {
    pub id: String,
    pub group_id: String,
    pub code: String,
    pub created_by: String,
    pub max_uses: i64,
    pub uses: i64,
    pub expires_at: Option<String>,
    pub created_at: String,
}

pub async fn create_invite(
    pool: &DbPool,
    id: &str,
    group_id: &str,
    code: &str,
    created_by: &str,
    max_uses: i32,
) -> Result<GroupInvite, sqlx::Error> {
    sqlx::query(
        "INSERT INTO group_invites (id, group_id, code, created_by, max_uses) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(group_id)
    .bind(code)
    .bind(created_by)
    .bind(max_uses)
    .execute(pool)
    .await?;

    get_invite(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_invite(pool: &DbPool, id: &str) -> Result<Option<GroupInvite>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, group_id, code, created_by, max_uses, uses, expires_at, created_at FROM group_invites WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| GroupInvite {
        id: r.get("id"),
        group_id: r.get("group_id"),
        code: r.get("code"),
        created_by: r.get("created_by"),
        max_uses: r.get("max_uses"),
        uses: r.get("uses"),
        expires_at: r.get("expires_at"),
        created_at: r.get("created_at"),
    }))
}

pub async fn get_invite_by_code(pool: &DbPool, code: &str) -> Result<Option<GroupInvite>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, group_id, code, created_by, max_uses, uses, expires_at, created_at FROM group_invites WHERE code = ?",
    )
    .bind(code)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| GroupInvite {
        id: r.get("id"),
        group_id: r.get("group_id"),
        code: r.get("code"),
        created_by: r.get("created_by"),
        max_uses: r.get("max_uses"),
        uses: r.get("uses"),
        expires_at: r.get("expires_at"),
        created_at: r.get("created_at"),
    }))
}

pub async fn use_invite(pool: &DbPool, code: &str) -> Result<GroupInvite, sqlx::Error> {
    let invite = get_invite_by_code(pool, code).await?.ok_or(sqlx::Error::RowNotFound)?;

    // Check max_uses (0 = unlimited)
    if invite.max_uses > 0 && invite.uses >= invite.max_uses {
        return Err(sqlx::Error::RowNotFound);
    }

    // Check expiry
    if let Some(ref exp) = invite.expires_at {
        let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string();
        if now > *exp {
            return Err(sqlx::Error::RowNotFound);
        }
    }

    sqlx::query("UPDATE group_invites SET uses = uses + 1 WHERE id = ?")
        .bind(&invite.id)
        .execute(pool)
        .await?;

    Ok(invite)
}

pub async fn list_invites(pool: &DbPool, group_id: &str) -> Result<Vec<GroupInvite>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, group_id, code, created_by, max_uses, uses, expires_at, created_at FROM group_invites WHERE group_id = ?",
    )
    .bind(group_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| GroupInvite {
            id: r.get("id"),
            group_id: r.get("group_id"),
            code: r.get("code"),
            created_by: r.get("created_by"),
            max_uses: r.get("max_uses"),
            uses: r.get("uses"),
            expires_at: r.get("expires_at"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn delete_invite(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    let result = sqlx::query("DELETE FROM group_invites WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }

    Ok(())
}
