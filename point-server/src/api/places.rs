use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct CreatePlaceRequest {
    pub name: String,
    #[serde(default = "default_geometry_type")]
    pub geometry_type: String,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub radius: Option<f64>,
    pub polygon_points: Option<Vec<LatLon>>,
}

fn default_geometry_type() -> String {
    "circle".to_string()
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct LatLon {
    pub lat: f64,
    pub lon: f64,
}

#[derive(Debug, Serialize)]
pub struct PlaceResponse {
    pub id: String,
    pub group_id: String,
    pub name: String,
    pub geometry_type: String,
    pub lat: f64,
    pub lon: f64,
    pub radius: f64,
    pub polygon_points: Option<serde_json::Value>,
    pub triggers: Vec<String>,
    pub created_at: String,
    pub user_id: Option<String>,
    pub is_personal: bool,
}

fn place_to_response(p: db::places::Place) -> PlaceResponse {
    let triggers: Vec<String> = serde_json::from_str(&p.triggers).unwrap_or_default();
    let polygon_points: Option<serde_json::Value> = p
        .polygon_points
        .as_deref()
        .and_then(|s| serde_json::from_str(s).ok());
    PlaceResponse {
        id: p.id,
        group_id: p.group_id,
        name: p.name,
        geometry_type: p.geometry_type,
        lat: p.lat,
        lon: p.lon,
        radius: p.radius,
        polygon_points,
        triggers,
        created_at: p.created_at,
        user_id: p.user_id,
        is_personal: p.is_personal,
    }
}

/// POST /api/groups/{group_id}/places
pub async fn create(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(group_id): Path<String>,
    Json(req): Json<CreatePlaceRequest>,
) -> Result<Json<PlaceResponse>, AppError> {
    // Must be a member of the group
    db::groups::get_member_role(&state.pool, &group_id, &auth.user_id)
        .await?
        .ok_or(AppError::Forbidden)?;

    if req.name.trim().is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let triggers = r#"["enter","exit"]"#;
    let geometry_type = req.geometry_type.as_str();

    // Validate based on geometry type
    match geometry_type {
        "circle" => {
            if req.lat.is_none() || req.lon.is_none() {
                return Err(AppError::BadRequest("circle requires lat and lon".into()));
            }
        }
        "polygon" => {
            match &req.polygon_points {
                Some(pts) if pts.len() >= 3 => {}
                _ => {
                    return Err(AppError::BadRequest(
                        "polygon requires at least 3 points".into(),
                    ));
                }
            }
        }
        _ => {
            return Err(AppError::BadRequest(
                "geometry_type must be 'circle' or 'polygon'".into(),
            ));
        }
    }

    let lat = req.lat.unwrap_or(0.0);
    let lon = req.lon.unwrap_or(0.0);
    let radius = req.radius.unwrap_or(100.0);
    let polygon_json = req
        .polygon_points
        .as_ref()
        .map(|pts| serde_json::to_string(pts).unwrap());

    let place = db::places::create_place(
        &state.pool,
        &id,
        &group_id,
        req.name.trim(),
        lat,
        lon,
        radius,
        geometry_type,
        polygon_json.as_deref(),
        triggers,
        None,
        false,
    )
    .await?;

    Ok(Json(place_to_response(place)))
}

/// GET /api/groups/{group_id}/places
pub async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(group_id): Path<String>,
) -> Result<Json<Vec<PlaceResponse>>, AppError> {
    // Must be a member of the group
    db::groups::get_member_role(&state.pool, &group_id, &auth.user_id)
        .await?
        .ok_or(AppError::Forbidden)?;

    let places = db::places::list_places_for_group(&state.pool, &group_id).await?;
    Ok(Json(places.into_iter().map(place_to_response).collect()))
}

/// DELETE /api/places/{id}
pub async fn delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let place = db::places::get_place(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("place not found".into()))?;

    // Personal places can be deleted by their owner
    if place.is_personal {
        if place.user_id.as_deref() != Some(&auth.user_id) {
            return Err(AppError::Forbidden);
        }
    } else {
        // Must be admin of the group
        let role = db::groups::get_member_role(&state.pool, &place.group_id, &auth.user_id)
            .await?
            .ok_or(AppError::Forbidden)?;

        if role != "admin" {
            return Err(AppError::Forbidden);
        }
    }

    db::places::delete_place(&state.pool, &id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// POST /api/places — create a personal place
pub async fn create_personal(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreatePlaceRequest>,
) -> Result<Json<PlaceResponse>, AppError> {
    if req.name.trim().is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let triggers = r#"["enter","exit"]"#;
    let geometry_type = req.geometry_type.as_str();

    match geometry_type {
        "circle" => {
            if req.lat.is_none() || req.lon.is_none() {
                return Err(AppError::BadRequest("circle requires lat and lon".into()));
            }
        }
        "polygon" => {
            match &req.polygon_points {
                Some(pts) if pts.len() >= 3 => {}
                _ => {
                    return Err(AppError::BadRequest(
                        "polygon requires at least 3 points".into(),
                    ));
                }
            }
        }
        _ => {
            return Err(AppError::BadRequest(
                "geometry_type must be 'circle' or 'polygon'".into(),
            ));
        }
    }

    let lat = req.lat.unwrap_or(0.0);
    let lon = req.lon.unwrap_or(0.0);
    let radius = req.radius.unwrap_or(100.0);
    let polygon_json = req
        .polygon_points
        .as_ref()
        .map(|pts| serde_json::to_string(pts).unwrap());

    let place = db::places::create_place(
        &state.pool,
        &id,
        "",  // empty group_id for personal places
        req.name.trim(),
        lat,
        lon,
        radius,
        geometry_type,
        polygon_json.as_deref(),
        triggers,
        Some(&auth.user_id),
        true,
    )
    .await?;

    Ok(Json(place_to_response(place)))
}

/// GET /api/places/personal — list personal places for the authenticated user
pub async fn list_personal(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<PlaceResponse>>, AppError> {
    let places = db::places::list_personal_places(&state.pool, &auth.user_id).await?;
    Ok(Json(places.into_iter().map(place_to_response).collect()))
}
