-- Add polygon support: JSON array of {lat, lon} points
ALTER TABLE places ADD COLUMN geometry_type TEXT NOT NULL DEFAULT 'circle';
ALTER TABLE places ADD COLUMN polygon_points TEXT; -- JSON: [{"lat":38.6,"lon":-90.2}, ...]
