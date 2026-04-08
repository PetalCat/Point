pub mod handler;
pub mod hub;
pub mod presence;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::Response;

use crate::api::AppState;
use crate::api::auth;

/// `GET /ws` — upgrade to WebSocket.
/// Auth via first message `{"type":"auth","token":"..."}` only.
/// Query param token was removed — tokens in URLs leak to logs/referrers.
pub async fn ws_upgrade(
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
    ws: WebSocketUpgrade,
) -> Result<Response, crate::error::AppError> {
    // Validate Origin header to prevent Cross-Site WebSocket Hijacking (CSWSH)
    if let Some(origin) = headers.get("origin").and_then(|v| v.to_str().ok()) {
        let allowed_origin = format!("https://{}", state.config.domain);
        if origin != allowed_origin && origin != "http://localhost:3000" && origin != "http://localhost:8080" {
            tracing::warn!(origin = %origin, "ws upgrade rejected: invalid origin");
            return Err(crate::error::AppError::Forbidden);
        }
    }
    // Native app connections (no browser) won't have an Origin header — that's fine

    // First-message auth only — no query param tokens
    let hub = state.hub.clone();
    Ok(ws.on_upgrade(move |socket| authenticate_then_handle(socket, state, hub)))
}

/// Wait for auth message, then hand off to the connection handler.
async fn authenticate_then_handle(mut ws: WebSocket, state: AppState, hub: hub::Hub) {
    // Wait up to 5 seconds for auth message
    let result = tokio::time::timeout(std::time::Duration::from_secs(5), async {
        while let Some(Ok(msg)) = ws.recv().await {
            if let Message::Text(text) = msg {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&text) {
                    if parsed.get("type").and_then(|t| t.as_str()) == Some("auth") {
                        if let Some(token) = parsed.get("token").and_then(|t| t.as_str()) {
                            return Some(token.to_string());
                        }
                    }
                }
                return None; // first message wasn't auth
            }
        }
        None
    })
    .await;

    match result {
        Ok(Some(token)) => {
            match auth::verify_token(&state.jwt_secret, &token) {
                Ok(claims) => {
                    handler::handle_connection(ws, claims, state, hub).await;
                }
                Err(_) => {
                    tracing::warn!("ws auth failed: invalid token");
                    drop(ws);
                }
            }
        }
        Ok(None) => {
            tracing::warn!("ws auth: invalid first message");
            drop(ws);
        }
        Err(_) => {
            tracing::warn!("ws auth: timeout waiting for auth message");
            drop(ws);
        }
    }
}
