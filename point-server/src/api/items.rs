use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct CreateItemRequest {
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub bridge_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ShareRequest {
    pub target_type: String,
    pub target_id: String,
    pub precision: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UnshareRequest {
    pub target_type: String,
    pub target_id: String,
}

#[derive(Debug, Serialize)]
pub struct ItemResponse {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub shares: Vec<ShareResponse>,
}

#[derive(Debug, Serialize)]
pub struct ShareResponse {
    pub target_type: String,
    pub target_id: String,
    pub precision: String,
}

async fn build_item_response(
    pool: &db::DbPool,
    item: db::items::Item,
) -> Result<ItemResponse, AppError> {
    let shares = db::items::get_item_shares(pool, &item.id).await?;
    Ok(ItemResponse {
        id: item.id,
        owner_id: item.owner_id,
        name: item.name,
        tracker_type: item.tracker_type,
        source_id: item.source_id,
        shares: shares
            .into_iter()
            .map(|s| ShareResponse {
                target_type: s.target_type,
                target_id: s.target_id,
                precision: s.precision,
            })
            .collect(),
    })
}

pub async fn create(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateItemRequest>,
) -> Result<Json<ItemResponse>, AppError> {
    if req.name.is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let item = db::items::create_item(
        &state.pool,
        &id,
        &auth.user_id,
        &req.name,
        &req.tracker_type,
        req.source_id.as_deref(),
        req.bridge_id.as_deref(),
    )
    .await?;

    let response = build_item_response(&state.pool, item).await?;
    Ok(Json(response))
}

pub async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<ItemResponse>>, AppError> {
    let items = db::items::list_user_items(&state.pool, &auth.user_id).await?;
    let mut responses = Vec::with_capacity(items.len());
    for item in items {
        responses.push(build_item_response(&state.pool, item).await?);
    }
    Ok(Json(responses))
}

pub async fn share(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<ShareRequest>,
) -> Result<Json<ShareResponse>, AppError> {
    let item = db::items::get_item(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    if req.target_type != "user" && req.target_type != "group" {
        return Err(AppError::BadRequest(
            "target_type must be 'user' or 'group'".into(),
        ));
    }

    let precision = req.precision.as_deref().unwrap_or("exact");

    db::items::share_item(&state.pool, &id, &req.target_type, &req.target_id, precision).await?;

    Ok(Json(ShareResponse {
        target_type: req.target_type,
        target_id: req.target_id,
        precision: precision.to_string(),
    }))
}

pub async fn unshare(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<UnshareRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let item = db::items::get_item(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    db::items::unshare_item(&state.pool, &id, &req.target_type, &req.target_id).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let item = db::items::get_item(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    db::items::delete_item(&state.pool, &id).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}
