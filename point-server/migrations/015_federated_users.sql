-- Federated users: shadow records for users from remote servers.
-- Allows foreign keys to work for share_requests, user_shares, etc.
-- Password hash is empty — federated users can't log in locally.
-- The 'is_federated' flag distinguishes them from local users.
ALTER TABLE users ADD COLUMN is_federated BOOLEAN NOT NULL DEFAULT FALSE;
