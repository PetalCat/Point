use axum::extract::ws::{Message, WebSocket};
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;

use crate::api::AppState;
use crate::api::auth::Claims;
use crate::db;

use super::hub::Hub;
use super::presence::PresenceUpdate;

/// Top-level envelope for all incoming WS messages.
#[derive(Deserialize, Debug)]
struct Envelope {
    #[serde(rename = "type")]
    msg_type: String,

    // location.update fields
    recipient_type: Option<String>,
    recipient_id: Option<String>,
    encrypted_blob: Option<String>,
    source_type: Option<String>,
    timestamp: Option<i64>,
    ttl: Option<i64>,

    // presence.update fields
    battery: Option<u8>,
    activity: Option<String>,

    // bridge.register / bridge.heartbeat fields
    bridge_id: Option<String>,
    bridge_type: Option<String>,
    status: Option<String>,
    error_message: Option<String>,

    // item.location fields
    item_id: Option<String>,

    // place.triggered fields
    place_id: Option<String>,
    place_name: Option<String>,
    event: Option<String>,

    // location.batch_update fields
    encrypted_blobs: Option<Vec<String>>,
    timestamps: Option<Vec<i64>>,

    // location.nudge fields
    target_user_id: Option<String>,
}

/// Drive a single WebSocket connection to completion.
pub async fn handle_connection(ws: WebSocket, claims: Claims, state: AppState, hub: Hub) {
    let user_id = claims.sub.clone();
    let (mut ws_tx, mut ws_rx) = ws.split();

    // Channel from hub -> this connection
    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();
    let conn_id = hub.add_connection(&user_id, tx);

    tracing::info!(user_id = %user_id, conn_id = %conn_id, "ws connected");

    // Task: forward hub messages to the websocket
    let send_task = tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if ws_tx.send(Message::Text(String::from_utf8_lossy(&data).into_owned().into())).await.is_err() {
                break;
            }
        }
    });

    // Task: read from websocket and process
    let hub2 = hub.clone();
    let uid = user_id.clone();
    let recv_task = tokio::spawn(async move {
        let mut rate_counters = std::collections::HashMap::new();
        while let Some(Ok(msg)) = ws_rx.next().await {
            match msg {
                Message::Text(text) => {
                    process_message(&uid, &text, &state, &hub2, &mut rate_counters).await;
                }
                Message::Binary(data) => {
                    if let Ok(text) = String::from_utf8(data.to_vec()) {
                        process_message(&uid, &text, &state, &hub2, &mut rate_counters).await;
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    // Wait for either task to finish, then clean up
    tokio::select! {
        _ = send_task => {}
        _ = recv_task => {}
    }

    hub.remove_connection(&user_id, &conn_id);
    tracing::info!(user_id = %user_id, conn_id = %conn_id, "ws disconnected");
}

/// Simple per-user rate limiter. Returns true if the message should be dropped.
fn rate_limited(counters: &mut std::collections::HashMap<String, (u32, std::time::Instant)>, msg_type: &str) -> bool {
    let (max_per_min, key) = match msg_type {
        "location.update" | "location.batch_update" => (60, "loc"),
        "location.nudge" => (10, "nudge"),
        "presence.update" => (30, "pres"),
        _ => (120, "other"),
    };

    let entry = counters.entry(key.to_string()).or_insert((0, std::time::Instant::now()));
    if entry.1.elapsed() > std::time::Duration::from_secs(60) {
        // Reset window
        *entry = (1, std::time::Instant::now());
        return false;
    }
    entry.0 += 1;
    entry.0 > max_per_min
}

async fn process_message(
    user_id: &str,
    text: &str,
    state: &AppState,
    hub: &Hub,
    rate_counters: &mut std::collections::HashMap<String, (u32, std::time::Instant)>,
) {
    let envelope: Envelope = match serde_json::from_str(text) {
        Ok(e) => e,
        Err(e) => {
            tracing::warn!(user_id = %user_id, error = %e, "invalid ws message");
            return;
        }
    };

    if rate_limited(rate_counters, &envelope.msg_type) {
        tracing::warn!(user_id = %user_id, msg_type = %envelope.msg_type, "rate limited");
        return;
    }

    match envelope.msg_type.as_str() {
        "location.update" => handle_location_update(user_id, &envelope, state, hub).await,
        "location.batch_update" => handle_location_batch_update(user_id, &envelope, state, hub).await,
        "presence.update" => handle_presence_update(user_id, &envelope, state, hub).await,
        "location.nudge" => handle_location_nudge(user_id, &envelope, state, hub).await,
        "location.subscribe" => {
            tracing::info!(user_id = %user_id, "location.subscribe received (no-op for now)");
        }
        "bridge.register" => handle_bridge_register(user_id, &envelope, state, hub).await,
        "bridge.heartbeat" => handle_bridge_heartbeat(user_id, &envelope, state).await,
        "item.location" => handle_item_location(user_id, &envelope, state, hub).await,
        "place.triggered" => handle_place_triggered(user_id, &envelope, state, hub).await,
        other => {
            tracing::warn!(user_id = %user_id, msg_type = %other, "unknown ws message type");
        }
    }
}

async fn handle_location_update(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let recipient_type = match &env.recipient_type {
        Some(v) => v.as_str(),
        None => return,
    };
    let recipient_id = match &env.recipient_id {
        Some(v) => v.as_str(),
        None => return,
    };
    let encrypted_blob = match &env.encrypted_blob {
        Some(v) => v.as_str(),
        None => return,
    };
    let source_type = env.source_type.as_deref().unwrap_or("native");
    let timestamp = env.timestamp.unwrap_or_else(|| chrono::Utc::now().timestamp());
    let ttl = env.ttl.unwrap_or(300);

    // Server-side ghost safety net — drop location if user is globally ghosted
    match db::users::is_ghost_active(&state.pool, user_id).await {
        Ok(true) => {
            tracing::debug!(user = %user_id, "dropping location broadcast — ghost active");
            return;
        }
        Ok(false) => {}
        Err(e) => {
            tracing::warn!(error = %e, "failed to check ghost flag, allowing broadcast");
        }
    }

    // Store in DB
    let id = uuid::Uuid::new_v4().to_string();
    if let Err(e) = db::locations::store_location(
        &state.pool,
        &id,
        user_id,
        recipient_type,
        recipient_id,
        encrypted_blob.as_bytes(),
        source_type,
        timestamp,
        ttl,
    )
    .await
    {
        tracing::error!(error = %e, "failed to store location update");
        return;
    }

    // Store a copy in location_history for trail/history feature
    let history_id = uuid::Uuid::new_v4().to_string();
    if let Err(e) = db::history::store_history_point(
        &state.pool,
        &history_id,
        user_id,
        encrypted_blob.as_bytes(),
        source_type,
        timestamp,
    )
    .await
    {
        tracing::error!(error = %e, "failed to store location history point");
    }

    // Build the outgoing message (forward as-is with sender info)
    let outgoing = serde_json::json!({
        "type": "location.broadcast",
        "sender_id": user_id,
        "recipient_type": recipient_type,
        "recipient_id": recipient_id,
        "encrypted_blob": encrypted_blob,
        "source_type": source_type,
        "timestamp": timestamp,
    });
    let data = outgoing.to_string().into_bytes();

    // Route to recipients
    match recipient_type {
        "group" => {
            match db::groups::get_members(&state.pool, recipient_id).await {
                Ok(members) => {
                    for m in &members {
                        if m.user_id != user_id {
                            hub.send_to_user(&m.user_id, &data);
                        }
                    }
                }
                Err(e) => {
                    tracing::error!(error = %e, "failed to look up group members");
                }
            }
        }
        "user" => {
            // Check if this is a federated recipient (user@otherdomain)
            let is_federated = recipient_id.contains('@')
                && recipient_id.split('@').nth(1).map_or(false, |d| d != state.config.domain);

            if is_federated {
                // Forward via federation
                let sender = if user_id.contains('@') {
                    user_id.to_string()
                } else {
                    format!("{}@{}", user_id, state.config.domain)
                };
                let msg = serde_json::json!({
                    "sender": sender,
                    "recipient": recipient_id,
                    "message_type": "location.update",
                    "payload": {
                        "encrypted_blob": encrypted_blob,
                        "source_type": source_type,
                    },
                    "timestamp": timestamp,
                });
                let fed_keys = state.federation_keys.clone();
                let recipient = recipient_id.to_string();
                tokio::spawn(async move {
                    if let Some(domain) = recipient.split('@').nth(1) {
                        let url = format!("https://{}/federation/inbox", domain);
                        let body_bytes = serde_json::to_vec(&msg).unwrap_or_default();
                        let signature = fed_keys.sign(&body_bytes);
                        let client = reqwest::Client::new();
                        if let Err(e) = client.post(&url)
                            .header("X-Point-Signature", &signature)
                            .json(&msg)
                            .timeout(std::time::Duration::from_secs(10))
                            .send()
                            .await
                        {
                            tracing::error!(error = %e, recipient = %recipient, "federation forward failed");
                        }
                    }
                });
            } else {
            // Local delivery — verify the sender and recipient have an active share
            match db::shares::are_sharing(&state.pool, user_id, recipient_id).await {
                Ok(true) => {
                    if recipient_id != user_id {
                        hub.send_to_user(recipient_id, &data);
                    }
                }
                Ok(false) => {
                    tracing::warn!(
                        sender = %user_id,
                        recipient = %recipient_id,
                        "location update dropped: no active share"
                    );
                }
                Err(e) => {
                    tracing::error!(error = %e, "failed to check share status");
                }
            }
            } // end else (local delivery)
        }
        other => {
            tracing::warn!(recipient_type = %other, "unknown recipient_type");
        }
    }
}

/// Handle a batched location update — multiple fixes sent as one message.
/// Stores ALL fixes in history for trail playback, but only broadcasts the
/// LATEST position to viewers.
async fn handle_location_batch_update(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let recipient_type = match &env.recipient_type {
        Some(v) => v.as_str(),
        None => return,
    };
    let recipient_id = match &env.recipient_id {
        Some(v) => v.as_str(),
        None => return,
    };
    let blobs = match &env.encrypted_blobs {
        Some(v) if !v.is_empty() => v,
        _ => return,
    };
    let timestamps = match &env.timestamps {
        Some(v) if v.len() == blobs.len() => v,
        _ => return,
    };
    let source_type = env.source_type.as_deref().unwrap_or("native");

    // Server-side ghost safety net
    match db::users::is_ghost_active(&state.pool, user_id).await {
        Ok(true) => {
            tracing::debug!(user = %user_id, "dropping batch location — ghost active");
            return;
        }
        Ok(false) => {}
        Err(e) => {
            tracing::warn!(error = %e, "failed to check ghost flag, allowing batch");
        }
    }

    // Store every fix in history for trail playback.
    for (blob, ts) in blobs.iter().zip(timestamps.iter()) {
        let history_id = uuid::Uuid::new_v4().to_string();
        if let Err(e) = db::history::store_history_point(
            &state.pool,
            &history_id,
            user_id,
            blob.as_bytes(),
            source_type,
            *ts,
        )
        .await
        {
            tracing::error!(error = %e, "failed to store batch history point");
        }
    }

    // Store only the latest fix as the current location.
    let latest_blob = &blobs[blobs.len() - 1];
    let latest_ts = timestamps[timestamps.len() - 1];
    let id = uuid::Uuid::new_v4().to_string();
    let ttl: i64 = 300;
    if let Err(e) = db::locations::store_location(
        &state.pool,
        &id,
        user_id,
        recipient_type,
        recipient_id,
        latest_blob.as_bytes(),
        source_type,
        latest_ts,
        ttl,
    )
    .await
    {
        tracing::error!(error = %e, "failed to store batch latest location");
        return;
    }

    // Broadcast only the LATEST position to viewers.
    let outgoing = serde_json::json!({
        "type": "location.broadcast",
        "sender_id": user_id,
        "recipient_type": recipient_type,
        "recipient_id": recipient_id,
        "encrypted_blob": latest_blob,
        "source_type": source_type,
        "timestamp": latest_ts,
    });
    let data = outgoing.to_string().into_bytes();

    match recipient_type {
        "group" => {
            match db::groups::get_members(&state.pool, recipient_id).await {
                Ok(members) => {
                    for m in &members {
                        if m.user_id != user_id {
                            hub.send_to_user(&m.user_id, &data);
                        }
                    }
                }
                Err(e) => {
                    tracing::error!(error = %e, "failed to look up group members for batch");
                }
            }
        }
        "user" => {
            let is_federated = recipient_id.contains('@')
                && recipient_id.split('@').nth(1).map_or(false, |d| d != state.config.domain);

            if is_federated {
                let sender = if user_id.contains('@') {
                    user_id.to_string()
                } else {
                    format!("{}@{}", user_id, state.config.domain)
                };
                let msg = serde_json::json!({
                    "sender": sender,
                    "recipient": recipient_id,
                    "message_type": "location.update",
                    "payload": {
                        "encrypted_blob": latest_blob,
                        "source_type": source_type,
                    },
                    "timestamp": latest_ts,
                });
                let fed_keys = state.federation_keys.clone();
                let recipient = recipient_id.to_string();
                tokio::spawn(async move {
                    if let Some(domain) = recipient.split('@').nth(1) {
                        let url = format!("https://{}/federation/inbox", domain);
                        let body_bytes = serde_json::to_vec(&msg).unwrap_or_default();
                        let signature = fed_keys.sign(&body_bytes);
                        let client = reqwest::Client::new();
                        if let Err(e) = client.post(&url)
                            .header("X-Point-Signature", &signature)
                            .json(&msg)
                            .timeout(std::time::Duration::from_secs(10))
                            .send()
                            .await
                        {
                            tracing::error!(error = %e, recipient = %recipient, "federation batch forward failed");
                        }
                    }
                });
            } else {
                match db::shares::are_sharing(&state.pool, user_id, recipient_id).await {
                    Ok(true) => {
                        if recipient_id != user_id {
                            hub.send_to_user(recipient_id, &data);
                        }
                    }
                    Ok(false) => {
                        tracing::warn!(
                            sender = %user_id,
                            recipient = %recipient_id,
                            "batch location update dropped: no active share"
                        );
                    }
                    Err(e) => {
                        tracing::error!(error = %e, "failed to check share status for batch");
                    }
                }
            }
        }
        other => {
            tracing::warn!(recipient_type = %other, "unknown recipient_type in batch");
        }
    }

    tracing::debug!(user_id = %user_id, count = blobs.len(), "batch location update processed");
}

/// Handle a location nudge — request a fresh update from a specific user.
/// If the target is online, relay via WS. If offline, send FCM wake push.
async fn handle_location_nudge(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let target = match &env.target_user_id {
        Some(v) => v.as_str(),
        None => return,
    };

    // Verify share relationship before allowing nudge
    let has_share = db::shares::are_sharing(&state.pool, user_id, target)
        .await
        .unwrap_or(false);
    if !has_share {
        tracing::warn!(requester = %user_id, target = %target, "nudge rejected: no active share");
        return;
    }

    // Check if target is federated
    let is_federated = target.contains('@')
        && target.split('@').nth(1).map_or(false, |d| d != state.config.domain);

    if is_federated {
        // Forward nudge via federation
        let sender = if user_id.contains('@') {
            user_id.to_string()
        } else {
            format!("{}@{}", user_id, state.config.domain)
        };
        let msg = serde_json::json!({
            "sender": sender,
            "recipient": target,
            "message_type": "location.nudge",
            "payload": {},
            "timestamp": chrono::Utc::now().timestamp(),
        });
        let target_domain = target.split('@').nth(1).unwrap_or("").to_string();
        let fed_keys = state.federation_keys.clone();
        tokio::spawn(async move {
            let url = format!("https://{}/federation/inbox", target_domain);
            let body_bytes = serde_json::to_vec(&msg).unwrap_or_default();
            let signature = fed_keys.sign(&body_bytes);
            let client = reqwest::Client::new();
            if let Err(e) = client.post(&url)
                .header("X-Point-Signature", &signature)
                .json(&msg)
                .timeout(std::time::Duration::from_secs(10))
                .send()
                .await
            {
                tracing::error!(error = %e, "federation nudge forward failed");
            }
        });
    } else {
        // Local delivery
        let msg = serde_json::json!({
            "type": "location.nudge",
            "requester_id": user_id,
        });
        hub.send_to_user(target, &msg.to_string().into_bytes());

        // FCM wake push if target is offline
        if !hub.is_online(target) {
            if let Some(ref fcm) = state.fcm {
                let fcm = fcm.clone();
                let pool = state.pool.clone();
                let target = target.to_string();
                tokio::spawn(async move {
                    fcm.send_wake_push(&pool, &target, "location.nudge").await;
                });
            }
        }
    }

    tracing::debug!(requester = %user_id, target = %target, "location nudge");
}

async fn handle_bridge_register(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let bridge_type = match &env.bridge_type {
        Some(v) => v.as_str(),
        None => return,
    };
    let bridge_id = env
        .bridge_id
        .clone()
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    match db::bridges::register_bridge(&state.pool, &bridge_id, user_id, bridge_type).await {
        Ok(_) => {
            let ack = serde_json::json!({
                "type": "bridge.registered",
                "bridge_id": bridge_id,
                "bridge_type": bridge_type,
            });
            hub.send_to_user(user_id, &ack.to_string().into_bytes());
        }
        Err(e) => {
            tracing::error!(error = %e, "failed to register bridge");
        }
    }
}

async fn handle_bridge_heartbeat(user_id: &str, env: &Envelope, state: &AppState) {
    let bridge_id = match &env.bridge_id {
        Some(v) => v.as_str(),
        None => return,
    };
    let status = match &env.status {
        Some(v) => v.as_str(),
        None => return,
    };
    let error_message = env.error_message.as_deref();

    // Verify this user owns the bridge before allowing heartbeat update
    match db::bridges::get_bridge(&state.pool, bridge_id).await {
        Ok(Some(bridge)) if bridge.user_id == user_id => {
            if let Err(e) =
                db::bridges::update_heartbeat(&state.pool, bridge_id, status, error_message).await
            {
                tracing::error!(error = %e, "failed to update bridge heartbeat");
            }
        }
        Ok(Some(_)) => {
            tracing::warn!(user = %user_id, bridge = %bridge_id, "bridge heartbeat rejected: not owner");
        }
        Ok(None) => {
            tracing::warn!(bridge = %bridge_id, "bridge heartbeat: bridge not found");
        }
        Err(e) => {
            tracing::error!(error = %e, "bridge ownership check failed");
        }
    }
}

async fn handle_item_location(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let item_id = match &env.item_id {
        Some(v) => v.as_str(),
        None => return,
    };
    let encrypted_blob = match &env.encrypted_blob {
        Some(v) => v.as_str(),
        None => return,
    };
    let source_type = env.source_type.as_deref().unwrap_or("bridge");
    let timestamp = env.timestamp.unwrap_or_else(|| chrono::Utc::now().timestamp());

    // Look up the item
    let item = match db::items::get_item(&state.pool, item_id).await {
        Ok(Some(item)) => item,
        Ok(None) => return,
        Err(e) => {
            tracing::error!(error = %e, "failed to look up item");
            return;
        }
    };

    // Build broadcast message
    let broadcast = serde_json::json!({
        "type": "item.broadcast",
        "item_id": item_id,
        "encrypted_blob": encrypted_blob,
        "source_type": source_type,
        "timestamp": timestamp,
    });
    let data = broadcast.to_string().into_bytes();

    // Collect all recipient user IDs
    let mut recipients = std::collections::HashSet::new();
    recipients.insert(item.owner_id.clone());

    // Look up shares to find additional recipients
    match db::items::get_item_shares(&state.pool, item_id).await {
        Ok(shares) => {
            for share in &shares {
                match share.target_type.as_str() {
                    "user" => {
                        recipients.insert(share.target_id.clone());
                    }
                    "group" => {
                        match db::groups::get_members(&state.pool, &share.target_id).await {
                            Ok(members) => {
                                for m in &members {
                                    recipients.insert(m.user_id.clone());
                                }
                            }
                            Err(e) => {
                                tracing::error!(error = %e, group_id = %share.target_id, "failed to get group members for item broadcast");
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        Err(e) => {
            tracing::error!(error = %e, "failed to get item shares");
        }
    }

    // Send to all recipients (excluding sender to avoid echo)
    for uid in &recipients {
        if uid != user_id {
            hub.send_to_user(uid, &data);
        }
    }
}

async fn handle_presence_update(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let update = PresenceUpdate {
        user_id: user_id.to_string(),
        online: true,
        battery: env.battery,
        activity: env.activity.clone(),
    };

    let outgoing = serde_json::json!({
        "type": "presence.update",
        "user_id": update.user_id,
        "online": update.online,
        "battery": update.battery,
        "activity": update.activity,
    });
    let data = outgoing.to_string().into_bytes();

    // Broadcast to all group members across all groups the user belongs to
    match db::groups::list_user_groups(&state.pool, user_id).await {
        Ok(groups) => {
            // Collect unique user IDs to avoid sending duplicates
            let mut seen = std::collections::HashSet::new();
            seen.insert(user_id.to_string());

            for group in &groups {
                match db::groups::get_members(&state.pool, &group.id).await {
                    Ok(members) => {
                        for m in &members {
                            if seen.insert(m.user_id.clone()) {
                                hub.send_to_user(&m.user_id, &data);
                            }
                        }
                    }
                    Err(e) => {
                        tracing::error!(error = %e, group_id = %group.id, "failed to get group members for presence");
                    }
                }
            }
        }
        Err(e) => {
            tracing::error!(error = %e, "failed to list user groups for presence");
        }
    }
}

async fn handle_place_triggered(user_id: &str, env: &Envelope, state: &AppState, hub: &Hub) {
    let place_id = match &env.place_id {
        Some(v) => v.as_str(),
        None => return,
    };
    let place_name = match &env.place_name {
        Some(v) => v.as_str(),
        None => return,
    };
    let event = match &env.event {
        Some(v) => v.as_str(),
        None => return,
    };

    // Look up the place to find which group it belongs to
    let place = match db::places::get_place(&state.pool, place_id).await {
        Ok(Some(p)) => p,
        Ok(None) => {
            tracing::warn!(place_id = %place_id, "place.triggered for unknown place");
            return;
        }
        Err(e) => {
            tracing::error!(error = %e, "failed to look up place");
            return;
        }
    };

    // Broadcast to all members of the place's group
    let outgoing = serde_json::json!({
        "type": "place.triggered",
        "place_id": place_id,
        "place_name": place_name,
        "event": event,
        "user_id": user_id,
    });
    let data = outgoing.to_string().into_bytes();

    match db::groups::get_members(&state.pool, &place.group_id).await {
        Ok(members) => {
            for m in &members {
                hub.send_to_user(&m.user_id, &data);
                // FCM wake-up push for offline members
                if let Some(ref fcm) = state.fcm {
                    if !hub.is_online(&m.user_id) {
                        let fcm = fcm.clone();
                        let pool = state.pool.clone();
                        let uid = m.user_id.clone();
                        tokio::spawn(async move { fcm.send_wake_push(&pool, &uid, "place.triggered").await; });
                    }
                }
            }
        }
        Err(e) => {
            tracing::error!(error = %e, "failed to get group members for place alert");
        }
    }
}
