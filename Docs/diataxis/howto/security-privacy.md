# Security and Privacy Best Practices

This guide covers security and privacy considerations when using SwiftMTP to transfer data between your computer and MTP devices.

## Overview

When transferring sensitive data over MTP (Media Transfer Protocol), several security considerations apply:

```
┌─────────────────────────────────────────────────────────────┐
│                  Security Layers                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 1. Transport Security (USB)                          │   │
│  │    - USB connections are local only                  │   │
│  │    - No network exposure by default                   │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 2. Device Authentication                             │   │
│  │    - Device trust prompts                            │   │
│  │    - Encryption varies by device                     │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 3. Data Handling                                    │   │
│  │    - Temporary file handling                         │   │
│  │    - Memory cleanup                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 4. Access Control                                   │   │
│  │    - File permission enforcement                     │   │
│  │    - Scope-limited operations                        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## USB Transport Security

### Understanding USB Security

MTP over USB has inherent security properties:

- **Local-only**: Data doesn't traverse the network
- **Direct connection**: Point-to-point USB link
- **No encryption**: Standard USB doesn't mandate encryption

### Best Practices

```bash
# Always use trusted USB ports
# Avoid public charging stations with data transfer

# Verify device fingerprint
swift run swiftmtp info --verbose

# Check for unexpected devices
system_profiler SPUSBDataType
```

### USB Port Security

```swift
// Only allow connections to specific devices
let trustedDevices: Set<String> = [
    "Google_Pixel_7_4ee1",
    "Samsung_Galaxy_S23_1234"
]

func connectIfTrusted(_ device: MTPDevice) throws {
    let fingerprint = device.identifier
    guard trustedDevices.contains(fingerprint) else {
        throw SecurityError.untrustedDevice(fingerprint)
    }
    try device.connect()
}
```

## Device Trust and Authentication

### Understanding Device Trust

Modern Android devices implement trust mechanisms:

```
┌─────────────────────────────────────────────────────────────┐
│              Device Trust Flow                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Device Connected                                            │
│        │                                                      │
│        ▼                                                      │
│  ┌─────────────┐     No      ┌────────────────┐             │
│  │ Trusted?    │────────────▶│ Show Trust     │             │
│  └─────────────┘             │ Prompt         │             │
│        │ Yes                 └────────────────┘             │
│        ▼                           │                         │
│  ┌─────────────┐                   │                         │
│  │ Allow MTP   │◀──────────────────┘                         │
│  │ Access      │                                            │
│  └─────────────┘                                            │
│        │                                                      │
│        ▼                                                      │
│  Session Established                                          │
└─────────────────────────────────────────────────────────────┘
```

### Managing Device Trust

```swift
// Handle trust prompts programmatically
class TrustManager {
    enum TrustState {
        case trusted
        case untrusted
        case unknown
    }
    
    func checkTrustState(for device: MTPDevice) async -> TrustState {
        do {
            // Attempt to open session
            try await device.openSession()
            return .trusted
        } catch MTPError.deviceNotTrusted {
            return .untrusted
        } catch {
            return .unknown
        }
    }
    
    func promptUserToTrust(device: MTPDevice) async throws {
        // Note: Trust must be granted by user on device
        // This method waits for user action
        var attempts = 0
        while attempts < 30 {
            let state = await checkTrustState(for: device)
            if state == .trusted { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            attempts += 1
        }
        throw TrustError.userDidNotGrantTrust
    }
}
```

## Data Handling Security

### Temporary Files

SwiftMTP creates temporary files during transfers. These are handled securely:

```swift
import Foundation

class SecureTransferHandler {
    private let tempDirectory: URL
    
