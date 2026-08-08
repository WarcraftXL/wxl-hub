-- The notification centre.
--
-- Kept in the database rather than in memory because the events worth a bell are the ones you were
-- not looking at when they happened: an install that failed while you were on another page, an
-- update that appeared during the boot fetch.
--
-- `ref` is what the notice is about, usually a module id. It exists so a second notice about the
-- same thing can replace the first instead of stacking: five failures of one install is one problem.

CREATE TABLE IF NOT EXISTS notification (
  id         INTEGER PRIMARY KEY,
  kind       TEXT    NOT NULL,
  ref        TEXT,
  level      TEXT    NOT NULL DEFAULT 'info',   -- info | good | bad
  title      TEXT    NOT NULL,
  body       TEXT,
  href       TEXT,
  created_at INTEGER NOT NULL,
  read_at    INTEGER
);

CREATE INDEX IF NOT EXISTS notification_unread ON notification (read_at, created_at);
