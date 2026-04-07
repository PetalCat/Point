use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub members_can_invite: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMember {
    pub user_id: String,
    pub role: String,
    pub precision: String,
    pub sharing: bool,
    pub schedule_type: String,
}

pub async fn create_group(
    pool: &DbPool,
    id: &str,
    name: &str,
    owner_id: &str,
) -> Result<Group, sqlx::Error> {
    sqlx::query("INSERT INTO groups (id, name, owner_id) VALUES (?, ?, ?)")
        .bind(id)
        .bind(name)
        .bind(owner_id)
        .execute(pool)
        .await?;

    // Owner joins as admin, sharing on
    add_member(pool, id, owner_id, "admin", "exact").await?;

    get_group(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_group(pool: &DbPool, id: &str) -> Result<Option<Group>, sqlx::Error> {
    let row = sqlx::query("SELECT id, name, owner_id, members_can_invite FROM groups WHERE id = ?")
        .bind(id)
        .fetch_optional(pool)
        .await?;

    Ok(row.map(|r| Group {
        id: r.get("id"),
        name: r.get("name"),
        owner_id: r.get("owner_id"),
        members_can_invite: r.get("members_can_invite"),
    }))
}

pub async fn list_user_groups(pool: &DbPool, user_id: &str) -> Result<Vec<Group>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT g.id, g.name, g.owner_id, g.members_can_invite \
         FROM groups g JOIN group_members gm ON g.id = gm.group_id WHERE gm.user_id = ?",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Group {
            id: r.get("id"),
            name: r.get("name"),
            owner_id: r.get("owner_id"),
            members_can_invite: r.get("members_can_invite"),
        })
        .collect())
}

pub async fn add_member(pool: &DbPool, group_id: &str, user_id: &str, role: &str, precision: &str) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO group_members (group_id, user_id, role, precision, sharing) VALUES (?, ?, ?, ?, TRUE)")
        .bind(group_id).bind(user_id).bind(role).bind(precision)
        .execute(pool).await?;
    Ok(())
}

pub async fn remove_member(pool: &DbPool, group_id: &str, user_id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM group_members WHERE group_id = ? AND user_id = ?")
        .bind(group_id).bind(user_id)
        .execute(pool).await?;
    Ok(())
}

pub async fn get_members(pool: &DbPool, group_id: &str) -> Result<Vec<GroupMember>, sqlx::Error> {
    let rows = sqlx::query("SELECT user_id, role, precision, sharing, schedule_type FROM group_members WHERE group_id = ?")
        .bind(group_id)
        .fetch_all(pool).await?;

    Ok(rows.into_iter().map(|r| GroupMember {
        user_id: r.get("user_id"),
        role: r.get("role"),
        precision: r.get("precision"),
        sharing: r.get("sharing"),
        schedule_type: r.get("schedule_type"),
    }).collect())
}

pub async fn get_member_role(pool: &DbPool, group_id: &str, user_id: &str) -> Result<Option<String>, sqlx::Error> {
    let row = sqlx::query("SELECT role FROM group_members WHERE group_id = ? AND user_id = ?")
        .bind(group_id).bind(user_id)
        .fetch_optional(pool).await?;
    Ok(row.map(|r| r.get("role")))
}

pub async fn update_my_settings(
    pool: &DbPool,
    group_id: &str,
    user_id: &str,
    precision: Option<&str>,
    sharing: Option<bool>,
    schedule_type: Option<&str>,
) -> Result<(), sqlx::Error> {
    if let Some(p) = precision {
        sqlx::query("UPDATE group_members SET precision = ? WHERE group_id = ? AND user_id = ?")
            .bind(p).bind(group_id).bind(user_id).execute(pool).await?;
    }
    if let Some(s) = sharing {
        sqlx::query("UPDATE group_members SET sharing = ? WHERE group_id = ? AND user_id = ?")
            .bind(s).bind(group_id).bind(user_id).execute(pool).await?;
    }
    if let Some(st) = schedule_type {
        sqlx::query("UPDATE group_members SET schedule_type = ? WHERE group_id = ? AND user_id = ?")
            .bind(st).bind(group_id).bind(user_id).execute(pool).await?;
    }
    Ok(())
}

pub async fn update_member_role(pool: &DbPool, group_id: &str, user_id: &str, role: &str) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE group_members SET role = ? WHERE group_id = ? AND user_id = ?")
        .bind(role).bind(group_id).bind(user_id).execute(pool).await?;
    Ok(())
}

pub async fn rename_group(pool: &DbPool, id: &str, name: &str) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE groups SET name = ? WHERE id = ?")
        .bind(name).bind(id).execute(pool).await?;
    Ok(())
}

pub async fn update_group_settings(pool: &DbPool, id: &str, members_can_invite: bool) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE groups SET members_can_invite = ? WHERE id = ?")
        .bind(members_can_invite).bind(id).execute(pool).await?;
    Ok(())
}

pub async fn delete_group(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM groups WHERE id = ?").bind(id).execute(pool).await?;
    Ok(())
}
