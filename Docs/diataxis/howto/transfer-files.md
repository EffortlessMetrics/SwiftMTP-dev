# How to Transfer Files

This guide provides detailed instructions for transferring files between your computer and MTP devices.

## Quick Reference

| Operation | Command |
|-----------|---------|
| Download file | `swift run swiftmtp pull <path>` |
| Upload file | `swift run swiftmtp push <file>` |
| Mirror folder | `swift run swiftmtp mirror <path>` |
| Delete file | `swift run swiftmtp rm <path>` |
| Move file | `swift run swiftmtp mv <src> <dst>` |

## Downloading Files

### Basic Download

Download a single file from your device:

```bash
# Download to current directory
swift run swiftmtp pull /DCIM/Camera/photo.jpg

# Download to specific location
swift run swiftmtp pull /DCIM/Camera/photo.jpg --output ~/Downloads/

# Download with custom filename
swift run swiftmtp pull /DCIM/Camera/photo.jpg --output ~/Downloads/vacation-photo.jpg
```

### Download with Progress

For large files, enable progress display:

```bash
swift run swiftmtp pull /DCIM/Camera/video.mp4 --verbose

# Output:
# [INFO] Downloading: video.mp4 (1.2 GB)
# [INFO] ████████████████████░░░░░░░░░░░░░ 45% 540 MB / 1.2 GB @ 45 MB/s ETA: 14s
```

### Download Multiple Files

```bash
# Download multiple files
swift run swiftmtp pull /DCIM/Camera/photo1.jpg /DCIM/Camera/photo2.jpg

# Download all files matching pattern
swift run swiftmtp pull /DCIM/Camera/*.jpg

# Download from specific folder
swift run swiftmtp pull /Pictures/WhatsApp/
```

### Resumable Downloads

If the device supports partial object transfer, downloads can be resumed:

```bash
# Check support
swift run swiftmtp device-info | grep -i partial

# Downloads resume automatically when interrupted
# Works with GetPartialObject64 capable devices
```

## Uploading Files

### Basic Upload

Upload a file to your device:

```bash
# Upload to root of primary storage
swift run swiftmtp push ~/Desktop/photo.jpg

# Upload to specific folder
swift run swiftmtp push ~/Desktop/photo.jpg --to /Download/

# Upload with custom name
swift run swiftmtp push ~/Desktop/photo.jpg --to /Pictures/ --name vacation.jpg
```

### Upload with Progress

```bash
swift run swiftmtp push ~/Desktop/video.mp4 --to /Movies/ --verbose

# Output:
# [INFO] Uploading: video.mp4 (1.2 GB)
# [INFO] ████████████████████░░░░░░░░░░░░ 45% 540 MB / 1.2 GB @ 38 MB/s ETA: 17s
```

### Upload Multiple Files

```bash
# Upload multiple files
swift run swiftmtp push ~/Photos/photo1.jpg ~/Photos/photo2.jpg --to /Pictures/

# Upload directory contents
swift run swiftmtp push ~/Photos/*.jpg --to /Pictures/

# Upload entire folder (creates folder)
swift run swiftmtp push ~/Backup/Documents/ --to /Download/
```

### Upload Options

| Option | Description |
|--------|-------------|
| `--to <path>` | Destination folder on device |
| `--name <name>` | Custom filename on device |
| `--overwrite` | Overwrite existing file |
| `--create-dirs` | Create parent directories |

## Mirroring Folders

The mirror command synchronizes folders bidirectionally.

### Basic Mirror

```bash
# Mirror device folder to local
swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM

# Mirror with direction specified
swift run swiftmtp mirror /Pictures --to ~/MTP-Backup/Pictures --download
```

### Selective Mirror

```bash
# Include only certain file types
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM \
  --include "*.jpg" --include "*.mp4"

# Exclude certain files
swift run swiftmtp mirror /Pictures --to ~/Backup/Pictures \
  --exclude "*.tmp" --exclude "*.log"

# Size filter
swift run swiftmtp mirror /Download --to ~/Backup/Download \
  --min-size 1024 --max-size 104857600
```

### Mirror Options

| Option | Description |
|--------|-------------|
| `--include <pattern>` | Include matching files |
| `--exclude <pattern>` | Exclude matching files |
| `--min-size <bytes>` | Minimum file size |
| `--max-size <bytes>` | Maximum file size |
| `--delete` | Delete local files not on device |
| `--dry-run` | Show what would be done |

### Mirror with Checksum Verification

```bash
# Verify file integrity
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM --verify

# Only sync changed files
swift run swiftmtp mirror /Pictures --to ~/Backup/Pictures --checksum
```

