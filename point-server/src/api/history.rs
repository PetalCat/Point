use axum::extract::{Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    pub since: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct HistoryPointResponse {
    pub id: String,
    pub user_id: String,
    pub encrypted_blob: String,
    pub source_type: String,
    pub timestamp: i64,
}

/// GET /api/history/{user_id} — Get history points for a user.
/// Requester must have an active share with the target user, or be in the same group.
pub async fn get_history(
    State(state): State<AppState>,
    user: AuthUser,
    Path(target_user_id): Path<String>,
    Query(query): Query<HistoryQuery>,
) -> Result<Json<Vec<HistoryPointResponse>>, AppError> {
    // Allow users to fetch their own history, or verify sharing relationship
    if target_user_id != user.user_id {
        let has_share = db::shares::are_sharing(&state.pool, &user.user_id, &target_user_id)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;

        if !has_share {
            // Check if they share a group
            let user_groups = db::groups::list_user_groups(&state.pool, &user.user_id)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;

            let target_groups = db::groups::list_user_groups(&state.pool, &target_user_id)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;

            let shared_group = user_groups
                .iter()
                .any(|ug| target_groups.iter().any(|tg| tg.id == ug.id));

            if !shared_group {
                return Err(AppError::Forbidden);
            }
        }
    }

    let since = query.since.unwrap_or(0);
    let limit = query.limit.unwrap_or(100).min(1000);

    let points = db::history::get_history_for_user(&state.pool, &target_user_id, since, limit)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let response: Vec<HistoryPointResponse> = points
        .into_iter()
        .map(|p| HistoryPointResponse {
            id: p.id,
            user_id: p.user_id,
            encrypted_blob: String::from_utf8_lossy(&p.encrypted_blob).to_string(),
            source_type: p.source_type,
            timestamp: p.timestamp,
        })
        .collect();

    Ok(Json(response))
}

/// DELETE /api/history — Delete your own history.
pub async fn delete_history(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<serde_json::Value>, AppError> {
    let deleted = db::history::delete_history_for_user(&state.pool, &user.user_id)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({ "deleted": deleted })))
}
