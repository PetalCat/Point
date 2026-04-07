-- Add lat/lon/radius columns to places for client-side geofence evaluation
ALTER TABLE places ADD COLUMN lat REAL NOT NULL DEFAULT 0;
ALTER TABLE places ADD COLUMN lon REAL NOT NULL DEFAULT 0;
ALTER TABLE places ADD COLUMN radius REAL NOT NULL DEFAULT 100;
