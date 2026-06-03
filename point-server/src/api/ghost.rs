use axum::extract::State;
use axum::Json;
use serde::Deserialize;

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct SetGhostBody {
    pub ghosted: bool,
}

/// PUT /api/ghost — Set the coarse server-side ghost flag.
/// When active, the server drops all location broadcasts from this user.
pub async fn set_ghost(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SetGhostBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::users::set_ghost_flag(&state.pool, &user.user_id, body.ghosted).await?;

    tracing::info!(user = %user.user_id, ghosted = body.ghosted, "ghost flag updated");

    Ok(Json(serde_json::json!({ "ok": true, "ghosted": body.ghosted })))
}

#[derive(Debug, Deserialize)]
pub struct SetGhostTargetsBody {
    /// Group IDs, user IDs, or '__all__' that the caller is currently ghosting.
    pub targets: Vec<String>,
}

/// PUT /api/ghost/targets — Replace the caller's per-target ghost set (P1-09).
/// The server enforces these in the relay path so a client bug or missed
/// transition can't leak location to a ghosted audience.
pub async fn set_ghost_targets(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SetGhostTargetsBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::users::set_ghost_targets(&state.pool, &user.user_id, &body.targets).await?;
    tracing::info!(user = %user.user_id, count = body.targets.len(), "ghost targets updated");
    Ok(Json(serde_json::json!({ "ok": true, "count": body.targets.len() })))
}
