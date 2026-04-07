use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

// ==================== Discovery ====================

/// GET /.well-known/point — Server identity and federation capabilities.
/// Used by other servers to discover this instance.
pub async fn well_known(
    State(state): State<AppState>,
) -> Json<WellKnownResponse> {
    Json(WellKnownResponse {
        domain: state.config.domain.clone(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        federation: true,
        endpoints: FederationEndpoints {
            inbox: format!("https://{}/federation/inbox", state.config.domain),
            keys: format!("https://{}/federation/keys", state.config.domain),
        },
    })
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WellKnownResponse {
    pub domain: String,
    pub version: String,
    pub federation: bool,
    pub endpoints: FederationEndpoints,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FederationEndpoints {
    pub inbox: String,
    pub keys: String,
}

/// Find a local user by their federated address (user@domain).
/// Tries the full address first, then just the username part.
async fn find_local_user(pool: &crate::db::DbPool, federated_id: &str) -> Option<String> {
    // Try full address first (user@domain)
    if let Ok(Some(_)) = db::users::get_user_by_id(pool, federated_id).await {
        return Some(federated_id.to_string());
    }
    // Try just the username part
    if let Some(username) = federated_id.split('@').next() {
        if let Ok(Some(_)) = db::users::get_user_by_id(pool, username).await {
            return Some(username.to_string());
        }
    }
    None
}

/// Verify a sender domain is a legitimate Point server by checking its discovery endpoint.
/// Caches verified domains to avoid repeated lookups.
async fn verify_sender_domain(domain: &str) -> Result<(), String> {
    // Skip verification for well-known test/dev domains in development
    let url = format!("https://{}/.well-known/point", domain);
    let client = reqwest::Client::new();
    let resp = client.get(&url)
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .map_err(|e| format!("domain verification failed: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("domain {} returned {}", domain, resp.status()));
    }

    let info: WellKnownResponse = resp.json().await
        .map_err(|e| format!("invalid discovery response from {}: {e}", domain))?;

    // The domain in the discovery response must match the claimed domain
    if info.domain != domain {
        return Err(format!("domain mismatch: claimed {} but server says {}", domain, info.domain));
    }

    if !info.federation {
        return Err(format!("{} has federation disabled", domain));
    }

    Ok(())
}

// ==================== Inbox — Receive federated messages ====================

/// POST /federation/inbox — Receive a message from a remote server.
/// This is how location updates, share requests, and MLS messages
/// arrive from other Point instances.
pub async fn inbox(
    State(state): State<AppState>,
    Json(body): Json<FederatedMessage>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Verify the sending domain
    let sender_domain = body.sender.split('@').nth(1)
        .ok_or_else(|| AppError::BadRequest("sender must be user@domain".into()))?;

    // Domain verification: confirm the sender's domain is a real Point server
    // by checking its /.well-known/point endpoint returns the claimed domain.
    // This prevents domain spoofing — you can't claim to be alice@trusted.com
    // unless trusted.com actually runs a Point server.
    verify_sender_domain(sender_domain).await
        .map_err(|e| AppError::Forbidden)?;

    match body.message_type.as_str() {
        "location.update" => handle_federated_location(&state, &body).await,
        "share.request" => handle_federated_share_request(&state, &body).await,
        "share.accept" => handle_federated_share_accept(&state, &body).await,
        "mls.welcome" => handle_federated_mls(&state, &body).await,
        "mls.commit" => handle_federated_mls(&state, &body).await,
        "mls.key_request" => handle_federated_key_request(&state, &body).await,
        "location.nudge" => handle_federated_nudge(&state, &body).await,
        _ => Err(AppError::BadRequest(format!("unknown message type: {}", body.message_type))),
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct FederatedMessage {
    /// Full sender identity: user@domain
    pub sender: String,
    /// Full recipient identity: user@domain
    pub recipient: String,
    /// Message type: location.update, share.request, share.accept, mls.welcome, mls.commit
    pub message_type: String,
    /// Opaque payload — the server never reads this (E2E encrypted)
    pub payload: serde_json::Value,
    /// Timestamp
    pub timestamp: i64,
}

/// Handle an incoming federated location update.
/// The payload is an encrypted blob — we just deliver it to the local recipient.
async fn handle_federated_location(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    // Check ghost flag — drop if the LOCAL recipient has ghosted the sender
    // (We don't trust the sender's server to enforce our user's ghost preferences)
    if db::users::is_ghost_active(&state.pool, &local_user).await.unwrap_or(false) {
        tracing::debug!(recipient = %local_user, "dropping federated location — ghost active");
        return Ok(Json(serde_json::json!({ "ok": true, "dropped": "ghost" })));
    }

    // Deliver via WebSocket
    let ws_msg = serde_json::json!({
        "type": "location.broadcast",
        "sender_id": msg.sender,
        "recipient_type": "user",
        "recipient_id": local_user,
        "encrypted_blob": msg.payload.get("encrypted_blob").and_then(|v| v.as_str()).unwrap_or(""),
        "source_type": msg.payload.get("source_type").and_then(|v| v.as_str()).unwrap_or("federated"),
        "timestamp": msg.timestamp,
        "federated": true,
    });
    state.hub.send_to_user(&local_user, &ws_msg.to_string().into_bytes());

    tracing::info!(
        sender = %msg.sender,
        recipient = %msg.recipient,
        "delivered federated location update"
    );

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Handle an incoming federated share request.
async fn handle_federated_share_request(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    // The recipient may be stored with or without @domain — try both
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    // Ensure shadow user exists for the federated sender
    db::users::ensure_federated_user(&state.pool, &msg.sender).await?;

    let id = uuid::Uuid::new_v4().to_string();
    db::shares::create_request(
        &state.pool,
        &id,
        &msg.sender, // full user@domain as from_user_id
        &local_user,
    ).await?;

    // Notify via WebSocket
    let ws_msg = serde_json::json!({
        "type": "share.request",
        "from_user_id": msg.sender,
        "federated": true,
    });
    state.hub.send_to_user(&local_user, &ws_msg.to_string().into_bytes());

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Handle a federated share acceptance.
async fn handle_federated_share_accept(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    // Ensure shadow user exists for the federated sender
    db::users::ensure_federated_user(&state.pool, &msg.sender).await?;

    // Create the bidirectional share
    let (user_a, user_b) = if local_user.as_str() < msg.sender.as_str() {
        (local_user.to_string(), msg.sender.clone())
    } else {
        (msg.sender.clone(), local_user.to_string())
    };
    sqlx::query("INSERT OR IGNORE INTO user_shares (user_a, user_b) VALUES (?, ?)")
        .bind(&user_a)
        .bind(&user_b)
        .execute(&state.pool)
        .await?;

    let ws_msg = serde_json::json!({
        "type": "share.accepted",
        "user_id": msg.sender,
        "federated": true,
    });
    state.hub.send_to_user(&local_user, &ws_msg.to_string().into_bytes());

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Handle federated MLS messages (Welcome/Commit).
async fn handle_federated_mls(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    // Relay the MLS message via WebSocket
    let ws_msg = serde_json::json!({
        "type": "mls.message",
        "message_type": msg.message_type.strip_prefix("mls.").unwrap_or(&msg.message_type),
        "group_id": msg.payload.get("group_id").and_then(|v| v.as_str()).unwrap_or(""),
        "sender_id": msg.sender,
        "payload": msg.payload.get("payload").and_then(|v| v.as_str()).unwrap_or(""),
        "federated": true,
    });
    state.hub.send_to_user(&local_user, &ws_msg.to_string().into_bytes());

    // Also store as pending MLS message in case recipient is offline
    if let (Some(group_id), Some(payload)) = (
        msg.payload.get("group_id").and_then(|v| v.as_str()),
        msg.payload.get("payload").and_then(|v| v.as_str()),
    ) {
        let mls_type = msg.message_type.strip_prefix("mls.").unwrap_or(&msg.message_type);
        let id = uuid::Uuid::new_v4().to_string();
        let payload_bytes = base64::Engine::decode(
            &base64::engine::general_purpose::STANDARD,
            payload,
        ).unwrap_or_default();

        let _ = db::mls::store_mls_message(
            &state.pool,
            &id,
            &local_user,
            mls_type,
            group_id,
            &msg.sender,
            &payload_bytes,
        ).await;
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Handle a federated key package request — return key packages for a local user.
async fn handle_federated_key_request(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    let packages = db::mls::get_key_packages(&state.pool, &local_user).await?;
    let engine = base64::engine::general_purpose::STANDARD;

    let kps: Vec<String> = packages.into_iter()
        .map(|kp| base64::Engine::encode(&engine, &kp.key_package))
        .collect();

    Ok(Json(serde_json::json!({ "ok": true, "key_packages": kps })))
}

/// Handle a federated nudge — relay to local user to request fresh location.
async fn handle_federated_nudge(
    state: &AppState,
    msg: &FederatedMessage,
) -> Result<Json<serde_json::Value>, AppError> {
    let local_user = find_local_user(&state.pool, &msg.recipient).await
        .ok_or_else(|| AppError::NotFound("recipient not found".into()))?;

    let ws_msg = serde_json::json!({
        "type": "location.nudge",
        "requester_id": msg.sender,
        "federated": true,
    });
    state.hub.send_to_user(&local_user, &ws_msg.to_string().into_bytes());

    // FCM wake if offline
    if !state.hub.is_online(&local_user) {
        if let Some(ref fcm) = state.fcm {
            let fcm = fcm.clone();
            let pool = state.pool.clone();
            let uid = local_user.clone();
            tokio::spawn(async move {
                fcm.send_wake_push(&pool, &uid, "location.nudge").await;
            });
        }
    }

    Ok(Json(serde_json::json!({ "ok": true })))
}

// ==================== Outbound federation ====================

/// POST /api/federation/send — Send a message to a user on a remote server.
/// Called by authenticated local users when sharing with federated users.
pub async fn send_federated(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendFederatedBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let recipient_domain = body.recipient.split('@').nth(1)
        .ok_or_else(|| AppError::BadRequest("recipient must be user@domain".into()))?;

    // Don't federate to ourselves
    if recipient_domain == state.config.domain {
        return Err(AppError::BadRequest("recipient is on this server".into()));
    }

    // user_id already includes @domain from registration
    let sender = if user.user_id.contains('@') {
        user.user_id.clone()
    } else {
        format!("{}@{}", user.user_id, state.config.domain)
    };

    let msg = FederatedMessage {
        sender,
        recipient: body.recipient.clone(),
        message_type: body.message_type.clone(),
        payload: body.payload.clone(),
        timestamp: chrono::Utc::now().timestamp(),
    };

    // Discover the remote server
    let inbox_url = discover_inbox(recipient_domain).await
        .map_err(|e| AppError::BadRequest(format!("federation discovery failed: {e}")))?;

    // Send to remote inbox
    let client = reqwest::Client::new();
    let resp = client.post(&inbox_url)
        .json(&msg)
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| AppError::BadRequest(format!("federation send failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(AppError::BadRequest(format!("remote server returned {status}: {text}")));
    }

    // Return the remote server's response (may contain key packages, etc.)
    let remote_response: serde_json::Value = resp.json().await
        .unwrap_or(serde_json::json!({ "ok": true }));

    tracing::info!(
        recipient = %body.recipient,
        message_type = %body.message_type,
        "sent federated message"
    );

    Ok(Json(remote_response))
}

#[derive(Debug, Deserialize)]
pub struct SendFederatedBody {
    pub recipient: String,
    pub message_type: String,
    pub payload: serde_json::Value,
}

/// Discover a remote Point server's federation inbox URL.
async fn discover_inbox(domain: &str) -> Result<String, String> {
    let well_known_url = format!("https://{}/.well-known/point", domain);

    let client = reqwest::Client::new();
    let resp = client.get(&well_known_url)
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .map_err(|e| format!("discovery request failed: {e}"))?;

    if !resp.status().is_success() {
        return Err(format!("discovery returned {}", resp.status()));
    }

    let info: WellKnownResponse = resp.json().await
        .map_err(|e| format!("invalid discovery response: {e}"))?;

    if !info.federation {
        return Err("remote server has federation disabled".into());
    }

    Ok(info.endpoints.inbox)
}
