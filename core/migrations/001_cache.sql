-- Cached remote reads: the store index, listings, descriptions, and whatever the heavier tools
-- produce later. A stale row is kept rather than deleted, so a hub with no network can still show
-- yesterday's catalogue instead of an empty page.

CREATE TABLE IF NOT EXISTS cache (
  key        TEXT PRIMARY KEY,
  value      BLOB NOT NULL,
  etag       TEXT,
  fetched_at INTEGER NOT NULL,
  ttl        INTEGER NOT NULL
);
