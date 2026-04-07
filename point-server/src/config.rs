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
}