## File Operations

### List Files

```bash
# List root folder
swift run swiftmtp ls

# List specific folder
swift run swiftmtp ls /DCIM

# List with details
swift run swiftmtp ls /DCIM --long

# List recursively
swift run swiftmtp ls /Pictures --recursive
```

### Delete Files

```bash
# Delete a file
swift run swiftmtp rm /Download/old-file.txt

# Delete multiple files
swift run swiftmtp rm /Download/file1.jpg /Download/file2.jpg

# Delete folder (with contents)
swift run swiftmtp rm /Download/folder/ --recursive
```

### Move/Rename Files

```bash
# Move file to different folder
swift run swiftmtp mv /DCIM/photo.jpg /Pictures/

# Rename file
swift run swiftmtp mv /Download/old-name.jpg /Download/new-name.jpg

# Move with new name
swift run swiftmtp mv /DCIM/photo.jpg /Pictures/vacation.jpg
```

### Copy Files

```bash
# Copy file
swift run swiftmtp cp /DCIM/photo.jpg /Pictures/

# Copy with new name
swift run swiftmtp cp /DCIM/photo.jpg /Pictures/backup.jpg
```

## Managing Folders

### Create Folder

```bash
# Create new folder
swift run swiftmtp mkdir /Pictures/Vacation2024

# Create nested folders
swift run swiftmtp mkdir /Download/Backups/Photos --parents
```

### Get Folder Info

```bash
# Get storage info
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

## Transfer Configuration

### Environment Variables

Configure transfer behavior:

```bash
# Timeout (milliseconds)
export SWIFTMTP_IO_TIMEOUT_MS=60000

# Chunk size (bytes)
export SWIFTMTP_CHUNK_SIZE=2097152

# Parallel transfers
export SWIFTMTP_PARALLEL_TRANSFERS=4

# Buffer size
export SWIFTMTP_BUFFER_SIZE=65536
```

### Programmatic Configuration

```swift
import SwiftMTPCore

let config = TransferConfiguration(
    chunkSize: 2 * 1024 * 1024,  // 2 MB
    timeout: .seconds(60),
    retryCount: 3,
    verifyChecksum: true
)

let device = try await MTPDevice(
    configuration: config
)
```

## Progress Monitoring

### CLI Progress

```bash
# Enable progress bar
swift run swiftmtp pull /large-file.mp4 --progress

# Verbose progress with speed
swift run swiftmtp push /video.mp4 --verbose
```

### SwiftUI Progress

The GUI app shows transfer queue:

```swift
import SwiftMTPUI

struct TransferListView: View {
    @StateObject var transferManager: TransferManager
    
    var body: some View {
        List(transferManager.transfers) { transfer in
            TransferRowView(transfer: transfer)
        }
    }
}
```

## Error Handling

### Common Transfer Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `0x2006` | File not found | Refresh listing |
| `0x200B` | Storage full | Free device space |
| `0x200C` | Write protected | Use different folder |
| `0x2011` | Access denied | Accept trust prompt |
| `timeout` | Transfer too slow | Increase timeout |

### Retry Logic

```swift
import SwiftMTPCore

let config = TransferConfiguration(
    retryCount: 3,
    retryDelay: .seconds(2),
    backoffMultiplier: 2.0
)
```

### Partial Transfer Recovery

```swift
// Check if partial transfer is possible
let supportsResume = device.capabilities.contains(.getPartialObject64)

if supportsResume {
    // Resume from offset
    let offset = existingFileSize
    try await device.read(handle: handle, offset: offset, to: localURL)
} else {
    // Restart transfer
    try await device.read(handle: handle, to: localURL)
}
```

## Best Practices

### For Large Files

1. Use a reliable USB cable (USB 3.0)
2. Keep device connected to power
3. Don't use USB hubs
4. Monitor with progress output

### For Many Small Files

1. Consider mirroring instead
2. Use parallel transfers
3. Group by folder

### For Reliability

1. Enable checksum verification
2. Use reasonable timeouts
3. Handle errors gracefully

## Related Documentation

- [Your First Transfer](../tutorials/first-transfer.md)
- [Debugging MTP Issues](../tutorials/debugging-mtp.md)
- [Device Quirks](device-quirks.md)
- [Error Codes Reference](../reference/error-codes.md)

## Summary

You now know how to:

1. ✅ Download files from device
2. ✅ Upload files to device
3. ✅ Mirror folders for backup
4. ✅ Perform file operations (delete, move, copy)
5. ✅ Manage folders
6. ✅ Configure transfer behavior
7. ✅ Monitor progress
8. ✅ Handle errors