# Testing MTP Devices

This guide covers comprehensive testing strategies for MTP devices with SwiftMTP, including automated tests, manual verification, and diagnostic procedures.

## Overview

Testing MTP devices requires understanding both the protocol capabilities and device-specific behaviors:

```
┌─────────────────────────────────────────────────────────────┐
│                  Testing Framework                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 1. Connection Tests                                  │   │
│  │    - Device discovery                                │   │
│  │    - Session establishment                           │   │
│  │    - Capability detection                            │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 2. Operations Tests                                  │   │
│  │    - File listing                                    │   │
│  │    - File transfer (read/write)                     │   │
│  │    - Folder operations                               │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 3. Performance Tests                                 │   │
│  │    - Transfer speed                                  │   │
│  │    - Latency measurement                             │   │
│  │    - Concurrent operations                           │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 4. Edge Case Tests                                   │   │
│  │    - Large files                                     │   │
│  │    - Special characters                              │   │
│  │    - Interrupted transfers                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

```bash
# Install required tools
brew install libusb

# Clone SwiftMTP for testing
git clone https://github.com/SwiftMTP/SwiftMTP.git
cd SwiftMTP
swift build
```

## Connection Testing

### Test 1: Device Discovery

```bash
# Basic device discovery
swift run swiftmtp devices

# Expected output:
# Found 1 device(s):
#   - Google Pixel 7 (USB: 18d1:4ee1)
```

### Test 2: Session Establishment

```swift
import SwiftMTPCore

/// Test device connection and session
func testDeviceConnection() async throws -> ConnectionTestResult {
    var results: [TestResult] = []
    
    // Test 1: Discover devices
    do {
        let devices = try await MTPDevice.discoverAll()
        results.append(TestResult(
            name: "Device Discovery",
            passed: !devices.isEmpty,
            message: "Found \(devices.count) device(s)"
        ))
    } catch {
        results.append(TestResult(
            name: "Device Discovery",
            passed: false,
            message: "Error: \(error)"
        ))
    }
    
    // Test 2: Open session
    if let device = try await MTPDevice.discoverFirst() {
        do {
            try await device.openSession()
            results.append(TestResult(
                name: "Session Open",
                passed: true,
                message: "Session established successfully"
            ))
            
            // Test 3: Get device info
            let info = try await device.getDeviceInfo()
            results.append(TestResult(
                name: "Device Info",
                passed: true,
                message: "Manufacturer: \(info.manufacturer), Model: \(info.model)"
            ))
            
            try await device.closeSession()
        } catch {
            results.append(TestResult(
                name: "Session Open",
                passed: false,
                message: "Error: \(error)"
            ))
        }
    }
    
    return ConnectionTestResult(results: results)
}
```

### Test 3: Capability Detection

```swift
/// Test and report device capabilities
func testDeviceCapabilities() async throws -> CapabilitiesReport {
    let device = try await MTPDevice.discoverFirst()
    try await device.openSession()
    
    let info = try await device.getDeviceInfo()
    
    let capabilities = DeviceCapabilities(
        // Operations
        canGetDeviceInfo: true,
        canGetStorageIDs: true,
        canGetStorageInfo: info.storages.count > 0,
        canGetObjectHandles: true,
        canGetObjectInfo: true,
        canGetObject: info.operations.contains(.getObject),
        canSendObjectInfo: info.operations.contains(.sendObjectInfo),
        canSendObject: info.operations.contains(.sendObject),
        canDeleteObject: info.operations.contains(.deleteObject),
        
        // Advanced
        supportsPartialDownload: info.operations.contains(.getPartialObject),
        supportsPartialDownload64: info.operations.contains(.getPartialObject64),
        supportsBatchOperations: info.operations.contains(.startBatch),
        supportsEvents: info.capabilities.contains(.events)
    )
    
    return CapabilitiesReport(
        deviceId: info.deviceId,
        deviceName: info.model,
        capabilities: capabilities
    )
}
```

## File Operations Testing

### Test 4: Directory Listing

```bash
# List root directory
swift run swiftmtp ls

# List with details
swift run swiftmtp ls -l /

# Expected output format:
# Storage: Primary (0)
# ├── DCIM/
# │   └── Camera/
# ├── Download/
# └── Pictures/
```

### Test 5: File Transfer Tests

```swift
/// Comprehensive file transfer test suite
class FileTransferTestSuite {
    private let device: MTPDevice
    private let testDirectory: String = "/SwiftMTP_Test"
    
    init(device: MTPDevice) {
        self.device = device
    }
    
    func runAllTests() async throws -> TransferTestReport {
        var results: [TransferTestResult] = []
        
        // Setup test directory
        try await setupTestDirectory()
        
        // Run tests
        results.append(try await testSmallFileUpload())
        results.append(try await testLargeFileUpload())
        results.append(try await testSmallFileDownload())
        results.append(try await testLargeFileDownload())
        results.append(try await testFolderCreation())
        results.append(try await testFileDeletion())
        results.append(try await testSpecialCharacters())
        
        // Cleanup
        try await cleanupTestDirectory()
        
        return TransferTestReport(results: results)
    }
    
