CREATE TABLE IF NOT EXISTS bridged_entities (
    id TEXT PRIMARY KEY,
    address TEXT NOT NULL UNIQUE,
    entity_type TEXT NOT NULL CHECK(entity_type IN ('person', 'item')),
    display_name TEXT NOT NULL,
    bridge_owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bridge_type TEXT NOT NULL,
    bridge_id TEXT REFERENCES bridges(id) ON DELETE SET NULL,
    source_id TEXT,
    tracker_type TEXT,
    capabilities TEXT NOT NULL DEFAULT '[]',
    last_location BLOB,
    last_seen TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bridged_entities_owner ON bridged_entities(bridge_owner_id);
CREATE INDEX IF NOT EXISTS idx_bridged_entities_bridge ON bridged_entities(bridge_id);

-- Bridge registry: available bridge types
CREATE TABLE IF NOT EXISTS bridge_registry (
    id TEXT PRIMARY KEY,
    bridge_type TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    icon TEXT NOT NULL DEFAULT '',
    supports_people BOOLEAN NOT NULL DEFAULT FALSE,
    supports_items BOOLEAN NOT NULL DEFAULT FALSE,
    supports_double_puppet BOOLEAN NOT NULL DEFAULT FALSE,
    setup_url TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed the registry with known bridge types
INSERT OR IGNORE INTO bridge_registry (id, bridge_type, display_name, description, icon, supports_people, supports_items) VALUES
    ('findmy', 'findmy', 'Apple Find My', 'Apple devices, AirTags, and Find My network accessories', '🍎', TRUE, TRUE),
    ('google', 'google', 'Google Maps', 'Google Maps location sharing', '🔵', TRUE, FALSE),
    ('life360', 'life360', 'Life360', 'Life360 family circles', '💜', TRUE, FALSE),
    ('tile', 'tile', 'Tile', 'Tile Bluetooth trackers', '🔲', FALSE, TRUE),
    ('owntracks', 'owntracks', 'OwnTracks', 'OwnTracks MQTT location sharing', '📡', TRUE, FALSE),
    ('smarttag', 'smarttag', 'Samsung SmartTag', 'Samsung SmartThings Find trackers', '📱', FALSE, TRUE);
