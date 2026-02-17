# Batch Operations

This tutorial covers advanced batch operations for efficiently managing large numbers of files with SwiftMTP.

## What You'll Learn

- Perform bulk file transfers
- Implement folder synchronization strategies
- Use parallel transfers for speed
- Handle batch operations with error recovery

## Prerequisites

- Completed [Getting Started](getting-started.md)
- Completed [Your First Transfer](first-transfer.md)
- Familiarity with [Transfer Files Guide](../howto/transfer-files.md)

## Understanding Batch Operations

Batch operations allow you to process multiple files efficiently. SwiftMTP provides several approaches:

| Approach | Best For | Performance |
|----------|----------|-------------|
| Sequential | Reliability, few files | Lower |
| Parallel | Many files, fast devices | Higher |
| Mirrored | Folder sync | Optimal |

## Step 1: Bulk File Listing

Before batch operations, analyze your device content:

```bash
# List all files recursively (JSON for parsing)
swift run swiftmtp ls --recursive --json > device-files.json

# Get storage summary
swift run swiftmtp df

# Output:
# Storage: Primary
#   Used: 45.2 GB
#   Free: 82.8 GB
#   Total: 128 GB

# Storage: SD Card
#   Used: 12.1 GB
#   Free: 59.9 GB
#   Total: 72 GB
```

### Filtering Files

```bash
# List only photos
swift run swiftmtp ls /DCIM --recursive | grep -E "\.(jpg|mp4|png)$"

# List files by date (programmatic)
swift run swiftmtp ls /DCIM --json | jq '.[] | select(.modified > "2024-01-01")'
```

## Step 2: Parallel Transfers

For multiple files, use parallel transfers:

```bash
# Enable parallel transfers
export SWIFTMTP_PARALLEL_TRANSFERS=4

# Download multiple files in parallel
swift run swiftmtp pull /DCIM/Camera/photo1.jpg /DCIM/Camera/photo2.jpg \
  /DCIM/Camera/photo3.jpg /DCIM/Camera/photo4.jpg
```

### Configuring Parallelism

| Environment Variable | Default | Description |
|----------------------|---------|-------------|
| `SWIFTMTP_PARALLEL_TRANSFERS` | 2 | Number of parallel transfers |
| `SWIFTMTP_CHUNK_SIZE` | 2MB | Transfer chunk size |

```bash
# Optimize for fast devices
export SWIFTMTP_PARALLEL_TRANSFERS=8
export SWIFTMTP_CHUNK_SIZE=4194304

# Optimize for slow devices
export SWIFTMTP_PARALLEL_TRANSFERS=1
export SWIFTMTP_CHUNK_SIZE=65536
```

## Step 3: Bulk Download

### Download All Photos

```bash
# Download all photos from DCIM
swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM \
  --include "*.jpg" --include "*.mp4" --include "*.HEIC"

# Verify with checksums
swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM \
  --include "*.jpg" --include "*.mp4" --verify
```

### Selective Download

```bash
# Download by date range
swift run swiftmtp ls /Pictures --json | jq -r '.[] | 
  select(.modified >= "2024-01-01" and .modified <= "2024-12-31") | .path' | \
  xargs -I{} swift run swiftmtp pull {}
```

### Download with Retry

```bash
# Scripted download with retry
#!/bin/bash
FILES=(
  "/DCIM/Camera/photo1.jpg"
  "/DCIM/Camera/photo2.jpg"
  "/DCIM/Camera/photo3.jpg"
)

for file in "${FILES[@]}"; do
  for i in {1..3}; do
    if swift run swiftmtp pull "$file" --output ~/Downloads/; then
      echo "Success: $file"
      break
    else
      echo "Retry $i: $file"
      sleep 2
    fi
  done
done
```

## Step 4: Bulk Upload

### Upload Entire Folder

```bash
# Upload folder contents
swift run swiftmtp push ~/Photos/Vacation2024/ --to /Pictures/Vacation2024/

# Upload with parallel transfers
export SWIFTMTP_PARALLEL_TRANSFERS=4
swift run swiftmtp push ~/Backup/Documents/ --to /Download/Documents/
```

### Batch Rename During Upload

```bash
# Upload with prefix
for file in ~/Photos/*.jpg; do
  filename=$(basename "$file")
  swift run swiftmtp push "$file" --to /Pictures/ --name "backup-$filename"
done
```

### Progress for Bulk Operations

```bash
# Enable verbose for progress
swift run swiftmtp push ~/Photos/*.jpg --to /Pictures/ --verbose

# Output:
# [INFO] Uploading: photo1.jpg (5.2 MB) [1/50]
# [INFO] Uploading: photo2.jpg (3.1 MB) [2/50]
# [INFO] ████████████░░░░░░░░░░░░░░░░░░░░░ 24% @ 15 MB/s
```

## Step 5: Folder Synchronization

### One-Way Sync (Device → Local)

```bash
# Mirror with deletion (remove local files not on device)
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM --delete

# Dry run first
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM --dry-run
```

### Incremental Sync

```bash
# Only sync new/modified files
swift run swiftmtp mirror /Pictures --to ~/MTP-Backup/Pictures \
  --checksum  # Use checksums instead of timestamp
```