    private func testSmallFileUpload() async throws -> TransferTestResult {
        let testFile = createTestFile(size: 1024)  // 1KB
        let startTime = Date()
        
        do {
            try await device.upload(
                from: testFile.path,
                to: "\(testDirectory)/small.txt"
            )
            
            let duration = Date().timeIntervalSince(startTime)
            return TransferTestResult(
                name: "Small File Upload (1KB)",
                passed: true,
                duration: duration,
                throughput: 1024 / duration
            )
        } catch {
            return TransferTestResult(
                name: "Small File Upload (1KB)",
                passed: false,
                error: error.localizedDescription
            )
        }
    }
    
    private func testLargeFileUpload() async throws -> TransferTestResult {
        let testFile = createTestFile(size: 10 * 1024 * 1024)  // 10MB
        let startTime = Date()
        
        do {
            try await device.upload(
                from: testFile.path,
                to: "\(testDirectory)/large.dat"
            )
            
            let duration = Date().timeIntervalSince(startTime)
            return TransferTestResult(
                name: "Large File Upload (10MB)",
                passed: true,
                duration: duration,
                throughput: (10 * 1024 * 1024) / duration
            )
        } catch {
            return TransferTestResult(
                name: "Large File Upload (10MB)",
                passed: false,
                error: error.localizedDescription
            )
        }
    }
    
    private func testSpecialCharacters() async throws -> TransferTestResult {
        let testFiles = [
            "simple.txt",
            "with spaces.txt",
            "with-dash.txt",
            "with_underscore.txt",
            "withemoji😀.txt",
            "utf8_日本語.txt"
        ]
        
        var allPassed = true
        var errors: [String] = []
        
        for filename in testFiles {
            do {
                let testFile = createTestFile(size: 100, filename: filename)
                try await device.upload(
                    from: testFile.path,
                    to: "\(testDirectory)/\(filename)"
                )
            } catch {
                allPassed = false
                errors.append("\(filename): \(error)")
            }
        }
        
        return TransferTestResult(
            name: "Special Characters",
            passed: allPassed,
            error: errors.isEmpty ? nil : errors.joined(separator: ", ")
        )
    }
    
    private func createTestFile(size: Int, filename: String = "test.dat") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent(filename)
        
        let data = Data(count: size)
        try? data.write(to: file)
        
        return file
    }
}
```

## Performance Testing

### Test 6: Transfer Speed Benchmark

```bash
# Run built-in benchmark
swift run swiftmtp benchmark --device "Pixel 7"

# Generate benchmark report
swift run swiftmtp benchmark \
  --iterations 5 \
  --sizes 1KB,1MB,10MB,100MB,1GB \
  --output benchmark.json
```

### Test 7: Latency Measurement

```swift
/// Measure command latency
class LatencyTest {
    func measureOperationLatency(
        device: MTPDevice,
        operation: String,
        iterations: Int = 100
    ) async throws -> LatencyReport {
        var latencies: [TimeInterval] = []
        
        for _ in 0..<iterations {
            let start = Date()
            
            switch operation {
            case "ls":
                _ = try await device.listDirectory(at: "/")
            case "stat":
                let handles = try await device.getObjectHandles(storage: 0)
                if let handle = handles.first {
                    _ = try await device.getObjectInfo(handle: handle)
                }
            default:
                break
            }
            
            let duration = Date().timeIntervalSince(start)
            latencies.append(duration)
            
            // Small delay between operations
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        latencies.sort()
        
        return LatencyReport(
            operation: operation,
            iterations: iterations,
            min: latencies.first ?? 0,
            max: latencies.last ?? 0,
            avg: latencies.reduce(0, +) / Double(iterations),
            p50: latencies[latencies.count / 2],
            p95: latencies[Int(Double(latencies.count) * 0.95)],
            p99: latencies[Int(Double(latencies.count) * 0.99)]
        )
    }
}
```

## Edge Case Testing

### Test 8: Large File Handling

```swift
/// Test handling of very large files
func testLargeFileSupport(device: MTPDevice) async throws -> LargeFileTestResult {
    let testSizes: [UInt64] = [
        100 * 1024 * 1024,      // 100MB
        500 * 1024 * 1024,      // 500MB
        1024 * 1024 * 1024,    // 1GB
    ]
    
    var results: [TestResult] = []
    
    for size in testSizes {
        let testFile = createTestFile(size: Int(size))
        
        let startTime = Date()
        do {
            try await device.upload(
                from: testFile.path,
                to: "/SwiftMTP_Test/large_\(size).dat"
            )
            
            let duration = Date().timeIntervalSince(startTime)
            results.append(TestResult(
                name: "Upload \(formatBytes(size))",
                passed: true,
                message: "Completed in \(String(format: "%.1f", duration))s"
            ))
        } catch {
            results.append(TestResult(
                name: "Upload \(formatBytes(size))",
                passed: false,
                message: "Failed: \(error)"
            ))
        }
    }
    
    return LargeFileTestResult(results: results)
}
```

### Test 9: Concurrent Operations

```swift
/// Test concurrent transfer handling
func testConcurrentOperations(device: MTPDevice) async throws -> ConcurrentTestResult {
    // Create multiple test files
    let files = (0..<5).map { i in
        createTestFile(size: 1024 * 1024, filename: "concurrent_\(i).dat")
    }
    
    // Upload concurrently
    await withTaskGroup(of: Void.self) { group in
        for file in files {
            group.addTask {
                try? await device.upload(
                    from: file.path,
                    to: "/SwiftMTP_Test/\(file.lastPathComponent)"
                )
            }
        }
    }
    
    // Verify all files
    var allSucceeded = true
    for file in files {
        let filename = file.lastPathComponent
        if !(try? await device.fileExists(at: "/SwiftMTP_Test/\(filename)")) {
            allSucceeded = false
        }
    }
    
    return ConcurrentTestResult(
        testName: "5 Concurrent Uploads",
        passed: allSucceeded,
        totalFiles: files.count
    )
}
```

## Automated Test Runner

### Running Full Test Suite

```bash
# Run complete test suite
swift test --device "Pixel 7" --suite full

# Run specific test categories
swift test --device "Pixel 7" --suite connection
swift test --device "Pixel 7" --suite transfer
swift test --device "Pixel 7" --suite performance
swift test --device "Pixel 7" --suite edge-cases

# Generate test report
swift test --device "Pixel 7" --output test-report.json
```

### CI Integration

```yaml
# .github/workflows/device-test.yml
name: Device Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build
        run: swift build
      
