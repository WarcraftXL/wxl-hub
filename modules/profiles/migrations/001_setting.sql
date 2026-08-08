-- User settings. Defaults live in the model and are never written on read, so changing a default
-- later still reaches everyone who never touched it.
--
-- Moved here from modules/settings when profiles became a module of their own. Migrations are
-- recorded by path, so this shows as newly applied on a database that already ran it under the old
-- name. That is cosmetic and safe: every statement below is idempotent.

CREATE TABLE IF NOT EXISTS setting (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
