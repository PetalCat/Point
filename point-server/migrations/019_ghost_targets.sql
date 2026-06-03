-- P1-09: per-target ghost enforcement. The global ghost flag (users.ghost_active)
-- remains the coarse kill switch; this table lets a user ghost specific groups or
-- contacts (or '__all__') and have the SERVER enforce it, instead of relying on
-- the client to suppress relays. target_id is a group_id, a user_id, or '__all__'.
CREATE TABLE IF NOT EXISTS ghost_targets (
    user_id   TEXT NOT NULL,
    target_id TEXT NOT NULL,
    PRIMARY KEY (user_id, target_id)
);
CREATE INDEX IF NOT EXISTS idx_ghost_targets_user ON ghost_targets (user_id);
