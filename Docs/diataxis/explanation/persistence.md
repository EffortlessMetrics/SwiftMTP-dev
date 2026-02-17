# Data Persistence and Caching

This document explains how SwiftMTP handles data persistence and caching to optimize performance while maintaining data consistency.

## Overview

SwiftMTP uses multiple layers of caching and persistence to minimize device access, speed up operations, and enable offline functionality:

```
┌─────────────────────────────────────────────────────────────┐
│                  Data Persistence Layers                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  1. In-Memory Cache                                  │   │
│  │     - Hot data                                        │   │
│  │     - Current session                                 │   │
│  │     - Fast access                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  2. SQLite Index                                      │   │
│  │     - Device structure                                │   │
│  │     - File metadata                                   │   │
│  │     - Change tracking                                 │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  3. Transfer Journal                                  │   │
│  │     - Pending transfers                               │   │
│  │     - Resume state                                    │   │
│  │     - Completion records                              │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  4. Quirks Database                                   │   │
│  │     - Device profiles                                  │   │
│  │     - Performance settings                            │   │
│  │     - Workarounds                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## In-Memory Cache

### Session Cache

The in-memory cache stores frequently accessed data during a session:

```swift
actor DeviceActor {
    // Session cache - cleared on disconnect
    private var objectCache: [UInt32: MTPObject] = [:]
    private var storageCache: [UInt32: MTPStorage] = [:]
    private var directoryCache: [UInt32?: [MTPObject]] = [:]
    
    func getObject(handle: UInt32) async throws -> MTPObject {
        // Check cache first
        if let cached = objectCache[handle] {
            return cached
        }
        
        // Fetch from device
        let object = try await protocol.getObjectInfo(handle: handle)
        objectCache[handle] = object
        return object
    }
    
    func invalidateCache() {
        objectCache.removeAll()
        storageCache.removeAll()
        directoryCache.removeAll()
    }
}
```

### Cache Invalidation

```swift
// Events that trigger cache invalidation
enum CacheInvalidationTrigger {
    case objectAdded(handle: UInt32)
    case objectRemoved(handle: UInt32)
    case objectModified(handle: UInt32)
    case storageChanged
    case sessionClosed
}
```

## SQLite Index

### Database Schema

```sql
-- Device identities
CREATE TABLE device_identities (
    id TEXT PRIMARY KEY,
    vendor_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    manufacturer TEXT,
    model TEXT,
    serial_number TEXT,
    first_seen DATETIME,
    last_seen DATETIME
);

-- File metadata cache
CREATE TABLE object_metadata (
    device_id TEXT NOT NULL,
    handle INTEGER NOT NULL,
    parent_handle INTEGER,
    storage_id INTEGER,
    name TEXT NOT NULL,
    size INTEGER,
    mime_type TEXT,
    created DATETIME,
    modified DATETIME,
    is_folder BOOLEAN,
    PRIMARY KEY (device_id, handle),
    FOREIGN KEY (device_id) REFERENCES device_identities(id)
);

-- Change tracking
CREATE TABLE change_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    handle INTEGER NOT NULL,
    change_type TEXT NOT NULL, -- 'added', 'removed', 'modified'
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (device_id) REFERENCES device_identities(id)
);

-- Storage information
CREATE TABLE storage_info (
    device_id TEXT NOT NULL,
    storage_id INTEGER NOT NULL,
    storage_type INTEGER,
    file_system_type TEXT,
    capacity INTEGER,
    free_space INTEGER,
    description TEXT,
    PRIMARY KEY (device_id, storage_id),
    FOREIGN KEY (device_id) REFERENCES device_identities(id)
);
```

### Index Management

```swift
class SQLiteIndex: MTPStore {
    private let db: SQLiteDatabase
    
    // Save device identity
    func saveDeviceIdentity(_ identity: DeviceIdentity) async throws {
        try await db.execute("""
            INSERT OR REPLACE INTO device_identities
            (id, vendor_id, product_id, manufacturer, model, serial_number, first_seen, last_seen)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            """,
            identity.id,
            identity.vendorId,
            identity.productId,
            identity.manufacturer,
            identity.model,
            identity.serialNumber
        )
    }
    
