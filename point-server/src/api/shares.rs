use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct SendRequestBody {
    pub to_user_id: String,
}

#[derive(Debug, Serialize)]
pub struct ShareRequestResponse {
    pub id: String,
    pub from_user_id: String,
    pub to_user_id: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Serialize)]
pub struct ShareResponse {
    pub user_id: String,
    pub created_at: String,
}

/// POST /api/shares/request — Send a share request to another user.
pub async fn send_request(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendRequestBody>,
) -> Result<Json<ShareRequestResponse>, AppError> {
    if body.to_user_id == user.user_id {
        return Err(AppError::BadRequest("cannot send share request to yourself".into()));
    }

    // Silently succeed even if target doesn't exist — prevents account enumeration
    let target = db::users::get_user_by_id(&state.pool, &body.to_user_id).await?;
    if target.is_none() {
        // Return success to prevent enumeration — request is silently dropped
        return Ok(Json(ShareRequestResponse {
            id: uuid::Uuid::new_v4().to_string(),
            from_user_id: user.user_id.clone(),
            to_user_id: body.to_user_id.clone(),
            status: "pending".into(),
            created_at: chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
        }));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let request = db::shares::create_request(&state.pool, &id, &user.user_id, &body.to_user_id)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(ref db_err) = e {
                if db_err.message().contains("UNIQUE") {
                    return AppError::Conflict("share request already exists".into());
                }
            }
            AppError::Internal(e.to_string())
        })?;

    // Push WS notification to the target user
    let notify = serde_json::json!({
        "type": "share.request",
        "from_user_id": user.user_id,
        "request_id": request.id,
    });
    state.hub.send_to_user(&body.to_user_id, serde_json::to_vec(&notify).unwrap_or_default().as_slice());

    // FCM wake-up push (no content — privacy safe)
    if let Some(ref fcm) = state.fcm {
        let pool = state.pool.clone();
        let to = body.to_user_id.clone();
        let fcm = fcm.clone();
        tokio::spawn(async move { fcm.send_wake_push(&pool, &to, "share.request").await; });
    }

    Ok(Json(ShareRequestResponse {
        id: request.id,
        from_user_id: request.from_user_id,
        to_user_id: request.to_user_id,
        status: request.status,
        created_at: request.created_at,
    }))
}

