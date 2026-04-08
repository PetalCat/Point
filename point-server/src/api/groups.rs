use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser, auth};

#[derive(Debug, Deserialize)]
pub struct CreateGroupRequest {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct AddMemberRequest {
    pub user_id: String,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateMySettingsRequest {
    pub precision: Option<String>,
    pub sharing: Option<bool>,
    pub schedule_type: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateMemberRoleRequest {
    pub role: String,
}

#[derive(Debug, Deserialize)]
pub struct UpdateGroupSettingsRequest {
    pub name: Option<String>,
    pub members_can_invite: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct GroupResponse {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub members_can_invite: bool,
    pub members: Vec<MemberResponse>,
}

#[derive(Debug, Serialize)]
pub struct MemberResponse {
    pub user_id: String,
    pub role: String,
    pub precision: String,
    pub sharing: bool,
    pub schedule_type: String,
}

async fn build_response(pool: &db::DbPool, group: db::groups::Group) -> Result<GroupResponse, AppError> {
    let members = db::groups::get_members(pool, &group.id).await?;
    Ok(GroupResponse {
        id: group.id,
        name: group.name,
        owner_id: group.owner_id,
        members_can_invite: group.members_can_invite,
        members: members.into_iter().map(|m| MemberResponse {
            user_id: m.user_id, role: m.role, precision: m.precision,
            sharing: m.sharing, schedule_type: m.schedule_type,
        }).collect(),
    })
}

/// Require caller to be a member, return their role
async fn require_member(pool: &db::DbPool, group_id: &str, user_id: &str) -> Result<String, AppError> {
    db::groups::get_member_role(pool, group_id, user_id).await?
        .ok_or(AppError::Forbidden)
}

/// Require caller to be admin
async fn require_admin(pool: &db::DbPool, group_id: &str, user_id: &str) -> Result<(), AppError> {
    let role = require_member(pool, group_id, user_id).await?;
    if role != "admin" { return Err(AppError::Forbidden); }
    Ok(())
}

// POST /api/groups
pub async fn create(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateGroupRequest>,
) -> Result<Json<GroupResponse>, AppError> {
    if req.name.trim().is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();
    let group = db::groups::create_group(&state.pool, &id, req.name.trim(), &auth.user_id).await?;
    Ok(Json(build_response(&state.pool, group).await?))
}

// GET /api/groups
pub async fn list(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<Vec<GroupResponse>>, AppError> {
    let groups = db::groups::list_user_groups(&state.pool, &auth.user_id).await?;
    let mut out = Vec::with_capacity(groups.len());
    for g in groups { out.push(build_response(&state.pool, g).await?); }
    Ok(Json(out))
}

// GET /api/groups/:id
pub async fn get(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<GroupResponse>, AppError> {
    require_member(&state.pool, &id, &auth.user_id).await?;
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;
    Ok(Json(build_response(&state.pool, group).await?))
}

// POST /api/groups/:id/members — add member (admin only)
pub async fn add_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<AddMemberRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Check: admin, or member if group allows member invites
    let caller_role = require_member(&state.pool, &id, &auth.user_id).await?;
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    let can_invite = caller_role == "admin" || (caller_role == "member" && group.members_can_invite);
    if !can_invite { return Err(AppError::Forbidden); }

    // Verify target user exists
    db::users::get_user_by_id(&state.pool, &req.user_id).await?
        .ok_or(AppError::NotFound("user not found".into()))?;

    let role = req.role.as_deref().unwrap_or("member");
    // Only admins can add other admins
    if role == "admin" && caller_role != "admin" {
        return Err(AppError::Forbidden);
    }

    db::groups::add_member(&state.pool, &id, &req.user_id, role, "exact").await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

// DELETE /api/groups/:id/members/:member_id — remove member or leave
pub async fn remove_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((id, member_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, AppError> {
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    if member_id == auth.user_id {
        // Leaving — owner can't leave without transferring
        if group.owner_id == auth.user_id {
            return Err(AppError::BadRequest("owner must transfer ownership before leaving".into()));
        }
    } else {
        // Removing someone — must be admin, can't remove owner
        require_admin(&state.pool, &id, &auth.user_id).await?;
        if member_id == group.owner_id {
            return Err(AppError::BadRequest("cannot remove the owner".into()));
        }
    }

    db::groups::remove_member(&state.pool, &id, &member_id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

// PUT /api/groups/:id/settings — update group settings (admin only)
pub async fn update_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<UpdateGroupSettingsRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    require_admin(&state.pool, &id, &auth.user_id).await?;

    if let Some(name) = &req.name {
        if !name.trim().is_empty() {
            db::groups::rename_group(&state.pool, &id, name.trim()).await?;
        }
    }
    if let Some(mci) = req.members_can_invite {
        db::groups::update_group_settings(&state.pool, &id, mci).await?;
    }
    Ok(Json(serde_json::json!({ "ok": true })))
}

// PUT /api/groups/:id/me — update YOUR settings for this group
pub async fn update_my_settings(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<UpdateMySettingsRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    require_member(&state.pool, &id, &auth.user_id).await?;

    db::groups::update_my_settings(
        &state.pool, &id, &auth.user_id,
        req.precision.as_deref(),
        req.sharing,
        req.schedule_type.as_deref(),
    ).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

// PUT /api/groups/:id/members/:member_id/role — change someone's role (admin only)
pub async fn update_member_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((id, member_id)): Path<(String, String)>,
    Json(req): Json<UpdateMemberRoleRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    require_admin(&state.pool, &id, &auth.user_id).await?;

    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    // Can't change owner's role
    if member_id == group.owner_id {
        return Err(AppError::BadRequest("cannot change owner's role".into()));
    }

    db::groups::update_member_role(&state.pool, &id, &member_id, &req.role).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

// POST /api/groups/:id/invite — create group invite
pub async fn create_invite(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let caller_role = require_member(&state.pool, &id, &auth.user_id).await?;
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    let can_invite = caller_role == "admin" || (caller_role == "member" && group.members_can_invite);
    if !can_invite { return Err(AppError::Forbidden); }

    let invite_id = uuid::Uuid::new_v4().to_string();
    let code: String = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..8).map(|_| {
            let idx = rng.gen_range(0..36);
            if idx < 10 { (b'0' + idx) as char } else { (b'a' + idx - 10) as char }
        }).collect()
    };

    let invite = db::group_invites::create_invite(&state.pool, &invite_id, &id, &code, &auth.user_id, 0).await?;
    Ok(Json(serde_json::json!({
        "id": invite.id,
        "code": invite.code,
        "group_id": invite.group_id,
        "url": format!("point://join?code={}", invite.code),
    })))
}

// POST /api/groups/join/:code — join a group via invite code
pub async fn join_by_code(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(code): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Rate limit join attempts: 5 per minute per user
    auth::check_auth_rate_limit(&format!("join:{}", auth.user_id))?;

    let invite = db::group_invites::use_invite(&state.pool, &code).await
        .map_err(|_| AppError::NotFound("invalid or expired invite code".into()))?;

    // Check if already a member
    let existing = db::groups::get_member_role(&state.pool, &invite.group_id, &auth.user_id).await?;
    if existing.is_some() {
        return Err(AppError::Conflict("already a member of this group".into()));
    }

    db::groups::add_member(&state.pool, &invite.group_id, &auth.user_id, "member", "exact").await?;
    Ok(Json(serde_json::json!({ "ok": true, "group_id": invite.group_id })))
}

// DELETE /api/groups/:id — delete group (owner only)
pub async fn delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    if group.owner_id != auth.user_id {
        return Err(AppError::Forbidden);
    }

    db::groups::delete_group(&state.pool, &id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
