use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

// -- Request types --

#[derive(Debug, Deserialize)]
pub struct CreateEntityRequest {
    pub entity_type: String,
    pub display_name: String,
    pub bridge_type: String,
    pub source_id: Option<String>,
    pub tracker_type: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DiscoverEntityRequest {
    pub bridge_id: String,
    pub entity_type: String,
    pub display_name: String,
    pub bridge_type: String,
    pub source_id: Option<String>,
    pub tracker_type: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ShareEntityRequest {
    pub target_type: String,
    pub target_id: String,
    pub precision: Option<String>,
}

// -- Response types --

#[derive(Debug, Serialize)]
pub struct EntityResponse {
    pub id: String,
    pub address: String,
    pub entity_type: String,
    pub display_name: String,
    pub bridge_owner_id: String,
    pub bridge_type: String,
    pub bridge_id: Option<String>,
    pub source_id: Option<String>,
    pub tracker_type: Option<String>,
    pub capabilities: String,
    pub last_seen: Option<String>,
    pub created_at: String,
}

impl From<db::bridged_entities::BridgedEntity> for EntityResponse {
    fn from(e: db::bridged_entities::BridgedEntity) -> Self {
        EntityResponse {
            id: e.id,
            address: e.address,
            entity_type: e.entity_type,
            display_name: e.display_name,
            bridge_owner_id: e.bridge_owner_id,
            bridge_type: e.bridge_type,
            bridge_id: e.bridge_id,
            source_id: e.source_id,
            tracker_type: e.tracker_type,
            capabilities: e.capabilities,
            last_seen: e.last_seen,
            created_at: e.created_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct ShareResponse {
    pub target_type: String,
    pub target_id: String,
    pub precision: String,
}

// -- Bridge Registry (public) --

pub async fn list_registry(
    State(state): State<AppState>,
) -> Result<Json<Vec<db::bridge_registry::BridgeType>>, AppError> {
    let types = db::bridge_registry::list_bridge_types(&state.pool).await?;
    Ok(Json(types))
}

// -- Entity Management (auth required) --

pub async fn create_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateEntityRequest>,
) -> Result<Json<EntityResponse>, AppError> {
    if req.display_name.is_empty() {
        return Err(AppError::BadRequest("display_name is required".into()));
    }
    if req.entity_type != "person" && req.entity_type != "item" {
        return Err(AppError::BadRequest(
            "entity_type must be 'person' or 'item'".into(),
        ));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let address = db::bridged_entities::generate_address(&id, &req.bridge_type, &state.config.domain);

    let entity = db::bridged_entities::create_entity(
        &state.pool,
        &id,
        &address,
        &req.entity_type,
        &req.display_name,
        &auth.user_id,
        &req.bridge_type,
        req.source_id.as_deref(),
        req.tracker_type.as_deref(),
    )
    .await?;

    Ok(Json(entity.into()))
}

pub async fn list_entities(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<EntityResponse>>, AppError> {
    let entities = db::bridged_entities::list_entities_for_owner(&state.pool, &auth.user_id).await?;
    Ok(Json(entities.into_iter().map(Into::into).collect()))
}

pub async fn get_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<EntityResponse>, AppError> {
    let entity = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    if entity.bridge_owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    Ok(Json(entity.into()))
}

pub async fn delete_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let entity = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    if entity.bridge_owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    db::bridged_entities::delete_entity(&state.pool, &id).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

// -- Entity Discovery (from bridge) --

pub async fn discover_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<DiscoverEntityRequest>,
) -> Result<Json<EntityResponse>, AppError> {
    if req.display_name.is_empty() {
        return Err(AppError::BadRequest("display_name is required".into()));
    }
    if req.entity_type != "person" && req.entity_type != "item" {
        return Err(AppError::BadRequest(
            "entity_type must be 'person' or 'item'".into(),
        ));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let address = db::bridged_entities::generate_address(&id, &req.bridge_type, &state.config.domain);

    let entity = db::bridged_entities::create_entity(
        &state.pool,
        &id,
        &address,
        &req.entity_type,
        &req.display_name,
        &auth.user_id,
        &req.bridge_type,
        req.source_id.as_deref(),
        req.tracker_type.as_deref(),
    )
    .await?;

    Ok(Json(entity.into()))
}

pub async fn confirm_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<EntityResponse>, AppError> {
    let entity = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    if entity.bridge_owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    db::bridged_entities::confirm_entity(&state.pool, &id, entity.bridge_id.as_deref()).await?;

    let updated = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    Ok(Json(updated.into()))
}

// -- Sharing (items only, enforced) --

pub async fn share_entity(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<ShareEntityRequest>,
) -> Result<Json<ShareResponse>, AppError> {
    let entity = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    if entity.bridge_owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    // Anti-surveillance enforcement: bridged people are NOT shareable
    if entity.entity_type == "person" {
        return Err(AppError::Forbidden);
    }

    if req.target_type != "user" && req.target_type != "group" {
        return Err(AppError::BadRequest(
            "target_type must be 'user' or 'group'".into(),
        ));
    }

    let precision = req.precision.as_deref().unwrap_or("exact");

    // Reuse the item_shares table for bridged entity sharing
    db::items::share_item(&state.pool, &id, &req.target_type, &req.target_id, precision).await?;

    Ok(Json(ShareResponse {
        target_type: req.target_type,
        target_id: req.target_id,
        precision: precision.to_string(),
    }))
}

pub async fn list_entity_shares(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<Vec<ShareResponse>>, AppError> {
    let entity = db::bridged_entities::get_entity(&state.pool, &id)
        .await?
        .ok_or(AppError::NotFound("entity not found".into()))?;

    if entity.bridge_owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    let shares = db::items::get_item_shares(&state.pool, &id).await?;
    Ok(Json(
        shares
            .into_iter()
            .map(|s| ShareResponse {
                target_type: s.target_type,
                target_id: s.target_id,
                precision: s.precision,
            })
            .collect(),
    ))
}
