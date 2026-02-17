# Getting Started with SwiftMTP

This tutorial walks you through setting up SwiftMTP and connecting to your first MTP device.

## Prerequisites

- macOS 26.0+ or iOS 26.0+
- Xcode 16.0+ with Swift 6.2+
- An MTP-compatible device (Android phone, camera, etc.)
- USB cable for device connection

## What You'll Learn

- Install SwiftMTP via Swift Package Manager
- Build and run the example app
- Connect to an MTP device
- List files on the device

## Step 1: Install SwiftMTP

### Using Swift Package Manager

Add SwiftMTP to your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyMTPApp",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/EffortlessMetrics/SwiftMTP.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyMTPApp",
            dependencies: ["SwiftMTPCore", "SwiftMTPUI"]
        )
    ]
)
```

### Using Homebrew (CLI only)

```bash
brew tap effortlessmetrics/swiftmtp
brew install swiftmtp
```

## Step 2: Set Up Your Device

Before running SwiftMTP, prepare your MTP device:

1. **Enable MTP Mode**: On Android, go to Settings > Storage > USB Computer Connection > File Transfer (MTP)
2. **Unlock Your Device**: Keep the screen unlocked during transfers
3. **Accept Trust Prompt**: When prompted on your device, tap "Trust This Computer"
4. **Use a Data Cable**: Ensure your USB cable supports data transfer (not charge-only)

## Step 3: Discover Devices

Run the CLI probe command to discover connected devices:

```bash
swift run swiftmtp probe
```

You should see output like:

```
[INFO] Scanning for MTP devices...
[INFO] Found device: Google Pixel 7 (18d1:4ee1)
[INFO] Manufacturer: Google
[INFO] Model: Pixel 7
[INFO] Serial: <redacted>
```

## Step 4: List Device Contents

Once a device is connected, list its contents:

```bash
swift run swiftmtp ls
```

This shows the storage volumes and top-level folders on your device.

## Step 5: Build the GUI App

To use the graphical interface:

```bash
swift run SwiftMTPApp
```

The app provides:
- Visual device browser
- Drag-and-drop file transfers
- Progress monitoring
- Device-specific settings

## Understanding the Output

### Device States

| State | Description |
|-------|-------------|
| `Discovered` | Device found on USB |
| `Enumerating` | Reading device information |
| `Ready` | Device ready for operations |
| `Transferring` | Active file transfer |
| `Error` | Error occurred |

### Common First Issues

**"No MTP device connected"**
- Verify device is in MTP mode (not PTP or charging)
- Try a different USB cable
- Unplug and reconnect the device

**"Permission denied"**
- Accept the "Trust This Computer" prompt
- Check USB debugging is disabled on Android

## Next Steps

Now that you've connected your first device:

- 📋 [Your First Transfer](first-transfer.md) - Learn to copy files
- 📋 [Run Benchmarks](../howto/run-benchmarks.md) - Test transfer performance
- 📋 [Troubleshoot Issues](../howto/troubleshoot-connection.md) - Common problems and solutions

## Summary

In this tutorial, you:
1. ✅ Added SwiftMTP to a project
2. ✅ Prepared an MTP device for connection
3. ✅ Discovered and probed the device
4. ✅ Launched the GUI application

Continue to [Your First Transfer](first-transfer.md) to learn about file operations.
