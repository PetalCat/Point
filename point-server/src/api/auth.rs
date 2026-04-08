use std::sync::LazyLock;
use axum::extract::State;
use axum::Json;
use dashmap::DashMap;
use serde::{Deserialize, Serialize};

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use jsonwebtoken::{encode, DecodingKey, EncodingKey, Header, Validation};

use crate::db;
use crate::error::AppError;

// IP-based rate limiter for auth endpoints: max 10 attempts per minute per username
static AUTH_RATE_LIMIT: LazyLock<DashMap<String, (u32, std::time::Instant)>> =
    LazyLock::new(DashMap::new);

// Global registration rate limiter — max 5 registrations per minute across all users
static REG_RATE_LIMIT: LazyLock<DashMap<String, (u32, std::time::Instant)>> =
    LazyLock::new(DashMap::new);

fn check_auth_rate_limit(key: &str) -> Result<(), AppError> {
    let mut entry = AUTH_RATE_LIMIT.entry(key.to_string()).or_insert((0, std::time::Instant::now()));
    if entry.1.elapsed() > std::time::Duration::from_secs(60) {
        *entry = (1, std::time::Instant::now());
        return Ok(());
    }
    entry.0 += 1;
    if entry.0 > 10 {
        return Err(AppError::BadRequest("too many attempts — try again in a minute".into()));
    }
    Ok(())
}

fn check_registration_rate_limit() -> Result<(), AppError> {
    let mut entry = REG_RATE_LIMIT.entry("global".to_string()).or_insert((0, std::time::Instant::now()));
    if entry.1.elapsed() > std::time::Duration::from_secs(60) {
        *entry = (1, std::time::Instant::now());
        return Ok(());
    }
    entry.0 += 1;
    if entry.0 > 5 {
        return Err(AppError::BadRequest("too many registrations — try again later".into()));
    }
    Ok(())
}

use super::{AppState, AuthUser};

#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub display_name: String,
    pub password: String,
    pub invite_code: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user_id: String,
    pub display_name: String,
    pub is_admin: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub is_admin: bool,
    pub exp: usize,
}

pub fn create_token(secret: &str, user_id: &str, is_admin: bool) -> Result<String, AppError> {
    let exp = chrono::Utc::now()
        .checked_add_signed(chrono::Duration::days(7))
        .unwrap()
        .timestamp() as usize;

    let claims = Claims {
        sub: user_id.to_string(),
        is_admin,
        exp,
    };

    // Pin to HS256 — prevent algorithm confusion attacks
    let header = Header::new(jsonwebtoken::Algorithm::HS256);
    encode(
        &header,
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(e.to_string()))
}

