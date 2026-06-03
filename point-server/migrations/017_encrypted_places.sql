-- P0-06: store place geometry as an MLS-encrypted blob instead of plaintext.
-- The server only needs group_id/user_id/name for routing triggers; geofence
-- evaluation is client-side, so the server never needs plaintext coordinates.
-- Legacy rows keep their plaintext lat/lon/radius until re-created by the client.
ALTER TABLE places ADD COLUMN encrypted_geometry TEXT;
