pub mod handler;
pub mod hub;
pub mod presence;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::Response;
use serde::Deserialize;

use crate::api::AppState;
use crate::api::auth;

#[derive(Deserialize)]
pub struct WsQuery {
    /// Legacy support: token in URL. Prefer first-message auth.
    token: Option<String>,
}

/// `GET /ws` — upgrade to WebSocket.
/// Auth via first message `{"type":"auth","token":"..."}` (preferred)
/// or via query param `?token=...` (legacy, for backwards compat).
pub async fn ws_upgrade(
    State(state): State<AppState>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, crate::error::AppError> {
    // If token is in the URL (legacy), verify immediately
    if let Some(ref token) = query.token {
        let claims = auth::verify_token(&state.jwt_secret, token)?;
        let hub = state.hub.clone();
        return Ok(ws.on_upgrade(move |socket| handler::handle_connection(socket, claims, state, hub)));
    }

    // No token in URL — expect first-message auth
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
