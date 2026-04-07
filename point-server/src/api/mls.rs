use axum::extract::{Path, State};
use axum::Json;
use base64::Engine;
use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

// ==================== Upload Key Packages ====================

#[derive(Debug, Deserialize)]
pub struct UploadKeysBody {
    pub key_packages: Vec<String>, // base64-encoded
}

#[derive(Debug, Serialize)]
pub struct UploadKeysResponse {
    pub stored: usize,
}

/// POST /api/mls/keys — Upload key packages for the authenticated user.
pub async fn upload_keys(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<UploadKeysBody>,
) -> Result<Json<UploadKeysResponse>, AppError> {
    if body.key_packages.is_empty() {
        return Err(AppError::BadRequest("key_packages must not be empty".into()));
    }

    let engine = base64::engine::general_purpose::STANDARD;
    let mut stored = 0;

    for kp_b64 in &body.key_packages {
        let bytes = engine
            .decode(kp_b64)
            .map_err(|e| AppError::BadRequest(format!("invalid base64: {e}")))?;

        let id = uuid::Uuid::new_v4().to_string();
        db::mls::store_key_package(&state.pool, &id, &user.user_id, &bytes).await?;
        stored += 1;
    }

    Ok(Json(UploadKeysResponse { stored }))
}

// ==================== Get Key Packages ====================

#[derive(Debug, Serialize)]
pub struct KeyPackageResponse {
    pub id: String,
    pub key_package: String, // base64
}

/// GET /api/mls/keys/{user_id} — Fetch key packages for a user.
/// Auth required: caller must share a group or have a direct share with the target.
pub async fn get_keys(
    State(state): State<AppState>,
    user: AuthUser,
    Path(target_user_id): Path<String>,
) -> Result<Json<Vec<KeyPackageResponse>>, AppError> {
    // Allow fetching own keys
    if target_user_id != user.user_id {
        // Check for share or group relationship
        let has_share = db::shares::are_sharing(&state.pool, &user.user_id, &target_user_id)
            .await
            .unwrap_or(false);

        let has_group = if !has_share {
            has_shared_group(&state.pool, &user.user_id, &target_user_id).await
        } else {
            true
        };

        if !has_share && !has_group {
            return Err(AppError::Forbidden);
        }
    }

    let packages = db::mls::get_key_packages(&state.pool, &target_user_id).await?;
    let engine = base64::engine::general_purpose::STANDARD;

    Ok(Json(
        packages
            .into_iter()
            .map(|kp| KeyPackageResponse {
                id: kp.id,
                key_package: engine.encode(&kp.key_package),
            })
            .collect(),
    ))
}

/// Check if two users share at least one group.
async fn has_shared_group(pool: &db::DbPool, user_a: &str, user_b: &str) -> bool {
    let groups_a = match db::groups::list_user_groups(pool, user_a).await {
        Ok(g) => g,
        Err(_) => return false,
    };

    for group in &groups_a {
        match db::groups::get_members(pool, &group.id).await {
            Ok(members) => {
                if members.iter().any(|m| m.user_id == user_b) {
                    return true;
                }
            }
            Err(_) => continue,
        }
    }

    false
}

// ==================== Send Welcome ====================

#[derive(Debug, Deserialize)]
pub struct SendWelcomeBody {
    pub recipient_id: String,
    pub group_id: String,
    pub payload: String, // base64
}

