use axum::extract::State;
use axum::Json;
use serde::Serialize;

use crate::db;
use crate::error::AppError;

use super::{AppState, AuthUser};

#[derive(Debug, Serialize)]
pub struct InfoResponse {
    pub version: String,
    pub domain: String,
    pub user_count: i64,
}

pub async fn info(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<InfoResponse>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let user_count = db::users::count_users(&state.pool).await?;

    Ok(Json(InfoResponse {
        version: env!("CARGO_PKG_VERSION").to_string(),
        domain: state.config.domain.clone(),
        user_count,
    }))
}