    init() {
        // Use secure temporary directory
        let tempPath = NSTemporaryDirectory()
        tempDirectory = URL(fileURLWithPath: tempPath)
            .appendingPathComponent("swiftmtp", isDirectory: true)
        
        // Create with restricted permissions
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700  // Owner read/write/execute only
            ]
        )
    }
    
    func secureTransfer(
        source: URL,
        destination: URL,
        cleanup: Bool = true
    ) async throws {
        let tempFile = tempDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            if cleanup {
                try? FileManager.default.removeItem(at: tempFile)
            }
        }
        
        // Perform transfer through temp file
        try await copyWithProgress(from: source, to: tempFile)
        
        // Move to final destination
        try FileManager.default.moveItem(at: tempFile, to: destination)
    }
}
```

### Memory Security

```swift
class SecureMemoryHandler {
    /// Clear sensitive data from memory
    func securelyWipe(_ data: inout Data) {
        data.withUnsafeMutableBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                memset(baseAddress, 0, buffer.count)
            }
        }
        data = Data()
    }
    
    /// Use secure string for sensitive data
    func processWithSecureString(_ operation: (SecureString) throws -> Void) {
        var secureString = SecureString()
        
        defer {
            secureString.clear()
        }
        
        try? operation(secureString)
    }
}

/// Secure string implementation
class SecureString {
    private var data: [UInt8] = []
    
    func append(_ character: UInt8) {
        data.append(character)
    }
    
    func clear() {
        for i in 0..<data.count {
            data[i] = 0
        }
        data.removeAll()
    }
}
```

## File Permission Security

### Understanding MTP Permissions

MTP devices enforce their own permission model:

| Permission | Description | SwiftMTP Handling |
|------------|-------------|-------------------|
| Read | View/download files | ✅ Supported |
| Write | Create/modify files | ✅ Supported |
| Delete | Remove files | ✅ Supported |
| Browse | Navigate storage | ✅ Supported |

### Permission Enforcement

```swift
import SwiftMTPCore

func safeTransfer(
    sourcePath: String,
    destinationPath: String,
    requireWriteAccess: Bool = true
) async throws {
    let device = try await MTPDevice.discoverFirst()
    try await device.openSession()
    
    // Check write access before transfer
    if requireWriteAccess {
        let parentPath = (destinationPath as NSString).deletingLastPathComponent
        guard try await device.canWrite(to: parentPath) else {
            throw SecurityError.noWritePermission(parentPath)
        }
    }
    
    // Perform transfer
    try await device.upload(from: sourcePath, to: destinationPath)
}
```

## Privacy Considerations

### Minimizing Data Exposure

```swift
class PrivacyManager {
    /// Log without sensitive data
    func logTransfer(_ info: TransferInfo) {
        let safeLog = """
        Transfer: \(info.filename)  # No full paths
        Size: \(info.fileSize)
        Status: \(info.status)
        """
        print(safeLog)
    }
    
    /// Anonymize device identifiers for analytics
    func anonymizeDeviceId(_ id: String) -> String {
        // Return truncated hash instead of actual ID
        let hash = id.hashValue
        return "device-\(String(hash, radix: 16).prefix(8))"
    }
}
```

### Avoiding Unintentional Data Transfer

```swift
class TransferScopeLimiter {
    /// Define allowed paths for transfer
    let allowedPaths = [
        "/DCIM/Camera",
        "/Download",
        "/Pictures/WhatsApp"
    ]
    
    /// Blocked paths that should never be accessed
    let blockedPaths = [
        "/Android/data",
        "/.android",
        "/.ssh",
        "/.gnupg"
    ]
    
    func validatePath(_ path: String) throws {
        // Check blocked paths first
        for blocked in blockedPaths {
            if path.hasPrefix(blocked) {
                throw SecurityError.pathBlocked(path)
            }
        }
        
        // Check allowed paths (if strict mode)
        let isAllowed = allowedPaths.contains { path.hasPrefix($0) }
        if !isAllowed && !allowedPaths.isEmpty {
            throw SecurityError.pathNotAllowed(path)
        }
    }
}
```

## Secure Configuration

### Environment Variables for Security

```bash
# Maximum transfer size (prevent accidental large transfers)
export SWIFTMTP_MAX_TRANSFER_SIZE=10737418240  # 10GB

