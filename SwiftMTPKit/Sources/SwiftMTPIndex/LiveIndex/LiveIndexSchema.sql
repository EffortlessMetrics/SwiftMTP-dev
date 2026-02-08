-- Live object index for cache-first File Provider.
-- Upsert model (not generational) — parallel to the existing objects table.

CREATE TABLE IF NOT EXISTS live_objects (
    deviceId      TEXT    NOT NULL,
    storageId     INTEGER NOT NULL,
    handle        INTEGER NOT NULL,
    parentHandle  INTEGER,
    name          TEXT    NOT NULL,
    pathKey       TEXT    NOT NULL,
    sizeBytes     INTEGER,
    mtime         INTEGER,
    formatCode    INTEGER NOT NULL,
    isDirectory   INTEGER NOT NULL DEFAULT 0,
    changeCounter INTEGER NOT NULL,
    crawledAt     INTEGER NOT NULL,
    stale         INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (deviceId, storageId, handle)
);
CREATE INDEX IF NOT EXISTS idx_live_parent ON live_objects(deviceId, storageId, parentHandle);
CREATE INDEX IF NOT EXISTS idx_live_change ON live_objects(deviceId, changeCounter);

CREATE TABLE IF NOT EXISTS live_storages (
    deviceId    TEXT    NOT NULL,
    storageId   INTEGER NOT NULL,
    description TEXT,
    capacity    INTEGER,
    free        INTEGER,
    readOnly    INTEGER,
    PRIMARY KEY (deviceId, storageId)
);

CREATE TABLE IF NOT EXISTS crawl_state (
    deviceId     TEXT    NOT NULL,
    storageId    INTEGER NOT NULL,
    parentHandle INTEGER NOT NULL,
    lastCrawledAt INTEGER,
    status       TEXT    NOT NULL DEFAULT 'pending',
    priority     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (deviceId, storageId, parentHandle)
);

CREATE TABLE IF NOT EXISTS device_index_state (
    deviceId      TEXT PRIMARY KEY,
    changeCounter INTEGER NOT NULL DEFAULT 0,
    lastFullCrawl INTEGER
);

-- Stable device identity mappings (survives live_objects rebuilds).
CREATE TABLE IF NOT EXISTS device_identities (
    domainId     TEXT PRIMARY KEY,
    identityKey  TEXT NOT NULL,
    displayName  TEXT NOT NULL,
    vendorId     INTEGER,
    productId    INTEGER,
    usbSerial    TEXT,
    mtpSerial    TEXT,
    manufacturer TEXT,
    model        TEXT,
    createdAt    INTEGER NOT NULL,
    lastSeenAt   INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_key ON device_identities(identityKey);

-- Change log for correct sync anchors (deduplication-based).
CREATE TABLE IF NOT EXISTS live_changes (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    deviceId      TEXT    NOT NULL,
    changeCounter INTEGER NOT NULL,
    storageId     INTEGER NOT NULL,
    handle        INTEGER,
    parentHandle  INTEGER,
    kind          TEXT    NOT NULL,  -- 'upsert', 'delete', 'refresh'
    createdAt     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_live_changes_device_counter
    ON live_changes(deviceId, changeCounter);
CREATE INDEX IF NOT EXISTS idx_live_changes_device_parent
    ON live_changes(deviceId, storageId, parentHandle, changeCounter);

CREATE TABLE IF NOT EXISTS cached_content (
    deviceId       TEXT    NOT NULL,
    storageId      INTEGER NOT NULL,
    handle         INTEGER NOT NULL,
    localPath      TEXT    NOT NULL,
    sizeBytes      INTEGER NOT NULL,
    etag           TEXT,
    state          TEXT    NOT NULL DEFAULT 'complete',
    committedBytes INTEGER NOT NULL DEFAULT 0,
    lastAccessedAt INTEGER NOT NULL,
    PRIMARY KEY (deviceId, storageId, handle)
);
CREATE INDEX IF NOT EXISTS idx_cache_lru ON cached_content(lastAccessedAt ASC);
