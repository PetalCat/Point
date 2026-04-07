use axum::extract::{Path, State};
use axum::Json;
use rand::distributions::Alphanumeric;
use rand::Rng;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct CreateInviteRequest {
    pub max_uses: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct InviteResponse {
    pub id: String,
    pub code: String,
    pub max_uses: i64,
    pub uses: i64,
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateInviteRequest>,
) -> Result<Json<InviteResponse>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let id = uuid::Uuid::new_v4().to_string();
    let code: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(8)
        .map(char::from)
        .collect();
    let max_uses = body.max_uses.unwrap_or(1);

    db::invites::create_invite(&state.pool, &id, &code, &user.user_id, max_uses as i32).await?;

    Ok(Json(InviteResponse {
        id,
        code,
        max_uses,
        uses: 0,
    }))
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<InviteResponse>>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let invites = db::invites::list_invites(&state.pool, &user.user_id).await?;

    Ok(Json(
        invites
            .into_iter()
            .map(|i| InviteResponse {
                id: i.id,
                code: i.code,
                max_uses: i.max_uses,
                uses: i.uses,
            })
            .collect(),
    ))
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    db::invites::delete_invite(&state.pool, &id)
        .await
        .map_err(|_| AppError::NotFound("invite not found".into()))?;

    Ok(Json(serde_json::json!({ "ok": true })))
}
