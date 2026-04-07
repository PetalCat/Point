use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PresenceUpdate {
    pub user_id: String,
    pub online: bool,
    pub battery: Option<u8>,
    pub activity: Option<String>,
}
