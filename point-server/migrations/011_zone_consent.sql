CREATE TABLE IF NOT EXISTS zone_consents (
    zone_owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    consenter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, rejected
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (zone_owner_id, consenter_id)
);
