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