pub fn verify_token(secret: &str, token: &str) -> Result<Claims, AppError> {
    // Pin validation to HS256 only — reject any other algorithm
    let mut validation = Validation::new(jsonwebtoken::Algorithm::HS256);
    validation.validate_exp = true;
    let data = jsonwebtoken::decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
    .map_err(|_| AppError::Unauthorized)?;

    Ok(data.claims)
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    check_auth_rate_limit(&req.username)?;
    check_registration_rate_limit()?;
    if req.username.is_empty() || req.password.is_empty() {
        return Err(AppError::BadRequest("username and password required".into()));
    }
    if req.username.len() < 3 || req.username.len() > 32 {
        return Err(AppError::BadRequest("username must be 3-32 characters".into()));
    }
    if req.password.len() < 8 {
        return Err(AppError::BadRequest("password must be at least 8 characters".into()));
    }
    // Only allow alphanumeric + underscore/hyphen in usernames
    if !req.username.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
        return Err(AppError::BadRequest("username may only contain letters, numbers, _ and -".into()));
    }

    let user_id = format!("{}@{}", req.username, state.config.domain);

    // Sanitize display_name: max 64 chars, strip HTML, normalize whitespace
    let display_name = req.display_name.trim();
    if display_name.is_empty() || display_name.len() > 64 {
        return Err(AppError::BadRequest("display_name must be 1-64 characters".into()));
    }
    // Strip anything that looks like HTML
    let display_name: String = display_name
        .replace('<', "").replace('>', "").replace('&', "&amp;")
        // Strip zero-width and invisible unicode characters
        .chars()
        .filter(|c| {
            !c.is_control()
            && !('\u{200B}'..='\u{200F}').contains(c)  // zero-width + LRM/RLM
            && !('\u{202A}'..='\u{202E}').contains(c)  // bidi embedding/override (RTL override)
            && !('\u{2066}'..='\u{2069}').contains(c)  // bidi isolates
            && *c != '\u{FEFF}'                         // BOM
        })
        .collect();

    // Check if user already exists — generic error to prevent enumeration
    if db::users::get_user_by_id(&state.pool, &user_id)
        .await?
        .is_some()
    {
        return Err(AppError::BadRequest("registration failed".into()));
    }

    // First user becomes admin, no invite needed
    let user_count = db::users::count_users(&state.pool).await?;
    let is_admin = user_count == 0;

    if !is_admin && !state.config.open_registration {
        // Invite-only mode: subsequent users need an invite code
        match &req.invite_code {
            Some(code) => {
                db::invites::use_invite(&state.pool, code)
                    .await
                    .map_err(|_| AppError::BadRequest("invalid or expired invite code".into()))?;
            }
            None => {
                return Err(AppError::BadRequest("invite code required".into()));
            }
        }
    }

    // Hash password
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(req.password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(e.to_string()))?
        .to_string();

    let user = db::users::create_user(
        &state.pool,
        &user_id,
        &display_name,
        &password_hash,
        is_admin,
    )
    .await?;

    let token = create_token(&state.jwt_secret, &user.id, user.is_admin)?;

    Ok(Json(AuthResponse {
        token,
        user_id: user.id,
        display_name: user.display_name,
        is_admin: user.is_admin,
    }))
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    check_auth_rate_limit(&req.username)?;
    let user_id = format!("{}@{}", req.username, state.config.domain);

    let user = db::users::get_user_by_id(&state.pool, &user_id)
        .await?
        .ok_or(AppError::Unauthorized)?;

    let parsed_hash =
        PasswordHash::new(&user.password_hash).map_err(|e| AppError::Internal(e.to_string()))?;

    Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthorized)?;

    let token = create_token(&state.jwt_secret, &user.id, user.is_admin)?;

    Ok(Json(AuthResponse {
        token,
        user_id: user.id,
        display_name: user.display_name,
        is_admin: user.is_admin,
    }))
}

#[derive(Debug, Deserialize)]
pub struct DeleteAccountRequest {
    pub password: String,
}

pub async fn delete_account(
    auth_user: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<DeleteAccountRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user = db::users::get_user_by_id(&state.pool, &auth_user.user_id)
        .await?
        .ok_or(AppError::Unauthorized)?;

    let parsed_hash =
        PasswordHash::new(&user.password_hash).map_err(|e| AppError::Internal(e.to_string()))?;

    Argon2::default()
        .verify_password(req.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::BadRequest("incorrect password".into()))?;

    db::users::delete_user(&state.pool, &auth_user.user_id).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

pub async fn change_password(
    auth_user: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<ChangePasswordRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    if req.new_password.is_empty() {
        return Err(AppError::BadRequest("new password cannot be empty".into()));
    }

    let user = db::users::get_user_by_id(&state.pool, &auth_user.user_id)
        .await?
        .ok_or(AppError::Unauthorized)?;

    let parsed_hash =
        PasswordHash::new(&user.password_hash).map_err(|e| AppError::Internal(e.to_string()))?;

    Argon2::default()
        .verify_password(req.current_password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::BadRequest("incorrect password".into()))?;

    let salt = SaltString::generate(&mut OsRng);
    let new_hash = Argon2::default()
        .hash_password(req.new_password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(e.to_string()))?
        .to_string();

    db::users::update_password(&state.pool, &auth_user.user_id, &new_hash).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Debug, Deserialize)]
pub struct FcmTokenRequest {
    pub token: String,
}

pub async fn register_fcm_token(
    auth_user: AuthUser,
    State(state): State<AppState>,
    Json(req): Json<FcmTokenRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    db::users::save_fcm_token(&state.pool, &auth_user.user_id, &req.token).await?;
    tracing::info!(user_id = %auth_user.user_id, "FCM token registered");
    Ok(Json(serde_json::json!({ "ok": true })))
}
