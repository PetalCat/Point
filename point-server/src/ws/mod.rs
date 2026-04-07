pub mod handler;
pub mod hub;
pub mod presence;

use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{Query, State};
use axum::response::Response;
use serde::Deserialize;

use crate::api::AppState;
use crate::api::auth;

#[derive(Deserialize)]
pub struct WsQuery {
    token: String,
}

/// `GET /ws?token=<jwt>` — upgrade to WebSocket after verifying the JWT.
pub async fn ws_upgrade(
    State(state): State<AppState>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, crate::error::AppError> {
    let claims = auth::verify_token(&state.jwt_secret, &query.token)?;
    let hub = state.hub.clone();

    Ok(ws.on_upgrade(move |socket| handler::handle_connection(socket, claims, state, hub)))
}
