PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = 1000;
PRAGMA temp_store = memory;

CREATE TABLE IF NOT EXISTS transfers(
  id TEXT PRIMARY KEY,           -- UUID
  deviceId TEXT NOT NULL,
  kind TEXT NOT NULL,            -- "read" | "write"
  handle INTEGER,                -- target object handle (read OR new handle from SendObjectInfo for write)
  parentHandle INTEGER,          -- for writes
  pathKey TEXT,                  -- best-effort identity across sessions
  name TEXT NOT NULL,
  totalBytes INTEGER,            -- expected size (if known)
  committedBytes INTEGER NOT NULL DEFAULT 0,
  supportsPartial INTEGER NOT NULL DEFAULT 0,
  etag_size INTEGER,             -- preconditions: size from ObjectInfo
  etag_mtime INTEGER,            -- preconditions: Date().timeIntervalSince1970 (secs)
  localTempURL TEXT NOT NULL,    -- temp path (host)
  finalURL TEXT,                 -- destination (read) or source (write)
  state TEXT NOT NULL,           -- "active" | "paused" | "failed" | "done"
  lastError TEXT,
  updatedAt INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_transfers_active ON transfers(state);
CREATE INDEX IF NOT EXISTS idx_transfers_device ON transfers(deviceId);

-- M6: Index, Diff, Mirror schema

CREATE TABLE IF NOT EXISTS devices(
  id TEXT PRIMARY KEY,
  model TEXT,
  lastSeenAt INTEGER
);

CREATE TABLE IF NOT EXISTS storages(
  id INTEGER,
  deviceId TEXT,
  description TEXT,
  capacity INTEGER,
  free INTEGER,
  readOnly INTEGER,
  lastIndexedAt INTEGER,
  PRIMARY KEY(id, deviceId),
  FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
);

-- Current object catalog (single table, "generation" partitioning)
CREATE TABLE IF NOT EXISTS objects(
  deviceId TEXT NOT NULL,
  storageId INTEGER NOT NULL,
  handle INTEGER NOT NULL,
  parentHandle INTEGER,
  name TEXT NOT NULL,
  pathKey TEXT NOT NULL,           -- normalized NFC, storage-rooted: "<sid>/<a>/<b>/<name>"
  size INTEGER,                    -- NULL if unknown
  mtime INTEGER,                   -- UNIX seconds; NULL if unknown
  format INTEGER NOT NULL,
  gen INTEGER NOT NULL,            -- snapshot generation
  tombstone INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(deviceId, storageId, handle),
  FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_objects_path ON objects(deviceId, pathKey);
CREATE INDEX IF NOT EXISTS idx_objects_gen  ON objects(deviceId, gen);

-- Snapshot bookkeeping
CREATE TABLE IF NOT EXISTS snapshots(
  deviceId TEXT NOT NULL,
  gen INTEGER NOT NULL,
  createdAt INTEGER NOT NULL,
  PRIMARY KEY(deviceId, gen),
  FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
);
