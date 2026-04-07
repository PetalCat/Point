-- Users
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    avatar BLOB,
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Devices
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    mls_key_package BLOB,
    push_token TEXT,
    last_seen TEXT NOT NULL DEFAULT (datetime('now')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Groups
CREATE TABLE IF NOT EXISTS groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    allow_places BOOLEAN NOT NULL DEFAULT TRUE,
    default_precision TEXT NOT NULL DEFAULT 'exact',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Group Members
CREATE TABLE IF NOT EXISTS group_members (
    group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    precision TEXT NOT NULL DEFAULT 'exact',
    schedule_type TEXT NOT NULL DEFAULT 'always',
    schedule_days TEXT,
    schedule_start TEXT,
    schedule_end TEXT,
    joined_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (group_id, user_id)
);

-- Bridges
CREATE TABLE IF NOT EXISTS bridges (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bridge_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'disconnected',
    double_puppet BOOLEAN NOT NULL DEFAULT FALSE,
    last_heartbeat TEXT,
    error_message TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Items
CREATE TABLE IF NOT EXISTS items (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    tracker_type TEXT NOT NULL,
    source_id TEXT,
    bridge_id TEXT REFERENCES bridges(id) ON DELETE SET NULL,
    capabilities TEXT NOT NULL DEFAULT '[]',
    last_location BLOB,
    last_seen TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Item Shares
CREATE TABLE IF NOT EXISTS item_shares (
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL,
    target_id TEXT NOT NULL,
    precision TEXT NOT NULL DEFAULT 'exact',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (item_id, target_type, target_id)
);

-- Places (Geofences)
CREATE TABLE IF NOT EXISTS places (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    encrypted_definition BLOB NOT NULL,
    triggers TEXT NOT NULL DEFAULT '["enter","exit"]',
    notify TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Location Updates
CREATE TABLE IF NOT EXISTS location_updates (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_type TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    encrypted_blob BLOB NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'native',
    timestamp INTEGER NOT NULL,
    ttl INTEGER NOT NULL DEFAULT 300,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_location_updates_recipient ON location_updates(recipient_type, recipient_id);
CREATE INDEX IF NOT EXISTS idx_location_updates_created ON location_updates(created_at);

-- Invites
CREATE TABLE IF NOT EXISTS invites (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    max_uses INTEGER NOT NULL DEFAULT 1,
    uses INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Temporary Shares
CREATE TABLE IF NOT EXISTS temporary_shares (
    id TEXT PRIMARY KEY,
    from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id TEXT,
    link_token TEXT UNIQUE,
    precision TEXT NOT NULL DEFAULT 'exact',
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
