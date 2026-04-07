pub mod admin;
pub mod auth;
pub mod groups;
pub mod history;
pub mod invites;
pub mod places;
pub mod items;
pub mod shares;
pub mod zones;
pub mod bridge_entities;
pub mod federation;
pub mod ghost;
pub mod mls;

use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::Router;
use axum::routing::{delete, get, post, put};

use crate::config::Config;
use crate::db::DbPool;
use crate::error::AppError;
use crate::fcm::FcmService;
use crate::federation_keys::FederationKeys;
use crate::ws::hub::Hub;

#[derive(Clone)]
pub struct AppState {
    pub pool: DbPool,
    pub config: Config,
    pub jwt_secret: String,
    pub hub: Hub,
    pub fcm: Option<FcmService>,
    pub federation_keys: std::sync::Arc<FederationKeys>,
}

/// Authenticated user extracted from Authorization header.
pub struct AuthUser {
    pub user_id: String,
    pub is_admin: bool,
}

impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync,
    AppState: FromRef<S>,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let app_state = AppState::from_ref(state);

        let header = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .ok_or(AppError::Unauthorized)?;

        let claims = auth::verify_token(&app_state.jwt_secret, token)?;

        Ok(AuthUser {
            user_id: claims.sub,
            is_admin: claims.is_admin,
        })
    }
}

/// Helper trait so we can extract AppState from itself.
trait FromRef<T> {
    fn from_ref(input: &T) -> Self;
}

impl FromRef<AppState> for AppState {
    fn from_ref(input: &AppState) -> Self {
        input.clone()
    }
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/api/register", post(auth::register))
        .route("/api/login", post(auth::login))
        .route("/api/account", delete(auth::delete_account))
        .route("/api/account/password", put(auth::change_password))
        .route("/api/groups", post(groups::create).get(groups::list))
        .route("/api/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/api/groups/{id}/settings", put(groups::update_settings))
        .route("/api/groups/{id}/me", put(groups::update_my_settings))
        .route("/api/groups/{id}/invite", post(groups::create_invite))
        .route("/api/groups/join/{code}", post(groups::join_by_code))
        .route("/api/groups/{id}/members", post(groups::add_member))
        .route("/api/groups/{id}/members/{member_id}", delete(groups::remove_member))
        .route("/api/groups/{id}/members/{member_id}/role", put(groups::update_member_role))
        .route("/api/items", post(items::create).get(items::list))
        .route("/api/items/{id}", delete(items::delete))
        .route("/api/items/{id}/share", post(items::share))
        .route("/api/items/{id}/unshare", post(items::unshare))
        .route("/api/shares", get(shares::list_shares))
        .route("/api/shares/temp", post(shares::create_temp).get(shares::list_temp))
        .route("/api/shares/temp/{id}", delete(shares::delete_temp))
        .route("/api/shares/request", post(shares::send_request))
        .route("/api/shares/requests", get(shares::list_incoming))
        .route("/api/shares/requests/outgoing", get(shares::list_outgoing))
        .route("/api/shares/requests/{id}/accept", post(shares::accept))
        .route("/api/shares/requests/{id}/reject", post(shares::reject))
        .route("/api/shares/{user_id}", delete(shares::remove_share))
        .route("/api/zones/consent/request", post(zones::request_consent))
        .route("/api/zones/consent/incoming", get(zones::list_incoming))
        .route("/api/zones/consent/granted", get(zones::list_granted))
        .route("/api/zones/consent/{owner_id}/accept", post(zones::accept_consent))
        .route("/api/zones/consent/{owner_id}/reject", post(zones::reject_consent))
        .route("/api/zones/consent/{owner_id}", delete(zones::revoke_consent))
        .route("/api/groups/{id}/places", post(places::create).get(places::list))
        .route("/api/places/personal", post(places::create_personal).get(places::list_personal))
        .route("/api/places/{id}", delete(places::delete))
        .route("/api/invites", post(invites::create).get(invites::list))
        .route("/api/invites/{id}", delete(invites::delete))
        .route("/api/history/{user_id}", get(history::get_history))
        .route("/api/history", delete(history::delete_history))
        .route("/api/bridges/registry", get(bridge_entities::list_registry))
        .route("/api/bridges/entities", post(bridge_entities::create_entity).get(bridge_entities::list_entities))
        .route("/api/bridges/entities/discovered", post(bridge_entities::discover_entity))
        .route("/api/bridges/entities/{id}", get(bridge_entities::get_entity).delete(bridge_entities::delete_entity))
        .route("/api/bridges/entities/{id}/confirm", post(bridge_entities::confirm_entity))
        .route("/api/bridges/entities/{id}/share", post(bridge_entities::share_entity))
        .route("/api/bridges/entities/{id}/shares", get(bridge_entities::list_entity_shares))
        .route("/api/ghost", put(ghost::set_ghost))
        .route("/.well-known/point", get(federation::well_known))
        .route("/federation/inbox", post(federation::inbox))
        .route("/api/federation/send", post(federation::send_federated))
        .route("/api/mls/keys", post(mls::upload_keys))
        .route("/api/mls/keys/{user_id}", get(mls::get_keys))
        .route("/api/mls/welcome", post(mls::send_welcome))
        .route("/api/mls/commit", post(mls::send_commit))
        .route("/api/mls/messages", get(mls::get_messages))
        .route("/api/mls/messages/{id}/ack", post(mls::ack_message))
        .route("/api/admin/info", get(admin::info))
        .route("/api/fcm/token", post(auth::register_fcm_token))
        .route("/ws", get(crate::ws::ws_upgrade))
        .with_state(state)
}
