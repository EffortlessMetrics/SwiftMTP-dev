# SwiftMTP Benchmark Report
Device: pixel7
Timestamp: Wed Sep  3 13:29:30 EDT 2025
Mode: Mock (pixel7)

## Device Information
```
warning: 'swiftmtpkit': Source files for target TransportTests should be located under 'Tests/TransportTests', or a custom sources path can be set with the 'path' property in Package.swift
warning: 'sqlite.swift': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Users/steven/Code/Mac/Swift/SwiftMTP/SwiftMTPKit/.build/checkouts/SQLite.swift/Sources/SQLite/PrivacyInfo.xcprivacy
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'swiftmtp' complete! (1.02s)
🔍 Probing device capabilities...

📱 Device Information:
   Manufacturer: Google
   Model: Pixel 7
   Version: Mock Version 1.0
   Serial Number: MOCK123456

⚙️  Supported Operations (4):
   0x1001 - GetDeviceInfo
   0x1002 - OpenSession
   0x1004 - GetStorageIDs
   0x1005 - GetStorageInfo

💾 Storage Devices (2):
   📁 Internal Storage
      Capacity: 119.2 GB
      Free: 74.5 GB
      Used: 44.7 GB (37.5%)
      Read-only: No

   📁 SD Card
      Capacity: 238.4 GB
      Free: 186.3 GB
      Used: 52.2 GB (21.9%)
      Read-only: No

📄 Sample Files (first 10 from root):
   Association: 2 files

✅ Probe complete
```

## Benchmark Results
### 100m Transfer
```
warning: 'swiftmtpkit': Source files for target TransportTests should be located under 'Tests/TransportTests', or a custom sources path can be set with the 'path' property in Package.swift
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'swiftmtp' complete! (0.13s)
🏃 Running transfer benchmark (100.0 MB test file)...

📝 Generating test file...
📤 Benchmarking write performance...
   ✅ Write: 0.49 MB/s (205.8s)
🔍 Locating uploaded file...
❌ Could not find uploaded test file
```

### 1g Transfer
```
warning: 'swiftmtpkit': Source files for target TransportTests should be located under 'Tests/TransportTests', or a custom sources path can be set with the 'path' property in Package.swift
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'swiftmtp' complete! (0.14s)
🏃 Running transfer benchmark (1.0 GB test file)...

📝 Generating test file...
📤 Benchmarking write performance...
   ✅ Write: 3.88 MB/s (264.2s)
🔍 Locating uploaded file...
❌ Could not find uploaded test file
```

### 500m Transfer
```
warning: 'swiftmtpkit': Source files for target TransportTests should be located under 'Tests/TransportTests', or a custom sources path can be set with the 'path' property in Package.swift
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'swiftmtp' complete! (0.14s)
🏃 Running transfer benchmark (500.0 MB test file)...

📝 Generating test file...
📤 Benchmarking write performance...
   ✅ Write: 3.85 MB/s (130.0s)
🔍 Locating uploaded file...
❌ Could not find uploaded test file
```

## Mirror Test
```
warning: 'swiftmtpkit': Source files for target TransportTests should be located under 'Tests/TransportTests', or a custom sources path can be set with the 'path' property in Package.swift
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build of product 'swiftmtp' complete! (0.14s)
🔄 Starting mirror operation...
   Source: test-device-1756920569
   Destination: /tmp/swiftmtp-test-mirror
✅ Mirror completed!
   Downloaded: 2
   Skipped: 0
   Failed: 0
   Success rate: 100.0%
```
