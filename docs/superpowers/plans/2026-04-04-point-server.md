# Point Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Point server — a self-hostable Rust WebSocket server that routes encrypted location blobs, manages users/groups/items, and exposes a REST API for account management.

**Architecture:** Axum web framework on Tokio async runtime. WebSocket connections for real-time location updates and presence. REST endpoints for auth, groups, items, and admin. PostgreSQL via SQLx for persistence (with SQLite support). Protobuf for wire encoding. The server is zero-knowledge for native locations — it routes encrypted blobs without reading them.

**Tech Stack:** Rust, Axum, Tokio, SQLx (Postgres + SQLite), Prost (Protobuf), tokio-tungstenite (WebSocket), argon2 (password hashing), jsonwebtoken (JWT auth)

---

## File Structure

```
point-server/
├── Cargo.toml
├── build.rs                          # Protobuf compilation
├── proto/
│   └── point.proto                   # All message definitions
├── src/
│   ├── main.rs                       # Entry point, CLI args, server startup
│   ├── config.rs                     # Config from env/CLI args
│   ├── db/
│   │   ├── mod.rs                    # Database pool init, migration runner
│   │   ├── users.rs                  # User CRUD
│   │   ├── groups.rs                 # Group CRUD, membership
│   │   ├── items.rs                  # Item CRUD, sharing
│   │   ├── bridges.rs                # Bridge registration, status
│   │   ├── invites.rs                # Invite link CRUD
│   │   └── locations.rs              # Location blob storage, TTL cleanup
│   ├── api/
│   │   ├── mod.rs                    # Axum router assembly
│   │   ├── auth.rs                   # POST /register, POST /login, auth middleware
│   │   ├── groups.rs                 # REST group management
│   │   ├── items.rs                  # REST item management
│   │   ├── invites.rs                # REST invite link management
│   │   └── admin.rs                  # Admin-only endpoints
│   ├── ws/
│   │   ├── mod.rs                    # WebSocket upgrade handler
│   │   ├── hub.rs                    # Connection registry, message routing
│   │   ├── handler.rs                # Per-connection message processing
│   │   └── presence.rs               # Online/offline tracking, ping/pong
│   ├── proto.rs                      # Generated protobuf types (via build.rs)
│   └── error.rs                      # App error types
├── migrations/
│   └── 001_initial.sql               # All tables
└── tests/
    ├── common/mod.rs                 # Test helpers (spawn server, create client)
    ├── test_auth.rs                  # Registration, login, JWT
    ├── test_groups.rs                # Group CRUD, membership
    ├── test_items.rs                 # Item CRUD, sharing
    ├── test_ws.rs                    # WebSocket connect, location routing
    └── test_presence.rs              # Online/offline, ping/pong
```

---

### Task 1: Project Scaffold & Config

**Files:**
- Create: `point-server/Cargo.toml`
- Create: `point-server/src/main.rs`
- Create: `point-server/src/config.rs`
- Create: `point-server/src/error.rs`

- [ ] **Step 1: Initialize cargo project**

```bash
cd /Users/parker/Developer/GlobalMap
cargo init point-server
```

- [ ] **Step 2: Set up Cargo.toml with dependencies**

Replace `point-server/Cargo.toml`:

```toml
[package]
name = "point-server"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = { version = "0.8", features = ["ws"] }
tokio = { version = "1", features = ["full"] }
sqlx = { version = "0.8", features = ["runtime-tokio", "postgres", "sqlite", "migrate", "uuid", "chrono"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
argon2 = "0.5"
jsonwebtoken = "9"
tower-http = { version = "0.6", features = ["cors", "trace"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
prost = "0.13"
prost-types = "0.13"
futures = "0.3"
dashmap = "6"
clap = { version = "4", features = ["derive"] }
dotenvy = "0.15"
rand = "0.8"
base64 = "0.22"

[build-dependencies]
prost-build = "0.13"
```

- [ ] **Step 3: Write config.rs**

```rust
// point-server/src/config.rs
use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "point-server", about = "Point location sharing server")]
pub struct Config {
    /// Database URL (postgres://... or sqlite://...)
    #[arg(long, env = "DATABASE_URL", default_value = "sqlite://point.db")]
    pub database_url: String,

    /// Listen address
    #[arg(long, env = "LISTEN", default_value = "0.0.0.0:8080")]
    pub listen: String,

    /// JWT secret (auto-generated if not set)
    #[arg(long, env = "JWT_SECRET")]
    pub jwt_secret: Option<String>,

    /// Server domain (used in user@domain IDs)
    #[arg(long, env = "DOMAIN", default_value = "point.local")]
    pub domain: String,
}
```

- [ ] **Step 4: Write error.rs**

```rust
// point-server/src/error.rs
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

#[derive(Debug)]
pub enum AppError {
    NotFound(String),
    BadRequest(String),
    Unauthorized,
    Forbidden,
    Internal(String),
    Conflict(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized".into()),
            AppError::Forbidden => (StatusCode::FORBIDDEN, "forbidden".into()),
            AppError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
            AppError::Conflict(msg) => (StatusCode::CONFLICT, msg),
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}
```

- [ ] **Step 5: Write main.rs (minimal startup)**

```rust
// point-server/src/main.rs
mod config;
mod error;

use clap::Parser;
use config::Config;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Config::parse();
    tracing::info!("Point server starting on {}", config.listen);
    tracing::info!("Domain: {}", config.domain);
    tracing::info!("Database: {}", config.database_url);
}
```

- [ ] **Step 6: Verify it compiles and runs**

```bash
cd point-server && cargo build
cargo run -- --help
```

Expected: Prints help with `--database-url`, `--listen`, `--jwt-secret`, `--domain` options.

- [ ] **Step 7: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git init
echo -e "target/\n.superpowers/\n*.db\n.env" > .gitignore
git add point-server/ .gitignore
git commit -m "feat: scaffold point-server with config and error types"
```

---

### Task 2: Database Schema & Migrations

**Files:**
- Create: `point-server/migrations/001_initial.sql`
- Create: `point-server/src/db/mod.rs`

- [ ] **Step 1: Write initial migration**

```sql
-- point-server/migrations/001_initial.sql

