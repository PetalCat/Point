use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Place {
    pub id: String,
    pub group_id: String,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub radius: f64,
    pub geometry_type: String,
    pub polygon_points: Option<String>,
    pub triggers: String,
    pub notify: String,
    pub created_at: String,
    pub user_id: Option<String>,
    pub is_personal: bool,
    /// MLS-encrypted geometry blob (base64). When present, lat/lon/radius/
    /// polygon are zeroed and the real geometry lives here (P0-06).
    pub encrypted_geometry: Option<String>,
}

pub async fn create_place(
    pool: &DbPool,
    id: &str,
    group_id: &str,
    name: &str,
    lat: f64,
    lon: f64,
    radius: f64,
    geometry_type: &str,
    polygon_points: Option<&str>,
    triggers: &str,
    user_id: Option<&str>,
    is_personal: bool,
    encrypted_geometry: Option<&str>,
) -> Result<Place, sqlx::Error> {
    // When the client supplies encrypted_geometry, lat/lon/radius/polygon are
    // zeroed — the real geometry lives only in the encrypted blob (P0-06).
    sqlx::query(
        "INSERT INTO places (id, group_id, name, encrypted_definition, lat, lon, radius, geometry_type, polygon_points, triggers, user_id, is_personal, encrypted_geometry) \
         VALUES (?, ?, ?, X'', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(id)
    .bind(group_id)
    .bind(name)
    .bind(lat)
    .bind(lon)
    .bind(radius)
    .bind(geometry_type)
    .bind(polygon_points)
    .bind(triggers)
    .bind(user_id)
    .bind(is_personal)
    .bind(encrypted_geometry)
    .execute(pool)
    .await?;

    get_place(pool, id).await?.ok_or(sqlx::Error::RowNotFound)
}

pub async fn get_place(pool: &DbPool, id: &str) -> Result<Option<Place>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, group_id, name, lat, lon, radius, geometry_type, polygon_points, triggers, notify, created_at, user_id, is_personal, encrypted_geometry FROM places WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| Place {
        id: r.get("id"),
        group_id: r.get("group_id"),
        name: r.get("name"),
        lat: r.get("lat"),
        lon: r.get("lon"),
        radius: r.get("radius"),
        geometry_type: r.get("geometry_type"),
        polygon_points: r.get("polygon_points"),
        triggers: r.get("triggers"),
        notify: r.get("notify"),
        created_at: r.get("created_at"),
        user_id: r.get("user_id"),
        is_personal: r.get("is_personal"),
        encrypted_geometry: r.get("encrypted_geometry"),
    }))
}

pub async fn list_places_for_group(pool: &DbPool, group_id: &str) -> Result<Vec<Place>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, group_id, name, lat, lon, radius, geometry_type, polygon_points, triggers, notify, created_at, user_id, is_personal, encrypted_geometry \
         FROM places WHERE group_id = ? AND is_personal = FALSE",
    )
    .bind(group_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Place {
            id: r.get("id"),
            group_id: r.get("group_id"),
            name: r.get("name"),
            lat: r.get("lat"),
            lon: r.get("lon"),
            radius: r.get("radius"),
            geometry_type: r.get("geometry_type"),
            polygon_points: r.get("polygon_points"),
            triggers: r.get("triggers"),
            notify: r.get("notify"),
            created_at: r.get("created_at"),
            user_id: r.get("user_id"),
            is_personal: r.get("is_personal"),
            encrypted_geometry: r.get("encrypted_geometry"),
        })
        .collect())
}

pub async fn list_places_for_user(pool: &DbPool, user_id: &str) -> Result<Vec<Place>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT p.id, p.group_id, p.name, p.lat, p.lon, p.radius, p.geometry_type, p.polygon_points, p.triggers, p.notify, p.created_at, p.user_id, p.is_personal, p.encrypted_geometry \
         FROM places p JOIN group_members gm ON p.group_id = gm.group_id WHERE gm.user_id = ? AND p.is_personal = FALSE \
         UNION \
         SELECT id, group_id, name, lat, lon, radius, geometry_type, polygon_points, triggers, notify, created_at, user_id, is_personal, encrypted_geometry \
         FROM places WHERE user_id = ? AND is_personal = TRUE",
    )
    .bind(user_id)
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Place {
            id: r.get("id"),
            group_id: r.get("group_id"),
            name: r.get("name"),
            lat: r.get("lat"),
            lon: r.get("lon"),
            radius: r.get("radius"),
            geometry_type: r.get("geometry_type"),
            polygon_points: r.get("polygon_points"),
            triggers: r.get("triggers"),
            notify: r.get("notify"),
            created_at: r.get("created_at"),
            user_id: r.get("user_id"),
            is_personal: r.get("is_personal"),
            encrypted_geometry: r.get("encrypted_geometry"),
        })
        .collect())
}

pub async fn list_personal_places(pool: &DbPool, user_id: &str) -> Result<Vec<Place>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, group_id, name, lat, lon, radius, geometry_type, polygon_points, triggers, notify, created_at, user_id, is_personal, encrypted_geometry \
         FROM places WHERE user_id = ? AND is_personal = TRUE",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| Place {
            id: r.get("id"),
            group_id: r.get("group_id"),
            name: r.get("name"),
            lat: r.get("lat"),
            lon: r.get("lon"),
            radius: r.get("radius"),
            geometry_type: r.get("geometry_type"),
            polygon_points: r.get("polygon_points"),
            triggers: r.get("triggers"),
            notify: r.get("notify"),
            created_at: r.get("created_at"),
            user_id: r.get("user_id"),
            is_personal: r.get("is_personal"),
            encrypted_geometry: r.get("encrypted_geometry"),
        })
        .collect())
}

pub async fn update_place(
    pool: &DbPool,
    id: &str,
    name: Option<&str>,
    lat: Option<f64>,
    lon: Option<f64>,
    radius: Option<f64>,
) -> Result<(), sqlx::Error> {
    if let Some(n) = name {
        sqlx::query("UPDATE places SET name = ? WHERE id = ?")
            .bind(n).bind(id).execute(pool).await?;
    }
    if let Some(la) = lat {
        sqlx::query("UPDATE places SET lat = ? WHERE id = ?")
            .bind(la).bind(id).execute(pool).await?;
    }
    if let Some(lo) = lon {
        sqlx::query("UPDATE places SET lon = ? WHERE id = ?")
            .bind(lo).bind(id).execute(pool).await?;
    }
    if let Some(r) = radius {
        sqlx::query("UPDATE places SET radius = ? WHERE id = ?")
            .bind(r).bind(id).execute(pool).await?;
    }
    Ok(())
}

pub async fn delete_place(pool: &DbPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM places WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}