/// POST /api/mls/welcome — Send a Welcome message to a specific recipient.
pub async fn send_welcome(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendWelcomeBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let engine = base64::engine::general_purpose::STANDARD;
    let payload_bytes = engine
        .decode(&body.payload)
        .map_err(|e| AppError::BadRequest(format!("invalid base64 payload: {e}")))?;

    let id = uuid::Uuid::new_v4().to_string();
    db::mls::store_mls_message(
        &state.pool,
        &id,
        &body.recipient_id,
        "welcome",
        &body.group_id,
        &user.user_id,
        &payload_bytes,
    )
    .await?;

    // Relay via WebSocket if recipient is online
    let ws_msg = serde_json::json!({
        "type": "mls.message",
        "message_type": "welcome",
        "group_id": body.group_id,
        "sender_id": user.user_id,
        "payload": body.payload,
    });
    state
        .hub
        .send_to_user(&body.recipient_id, &ws_msg.to_string().into_bytes());

    // FCM wake-up push if offline
    if let Some(ref fcm) = state.fcm {
        if !state.hub.is_online(&body.recipient_id) {
            let fcm = fcm.clone();
            let pool = state.pool.clone();
            let recipient = body.recipient_id.clone();
            tokio::spawn(async move {
                fcm.send_wake_push(&pool, &recipient, "mls.welcome").await;
            });
        }
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

// ==================== Send Commit ====================

#[derive(Debug, Deserialize)]
pub struct SendCommitBody {
    pub group_id: String,
    pub payload: String, // base64
}

/// POST /api/mls/commit — Send a Commit to all group members.
pub async fn send_commit(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendCommitBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let engine = base64::engine::general_purpose::STANDARD;
    let payload_bytes = engine
        .decode(&body.payload)
        .map_err(|e| AppError::BadRequest(format!("invalid base64 payload: {e}")))?;

    // Look up group members
    let members = db::groups::get_members(&state.pool, &body.group_id)
        .await
        .map_err(|_| AppError::NotFound("group not found".into()))?;

    let ws_msg = serde_json::json!({
        "type": "mls.message",
        "message_type": "commit",
        "group_id": body.group_id,
        "sender_id": user.user_id,
        "payload": body.payload,
    });
    let ws_data = ws_msg.to_string().into_bytes();

    for member in &members {
        if member.user_id == user.user_id {
            continue; // skip sender
        }

        let id = uuid::Uuid::new_v4().to_string();
        if let Err(e) = db::mls::store_mls_message(
            &state.pool,
            &id,
            &member.user_id,
            "commit",
            &body.group_id,
            &user.user_id,
            &payload_bytes,
        )
        .await
        {
            tracing::error!(error = %e, recipient = %member.user_id, "failed to store mls commit");
            continue;
        }

        // Relay via WebSocket if online
        state.hub.send_to_user(&member.user_id, &ws_data);

        // FCM wake-up push if offline
        if let Some(ref fcm) = state.fcm {
            if !state.hub.is_online(&member.user_id) {
                let fcm = fcm.clone();
                let pool = state.pool.clone();
                let uid = member.user_id.clone();
                tokio::spawn(async move {
                    fcm.send_wake_push(&pool, &uid, "mls.commit").await;
                });
            }
        }
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

// ==================== Get Pending Messages ====================

#[derive(Debug, Serialize)]
pub struct MlsMessageResponse {
    pub id: String,
    pub message_type: String,
    pub group_id: String,
    pub sender_id: String,
    pub payload: String, // base64
    pub created_at: String,
}

/// GET /api/mls/messages — Fetch pending MLS messages for the authenticated user.
pub async fn get_messages(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<MlsMessageResponse>>, AppError> {
    let messages = db::mls::get_pending_messages(&state.pool, &user.user_id).await?;
    let engine = base64::engine::general_purpose::STANDARD;

    Ok(Json(
        messages
            .into_iter()
            .map(|m| MlsMessageResponse {
                id: m.id,
                message_type: m.message_type,
                group_id: m.group_id,
                sender_id: m.sender_id,
                payload: engine.encode(&m.payload),
                created_at: m.created_at,
            })
            .collect(),
    ))
}

// ==================== Acknowledge Message ====================

/// POST /api/mls/messages/{id}/ack — Mark a message as processed.
pub async fn ack_message(
    State(state): State<AppState>,
    user: AuthUser,
    Path(message_id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Verify the message belongs to this user before marking processed
    let pending = db::mls::get_pending_messages(&state.pool, &user.user_id).await?;
    if !pending.iter().any(|m| m.id == message_id) {
        return Err(AppError::NotFound("message not found".into()));
    }

    db::mls::mark_message_processed(&state.pool, &message_id).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}