    // Save file metadata
    func saveMetadata(_ metadata: ObjectMetadata) async throws {
        try await db.execute("""
            INSERT OR REPLACE INTO object_metadata
            (device_id, handle, parent_handle, storage_id, name, size, mime_type, created, modified, is_folder)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            metadata.deviceId,
            metadata.handle,
            metadata.parentHandle,
            metadata.storageId,
            metadata.name,
            metadata.size,
            metadata.mimeType,
            metadata.created,
            metadata.modified,
            metadata.isFolder
        )
    }
}
```

### Caching Strategy

```
┌─────────────────────────────────────────────────────────────┐
│              Cache-First Lookup Strategy                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Request for /DCIM/Camera                                   │
│                    │                                          │
│                    ▼                                          │
│         ┌──────────────────┐                                 │
│         │  Memory Cache    │                                 │
│         │  Check           │                                 │
│         └────────┬─────────┘                                 │
│                  │ Found                                      │
│                  ▼ Not Found                                  │
│         ┌──────────────────┐                                 │
│         │  SQLite Index    │                                 │
│         │  Check           │                                 │
│         └────────┬─────────┘                                 │
│                  │ Found                                      │
│                  ▼ Not Found                                  │
│         ┌──────────────────┐                                 │
│         │  Device Query     │                                 │
│         │  (Expensive)      │                                 │
│         └────────┬─────────┘                                 │
│                  │                                           │
│                  ▼                                           │
│         ┌──────────────────┐                                 │
│         │  Update Caches  │                                 │
│         │  (Memory + SQL) │                                 │
│         └──────────────────┘                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Transfer Journal

### Purpose

The transfer journal maintains state for resumable transfers and provides audit trails:

```swift
// Transfer record structure
struct TransferRecord: Codable, Sendable {
    let id: UUID
    let deviceId: String
    let sourcePath: String
    let destinationPath: String
    let totalBytes: UInt64
    var transferredBytes: UInt64
    let startTime: Date
    var lastResumeTime: Date?
    var status: TransferStatus
    var checksum: String?
    var error: String?
}
```

### Journal Operations

```swift
protocol TransferJournal {
    // Record a new transfer
    func recordTransfer(_ record: TransferRecord) async throws
    
    // Get all pending transfers
    func pendingTransfers() async throws -> [TransferRecord]
    
    // Mark transfer complete
    func markCompleted(_ record: TransferRecord) async throws
    
    // Mark transfer failed
    func markFailed(_ record: TransferRecord, error: Error) async throws
    
    // Get transfer history
    func transferHistory(
        deviceId: String,
        from: Date,
        to: Date
    ) async throws -> [TransferRecord]
}
```

### Implementation Example

```swift
class FileTransferJournal: TransferJournal {
    private let db: SQLiteDatabase
    
    func recordTransfer(_ record: TransferRecord) async throws {
        try await db.execute("""
            INSERT INTO transfer_journal
            (id, device_id, source_path, destination_path, total_bytes, 
             transferred_bytes, start_time, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            record.id.uuidString,
            record.deviceId,
            record.sourcePath,
            record.destinationPath,
            record.totalBytes,
            record.transferredBytes,
            record.startTime,
            record.status.rawValue
        )
    }
    
    func pendingTransfers() async throws -> [TransferRecord] {
        let rows = try await db.query("""
            SELECT * FROM transfer_journal 
            WHERE status IN ('pending', 'in_progress')
            ORDER BY start_time ASC
            """)
        
        return rows.compactMap { row in
            try? TransferRecord(from: row)
        }
    }
}
```

### Resume Flow

```
┌─────────────────────────────────────────────────────────────┐
│              Resume Transfer Flow                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  App Starts                                                  │
│      │                                                      │
│      ▼                                                      │
│  Check Journal for Pending                                  │
│      │                                                      │
│      ▼                                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Pending transfers found?                             │   │
│  └────────────────────┬────────────────────────────────┘   │
│         Yes           │ No                                  │
│         ▼              ▼                                    │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │ User selects │  │ Normal       │                        │
│  │ to resume    │  │ operation    │                        │
│  └──────┬───────┘  └──────────────┘                        │
│         │                                                   │
│         ▼                                                   │
│  Get Transfer State                                         │
│  - total_bytes                                              │
│  - transferred_bytes                                        │
│  - source_path                                              │
│      │                                                      │
│      ▼                                                      │
│  Resume Transfer from offset                                 │
│      │                                                      │
│      ▼                                                      │
│  Update journal progress                                     │
│      │                                                      │
│      ▼                                                      │
│  On complete: markCompleted()                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Quirks Database

### Storage

```swift
struct DeviceQuirks: Codable {
    let deviceId: String
    let vendorId: Int
    let productId: Int
    let name: String
    let enabled: Bool
    
    // Transfer settings
    let chunkSize: Int?
    let maxParallel: Int?
    let useSendObject: Bool?
    
    // Timeout overrides
    let ioTimeoutMs: Int?
    let connectTimeoutMs: Int?
    
    // Workarounds
    let brokenGetObjectHandles: Bool?
    let needsObjectIdRefresh: Bool?
}
```

### Loading Quirks

```swift
class QuirksStore {
    private var quirksCache: [String: DeviceQuirks] = [:]
    private let bundledPath: URL
    private let userPath: URL
    
    func loadQuirks(deviceId: String) async throws -> DeviceQuirks {
        // Check cache
        if let cached = quirksCache[deviceId] {
            return cached
        }
        
        // Load from bundled + user quirks
        let allQuirks = try await loadAllQuirks()
        
        guard let quirks = allQuirks.first(where: { $0.deviceId == deviceId }) else {
            throw QuirksError.notFound(deviceId)
        }
        
        quirksCache[deviceId] = quirks
        return quirks
    }
}
```

## Cache Configuration

### Configuration Options

```swift
struct CacheConfig {
    // Memory cache size (objects)
    var maxMemoryCacheSize: Int = 1000
    
    // SQLite cache expiry
    var metadataTTLSeconds: TimeInterval = 3600  // 1 hour
    
    // Whether to cache at all
    var enableCaching: Bool = true
    
    // Whether to use persistent storage
    var enablePersistence: Bool = true
}

let config = CacheConfig(
    maxMemoryCacheSize: 500,
    metadataTTLSeconds: 1800,  // 30 minutes
    enableCaching: true,
    enablePersistence: true
)
```

### Applying Configuration

```swift
let manager = MTPDeviceManager.shared

// Configure caching
try await manager.configureCache(with: config)

// Or per-device
let device = try await manager.openDevice(summary: summary)
try await device.setCacheConfig(config)
```

## Data Consistency

### Change Tracking

```swift
class ChangeTracker {
    private let db: SQLiteDatabase
    
    // Record a change
    func recordChange(
        deviceId: String,
        handle: UInt32,
        type: ChangeType
    ) async throws {
        try await db.execute("""
            INSERT INTO change_log (device_id, handle, change_type)
            VALUES (?, ?, ?)
            """,
            deviceId,
            handle,
            type.rawValue
        )
    }
    
    // Get changes since timestamp
    func getChanges(
        deviceId: String,
        since: Date
    ) async throws -> [ChangeRecord] {
        let rows = try await db.query("""
            SELECT * FROM change_log
            WHERE device_id = ? AND timestamp > ?
            ORDER BY timestamp ASC
            """,
            deviceId,
            since
        )
        
        return rows.compactMap { ChangeRecord(from: $0) }
    }
}
```

### Sync Strategy

```
┌─────────────────────────────────────────────────────────────┐
│              Incremental Sync Strategy                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Get last sync timestamp                                 │
│           │                                                  │
│           ▼                                                  │
│  2. Query changes since last sync                           │
│     SELECT * FROM change_log WHERE timestamp > ?             │
│           │                                                  │
│           ▼                                                  │
│  3. Process each change                                     │
│     - Added: Download new file                              │
│     - Modified: Update local copy                           │
│     - Removed: Delete local file                            │
│           │                                                  │
│           ▼                                                  │
│  4. Update last sync timestamp                              │
│           │                                                  │
│           ▼                                                  │
│  5. Complete                                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Performance Considerations

### Cache Hit Rates

| Cache | Typical Hit Rate | Impact |
|-------|-----------------|--------|
| Memory | 80-95% | Very high - fastest |
| SQLite | 60-80% | High - avoids device I/O |
| Device | 5-20% | Low - slowest |

### Optimizing Cache Performance

```swift
// Prefetch directory contents
func prefetchDirectory(_ path: String) async {
    // Load all children into memory cache
    let objects = try await device.list(at: path)
    
    for object in objects {
        await device.cacheObject(object)
    }
}

// Clear stale cache periodically
func cleanupCache() async {
    let cutoff = Date().addingTimeInterval(-3600)  // 1 hour ago
    
    try await db.execute("""
        DELETE FROM object_metadata 
        WHERE last_accessed < ?
        """,
        cutoff
    )
}
```

## Troubleshooting Cache Issues

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Stale data | Old file listings | Force refresh with `device.invalidateCache()` |
| Cache corruption | SQLite errors | Delete cache files in Application Support |
| Memory pressure | High memory usage | Reduce `maxMemoryCacheSize` |
| Slow queries | Laggy directory listings | Rebuild SQLite indexes |

### Cache Debugging

```swift
// Enable cache logging
let config = SwiftMTPConfig(
    loggingEnabled: true,
    logLevel: .debug
)

// Get cache statistics
let stats = await device.getCacheStats()
print("""
Cache Stats:
- Memory hits: \(stats.memoryHits)
- Memory misses: \(stats.memoryMisses)
- SQLite hits: \(stats.sqliteHits)
- SQLite misses: \(stats.sqliteMisses)
- Hit rate: \(stats.hitRate * 100)%
""")

// Force cache clear
try await device.clearCache()
```

## Related Documentation

- [Architecture Overview](architecture.md) - System architecture
- [SQLite Integration](architecture.md) - Index implementation
- [Transfer Modes](transfer-modes.md) - Transfer operations
- [Performance Tuning](../howto/performance-tuning.md) - Cache optimization

## Summary

Key points about persistence and caching:

1. ✅ Multi-layer caching (memory → SQLite → device)
2. ✅ Transfer journal for resume capability
3. ✅ Change tracking for incremental sync
4. ✅ Configurable cache behavior
5. ✅ Cache invalidation on device changes
6. ✅ Debugging and monitoring tools
7. ✅ Performance optimization via prefetching
