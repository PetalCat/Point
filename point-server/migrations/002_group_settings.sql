-- Group settings
ALTER TABLE groups ADD COLUMN members_can_invite BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE groups ADD COLUMN notify_on_join BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE groups ADD COLUMN notify_on_leave BOOLEAN NOT NULL DEFAULT TRUE;

-- Per-user group settings (self-controlled)
ALTER TABLE group_members ADD COLUMN sharing BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE group_members ADD COLUMN notify_join_leave BOOLEAN NOT NULL DEFAULT TRUE;
