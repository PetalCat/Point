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
