# CLI Automation

This guide covers automating SwiftMTP operations using scripts and command-line tools.

## Quick Reference

| Task | Command | Automation |
|------|---------|------------|
| List devices | `swift run swiftmtp probe` | Cron, launchd |
| Transfer files | `swift run swiftmtp pull/push` | Scripts |
| Monitor events | `swift run swiftmtp events` | Daemon |
| Run benchmarks | `swift run swiftmtp bench` | CI/CD |

## Basic Automation

### Shell Script Basics

```bash
#!/bin/bash
# Simple backup script

DEVICE_PATH="/DCIM"
LOCAL_PATH="$HOME/MTP-Backup/DCIM"

echo "Starting backup..."
swift run swiftmtp mirror "$DEVICE_PATH" --to "$LOCAL_PATH" --verbose
echo "Backup complete!"
```

### Make Executable

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

## Cron Jobs

### Scheduled Backups

```bash
# Edit crontab
crontab -e

# Add entry (daily at 2am)
0 2 * * * /Users/you/Code/SwiftMTP/scripts/backup.sh >> /tmp/backup.log 2>&1
```

### Cron Environment

```bash
# Set environment in script
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export SWIFTMTP_LOG_FILE="/tmp/swiftmtp-cron.log"

cd /Users/you/Code/SwiftMTP
swift run swiftmtp mirror /DCIM --to ~/Backup/DCIM
```

### Cron Script Example

```bash
#!/bin/bash
# /Users/you/Code/SwiftMTP/scripts/daily-backup.sh

LOGFILE="/Users/you/logs/mtp-backup.log"
DEVICE_PATH="/DCIM"
BACKUP_PATH="/Users/you/Backup/DCIM"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log "Starting daily backup"

# Check device connected
if ! swift run swiftmtp probe --json | grep -q .; then
    log "ERROR: No device found"
    exit 1
fi

# Run backup
log "Mirroring files..."
swift run swiftmtp mirror "$DEVICE_PATH" --to "$BACKUP_PATH" \
    --verbose >> "$LOGFILE" 2>&1

if [ $? -eq 0 ]; then
    log "Backup completed successfully"
else
    log "ERROR: Backup failed"
    exit 1
fi
```

## LaunchD Daemon

### Device Monitoring Daemon

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.swiftmtp.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/you/Code/SwiftMTP/scripts/device-monitor.sh</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/Users/you/Documents/ToUpload</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

### Device Monitor Script

```bash
#!/bin/bash
# /Users/you/Code/SwiftMTP/scripts/device-monitor.sh

WATCH_DIR="/Users/you/Documents/ToUpload"
DEVICE_PATH="/Download/AutoBackup"

log() {
    echo "[$(date)] $1"
}

while true; do
    # Check for new files
    if [ "$(ls -A $WATCH_DIR)" ]; then
        log "New files detected"
        
        # Wait for device
        while ! swift run swiftmtp probe | grep -q .; do
            sleep 5
        done
        
        # Upload new files
        for file in $WATCH_DIR/*; do
            if [ -f "$file" ]; then
                log "Uploading: $file"
                swift run swiftmtp push "$file" --to "$DEVICE_PATH"
            fi
        done
    fi
    
    sleep 30
done
```

## JSON Output for Scripting

### Parsing Device List

```bash
# Get device as JSON
swift run swiftmtp probe --json | jq '.'

# Output:
# [
#   {
#     "vendorId": 18d1,
#     "productId": 4ee1,
#     "manufacturer": "Google",
#     "model": "Pixel 7",
#     "serial": "..."
#   }
# ]
```

### Script with JSON Parsing

```bash
#!/bin/bash
# Find specific device

DEVICE_MODEL="Pixel 7"

DEVICES=$(swift run swiftmtp probe --json)

if echo "$DEVICES" | jq -e '.[] | select(.model == "'$DEVICE_MODEL'")' > /dev/null 2>&1; then
    echo "Found $DEVICE_MODEL"
else
    echo "Device not found"
    exit 1
fi
```

### File Listing Script

```bash
#!/bin/bash
# Count files in device folders

swift run swiftmtp ls /DCIM --json | jq 'length'
swift run swiftmtp ls /Pictures --json | jq 'length'
swift run swiftmtp ls /Movies --json | jq 'length'
```

## Advanced Scripting

### Auto-Sync Script

```bash
#!/bin/bash
# Bidirectional sync with conflict resolution

set -e

LOCAL_DIR="$HOME/MTP-Sync"
REMOTE_DIR="/MTP-Sync"
LOG_FILE="$HOME/logs/sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check device
if ! swift run swiftmtp probe | grep -q .; then
    log "No device connected"
    exit 1
fi

# Create local directory
mkdir -p "$LOCAL_DIR"

# Download new files from device
log "Downloading new files..."
swift run swiftmtp mirror "$REMOTE_DIR" --to "$LOCAL_DIR" --verbose

# Upload new local files
log "Uploading new files..."
for file in "$LOCAL_DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # Check if exists on device
        if ! swift run swiftmtp ls "$REMOTE_DIR" --json | jq -e '.[] | select(.name == "'$filename'")' > /dev/null 2>&1; then
            log "Uploading: $filename"
            swift run swiftmtp push "$file" --to "$REMOTE_DIR"
        fi
    fi
done

log "Sync complete"
```

### Batch Processing Script

