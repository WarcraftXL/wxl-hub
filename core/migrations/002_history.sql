-- What the user last opened. Spans modules -- the store records a listing, the tools page records a
-- tool, the home page shows both -- which is why it is core and not owned by either.

CREATE TABLE IF NOT EXISTS history (
  href     TEXT PRIMARY KEY,
  kind     TEXT NOT NULL,
  ref      TEXT,
  title    TEXT NOT NULL,
  subtitle TEXT,
  icon     TEXT,
  seen_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS history_seen ON history (seen_at DESC);
