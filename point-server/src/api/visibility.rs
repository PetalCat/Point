use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Serialize)]
pub struct ModeResponse {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub group_ids: Vec<String>,
    pub user_ids: Vec<String>,
    pub active: bool,
}

fn to_response(m: db::visibility::VisibilityMode, active_id: &Option<String>) -> ModeResponse {
    let active = active_id.as_deref() == Some(m.id.as_str());
    ModeResponse {
        id: m.id,
        name: m.name,
        icon: m.icon,
        group_ids: m.group_ids,
        user_ids: m.user_ids,
        active,
    }
}

#[derive(Debug, Serialize)]
pub struct ModesListResponse {
    pub modes: Vec<ModeResponse>,
    pub active_mode_id: Option<String>,
}

/// GET /api/visibility/modes — list the caller's saved audiences.
pub async fn list_modes(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ModesListResponse>, AppError> {
    let active = db::visibility::get_active_mode(&state.pool, &user.user_id).await?;
    let modes = db::visibility::list_modes(&state.pool, &user.user_id).await?;
    Ok(Json(ModesListResponse {
        modes: modes.into_iter().map(|m| to_response(m, &active)).collect(),
        active_mode_id: active,
    }))
}

#[derive(Debug, Deserialize)]
pub struct ModeBody {
    pub name: String,
    #[serde(default = "default_icon")]
    pub icon: String,
    #[serde(default)]
    pub group_ids: Vec<String>,
    #[serde(default)]
    pub user_ids: Vec<String>,
}

fn default_icon() -> String {
    "users".to_string()
}

/// POST /api/visibility/modes — create a saved audience.
pub async fn create_mode(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ModeBody>,
) -> Result<Json<ModeResponse>, AppError> {
    if body.name.trim().is_empty() || body.name.len() > 64 {
        return Err(AppError::BadRequest("name must be 1-64 characters".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();
    let mode = db::visibility::create_mode(
        &state.pool,
        &id,
        &user.user_id,
        body.name.trim(),
        &body.icon,
        &body.group_ids,
        &body.user_ids,
    )
    .await?;
    let active = db::visibility::get_active_mode(&state.pool, &user.user_id).await?;
    Ok(Json(to_response(mode, &active)))
}

/// PUT /api/visibility/modes/{id} — edit a saved audience.
pub async fn update_mode(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ModeBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let existing = db::visibility::get_mode(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("mode not found".into()))?;
    if existing.user_id != user.user_id {
        return Err(AppError::Forbidden);
    }
    if body.name.trim().is_empty() || body.name.len() > 64 {
        return Err(AppError::BadRequest("name must be 1-64 characters".into()));
    }
    db::visibility::update_mode(
        &state.pool,
        &id,
        &user.user_id,
        body.name.trim(),
        &body.icon,
        &body.group_ids,
        &body.user_ids,
    )
    .await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// DELETE /api/visibility/modes/{id}
pub async fn delete_mode(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::visibility::delete_mode(&state.pool, &id, &user.user_id).await?;
    // Clear active pointer if it referenced the deleted mode.
    if db::visibility::get_active_mode(&state.pool, &user.user_id).await? == Some(id.clone()) {
        db::visibility::set_active_mode(&state.pool, &user.user_id, None).await?;
    }
    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Debug, Deserialize)]
pub struct ActiveModeBody {
    /// Mode ID to mark active, or null for Custom.
    pub mode_id: Option<String>,
}

/// PUT /api/visibility/active — record which mode is currently applied.
/// The client performs the actual share toggles; this just persists the pointer
/// so the active mode survives restarts and syncs across devices.
pub async fn set_active(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ActiveModeBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    if let Some(ref mid) = body.mode_id {
        let m = db::visibility::get_mode(&state.pool, mid)
            .await?
            .ok_or(AppError::NotFound("mode not found".into()))?;
        if m.user_id != user.user_id {
            return Err(AppError::Forbidden);
        }
    }
    db::visibility::set_active_mode(&state.pool, &user.user_id, body.mode_id.as_deref()).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
