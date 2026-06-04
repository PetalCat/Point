-- Visibility "modes" — Focus-style saved audiences for the redesign.
-- A mode is a named set of groups + individual users; applying it configures
-- the user's per-group sharing and direct shares. The server stores the mode
-- definitions and which one is currently active; the client applies a mode by
-- toggling the underlying share/ghost state through the existing endpoints.
CREATE TABLE IF NOT EXISTS visibility_modes (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL,
    name       TEXT NOT NULL,
    icon       TEXT NOT NULL DEFAULT 'users',
    group_ids  TEXT NOT NULL DEFAULT '[]',  -- JSON array of group IDs
    user_ids   TEXT NOT NULL DEFAULT '[]',  -- JSON array of user IDs
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_vis_modes_user ON visibility_modes (user_id);

-- Which mode the user currently has applied (NULL = Custom / none).
ALTER TABLE users ADD COLUMN active_mode_id TEXT;