# Timeout settings (prevent hanging connections)
export SWIFTMTP_CONNECT_TIMEOUT_MS=10000
export SWIFTMTP_IO_TIMEOUT_MS=30000

# Disable auto-connect to unknown devices
export SWIFTMTP_AUTO_CONNECT=false
```

### Code Configuration

```swift
import SwiftMTPCore

let secureOptions = DeviceOptions(
    // Connection security
    autoConnect: false,
    verifyDeviceCertificate: true,
    
    // Transfer security
    maxTransferSize: 10 * 1024 * 1024 * 1024,  // 10GB
    encryptTempFiles: true,
    
    // Privacy
    logLevel: .error,  // Reduce logging in production
    anonymizeLogs: true
)

let device = try await MTPDevice.connect(options: secureOptions)
```

## Security Auditing

### Enable Security Logging

```bash
# Enable security-relevant logging
export SWIFTMTP_LOG_LEVEL=debug
export SWIFTMTP_LOG_SECURITY=true

# Run with audit logging
swift run swiftmtp --audit-log /var/log/swiftmtp/audit.log ls
```

### Audit Events

```swift
enum SecurityAuditEvent: Codable {
    case deviceConnected(deviceId: String)
    case deviceDisconnected(deviceId: String)
    case transferStarted(path: String, size: UInt64)
    case transferCompleted(path: String)
    case permissionDenied(path: String)
    case trustPromptShown(deviceId: String)
    case untrustedDeviceBlocked(deviceId: String)
}

class SecurityAuditor {
    func log(_ event: SecurityAuditEvent) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(event),
           let json = String(data: data, encoding: .utf8) {
            // Write to secure audit log
            writeToAuditLog(json)
        }
    }
}
```

## Common Security Scenarios

### Scenario 1: Transfer Sensitive Photos

```swift
// Ensure photos are transferred securely
func transferSensitivePhotos() async throws {
    let device = try await MTPDevice.discoverFirst()
    try await device.openSession()
    
    let options = TransferOptions(
        encryptTempFiles: true,
        verifyChecksum: true,
        cleanupTempFiles: true
    )
    
    // Transfer with security measures
    try await device.download(
        from: "/DCIM/Camera/sensitive.jpg",
        to: "~/Secure/sensitive.jpg",
        options: options
    )
}
```

### Scenario 2: Work Device with Strict Policy

```swift
// Configure for corporate/secure environment
func configureForSecureEnvironment() {
    let strictOptions = DeviceOptions(
        autoConnect: false,
        requireUserApproval: true,
        allowedPaths: ["/Download", "/Documents/Work"],
        blockedPaths: ["/Private", "/.ssh", "/.android"],
        maxTransferSize: 1024 * 1024 * 1024,  // 1GB
        auditAllOperations: true
    )
    
    // Apply to device
    configureDevice(with: strictOptions)
}
```

## Troubleshooting Security Issues

| Issue | Solution |
|-------|----------|
| "Device not trusted" | Unlock device and accept trust prompt on device screen |
| "Permission denied" | Check folder permissions on device |
| "Transfer blocked" | Verify path is not in blocked list |
| "Unusual device detected" | Check connected devices with `system_profiler SPUSBDataType` |

## Related Documentation

- 📋 [Transfer Files](transfer-files.md) - Basic transfer operations
- 📋 [Troubleshoot Connection](troubleshoot-connection.md) - Connection issues
- 📋 [Device Quirks](device-quirks.md) - Device-specific behavior

## Summary

Key security practices when using SwiftMTP:

1. ✅ Use trusted USB ports and cables
2. ✅ Verify device trust before sensitive transfers
3. ✅ Configure secure temporary file handling
4. ✅ Set appropriate transfer limits
5. ✅ Enable audit logging for sensitive operations
6. ✅ Follow the principle of least privilege for file access