```bash
#!/bin/bash
# Process multiple folders

FOLDERS=("/DCIM" "/Pictures" "/Movies" "/Download")
BACKUP_BASE="$HOME/MTP-Backup"

for folder in "${FOLDERS[@]}"; do
    folder_name=$(basename "$folder")
    backup_path="$BACKUP_BASE/$folder_name"
    
    echo "Syncing $folder..."
    swift run swiftmtp mirror "$folder" --to "$backup_path" \
        --include "*.jpg" --include "*.mp4" --include "*.HEIC"
done
```

### Error Handling Script

```bash
#!/bin/bash
# Robust transfer with retry and logging

MAX_RETRIES=3
RETRY_DELAY=2

transfer_with_retry() {
    local source="$1"
    local dest="$2"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if swift run swiftmtp push "$source" --to "$dest"; then
            return 0
        fi
        
        retries=$((retries + 1))
        echo "Retry $retries/$MAX_RETRIES for $source"
        sleep $RETRY_DELAY
    done
    
    echo "FAILED after $MAX_RETRIES attempts: $source" >> failures.log
    return 1
}

# Process files
for file in "$@"; do
    transfer_with_retry "$file" "/Download/Backup"
done

# Report failures
if [ -f failures.log ]; then
    echo "=== Failed files ==="
    cat failures.log
    rm failures.log
fi
```

## CI/CD Integration

### GitHub Actions

```yaml
name: MTP Device Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Swift
        uses: swift-actions/setup-swift@v1
        with:
          swift-version: "5.9"
      
      - name: Run device tests
        run: |
          swift run swiftmtp probe --json > devices.json
          if [ $(jq 'length' devices.json) -eq 0 ]; then
            echo "No devices connected, skipping tests"
            exit 0
          fi
          swift test
      
      - name: Run benchmarks
        if: github.event_name == 'schedule'
        run: |
          swift run swiftmtp bench 100M --out benchmark.csv
```

### Jenkins Pipeline

```groovy
pipeline {
    agent { macos }
    
    environment {
        SWIFTMTP_VERBOSE = '1'
    }
    
    stages {
        stage('Probe Devices') {
            steps {
                sh 'swift run swiftmtp probe --json > devices.json'
                sh 'cat devices.json'
            }
        }
        
        stage('Run Tests') {
            steps {
                sh 'swift test'
            }
        }
    }
}
```

## Interactive Scripts

### Wizard-Style Script

```bash
#!/bin/bash
# Interactive device setup

echo "=== SwiftMTP Device Setup ==="
echo

# Select device
echo "Available devices:"
IFS=$'\n' read -r -d '' -a DEVICES < <(swift run swiftmtp probe --json | jq -r '.[] | "\(.manufacturer) \(.model) (\(.serial))"' && IFS=$'\n')
select DEVICE in "${DEVICES[@]}" "Quit"; do
    if [ "$REPLY" -eq $((${#DEVICES[@]} + 1)) ]; then
        exit 0
    fi
    break
done

# Select operation
echo
echo "Select operation:"
select OPERATION in "Backup all photos" "Sync Downloads" "Mirror SD Card" "Quit"; do
    case $OPERATION in
        "Backup all photos")
            swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM
            ;;
        "Sync Downloads")
            swift run swiftmtp mirror /Download --to ~/MTP-Backup/Download
            ;;
        "Mirror SD Card")
            swift run swiftmtp mirror /Storage/SDCard --to ~/MTP-Backup/SDCard
            ;;
        "Quit")
            exit 0
            ;;
    esac
    break
done
```

### Interactive Menu

```bash
#!/bin/bash
# Interactive menu

show_menu() {
    clear
    echo "=== SwiftMTP Menu ==="
    echo "1. List devices"
    echo "2. Browse files"
    echo "3. Backup DCIM"
    echo "4. Upload files"
    echo "5. Run benchmark"
    echo "6. Device info"
    echo "7. Quit"
    echo
}

while true; do
    show_menu
    read -p "Select option: " choice
    
    case $choice in
        1) swift run swiftmtp probe ;;
        2) read -p "Path: " path; swift run swiftmtp ls "$path" ;;
        3) swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM ;;
        4) read -p "File: " file; swift run swiftmtp push "$file" ;;
        5) read -p "Size: " size; swift run swiftmtp bench "$size" ;;
        6) swift run swiftmtp device-info ;;
        7) exit 0 ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
done
```

## Best Practices

### Script Checklist

1. ✅ Use `set -e` for error handling
2. ✅ Log all operations
3. ✅ Check return codes
4. ✅ Implement retry logic
5. ✅ Handle missing devices
6. ✅ Use JSON for parsing

### Production Tips

```bash
# Use absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set explicit paths
SWIFTMTP="/Users/you/Code/SwiftMTP/.build/debug/swiftmtp"
WORK_DIR="/Users/you/MTP-Work"

# Comprehensive logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Error handling
set -euo pipefail
```

## Related Documentation

- [CLI Commands Reference](../reference/cli-commands.md)
- [Batch Operations Tutorial](../tutorials/batch-operations.md)
- [Run Benchmarks](run-benchmarks.md)
- [Error Recovery](error-recovery.md)

## Summary

Automation techniques covered:

1. ✅ **Shell scripts** - Basic automation
2. ✅ **Cron jobs** - Scheduled operations
3. ✅ **LaunchD** - Daemon services
4. ✅ **JSON parsing** - Script integration
5. ✅ **CI/CD** - GitHub Actions, Jenkins
6. ✅ **Interactive scripts** - User-friendly automation
7. ✅ **Best practices** - Error handling, logging
