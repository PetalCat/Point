use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "point-server", about = "Point location sharing server")]
pub struct Config {
    #[arg(long, env = "DATABASE_URL", default_value = "sqlite:point.db?mode=rwc")]
    pub database_url: String,
    #[arg(long, env = "LISTEN", default_value = "0.0.0.0:8080")]
    pub listen: String,
    #[arg(long, env = "JWT_SECRET")]
    pub jwt_secret: Option<String>,
    #[arg(long, env = "DOMAIN", default_value = "point.local")]
    pub domain: String,
    /// Allow open registration (no invite code needed)
    #[arg(long, env = "OPEN_REGISTRATION", default_value = "true")]
    pub open_registration: bool,
    /// Enable bridge/item tracker endpoints. Off by default — these are
    /// incomplete (no real bridge daemons, item flows are scaffolding) and
    /// should stay hidden until finished (P1-16).
    #[arg(long, env = "ENABLE_BRIDGES", default_value = "false")]
    pub enable_bridges: bool,
    /// Trust x-real-ip / x-forwarded-for headers for rate limiting. Only enable
    /// when behind a reverse proxy that SETS these headers (Traefik/Caddy/nginx)
    /// — otherwise a client can spoof them to evade IP rate limits (P2-19).
    #[arg(long, env = "TRUST_PROXY_HEADERS", default_value = "false")]
    pub trust_proxy_headers: bool,
}