/// GET /api/shares — List active shares (accepted connections).
pub async fn list_shares(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ShareResponse>>, AppError> {
    let shares = db::shares::get_shares_for_user(&state.pool, &user.user_id).await?;

    Ok(Json(
        shares
            .into_iter()
            .map(|s| ShareResponse {
                user_id: s.other_user_id,
                created_at: s.created_at,
            })
            .collect(),
    ))
}

/// GET /api/shares/requests — List incoming pending requests.
pub async fn list_incoming(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ShareRequestResponse>>, AppError> {
    let requests =
        db::shares::get_pending_requests_for_user(&state.pool, &user.user_id).await?;

    Ok(Json(
        requests
            .into_iter()
            .map(|r| ShareRequestResponse {
                id: r.id,
                from_user_id: r.from_user_id,
                to_user_id: r.to_user_id,
                status: r.status,
                created_at: r.created_at,
            })
            .collect(),
    ))
}

/// GET /api/shares/requests/outgoing — List outgoing requests.
pub async fn list_outgoing(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ShareRequestResponse>>, AppError> {
    let requests = db::shares::get_outgoing_requests(&state.pool, &user.user_id).await?;

    Ok(Json(
        requests
            .into_iter()
            .map(|r| ShareRequestResponse {
                id: r.id,
                from_user_id: r.from_user_id,
                to_user_id: r.to_user_id,
                status: r.status,
                created_at: r.created_at,
            })
            .collect(),
    ))
}

/// POST /api/shares/requests/{id}/accept — Accept an incoming request.
pub async fn accept(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Get the request to find who sent it
    let requests = db::shares::get_pending_requests_for_user(&state.pool, &user.user_id).await?;
    let from_user = requests.iter().find(|r| r.id == id).map(|r| r.from_user_id.clone());

    db::shares::accept_request(&state.pool, &id, &user.user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => {
                AppError::NotFound("request not found or not addressed to you".into())
            }
            other => AppError::Internal(other.to_string()),
        })?;

    // Notify the requester that their request was accepted
    if let Some(from) = from_user {
        let notify = serde_json::json!({
            "type": "share.accepted",
            "by_user_id": user.user_id,
        });
        state.hub.send_to_user(&from, serde_json::to_vec(&notify).unwrap_or_default().as_slice());
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// POST /api/shares/requests/{id}/reject — Reject an incoming request.
pub async fn reject(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let requests = db::shares::get_pending_requests_for_user(&state.pool, &user.user_id).await?;
    let from_user = requests.iter().find(|r| r.id == id).map(|r| r.from_user_id.clone());

    db::shares::reject_request(&state.pool, &id, &user.user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => {
                AppError::NotFound("request not found or not addressed to you".into())
            }
            other => AppError::Internal(other.to_string()),
        })?;

    if let Some(from) = from_user {
        let notify = serde_json::json!({
            "type": "share.rejected",
            "by_user_id": user.user_id,
        });
        state.hub.send_to_user(&from, serde_json::to_vec(&notify).unwrap_or_default().as_slice());
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

// ==================== TEMPORARY SHARES ====================

#[derive(Debug, Deserialize)]
pub struct CreateTempShareBody {
    pub to_user_id: String,
    pub duration_minutes: i64,
    #[serde(default = "default_precision")]
    pub precision: String,
}

fn default_precision() -> String {
    "exact".to_string()
}

#[derive(Debug, Serialize)]
pub struct TempShareResponse {
    pub id: String,
    pub from_user_id: String,
    pub to_user_id: Option<String>,
    pub precision: String,
    pub expires_at: String,
    pub created_at: String,
}

/// POST /api/shares/temp — Create a temporary share.
pub async fn create_temp(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateTempShareBody>,
) -> Result<Json<TempShareResponse>, AppError> {
    if body.to_user_id == user.user_id {
        return Err(AppError::BadRequest("cannot share with yourself".into()));
    }
    if body.duration_minutes <= 0 || body.duration_minutes > 525600 {
        return Err(AppError::BadRequest("duration must be between 1 and 525600 minutes".into()));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let expires_at = chrono::Utc::now()
        + chrono::Duration::minutes(body.duration_minutes);
    let expires_str = expires_at.format("%Y-%m-%d %H:%M:%S").to_string();

    db::shares::create_temp_share(
        &state.pool,
        &id,
        &user.user_id,
        Some(&body.to_user_id),
        None,
        &body.precision,
        &expires_str,
    )
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    // Notify the recipient via WS
    let notify = serde_json::json!({
        "type": "share.temp_created",
        "from_user_id": user.user_id,
        "expires_at": expires_str,
    });
    state.hub.send_to_user(
        &body.to_user_id,
        serde_json::to_vec(&notify).unwrap_or_default().as_slice(),
    );

    Ok(Json(TempShareResponse {
        id,
        from_user_id: user.user_id,
        to_user_id: Some(body.to_user_id),
        precision: body.precision,
        expires_at: expires_str.clone(),
        created_at: chrono::Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
    }))
}

/// GET /api/shares/temp — List your active (non-expired) temp shares.
pub async fn list_temp(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<TempShareResponse>>, AppError> {
    let shares = db::shares::get_active_temp_shares(&state.pool, &user.user_id)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(
        shares
            .into_iter()
            .map(|s| TempShareResponse {
                id: s.id,
                from_user_id: s.from_user_id,
                to_user_id: s.to_user_id,
                precision: s.precision,
                expires_at: s.expires_at,
                created_at: s.created_at,
            })
            .collect(),
    ))
}

/// DELETE /api/shares/temp/{id} — Cancel a temp share early.
pub async fn delete_temp(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Verify the share belongs to the user
    let shares = db::shares::get_active_temp_shares(&state.pool, &user.user_id)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    if !shares.iter().any(|s| s.id == id) {
        return Err(AppError::NotFound("temp share not found".into()));
    }

    db::shares::delete_temp_share(&state.pool, &id)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// DELETE /api/shares/{user_id} — Remove an active share.
pub async fn remove_share(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other_user_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::shares::remove_share(&state.pool, &user.user_id, &other_user_id)
        .await
        .map_err(|e| match e {
            sqlx::Error::RowNotFound => AppError::NotFound("share not found".into()),
            other => AppError::Internal(other.to_string()),
        })?;

    Ok(Json(serde_json::json!({ "ok": true })))
}