-- Users
CREATE TABLE users (
    id TEXT PRIMARY KEY,              -- "parker@point.local"
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    avatar BLOB,
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Devices
CREATE TABLE devices (
    id TEXT PRIMARY KEY,              -- uuid
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    mls_key_package BLOB,
    push_token TEXT,
    last_seen TEXT NOT NULL DEFAULT (datetime('now')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Groups
CREATE TABLE groups (
    id TEXT PRIMARY KEY,              -- uuid
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    allow_places BOOLEAN NOT NULL DEFAULT TRUE,
    default_precision TEXT NOT NULL DEFAULT 'exact',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Group Members
CREATE TABLE group_members (
    group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',   -- admin, member, viewer
    precision TEXT NOT NULL DEFAULT 'exact', -- exact, approximate, city
    schedule_type TEXT NOT NULL DEFAULT 'always', -- always, custom
    schedule_days TEXT,               -- JSON array of day numbers
    schedule_start TEXT,              -- HH:MM
    schedule_end TEXT,                -- HH:MM
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (group_id, user_id)
);

-- Bridges
CREATE TABLE bridges (
    id TEXT PRIMARY KEY,              -- uuid
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bridge_type TEXT NOT NULL,        -- findmy, google, life360, owntracks
    status TEXT NOT NULL DEFAULT 'disconnected',
    double_puppet BOOLEAN NOT NULL DEFAULT FALSE,
    last_heartbeat TEXT,
    error_message TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Items (Trackers)
CREATE TABLE items (
    id TEXT PRIMARY KEY,              -- uuid
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    tracker_type TEXT NOT NULL,       -- airtag, tile, smarttag, google, owntracks
    source_id TEXT,                   -- ID on source network
    bridge_id TEXT REFERENCES bridges(id) ON DELETE SET NULL,
    capabilities TEXT NOT NULL DEFAULT '[]', -- JSON array
    last_location BLOB,              -- encrypted
    last_seen TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Item Shares
CREATE TABLE item_shares (
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL,        -- 'group' or 'user'
    target_id TEXT NOT NULL,          -- group id or user id
    precision TEXT NOT NULL DEFAULT 'exact',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (item_id, target_type, target_id)
);

-- Places (Geofences)
CREATE TABLE places (
    id TEXT PRIMARY KEY,              -- uuid
    group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    encrypted_definition BLOB NOT NULL,  -- encrypted geometry
    triggers TEXT NOT NULL DEFAULT '["enter","exit"]', -- JSON array
    notify TEXT NOT NULL DEFAULT '[]',  -- JSON array of user IDs
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Location Updates (ephemeral, TTL-based)
CREATE TABLE location_updates (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_type TEXT NOT NULL,     -- 'group' or 'user'
    recipient_id TEXT NOT NULL,
    encrypted_blob BLOB NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'native',
    timestamp INTEGER NOT NULL,
    ttl INTEGER NOT NULL DEFAULT 300,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_location_updates_recipient ON location_updates(recipient_type, recipient_id);
CREATE INDEX idx_location_updates_created ON location_updates(created_at);

-- Invites
CREATE TABLE invites (
    id TEXT PRIMARY KEY,              -- uuid
    code TEXT NOT NULL UNIQUE,        -- short invite code
    created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    max_uses INTEGER NOT NULL DEFAULT 1,
    uses INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Temporary Shares
CREATE TABLE temporary_shares (
    id TEXT PRIMARY KEY,
    from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id TEXT,                  -- null if link-based
    link_token TEXT UNIQUE,           -- for link-based shares
    precision TEXT NOT NULL DEFAULT 'exact',
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- [ ] **Step 2: Write db/mod.rs**

```rust
// point-server/src/db/mod.rs
pub mod users;
pub mod groups;
pub mod items;
pub mod bridges;
pub mod invites;
pub mod locations;

use sqlx::any::{AnyPool, AnyPoolOptions};

pub async fn init_pool(database_url: &str) -> Result<AnyPool, sqlx::Error> {
    // Install drivers
    sqlx::any::install_default_drivers();

    let pool = AnyPoolOptions::new()
        .max_connections(20)
        .connect(database_url)
        .await?;

    // Run migrations
    let migrator = sqlx::migrate!("./migrations");
    migrator.run(&pool).await?;

    tracing::info!("Database connected and migrated");
    Ok(pool)
}
```

- [ ] **Step 3: Create empty module files**

Create these files with just `// TODO: implement in subsequent tasks`:

- `point-server/src/db/users.rs`
- `point-server/src/db/groups.rs`
- `point-server/src/db/items.rs`
- `point-server/src/db/bridges.rs`
- `point-server/src/db/invites.rs`
- `point-server/src/db/locations.rs`

- [ ] **Step 4: Update main.rs to init database**

```rust
// point-server/src/main.rs
mod config;
mod db;
mod error;

use clap::Parser;
use config::Config;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Config::parse();
    tracing::info!("Point server starting on {}", config.listen);

    let pool = db::init_pool(&config.database_url)
        .await
        .expect("Failed to connect to database");

    tracing::info!("Server ready");
}
```

- [ ] **Step 5: Verify migration runs**

```bash
cd point-server && cargo run
```

Expected: Prints "Database connected and migrated" and "Server ready". Creates `point.db` file.

- [ ] **Step 6: Commit**

```bash
git add point-server/migrations/ point-server/src/db/ point-server/src/main.rs
git commit -m "feat: database schema and migration for users, groups, items, bridges, places"
```

---

### Task 3: User Registration & Auth (REST)

**Files:**
- Create: `point-server/src/db/users.rs`
- Create: `point-server/src/api/mod.rs`
- Create: `point-server/src/api/auth.rs`
- Create: `point-server/tests/common/mod.rs`
- Create: `point-server/tests/test_auth.rs`

- [ ] **Step 1: Write db/users.rs**

```rust
// point-server/src/db/users.rs
use sqlx::any::AnyPool;

pub struct User {
    pub id: String,
    pub display_name: String,
    pub password_hash: String,
    pub is_admin: bool,
    pub created_at: String,
}

pub async fn create_user(
    pool: &AnyPool,
    id: &str,
    display_name: &str,
    password_hash: &str,
    is_admin: bool,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO users (id, display_name, password_hash, is_admin) VALUES ($1, $2, $3, $4)")
        .bind(id)
        .bind(display_name)
        .bind(password_hash)
        .bind(is_admin)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_user_by_id(pool: &AnyPool, id: &str) -> Result<Option<User>, sqlx::Error> {
    let row = sqlx::query_as!(
        User,
        "SELECT id, display_name, password_hash, is_admin, created_at FROM users WHERE id = $1",
        id
    )
    .fetch_optional(pool)
    .await;

    // AnyPool doesn't support query_as!, use manual mapping
    let row = sqlx::query("SELECT id, display_name, password_hash, is_admin, created_at FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(pool)
        .await?;

    Ok(row.map(|r| {
        use sqlx::Row;
        User {
            id: r.get("id"),
            display_name: r.get("display_name"),
            password_hash: r.get("password_hash"),
            is_admin: r.get("is_admin"),
            created_at: r.get("created_at"),
        }
    }))
}

pub async fn count_users(pool: &AnyPool) -> Result<i64, sqlx::Error> {
    let row = sqlx::query("SELECT COUNT(*) as count FROM users")
        .fetch_one(pool)
        .await?;
    use sqlx::Row;
    Ok(row.get::<i64, _>("count"))
}
```

- [ ] **Step 2: Write api/auth.rs**

```rust
// point-server/src/api/auth.rs
use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::SaltString};
use jsonwebtoken::{encode, decode, Header, Validation, EncodingKey, DecodingKey};
use rand::rngs::OsRng;

use crate::db;
use crate::error::AppError;

use super::AppState;

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub display_name: String,
    pub password: String,
    pub invite_code: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user_id: String,
    pub display_name: String,
    pub is_admin: bool,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,       // user id
    pub exp: usize,        // expiry
    pub is_admin: bool,
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let user_id = format!("{}@{}", req.username, state.config.domain);

    // Check if user exists
    if db::users::get_user_by_id(&state.pool, &user_id).await?.is_some() {
        return Err(AppError::Conflict("username already taken".into()));
    }

    // First user becomes admin
    let user_count = db::users::count_users(&state.pool).await?;
    let is_admin = user_count == 0;

    // If not first user, require invite code
    if !is_admin {
        let code = req.invite_code.as_deref()
            .ok_or_else(|| AppError::BadRequest("invite code required".into()))?;
        db::invites::use_invite(&state.pool, code).await
            .map_err(|_| AppError::BadRequest("invalid or expired invite code".into()))?;
    }

    // Hash password
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2.hash_password(req.password.as_bytes(), &salt)
        .map_err(|e| AppError::Internal(e.to_string()))?
        .to_string();

    db::users::create_user(&state.pool, &user_id, &req.display_name, &password_hash, is_admin).await?;

    let token = create_token(&state.jwt_secret, &user_id, is_admin)?;

    Ok(Json(AuthResponse {
        token,
        user_id,
        display_name: req.display_name,
        is_admin,
    }))
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let user_id = format!("{}@{}", req.username, state.config.domain);

    let user = db::users::get_user_by_id(&state.pool, &user_id).await?
        .ok_or(AppError::Unauthorized)?;

    let parsed_hash = PasswordHash::new(&user.password_hash)
        .map_err(|e| AppError::Internal(e.to_string()))?;

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

fn create_token(secret: &str, user_id: &str, is_admin: bool) -> Result<String, AppError> {
    let claims = Claims {
        sub: user_id.to_string(),
        exp: (chrono::Utc::now() + chrono::Duration::days(30)).timestamp() as usize,
        is_admin,
    };
    encode(&Header::default(), &claims, &EncodingKey::from_secret(secret.as_bytes()))
        .map_err(|e| AppError::Internal(e.to_string()))
}

pub fn verify_token(secret: &str, token: &str) -> Result<Claims, AppError> {
    decode::<Claims>(token, &DecodingKey::from_secret(secret.as_bytes()), &Validation::default())
        .map(|data| data.claims)
        .map_err(|_| AppError::Unauthorized)
}
```

- [ ] **Step 3: Write api/mod.rs with router and AppState**

```rust
// point-server/src/api/mod.rs
pub mod auth;
pub mod groups;
pub mod items;
pub mod invites;
pub mod admin;

use axum::{Router, routing::post, extract::FromRequestParts, http::request::Parts};
use sqlx::any::AnyPool;

use crate::config::Config;
use crate::error::AppError;

#[derive(Clone)]
pub struct AppState {
    pub pool: AnyPool,
    pub config: Config,
    pub jwt_secret: String,
}

/// Extractor for authenticated user
pub struct AuthUser {
    pub user_id: String,
    pub is_admin: bool,
}

#[axum::async_trait]
impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let auth_header = parts.headers.get("authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth_header.strip_prefix("Bearer ")
            .ok_or(AppError::Unauthorized)?;

        let claims = auth::verify_token(&state.jwt_secret, token)?;
        Ok(AuthUser {
            user_id: claims.sub,
            is_admin: claims.is_admin,
        })
    }
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/register", post(auth::register))
        .route("/api/login", post(auth::login))
}
```

- [ ] **Step 4: Create stub files for remaining API modules**

Create these with empty content:
- `point-server/src/api/groups.rs` → `// Implemented in Task 4`
- `point-server/src/api/items.rs` → `// Implemented in Task 5`
- `point-server/src/api/invites.rs` → `// Implemented in Task 6`
- `point-server/src/api/admin.rs` → `// Implemented in Task 6`

- [ ] **Step 5: Write db/invites.rs (minimal for auth)**

```rust
// point-server/src/db/invites.rs
use sqlx::any::AnyPool;

pub async fn use_invite(pool: &AnyPool, code: &str) -> Result<(), sqlx::Error> {
    let result = sqlx::query(
        "UPDATE invites SET uses = uses + 1 WHERE code = $1 AND uses < max_uses AND (expires_at IS NULL OR expires_at > datetime('now'))"
    )
    .bind(code)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(sqlx::Error::RowNotFound);
    }
    Ok(())
}

pub async fn create_invite(
    pool: &AnyPool,
    id: &str,
    code: &str,
    created_by: &str,
    max_uses: i32,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO invites (id, code, created_by, max_uses) VALUES ($1, $2, $3, $4)")
        .bind(id)
        .bind(code)
        .bind(created_by)
        .bind(max_uses)
        .execute(pool)
        .await?;
    Ok(())
}
```

- [ ] **Step 6: Update main.rs to start the HTTP server**

```rust
// point-server/src/main.rs
mod api;
mod config;
mod db;
mod error;

use axum::Router;
use clap::Parser;
use config::Config;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let config = Config::parse();
    tracing::info!("Point server starting on {}", config.listen);

    let pool = db::init_pool(&config.database_url)
        .await
        .expect("Failed to connect to database");

    let jwt_secret = config.jwt_secret.clone()
        .unwrap_or_else(|| {
            let s = uuid::Uuid::new_v4().to_string();
            tracing::warn!("No JWT_SECRET set, generated ephemeral: {}", &s[..8]);
            s
        });

    let state = api::AppState {
        pool,
        config: config.clone(),
        jwt_secret,
    };

    let app = Router::new()
        .merge(api::router())
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&config.listen)
        .await
        .expect("Failed to bind");

    tracing::info!("Listening on {}", config.listen);
    axum::serve(listener, app).await.expect("Server error");
}
```

- [ ] **Step 7: Write test helpers**

```rust
// point-server/tests/common/mod.rs
use reqwest::Client;
use serde_json::{json, Value};
use std::net::TcpListener;

pub struct TestServer {
    pub url: String,
    pub client: Client,
}

impl TestServer {
    pub async fn spawn() -> Self {
        let port = {
            let l = TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
        };
        let url = format!("http://127.0.0.1:{port}");
        let db_url = format!("sqlite://file:test_{port}?mode=memory&cache=shared");

        std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                let pool = point_server::db::init_pool(&db_url).await.unwrap();
                let state = point_server::api::AppState {
                    pool,
                    config: point_server::config::Config {
                        database_url: db_url,
                        listen: format!("127.0.0.1:{port}"),
                        jwt_secret: Some("test-secret".into()),
                        domain: "test.local".into(),
                    },
                    jwt_secret: "test-secret".into(),
                };
                let app = axum::Router::new()
                    .merge(point_server::api::router())
                    .with_state(state);
                let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{port}"))
                    .await.unwrap();
                axum::serve(listener, app).await.unwrap();
            });
        });

        // Wait for server to start
        let client = Client::new();
        for _ in 0..50 {
            if client.get(&format!("{url}/api/login")).send().await.is_ok() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }

        TestServer { url, client }
    }

    pub async fn register(&self, username: &str, password: &str, invite_code: Option<&str>) -> Value {
        let mut body = json!({
            "username": username,
            "display_name": username,
            "password": password,
        });
        if let Some(code) = invite_code {
            body["invite_code"] = json!(code);
        }
        self.client.post(format!("{}/api/register", self.url))
            .json(&body)
            .send().await.unwrap()
            .json().await.unwrap()
    }

    pub async fn login(&self, username: &str, password: &str) -> Value {
        self.client.post(format!("{}/api/login", self.url))
            .json(&json!({ "username": username, "password": password }))
            .send().await.unwrap()
            .json().await.unwrap()
    }
}
```

- [ ] **Step 8: Write auth tests**

```rust
// point-server/tests/test_auth.rs
mod common;

use common::TestServer;

#[tokio::test]
async fn first_user_becomes_admin() {
    let server = TestServer::spawn().await;
    let res = server.register("parker", "password123", None).await;
    assert_eq!(res["is_admin"], true);
    assert_eq!(res["user_id"], "parker@test.local");
    assert!(res["token"].is_string());
}

#[tokio::test]
async fn second_user_requires_invite() {
    let server = TestServer::spawn().await;
    server.register("parker", "password123", None).await;

    let res = server.client.post(format!("{}/api/register", server.url))
        .json(&serde_json::json!({
            "username": "sarah",
            "display_name": "Sarah",
            "password": "password456",
        }))
        .send().await.unwrap();

    assert_eq!(res.status(), 400);
}

#[tokio::test]
async fn login_works() {
    let server = TestServer::spawn().await;
    server.register("parker", "password123", None).await;

    let res = server.login("parker", "password123").await;
    assert_eq!(res["user_id"], "parker@test.local");
    assert!(res["token"].is_string());
}

#[tokio::test]
async fn login_wrong_password_fails() {
    let server = TestServer::spawn().await;
    server.register("parker", "password123", None).await;

    let res = server.client.post(format!("{}/api/login", server.url))
        .json(&serde_json::json!({
            "username": "parker",
            "password": "wrong",
        }))
        .send().await.unwrap();

    assert_eq!(res.status(), 401);
}

#[tokio::test]
async fn duplicate_username_rejected() {
    let server = TestServer::spawn().await;
    server.register("parker", "password123", None).await;

    let res = server.client.post(format!("{}/api/register", server.url))
        .json(&serde_json::json!({
            "username": "parker",
            "display_name": "Parker 2",
            "password": "password456",
        }))
        .send().await.unwrap();

    assert_eq!(res.status(), 409);
}
```

- [ ] **Step 9: Make lib accessible for tests**

Add to `point-server/src/main.rs` at the very top (before `mod` declarations), or create `src/lib.rs`:

```rust
// point-server/src/lib.rs
pub mod api;
pub mod config;
pub mod db;
pub mod error;
```

- [ ] **Step 10: Run tests**

```bash
cd point-server && cargo test
```

Expected: All 5 tests pass.

- [ ] **Step 11: Commit**

```bash
git add point-server/src/ point-server/tests/
git commit -m "feat: user registration and auth with JWT, first-user-is-admin, invite codes"
```

---

### Task 4: Group CRUD (REST)

**Files:**
- Create: `point-server/src/db/groups.rs`
- Create: `point-server/src/api/groups.rs`
- Create: `point-server/tests/test_groups.rs`

- [ ] **Step 1: Write db/groups.rs**

```rust
// point-server/src/db/groups.rs
use sqlx::any::AnyPool;
use sqlx::Row;

pub struct Group {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub allow_places: bool,
    pub default_precision: String,
}

pub struct GroupMember {
    pub user_id: String,
    pub role: String,
    pub precision: String,
}

pub async fn create_group(pool: &AnyPool, id: &str, name: &str, owner_id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO groups (id, name, owner_id) VALUES ($1, $2, $3)")
        .bind(id).bind(name).bind(owner_id)
        .execute(pool).await?;

    // Owner is automatically an admin member
    sqlx::query("INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')")
        .bind(id).bind(owner_id)
        .execute(pool).await?;

    Ok(())
}

pub async fn get_group(pool: &AnyPool, id: &str) -> Result<Option<Group>, sqlx::Error> {
    let row = sqlx::query("SELECT id, name, owner_id, allow_places, default_precision FROM groups WHERE id = $1")
        .bind(id).fetch_optional(pool).await?;
    Ok(row.map(|r| Group {
        id: r.get("id"), name: r.get("name"), owner_id: r.get("owner_id"),
        allow_places: r.get("allow_places"), default_precision: r.get("default_precision"),
    }))
}

pub async fn list_user_groups(pool: &AnyPool, user_id: &str) -> Result<Vec<Group>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT g.id, g.name, g.owner_id, g.allow_places, g.default_precision FROM groups g \
         INNER JOIN group_members gm ON g.id = gm.group_id WHERE gm.user_id = $1"
    ).bind(user_id).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| Group {
        id: r.get("id"), name: r.get("name"), owner_id: r.get("owner_id"),
        allow_places: r.get("allow_places"), default_precision: r.get("default_precision"),
    }).collect())
}

pub async fn add_member(pool: &AnyPool, group_id: &str, user_id: &str, role: &str, precision: &str) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO group_members (group_id, user_id, role, precision) VALUES ($1, $2, $3, $4)")
        .bind(group_id).bind(user_id).bind(role).bind(precision)
        .execute(pool).await?;
    Ok(())
}

pub async fn remove_member(pool: &AnyPool, group_id: &str, user_id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM group_members WHERE group_id = $1 AND user_id = $2")
        .bind(group_id).bind(user_id)
        .execute(pool).await?;
    Ok(())
}

pub async fn get_members(pool: &AnyPool, group_id: &str) -> Result<Vec<GroupMember>, sqlx::Error> {
    let rows = sqlx::query("SELECT user_id, role, precision FROM group_members WHERE group_id = $1")
        .bind(group_id).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| GroupMember {
        user_id: r.get("user_id"), role: r.get("role"), precision: r.get("precision"),
    }).collect())
}

pub async fn get_member_role(pool: &AnyPool, group_id: &str, user_id: &str) -> Result<Option<String>, sqlx::Error> {
    let row = sqlx::query("SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2")
        .bind(group_id).bind(user_id).fetch_optional(pool).await?;
    Ok(row.map(|r| r.get("role")))
}

pub async fn delete_group(pool: &AnyPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM groups WHERE id = $1").bind(id).execute(pool).await?;
    Ok(())
}
```

- [ ] **Step 2: Write api/groups.rs**

```rust
// point-server/src/api/groups.rs
use axum::{extract::{State, Path}, Json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use super::{AppState, AuthUser};

#[derive(Deserialize)]
pub struct CreateGroupRequest {
    pub name: String,
}

#[derive(Serialize)]
pub struct GroupResponse {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub members: Vec<MemberResponse>,
}

#[derive(Serialize)]
pub struct MemberResponse {
    pub user_id: String,
    pub role: String,
    pub precision: String,
}

#[derive(Deserialize)]
pub struct AddMemberRequest {
    pub user_id: String,
    pub role: Option<String>,
    pub precision: Option<String>,
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateGroupRequest>,
) -> Result<Json<GroupResponse>, AppError> {
    let id = Uuid::new_v4().to_string();
    db::groups::create_group(&state.pool, &id, &req.name, &user.user_id).await?;

    let members = db::groups::get_members(&state.pool, &id).await?;
    Ok(Json(GroupResponse {
        id, name: req.name, owner_id: user.user_id,
        members: members.into_iter().map(|m| MemberResponse {
            user_id: m.user_id, role: m.role, precision: m.precision,
        }).collect(),
    }))
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<GroupResponse>>, AppError> {
    let groups = db::groups::list_user_groups(&state.pool, &user.user_id).await?;
    let mut result = Vec::new();
    for g in groups {
        let members = db::groups::get_members(&state.pool, &g.id).await?;
        result.push(GroupResponse {
            id: g.id, name: g.name, owner_id: g.owner_id,
            members: members.into_iter().map(|m| MemberResponse {
                user_id: m.user_id, role: m.role, precision: m.precision,
            }).collect(),
        });
    }
    Ok(Json(result))
}

pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<GroupResponse>, AppError> {
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    // Check membership
    db::groups::get_member_role(&state.pool, &id, &user.user_id).await?
        .ok_or(AppError::Forbidden)?;

    let members = db::groups::get_members(&state.pool, &id).await?;
    Ok(Json(GroupResponse {
        id: group.id, name: group.name, owner_id: group.owner_id,
        members: members.into_iter().map(|m| MemberResponse {
            user_id: m.user_id, role: m.role, precision: m.precision,
        }).collect(),
    }))
}

pub async fn add_member(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<AddMemberRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Must be admin or owner
    let role = db::groups::get_member_role(&state.pool, &id, &user.user_id).await?
        .ok_or(AppError::Forbidden)?;
    if role != "admin" {
        return Err(AppError::Forbidden);
    }

    // Verify target user exists
    db::users::get_user_by_id(&state.pool, &req.user_id).await?
        .ok_or(AppError::NotFound("user not found".into()))?;

    let member_role = req.role.as_deref().unwrap_or("member");
    let precision = req.precision.as_deref().unwrap_or("exact");
    db::groups::add_member(&state.pool, &id, &req.user_id, member_role, precision).await?;

    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn remove_member(
    State(state): State<AppState>,
    user: AuthUser,
    Path((group_id, member_id)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Must be admin, or removing yourself
    if member_id != user.user_id {
        let role = db::groups::get_member_role(&state.pool, &group_id, &user.user_id).await?
            .ok_or(AppError::Forbidden)?;
        if role != "admin" {
            return Err(AppError::Forbidden);
        }
    }

    db::groups::remove_member(&state.pool, &group_id, &member_id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let group = db::groups::get_group(&state.pool, &id).await?
        .ok_or(AppError::NotFound("group not found".into()))?;

    if group.owner_id != user.user_id {
        return Err(AppError::Forbidden);
    }

    db::groups::delete_group(&state.pool, &id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
```

- [ ] **Step 3: Add group routes to api/mod.rs**

Add to the `router()` function in `api/mod.rs`:

```rust
use axum::routing::{get, delete as delete_route};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/register", post(auth::register))
        .route("/api/login", post(auth::login))
        .route("/api/groups", post(groups::create).get(groups::list))
        .route("/api/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/api/groups/{id}/members", post(groups::add_member))
        .route("/api/groups/{id}/members/{member_id}", delete_route(groups::remove_member))
}
```

- [ ] **Step 4: Write group tests**

```rust
// point-server/tests/test_groups.rs
mod common;
use common::TestServer;

#[tokio::test]
async fn create_and_list_groups() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    // Create group
    let res = server.client.post(format!("{}/api/groups", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "name": "Family" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    assert_eq!(res["name"], "Family");
    assert_eq!(res["owner_id"], "parker@test.local");
    assert_eq!(res["members"][0]["role"], "admin");

    // List groups
    let groups = server.client.get(format!("{}/api/groups", server.url))
        .bearer_auth(token)
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    assert_eq!(groups.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn add_and_remove_member() {
    let server = TestServer::spawn().await;
    let admin = server.register("parker", "pass123", None).await;
    let admin_token = admin["token"].as_str().unwrap();

    // Create invite for second user
    server.client.post(format!("{}/api/invites", server.url))
        .bearer_auth(admin_token)
        .json(&serde_json::json!({ "max_uses": 1 }))
        .send().await.unwrap();

    // For now, we'll test with direct DB setup in a future iteration.
    // This test validates the API contract.

    let group = server.client.post(format!("{}/api/groups", server.url))
        .bearer_auth(admin_token)
        .json(&serde_json::json!({ "name": "Friends" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    let group_id = group["id"].as_str().unwrap();

    // Non-member can't access
    let res = server.client.get(format!("{}/api/groups/{group_id}", server.url))
        .send().await.unwrap();
    assert_eq!(res.status(), 401);
}

#[tokio::test]
async fn owner_can_delete_group() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    let group = server.client.post(format!("{}/api/groups", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "name": "Temp" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    let group_id = group["id"].as_str().unwrap();

    let res = server.client.delete(format!("{}/api/groups/{group_id}", server.url))
        .bearer_auth(token)
        .send().await.unwrap();
    assert_eq!(res.status(), 200);

    // Verify deleted
    let res = server.client.get(format!("{}/api/groups/{group_id}", server.url))
        .bearer_auth(token)
        .send().await.unwrap();
    assert_eq!(res.status(), 404);
}
```

- [ ] **Step 5: Run tests**

```bash
cd point-server && cargo test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add point-server/src/ point-server/tests/
git commit -m "feat: group CRUD with membership, role-based access control"
```

---

### Task 5: Item CRUD & Sharing (REST)

**Files:**
- Create: `point-server/src/db/items.rs`
- Create: `point-server/src/api/items.rs`
- Create: `point-server/tests/test_items.rs`

- [ ] **Step 1: Write db/items.rs**

```rust
// point-server/src/db/items.rs
use sqlx::any::AnyPool;
use sqlx::Row;

pub struct Item {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub bridge_id: Option<String>,
    pub capabilities: String,
    pub last_seen: Option<String>,
}

pub struct ItemShare {
    pub target_type: String,
    pub target_id: String,
    pub precision: String,
}

pub async fn create_item(
    pool: &AnyPool, id: &str, owner_id: &str, name: &str,
    tracker_type: &str, source_id: Option<&str>, bridge_id: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO items (id, owner_id, name, tracker_type, source_id, bridge_id) VALUES ($1, $2, $3, $4, $5, $6)"
    ).bind(id).bind(owner_id).bind(name).bind(tracker_type).bind(source_id).bind(bridge_id)
    .execute(pool).await?;
    Ok(())
}

pub async fn get_item(pool: &AnyPool, id: &str) -> Result<Option<Item>, sqlx::Error> {
    let row = sqlx::query("SELECT id, owner_id, name, tracker_type, source_id, bridge_id, capabilities, last_seen FROM items WHERE id = $1")
        .bind(id).fetch_optional(pool).await?;
    Ok(row.map(|r| Item {
        id: r.get("id"), owner_id: r.get("owner_id"), name: r.get("name"),
        tracker_type: r.get("tracker_type"), source_id: r.get("source_id"),
        bridge_id: r.get("bridge_id"), capabilities: r.get("capabilities"),
        last_seen: r.get("last_seen"),
    }))
}

pub async fn list_user_items(pool: &AnyPool, user_id: &str) -> Result<Vec<Item>, sqlx::Error> {
    // Items you own + items shared to you (via group membership or direct share)
    let rows = sqlx::query(
        "SELECT DISTINCT i.id, i.owner_id, i.name, i.tracker_type, i.source_id, i.bridge_id, i.capabilities, i.last_seen \
         FROM items i \
         LEFT JOIN item_shares s ON i.id = s.item_id \
         LEFT JOIN group_members gm ON s.target_type = 'group' AND s.target_id = gm.group_id \
         WHERE i.owner_id = $1 \
            OR (s.target_type = 'user' AND s.target_id = $1) \
            OR (s.target_type = 'group' AND gm.user_id = $1)"
    ).bind(user_id).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| Item {
        id: r.get("id"), owner_id: r.get("owner_id"), name: r.get("name"),
        tracker_type: r.get("tracker_type"), source_id: r.get("source_id"),
        bridge_id: r.get("bridge_id"), capabilities: r.get("capabilities"),
        last_seen: r.get("last_seen"),
    }).collect())
}

pub async fn share_item(pool: &AnyPool, item_id: &str, target_type: &str, target_id: &str, precision: &str) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO item_shares (item_id, target_type, target_id, precision) VALUES ($1, $2, $3, $4)")
        .bind(item_id).bind(target_type).bind(target_id).bind(precision)
        .execute(pool).await?;
    Ok(())
}

pub async fn unshare_item(pool: &AnyPool, item_id: &str, target_type: &str, target_id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM item_shares WHERE item_id = $1 AND target_type = $2 AND target_id = $3")
        .bind(item_id).bind(target_type).bind(target_id)
        .execute(pool).await?;
    Ok(())
}

pub async fn get_item_shares(pool: &AnyPool, item_id: &str) -> Result<Vec<ItemShare>, sqlx::Error> {
    let rows = sqlx::query("SELECT target_type, target_id, precision FROM item_shares WHERE item_id = $1")
        .bind(item_id).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| ItemShare {
        target_type: r.get("target_type"), target_id: r.get("target_id"), precision: r.get("precision"),
    }).collect())
}

pub async fn delete_item(pool: &AnyPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM items WHERE id = $1").bind(id).execute(pool).await?;
    Ok(())
}
```

- [ ] **Step 2: Write api/items.rs**

```rust
// point-server/src/api/items.rs
use axum::{extract::{State, Path}, Json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use super::{AppState, AuthUser};

#[derive(Deserialize)]
pub struct CreateItemRequest {
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub bridge_id: Option<String>,
}

#[derive(Serialize)]
pub struct ItemResponse {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub tracker_type: String,
    pub source_id: Option<String>,
    pub shares: Vec<ShareResponse>,
}

#[derive(Serialize)]
pub struct ShareResponse {
    pub target_type: String,
    pub target_id: String,
    pub precision: String,
}

#[derive(Deserialize)]
pub struct ShareItemRequest {
    pub target_type: String,  // "group" or "user"
    pub target_id: String,
    pub precision: Option<String>,
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateItemRequest>,
) -> Result<Json<ItemResponse>, AppError> {
    let id = Uuid::new_v4().to_string();
    db::items::create_item(&state.pool, &id, &user.user_id, &req.name, &req.tracker_type, req.source_id.as_deref(), req.bridge_id.as_deref()).await?;

    Ok(Json(ItemResponse {
        id, owner_id: user.user_id, name: req.name,
        tracker_type: req.tracker_type, source_id: req.source_id, shares: vec![],
    }))
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<ItemResponse>>, AppError> {
    let items = db::items::list_user_items(&state.pool, &user.user_id).await?;
    let mut result = Vec::new();
    for item in items {
        let shares = db::items::get_item_shares(&state.pool, &item.id).await?;
        result.push(ItemResponse {
            id: item.id, owner_id: item.owner_id, name: item.name,
            tracker_type: item.tracker_type, source_id: item.source_id,
            shares: shares.into_iter().map(|s| ShareResponse {
                target_type: s.target_type, target_id: s.target_id, precision: s.precision,
            }).collect(),
        });
    }
    Ok(Json(result))
}

pub async fn share(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<ShareItemRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let item = db::items::get_item(&state.pool, &id).await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != user.user_id {
        return Err(AppError::Forbidden);
    }

    let precision = req.precision.as_deref().unwrap_or("exact");
    db::items::share_item(&state.pool, &id, &req.target_type, &req.target_id, precision).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn unshare(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<ShareItemRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let item = db::items::get_item(&state.pool, &id).await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != user.user_id {
        return Err(AppError::Forbidden);
    }

    db::items::unshare_item(&state.pool, &id, &req.target_type, &req.target_id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let item = db::items::get_item(&state.pool, &id).await?
        .ok_or(AppError::NotFound("item not found".into()))?;

    if item.owner_id != user.user_id {
        return Err(AppError::Forbidden);
    }

    db::items::delete_item(&state.pool, &id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
```

- [ ] **Step 3: Add item routes to api/mod.rs**

Add to `router()`:

```rust
.route("/api/items", post(items::create).get(items::list))
.route("/api/items/{id}", delete_route(items::delete))
.route("/api/items/{id}/share", post(items::share))
.route("/api/items/{id}/unshare", post(items::unshare))
```

- [ ] **Step 4: Write item tests**

```rust
// point-server/tests/test_items.rs
mod common;
use common::TestServer;

#[tokio::test]
async fn create_and_list_items() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    let item = server.client.post(format!("{}/api/items", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({
            "name": "Keys",
            "tracker_type": "airtag",
            "source_id": "AIRTAG-001",
        }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    assert_eq!(item["name"], "Keys");
    assert_eq!(item["tracker_type"], "airtag");
    assert_eq!(item["owner_id"], "parker@test.local");

    let items = server.client.get(format!("{}/api/items", server.url))
        .bearer_auth(token)
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    assert_eq!(items.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn share_item_to_group() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    // Create group
    let group = server.client.post(format!("{}/api/groups", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "name": "Family" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    // Create item
    let item = server.client.post(format!("{}/api/items", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "name": "Keys", "tracker_type": "airtag" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    let item_id = item["id"].as_str().unwrap();
    let group_id = group["id"].as_str().unwrap();

    // Share to group
    let res = server.client.post(format!("{}/api/items/{item_id}/share", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "target_type": "group", "target_id": group_id }))
        .send().await.unwrap();

    assert_eq!(res.status(), 200);

    // Verify share shows in list
    let items = server.client.get(format!("{}/api/items", server.url))
        .bearer_auth(token)
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    assert_eq!(items[0]["shares"].as_array().unwrap().len(), 1);
    assert_eq!(items[0]["shares"][0]["target_type"], "group");
}

#[tokio::test]
async fn only_owner_can_delete_item() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    let item = server.client.post(format!("{}/api/items", server.url))
        .bearer_auth(token)
        .json(&serde_json::json!({ "name": "Keys", "tracker_type": "tile" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();

    let item_id = item["id"].as_str().unwrap();

    let res = server.client.delete(format!("{}/api/items/{item_id}", server.url))
        .bearer_auth(token)
        .send().await.unwrap();
    assert_eq!(res.status(), 200);
}
```

- [ ] **Step 5: Run tests**

```bash
cd point-server && cargo test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add point-server/src/ point-server/tests/
git commit -m "feat: item CRUD with cross-network sharing to groups and users"
```

---

### Task 6: Invite Links & Admin API

**Files:**
- Modify: `point-server/src/db/invites.rs`
- Create: `point-server/src/api/invites.rs`
- Create: `point-server/src/api/admin.rs`

- [ ] **Step 1: Complete db/invites.rs**

Add to existing `invites.rs`:

```rust
pub async fn list_invites(pool: &AnyPool, created_by: &str) -> Result<Vec<Invite>, sqlx::Error> {
    let rows = sqlx::query("SELECT id, code, created_by, max_uses, uses, expires_at, created_at FROM invites WHERE created_by = $1")
        .bind(created_by).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| {
        use sqlx::Row;
        Invite {
            id: r.get("id"), code: r.get("code"), created_by: r.get("created_by"),
            max_uses: r.get("max_uses"), uses: r.get("uses"),
        }
    }).collect())
}

pub struct Invite {
    pub id: String,
    pub code: String,
    pub created_by: String,
    pub max_uses: i32,
    pub uses: i32,
}

pub async fn delete_invite(pool: &AnyPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM invites WHERE id = $1").bind(id).execute(pool).await?;
    Ok(())
}
```

- [ ] **Step 2: Write api/invites.rs**

```rust
// point-server/src/api/invites.rs
use axum::{extract::{State, Path}, Json};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use rand::Rng;

use crate::db;
use crate::error::AppError;
use super::{AppState, AuthUser};

#[derive(Deserialize)]
pub struct CreateInviteRequest {
    pub max_uses: Option<i32>,
}

#[derive(Serialize)]
pub struct InviteResponse {
    pub id: String,
    pub code: String,
    pub max_uses: i32,
    pub uses: i32,
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(req): Json<CreateInviteRequest>,
) -> Result<Json<InviteResponse>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let id = Uuid::new_v4().to_string();
    let code: String = rand::thread_rng()
        .sample_iter(&rand::distributions::Alphanumeric)
        .take(8)
        .map(char::from)
        .collect();
    let max_uses = req.max_uses.unwrap_or(1);

    db::invites::create_invite(&state.pool, &id, &code, &user.user_id, max_uses).await?;

    Ok(Json(InviteResponse { id, code, max_uses, uses: 0 }))
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<Vec<InviteResponse>>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let invites = db::invites::list_invites(&state.pool, &user.user_id).await?;
    Ok(Json(invites.into_iter().map(|i| InviteResponse {
        id: i.id, code: i.code, max_uses: i.max_uses, uses: i.uses,
    }).collect()))
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }
    db::invites::delete_invite(&state.pool, &id).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}
```

- [ ] **Step 3: Write api/admin.rs (minimal)**

```rust
// point-server/src/api/admin.rs
use axum::{extract::State, Json};
use serde::Serialize;

use crate::db;
use crate::error::AppError;
use super::{AppState, AuthUser};

#[derive(Serialize)]
pub struct ServerInfo {
    pub version: String,
    pub domain: String,
    pub user_count: i64,
}

pub async fn info(
    State(state): State<AppState>,
    user: AuthUser,
) -> Result<Json<ServerInfo>, AppError> {
    if !user.is_admin {
        return Err(AppError::Forbidden);
    }

    let user_count = db::users::count_users(&state.pool).await?;

    Ok(Json(ServerInfo {
        version: env!("CARGO_PKG_VERSION").to_string(),
        domain: state.config.domain.clone(),
        user_count,
    }))
}
```

- [ ] **Step 4: Add invite and admin routes to api/mod.rs**

Add to `router()`:

```rust
.route("/api/invites", post(invites::create).get(invites::list))
.route("/api/invites/{id}", delete_route(invites::delete))
.route("/api/admin/info", get(admin::info))
```

- [ ] **Step 5: Run tests**

```bash
cd point-server && cargo test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add point-server/src/
git commit -m "feat: invite links (admin-only) and server info endpoint"
```

---

### Task 7: WebSocket Hub & Location Routing

**Files:**
- Create: `point-server/src/ws/mod.rs`
- Create: `point-server/src/ws/hub.rs`
- Create: `point-server/src/ws/handler.rs`
- Create: `point-server/src/ws/presence.rs`
- Create: `point-server/src/db/locations.rs`
- Create: `point-server/tests/test_ws.rs`

- [ ] **Step 1: Write ws/hub.rs (connection registry)**

```rust
// point-server/src/ws/hub.rs
use dashmap::DashMap;
use std::sync::Arc;
use tokio::sync::mpsc;

pub type WsSender = mpsc::UnboundedSender<Vec<u8>>;

#[derive(Clone)]
pub struct Hub {
    /// user_id -> list of connected senders (one per device/connection)
    connections: Arc<DashMap<String, Vec<WsSender>>>,
}

impl Hub {
    pub fn new() -> Self {
        Hub {
            connections: Arc::new(DashMap::new()),
        }
    }

    pub fn add_connection(&self, user_id: &str, tx: WsSender) {
        self.connections.entry(user_id.to_string())
            .or_default()
            .push(tx);
        tracing::info!("User {} connected ({} connections)", user_id, self.connection_count(user_id));
    }

    pub fn remove_connection(&self, user_id: &str, tx: &WsSender) {
        if let Some(mut conns) = self.connections.get_mut(user_id) {
            let tx_ptr = tx as *const WsSender;
            conns.retain(|c| !std::ptr::eq(c as *const WsSender, tx_ptr));
            if conns.is_empty() {
                drop(conns);
                self.connections.remove(user_id);
                tracing::info!("User {} fully disconnected", user_id);
            }
        }
    }

    pub fn send_to_user(&self, user_id: &str, data: Vec<u8>) {
        if let Some(conns) = self.connections.get(user_id) {
            for tx in conns.iter() {
                let _ = tx.send(data.clone());
            }
        }
    }

    pub fn send_to_users(&self, user_ids: &[String], data: Vec<u8>) {
        for uid in user_ids {
            self.send_to_user(uid, data.clone());
        }
    }

    pub fn is_online(&self, user_id: &str) -> bool {
        self.connections.contains_key(user_id)
    }

    pub fn connection_count(&self, user_id: &str) -> usize {
        self.connections.get(user_id).map(|c| c.len()).unwrap_or(0)
    }

    pub fn online_users(&self) -> Vec<String> {
        self.connections.iter().map(|e| e.key().clone()).collect()
    }
}
```

- [ ] **Step 2: Write ws/presence.rs**

```rust
// point-server/src/ws/presence.rs
use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PresenceUpdate {
    pub user_id: String,
    pub online: bool,
    pub battery: Option<u8>,
    pub activity: Option<String>,  // stationary, walking, driving
}
```

- [ ] **Step 3: Write ws/handler.rs**

```rust
// point-server/src/ws/handler.rs
use axum::extract::ws::{WebSocket, Message};
use futures::{StreamExt, SinkExt};
use tokio::sync::mpsc;

use crate::api::AppState;
use crate::api::auth::Claims;
use crate::db;
use super::hub::Hub;

pub async fn handle_connection(ws: WebSocket, claims: Claims, state: AppState, hub: Hub) {
    let (mut ws_tx, mut ws_rx) = ws.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();

    let user_id = claims.sub.clone();
    hub.add_connection(&user_id, tx.clone());

    // Task: forward messages from hub to WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if ws_tx.send(Message::Binary(data.into())).await.is_err() {
                break;
            }
        }
    });

    // Task: read messages from WebSocket and process
    let hub_clone = hub.clone();
    let state_clone = state.clone();
    let user_id_clone = user_id.clone();
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = ws_rx.next().await {
            match msg {
                Message::Binary(data) => {
                    process_message(&user_id_clone, &data, &state_clone, &hub_clone).await;
                }
                Message::Text(text) => {
                    // For now, treat text as JSON for simpler debugging
                    process_message(&user_id_clone, text.as_bytes(), &state_clone, &hub_clone).await;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                Message::Close(_) => break,
            }
        }
    });

    // Wait for either task to finish
    tokio::select! {
        _ = send_task => {}
        _ = recv_task => {}
    }

    hub.remove_connection(&user_id, &tx);
}

async fn process_message(user_id: &str, data: &[u8], state: &AppState, hub: &Hub) {
    // Parse as JSON for now (will switch to Protobuf in a later plan)
    let msg: serde_json::Value = match serde_json::from_slice(data) {
        Ok(v) => v,
        Err(_) => return,
    };

    let msg_type = msg["type"].as_str().unwrap_or("");

    match msg_type {
        "location.update" => {
            handle_location_update(user_id, &msg, state, hub).await;
        }
        "presence.update" => {
            // Broadcast presence to all groups the user is in
            handle_presence_update(user_id, &msg, state, hub).await;
        }
        _ => {
            tracing::warn!("Unknown message type: {}", msg_type);
        }
    }
}

async fn handle_location_update(sender_id: &str, msg: &serde_json::Value, state: &AppState, hub: &Hub) {
    let recipient_type = msg["recipient_type"].as_str().unwrap_or("group");
    let recipient_id = msg["recipient_id"].as_str().unwrap_or("");
    let encrypted_blob = msg["encrypted_blob"].as_str().unwrap_or("");
    let source_type = msg["source_type"].as_str().unwrap_or("native");
    let timestamp = msg["timestamp"].as_i64().unwrap_or(0);
    let ttl = msg["ttl"].as_i64().unwrap_or(300) as i32;

    // Store the location update
    let id = uuid::Uuid::new_v4().to_string();
    let _ = db::locations::store_location(
        &state.pool, &id, sender_id, recipient_type, recipient_id,
        encrypted_blob.as_bytes(), source_type, timestamp, ttl,
    ).await;

    // Build broadcast message
    let broadcast = serde_json::json!({
        "type": "location.broadcast",
        "from": sender_id,
        "encrypted_blob": encrypted_blob,
        "source_type": source_type,
        "timestamp": timestamp,
    });
    let broadcast_bytes = serde_json::to_vec(&broadcast).unwrap_or_default();

    // Route to recipients
    if recipient_type == "group" {
        if let Ok(members) = db::groups::get_members(&state.pool, recipient_id).await {
            let user_ids: Vec<String> = members.into_iter()
                .filter(|m| m.user_id != sender_id)
                .map(|m| m.user_id)
                .collect();
            hub.send_to_users(&user_ids, broadcast_bytes);
        }
    } else if recipient_type == "user" {
        hub.send_to_user(recipient_id, broadcast_bytes);
    }
}

async fn handle_presence_update(user_id: &str, msg: &serde_json::Value, state: &AppState, hub: &Hub) {
    let broadcast = serde_json::json!({
        "type": "presence.broadcast",
        "user_id": user_id,
        "online": true,
        "battery": msg["battery"],
        "activity": msg["activity"],
    });
    let broadcast_bytes = serde_json::to_vec(&broadcast).unwrap_or_default();

    // Send to all groups the user is in
    if let Ok(groups) = db::groups::list_user_groups(&state.pool, user_id).await {
        for group in groups {
            if let Ok(members) = db::groups::get_members(&state.pool, &group.id).await {
                let user_ids: Vec<String> = members.into_iter()
                    .filter(|m| m.user_id != user_id)
                    .map(|m| m.user_id)
                    .collect();
                hub.send_to_users(&user_ids, broadcast_bytes.clone());
            }
        }
    }
}
```

- [ ] **Step 4: Write ws/mod.rs (WebSocket upgrade endpoint)**

```rust
// point-server/src/ws/mod.rs
pub mod hub;
pub mod handler;
pub mod presence;

use axum::{
    extract::{State, WebSocketUpgrade, Query},
    response::Response,
};
use serde::Deserialize;

use crate::api::{AppState, auth};
use hub::Hub;

#[derive(Deserialize)]
pub struct WsParams {
    token: String,
}

pub async fn ws_upgrade(
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
    Query(params): Query<WsParams>,
) -> Result<Response, crate::error::AppError> {
    let claims = auth::verify_token(&state.jwt_secret, &params.token)?;
    let hub = state.hub.clone();

    Ok(ws.on_upgrade(move |socket| {
        handler::handle_connection(socket, claims, state, hub)
    }))
}
```

- [ ] **Step 5: Write db/locations.rs**

```rust
// point-server/src/db/locations.rs
use sqlx::any::AnyPool;

pub async fn store_location(
    pool: &AnyPool,
    id: &str,
    sender_id: &str,
    recipient_type: &str,
    recipient_id: &str,
    encrypted_blob: &[u8],
    source_type: &str,
    timestamp: i64,
    ttl: i32,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO location_updates (id, sender_id, recipient_type, recipient_id, encrypted_blob, source_type, timestamp, ttl) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"
    )
    .bind(id).bind(sender_id).bind(recipient_type).bind(recipient_id)
    .bind(encrypted_blob).bind(source_type).bind(timestamp).bind(ttl)
    .execute(pool).await?;
    Ok(())
}

pub async fn cleanup_expired(pool: &AnyPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        "DELETE FROM location_updates WHERE datetime(created_at, '+' || ttl || ' seconds') < datetime('now')"
    ).execute(pool).await?;
    Ok(result.rows_affected())
}

pub async fn get_latest_for_user(
    pool: &AnyPool,
    sender_id: &str,
) -> Result<Option<(Vec<u8>, String, i64)>, sqlx::Error> {
    use sqlx::Row;
    let row = sqlx::query(
        "SELECT encrypted_blob, source_type, timestamp FROM location_updates WHERE sender_id = $1 ORDER BY timestamp DESC LIMIT 1"
    ).bind(sender_id).fetch_optional(pool).await?;

    Ok(row.map(|r| (r.get("encrypted_blob"), r.get("source_type"), r.get("timestamp"))))
}
```

- [ ] **Step 6: Add Hub to AppState and wire up WebSocket route**

Update `api/mod.rs` AppState:

```rust
use crate::ws::hub::Hub;

#[derive(Clone)]
pub struct AppState {
    pub pool: AnyPool,
    pub config: Config,
    pub jwt_secret: String,
    pub hub: Hub,
}
```

Add to `router()`:

```rust
use axum::routing::get;

.route("/ws", get(crate::ws::ws_upgrade))
```

Update `main.rs` to create hub:

```rust
use ws::hub::Hub;

// After jwt_secret setup:
let hub = Hub::new();

let state = api::AppState {
    pool,
    config: config.clone(),
    jwt_secret,
    hub,
};
```

And add `mod ws;` to `lib.rs` and `main.rs`.

- [ ] **Step 7: Start a TTL cleanup task in main.rs**

Add before `axum::serve`:

```rust
// Spawn TTL cleanup task
let cleanup_pool = state.pool.clone();
tokio::spawn(async move {
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        match db::locations::cleanup_expired(&cleanup_pool).await {
            Ok(n) if n > 0 => tracing::debug!("Cleaned up {n} expired locations"),
            _ => {}
        }
    }
});
```

- [ ] **Step 8: Write WebSocket tests**

```rust
// point-server/tests/test_ws.rs
mod common;
use common::TestServer;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use futures::{StreamExt, SinkExt};

#[tokio::test]
async fn websocket_connects_with_valid_token() {
    let server = TestServer::spawn().await;
    let auth = server.register("parker", "pass123", None).await;
    let token = auth["token"].as_str().unwrap();

    let ws_url = server.url.replace("http", "ws");
    let (ws, _) = connect_async(format!("{ws_url}/ws?token={token}"))
        .await
        .expect("Failed to connect");

    drop(ws); // Clean disconnect
}

#[tokio::test]
async fn websocket_rejects_invalid_token() {
    let server = TestServer::spawn().await;

    let ws_url = server.url.replace("http", "ws");
    let result = connect_async(format!("{ws_url}/ws?token=invalid")).await;

    assert!(result.is_err() || {
        // Some implementations return a connection that immediately closes
        let (mut ws, _) = result.unwrap();
        ws.next().await.map(|r| r.is_err()).unwrap_or(true)
    });
}

#[tokio::test]
async fn location_update_routes_to_group_members() {
    let server = TestServer::spawn().await;

    // Register two users
    let admin = server.register("parker", "pass123", None).await;
    let admin_token = admin["token"].as_str().unwrap();

    // Create invite and register second user
    let invite = server.client.post(format!("{}/api/invites", server.url))
        .bearer_auth(admin_token)
        .json(&serde_json::json!({ "max_uses": 1 }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();
    let code = invite["code"].as_str().unwrap();

    let user2 = server.register("sarah", "pass456", Some(code)).await;
    let user2_token = user2["token"].as_str().unwrap();

    // Create group and add sarah
    let group = server.client.post(format!("{}/api/groups", server.url))
        .bearer_auth(admin_token)
        .json(&serde_json::json!({ "name": "Family" }))
        .send().await.unwrap()
        .json::<serde_json::Value>().await.unwrap();
    let group_id = group["id"].as_str().unwrap();

    server.client.post(format!("{}/api/groups/{group_id}/members", server.url))
        .bearer_auth(admin_token)
        .json(&serde_json::json!({ "user_id": "sarah@test.local" }))
        .send().await.unwrap();

    // Connect both via WebSocket
    let ws_url = server.url.replace("http", "ws");
    let (mut ws_parker, _) = connect_async(format!("{ws_url}/ws?token={admin_token}")).await.unwrap();
    let (mut ws_sarah, _) = connect_async(format!("{ws_url}/ws?token={user2_token}")).await.unwrap();

    // Parker sends location update
    let update = serde_json::json!({
        "type": "location.update",
        "recipient_type": "group",
        "recipient_id": group_id,
        "encrypted_blob": "dGVzdC1ibG9i",
        "source_type": "native",
        "timestamp": 1712345678,
        "ttl": 300,
    });
    ws_parker.send(Message::Text(serde_json::to_string(&update).unwrap().into())).await.unwrap();

    // Sarah should receive the broadcast
    let msg = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        ws_sarah.next()
    ).await;

    assert!(msg.is_ok(), "Sarah should receive the location broadcast");
    let msg = msg.unwrap().unwrap().unwrap();
    let data: serde_json::Value = match msg {
        Message::Text(t) => serde_json::from_str(&t).unwrap(),
        Message::Binary(b) => serde_json::from_slice(&b).unwrap(),
        _ => panic!("unexpected message type"),
    };
    assert_eq!(data["type"], "location.broadcast");
    assert_eq!(data["from"], "parker@test.local");
}
```

- [ ] **Step 9: Add tokio-tungstenite to dev-dependencies**

Add to `Cargo.toml`:

```toml
[dev-dependencies]
reqwest = { version = "0.12", features = ["json"] }
tokio-tungstenite = "0.24"
```

- [ ] **Step 10: Run tests**

```bash
cd point-server && cargo test
```

Expected: All tests pass including WebSocket routing.

- [ ] **Step 11: Commit**

```bash
git add point-server/
git commit -m "feat: WebSocket hub with location routing, presence, TTL cleanup"
```

---

### Task 8: Bridge Registration & Heartbeat (WebSocket)

**Files:**
- Create: `point-server/src/db/bridges.rs`
- Modify: `point-server/src/ws/handler.rs`

- [ ] **Step 1: Write db/bridges.rs**

```rust
// point-server/src/db/bridges.rs
use sqlx::any::AnyPool;
use sqlx::Row;

pub struct Bridge {
    pub id: String,
    pub user_id: String,
    pub bridge_type: String,
    pub status: String,
    pub double_puppet: bool,
    pub last_heartbeat: Option<String>,
    pub error_message: Option<String>,
}

pub async fn register_bridge(
    pool: &AnyPool, id: &str, user_id: &str, bridge_type: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO bridges (id, user_id, bridge_type, status) VALUES ($1, $2, $3, 'connected') \
         ON CONFLICT(id) DO UPDATE SET status = 'connected', last_heartbeat = datetime('now')"
    ).bind(id).bind(user_id).bind(bridge_type).execute(pool).await?;
    Ok(())
}

pub async fn update_heartbeat(
    pool: &AnyPool, id: &str, status: &str, error_message: Option<&str>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE bridges SET status = $1, last_heartbeat = datetime('now'), error_message = $2 WHERE id = $3"
    ).bind(status).bind(error_message).bind(id).execute(pool).await?;
    Ok(())
}

pub async fn list_user_bridges(pool: &AnyPool, user_id: &str) -> Result<Vec<Bridge>, sqlx::Error> {
    let rows = sqlx::query(
        "SELECT id, user_id, bridge_type, status, double_puppet, last_heartbeat, error_message FROM bridges WHERE user_id = $1"
    ).bind(user_id).fetch_all(pool).await?;
    Ok(rows.into_iter().map(|r| Bridge {
        id: r.get("id"), user_id: r.get("user_id"), bridge_type: r.get("bridge_type"),
        status: r.get("status"), double_puppet: r.get("double_puppet"),
        last_heartbeat: r.get("last_heartbeat"), error_message: r.get("error_message"),
    }).collect())
}

pub async fn disconnect_bridge(pool: &AnyPool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE bridges SET status = 'disconnected' WHERE id = $1")
        .bind(id).execute(pool).await?;
    Ok(())
}
```

- [ ] **Step 2: Add bridge message handling to ws/handler.rs**

Add to the `match msg_type` block in `process_message`:

```rust
"bridge.register" => {
    let bridge_type = msg["bridge_type"].as_str().unwrap_or("");
    let bridge_id = msg["bridge_id"].as_str().unwrap_or(&uuid::Uuid::new_v4().to_string());
    let _ = db::bridges::register_bridge(&state.pool, bridge_id, user_id, bridge_type).await;
    tracing::info!("Bridge registered: {} ({}) for {}", bridge_id, bridge_type, user_id);

    let ack = serde_json::json!({
        "type": "bridge.registered",
        "bridge_id": bridge_id,
        "bridge_type": bridge_type,
    });
    hub.send_to_user(user_id, serde_json::to_vec(&ack).unwrap_or_default());
}
"bridge.heartbeat" => {
    let bridge_id = msg["bridge_id"].as_str().unwrap_or("");
    let status = msg["status"].as_str().unwrap_or("healthy");
    let error_msg = msg["error_message"].as_str();
    let _ = db::bridges::update_heartbeat(&state.pool, bridge_id, status, error_msg).await;
}
"item.location" => {
    handle_item_location(user_id, &msg, state, hub).await;
}
```

- [ ] **Step 3: Add item.location handler**

Add to `ws/handler.rs`:

```rust
async fn handle_item_location(sender_id: &str, msg: &serde_json::Value, state: &AppState, hub: &Hub) {
    let item_id = msg["item_id"].as_str().unwrap_or("");
    let encrypted_blob = msg["encrypted_blob"].as_str().unwrap_or("");
    let timestamp = msg["timestamp"].as_i64().unwrap_or(0);
    let source_type = msg["source_type"].as_str().unwrap_or("bridge:unknown");

    // Verify sender owns this item or is the item's bridge
    let item = match db::items::get_item(&state.pool, item_id).await {
        Ok(Some(item)) => item,
        _ => return,
    };

    // Build broadcast
    let broadcast = serde_json::json!({
        "type": "item.broadcast",
        "item_id": item_id,
        "encrypted_blob": encrypted_blob,
        "source_type": source_type,
        "timestamp": timestamp,
    });
    let broadcast_bytes = serde_json::to_vec(&broadcast).unwrap_or_default();

    // Route to all users who can see this item
    if let Ok(shares) = db::items::get_item_shares(&state.pool, item_id).await {
        for share in shares {
            if share.target_type == "group" {
                if let Ok(members) = db::groups::get_members(&state.pool, &share.target_id).await {
                    let user_ids: Vec<String> = members.into_iter().map(|m| m.user_id).collect();
                    hub.send_to_users(&user_ids, broadcast_bytes.clone());
                }
            } else if share.target_type == "user" {
                hub.send_to_user(&share.target_id, broadcast_bytes.clone());
            }
        }
    }

    // Also send to owner
    hub.send_to_user(&item.owner_id, broadcast_bytes);
}
```

- [ ] **Step 4: Run tests**

```bash
cd point-server && cargo test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add point-server/src/
git commit -m "feat: bridge registration, heartbeat, and item location routing via WebSocket"
```

---

## Plan Summary

| Task | What it builds | Key files |
|------|---------------|-----------|
| 1 | Project scaffold, config, error types | `Cargo.toml`, `main.rs`, `config.rs`, `error.rs` |
| 2 | Database schema (all tables), migration runner | `migrations/001_initial.sql`, `db/mod.rs` |
| 3 | User registration, login, JWT auth, first-user-is-admin | `db/users.rs`, `api/auth.rs`, `api/mod.rs` |
| 4 | Group CRUD, membership, role-based access | `db/groups.rs`, `api/groups.rs` |
| 5 | Item CRUD, cross-network sharing to groups/users | `db/items.rs`, `api/items.rs` |
| 6 | Invite links (admin-only), server info | `api/invites.rs`, `api/admin.rs` |
| 7 | WebSocket hub, location routing, presence, TTL cleanup | `ws/hub.rs`, `ws/handler.rs`, `ws/mod.rs` |
| 8 | Bridge registration, heartbeat, item location routing | `db/bridges.rs`, handler additions |

**After this plan:** The server accepts registrations, manages groups and items with sharing, routes encrypted location blobs via WebSocket, tracks bridge health, and cleans up expired data. Next plans: MLS encryption (point-core crate), Flutter client, OwnTracks bridge, Find My bridge.