      - name: Run Tests
        run: |
          swift test --device "Test Device" \
            --output test-results.json
      
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test-results.json
```

## Device-Specific Testing

### Android Devices

```bash
# Enable developer mode and USB debugging
# Settings > About Phone > Build Number (tap 7 times)
# Settings > Developer Options > USB Debugging

# Verify MTP mode
swift run swiftmtp devices -v

# Run Android-specific tests
swift test --device "Pixel" --include android
```

### iOS Devices (via Files App)

```bash
# Connect iOS device and approve in Finder
# Ensure "Connect to this iPhone over Wi-Fi" is disabled for testing

swift run swiftmtp devices
# Should show iOS device

swift test --device "iPhone" --include ios
```

## Test Result Analysis

### Understanding Test Results

```swift
struct TestSummary {
    let totalTests: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    
    var passRate: Double {
        guard totalTests > 0 else { return 0 }
        return Double(passed) / Double(totalTests) * 100
    }
    
    var status: String {
        if failed == 0 { return "✅ PASS" }
        if passRate > 80 { return "⚠️ MOSTLY PASS" }
        return "❌ FAIL"
    }
}

func analyzeResults(_ report: TestReport) -> TestSummary {
    let summary = TestSummary(
        totalTests: report.results.count,
        passed: report.results.filter { $0.passed }.count,
        failed: report.results.filter { !$0.passed }.count,
        skipped: report.results.filter { $0.skipped }.count
    )
    
    print("""
    Test Summary
    ============
    Total: \(summary.totalTests)
    Passed: \(summary.passed)
    Failed: \(summary.failed)
    Skipped: \(summary.skipped)
    Pass Rate: \(String(format: "%.1f", summary.passRate))%
    Status: \(summary.status)
    """)
    
    return summary
}
```

## Common Test Failures

| Error Code | Description | Likely Cause | Solution |
|------------|-------------|--------------|----------|
| 0x2019 | Store not available | Storage disconnected | Re-mount storage |
| 0x201D | Invalid parameter | Path issue | Check path format |
| 0x201F | Store read-only | Write-protected | Check device settings |
| 0x2020 | Object not found | File deleted | Refresh listing |
| 0x2021 | Device busy | Concurrent access | Retry after delay |
| 0x2022 | Operation canceled | User canceled | Retry |

## Submitting Test Results

If you've tested a new device, submit results to help improve SwiftMTP:

```bash
# Generate device probe
swift run swiftmtp probe --output my-device-probe.txt

# Submit via GitHub issue or pull request
# See CONTRIBUTING.md for submission guidelines
```

## Related Documentation

- 📋 [Device Probing](device-probing.md) - Analyzing device capabilities
- 📋 [Device Quirks](device-quirks.md) - Handling device-specific issues
- 📋 [Add Device Support](add-device-support.md) - Adding new device support
- 📋 [Run Benchmarks](run-benchmarks.md) - Performance testing

## Summary

Testing checklist for MTP devices:

1. ✅ Connection tests (discovery, session, info)
2. ✅ Capability detection
3. ✅ File upload/download
4. ✅ Folder operations
5. ✅ Special character handling
6. ✅ Large file support
7. ✅ Concurrent operations
8. ✅ Performance benchmarks
9. ✅ Error handling
10. ✅ Submit results to improve SwiftMTP
