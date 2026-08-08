-- What is installed, and every file the hub wrote to put it there.
--
-- `deployed` is the ledger that makes an uninstall exact: knowing each path with its hash is what
-- lets the hub tell a file it placed from one the user edited afterwards, and remove only the first
-- kind.

CREATE TABLE IF NOT EXISTS installed (
  id           TEXT PRIMARY KEY,
  version      TEXT NOT NULL,
  abi          TEXT,
  repo         TEXT,
  enabled      INTEGER NOT NULL DEFAULT 1,
  installed_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS deployed (
  id     TEXT NOT NULL,
  path   TEXT NOT NULL,
  sha256 TEXT,
  PRIMARY KEY (id, path)
);