### Two-Way Sync Script

```swift
import SwiftMTPCore

// Two-way sync implementation
actor FolderSync {
    private let device: MTPDevice
    private let localBase: URL
    private let remoteBase: String
    
    func sync() async throws {
        // Get remote listing
        let remoteFiles = try await device.listDirectory(path: remoteBase)
        
        // Get local listing
        let localFiles = try FileManager.default.contentsOfDirectory(
            at: localBase,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        
        // Determine actions
        for remote in remoteFiles {
            let localURL = localBase.appendingPathComponent(remote.name)
            
            if !FileManager.default.fileExists(atPath: localURL.path) {
                // Download new files
                try await device.read(handle: remote.handle, to: localURL)
            }
        }
        
        for local in localFiles {
            if !remoteFiles.contains(where: { $0.name == local.lastPathComponent }) {
                // Upload new local files
                _ = try await device.write(fileURL: local, to: remoteBase)
            }
        }
    }
}
```

## Step 6: Queue-Based Operations

For reliable batch processing, use a queue:

```swift
import SwiftMTPCore

struct TransferQueue {
    private var pending: [TransferTask] = []
    private var completed: [TransferTask] = []
    private var failed: [TransferTask] = []
    
    enum TransferTask {
        case download(remotePath: String, localURL: URL)
        case upload(localURL: URL, remotePath: String)
        case delete(path: String)
    }
    
    mutating func enqueue(_ task: TransferTask) {
        pending.append(task)
    }
    
    mutating func process(device: MTPDevice, parallel: Int = 2) async throws {
        while !pending.isEmpty {
            let batch = Array(pending.prefix(parallel))
            pending.removeFirst(min(parallel, pending.count))
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                for task in batch {
                    group.addTask {
                        switch task {
                        case .download(let remotePath, let localURL):
                            try await device.read(handle: remotePath, to: localURL)
                        case .upload(let localURL, let remotePath):
                            _ = try await device.write(fileURL: localURL, to: remotePath)
                        case .delete(let path):
                            try await device.delete(path: path)
                        }
                    }
                }
                
                do {
                    try await group.waitForAll()
                    completed.append(contentsOf: batch)
                } catch {
                    failed.append(contentsOf: batch)
                    throw error
                }
            }
        }
    }
}
```

## Step 7: Error Recovery

### Checkpoint-Based Processing

```swift
import SwiftMTPCore

class CheckpointBatchTransfer {
    private let device: MTPDevice
    private var checkpointFile: URL
    private var completedPaths: Set<String> = []
    
    init(device: MTPDevice, checkpointPath: URL) {
        self.device = device
        self.checkpointFile = checkpointPath
        loadCheckpoint()
    }
    
    func processBatch(paths: [String]) async throws {
        for path in paths {
            if completedPaths.contains(path) {
                print("Skipping (completed): \(path)")
                continue
            }
            
            do {
                try await device.read(handle: path, to: localURL(for: path))
                completedPaths.insert(path)
                saveCheckpoint()
            } catch {
                print("Failed: \(path) - \(error)")
                throw error
            }
        }
    }
    
    private func loadCheckpoint() {
        // Load from file
    }
    
    private func saveCheckpoint() {
        // Save to file
    }
}
```

### Partial Failure Handling

```bash
# Continue on error, report failures
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM --continue-on-error

# Or use script with error handling
for file in $(cat files.txt); do
  swift run swiftmtp pull "$file" --output ./ || echo "FAILED: $file" >> failures.txt
done

# Retry failures
cat failures.txt | xargs -I{} swift run swiftmtp pull {}
```

## Best Practices

### For Large Batch Operations

1. **Use mirroring** for folder sync - handles incremental updates
2. **Enable parallel transfers** for speed (2-8 depending on device)
3. **Use checksums** for verification on unreliable connections
4. **Implement checkpoints** for very large batches
5. **Monitor progress** with verbose output

### For Reliability

1. **Always verify** with `--verify` flag
2. **Use appropriate timeouts** for slow devices
3. **Handle errors gracefully** with retry logic
4. **Keep logs** for debugging failures

```bash
# Recommended for production
export SWIFTMTP_PARALLEL_TRANSFERS=4
export SWIFTMTP_IO_TIMEOUT_MS=60000
export SWIFTMTP_CHUNK_SIZE=2097152

swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM --verify --checksum
```

## Next Steps

- 📋 [Advanced Transfer Strategies](advanced-transfer.md) - More transfer options
- 📋 [Performance Tuning](../howto/performance-tuning.md) - Optimize speeds
- 📋 [Error Recovery](../howto/error-recovery.md) - Handle failures gracefully
- 📋 [CLI Automation](../howto/cli-automation.md) - Scripting and automation

## Summary

In this tutorial, you learned how to:

1. ✅ List and filter device files in bulk
2. ✅ Use parallel transfers for speed
3. ✅ Perform bulk downloads with selective filtering
4. ✅ Execute bulk uploads with progress tracking
5. ✅ Implement folder synchronization strategies
6. ✅ Build queue-based batch processors
7. ✅ Handle errors with checkpoints and retry logic
