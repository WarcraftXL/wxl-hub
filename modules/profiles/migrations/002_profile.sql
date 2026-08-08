-- Profiles.
--
-- A profile holds the client you launch and the paths that go with it. Everything else describes
-- this machine and this user, follows them across profiles, and stays in the flat `setting` table.
--
-- The old flat rows are moved rather than dropped: values chosen before profiles existed belong to
-- the profile the user has been using all along, which is the one being created here.
--
-- Moved here from modules/settings. Migrations are recorded by path, so this shows as newly applied
-- on a database that already ran it under the old name. Every statement is guarded to make that a
-- no-op rather than a second migration.

CREATE TABLE IF NOT EXISTS profile (
  id         INTEGER PRIMARY KEY,
  name       TEXT    NOT NULL UNIQUE,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS profile_setting (
  profile_id INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
  key        TEXT    NOT NULL,
  value      TEXT    NOT NULL,
  PRIMARY KEY (profile_id, key)
);

INSERT INTO profile (id, name)
SELECT 1, COALESCE((SELECT value FROM setting WHERE key = 'profile'), 'Default')
WHERE NOT EXISTS (SELECT 1 FROM profile);

INSERT OR IGNORE INTO profile_setting (profile_id, key, value)
SELECT 1, key, value FROM setting WHERE key IN ('client_path', 'core_path', 'autolaunch');

DELETE FROM setting WHERE key IN ('client_path', 'core_path', 'autolaunch', 'profile');

INSERT OR IGNORE INTO setting (key, value) VALUES ('active_profile', '1');
