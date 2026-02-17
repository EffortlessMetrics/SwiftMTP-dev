# Your First Device Transfer

This tutorial shows you how to transfer files between your computer and an MTP device.

## What You'll Learn

- Download (pull) files from your device
- Upload (push) files to your device
- Mirror entire folders
- Monitor transfer progress

## Prerequisites

- Completed [Getting Started](getting-started.md)
- An MTP device with files to transfer

## Step 1: List Available Files

First, see what's on your device:

```bash
# List root folders
swift run swiftmtp ls

# List specific folder
swift run swiftmtp ls /DCIM
```

Output looks like:

```
Storage: Primary (0)
├── DCIM/
│   └── Camera/
├── Download/
├── Pictures/
│   ├── Screenshots/
│   └── WhatsApp/
└── Movies/
```

## Step 2: Download a File

Use the `pull` command to download files:

```bash
# Download single file
swift run swiftmtp pull /DCIM/Camera/photo.jpg

# Download to specific location
swift run swiftmtp pull /DCIM/Camera/photo.jpg --output ~/Desktop/
```

### Download with Progress

```bash
# Download with progress output
swift run swiftmtp pull /DCIM/Camera/video.mp4 --verbose
```

The CLI shows:
- File size
- Transfer speed
- Progress percentage
- ETA for large files

## Step 3: Upload a File

Use the `push` command to upload files:

```bash
# Upload to root
swift run swiftmtp push ~/Desktop/photo.jpg

# Upload to specific folder
swift run swiftmtp push ~/Desktop/photo.jpg --to /Download/

# Upload multiple files
swift run swiftmtp push ~/Photos/vacation/*.jpg --to /Pictures/
```

### Upload to Writable Folders

Some folders are read-only on certain devices. Common writable folders:
- `/Download/`
- `/DCIM/`
- `/Pictures/`

If you get error `0x201D` (InvalidParameter), try a different folder.

## Step 4: Mirror a Folder

For efficient backup, mirror entire folders:

```bash
# Mirror DCIM to local folder
swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM

# Mirror with filter
swift run swiftmtp mirror /Pictures --to ~/MTP-Backup/Pictures \
  --include "*.jpg" --include "*.mp4"
```

The mirror command:
- Only downloads new/changed files
- Preserves folder structure
- Skips unchanged files (checksum comparison)
- Creates a complete local backup

## Step 5: Using the GUI

The SwiftMTP app provides drag-and-drop transfers:

1. **Launch the app**: `swift run SwiftMTPApp`
2. **Connect device**: Select from sidebar
3. **Browse files**: Navigate folders
4. **Drag files**: From device to Finder (or vice versa)
5. **Monitor**: Watch progress in transfer queue

## Understanding Transfer Resume

SwiftMTP supports resume for interrupted transfers:

| Operation | Resume Support |
|-----------|----------------|
| Download | Automatic (if device supports GetPartialObject64) |
| Upload | Single-pass only (no resume) |
| Mirror | Automatic based on checksums |

## Troubleshooting Transfer Issues

### "Operation timed out"

- Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=60000`
- Try a different USB port/cable
- Keep device screen unlocked

### "Storage full"

- Free space on device
- Check device storage settings

### "Object not found"

- Refresh the listing
- Verify the file still exists on device

### "Permission denied"

- Unlock device screen
- Accept trust prompt
- Check folder is writable

## Next Steps

- 📋 [Run Benchmarks](../howto/run-benchmarks.md) - Test your transfer speeds
- 📋 [Troubleshoot Issues](../howto/troubleshoot-connection.md) - Fix common problems
- 📋 [Device-Specific Guides](../reference/../SwiftMTP.docc/Devices/) - Learn about supported devices

## Summary

In this tutorial, you:
1. ✅ Listed device contents
2. ✅ Downloaded files from device
3. ✅ Uploaded files to device
4. ✅ Mirrored folders for backup
5. ✅ Used the GUI for drag-and-drop

You now know how to transfer files with SwiftMTP!
