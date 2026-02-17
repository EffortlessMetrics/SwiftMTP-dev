# Performance Tuning Guide

This guide covers optimization techniques to maximize transfer speeds and overall performance when using SwiftMTP.

## Understanding Performance Factors

Multiple factors affect MTP transfer performance:

```
┌─────────────────────────────────────────────────────────────┐
│              Performance Factors                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐    ┌──────────────────┐              │
│  │  Hardware        │    │  Protocol        │              │
│  │  - USB version   │    │  - Chunk size    │              │
│  │  - Cable quality │    │  - Parallel ops  │              │
│  │  - Device speed  │    │  - Buffering     │              │
│  └──────────────────┘    └──────────────────┘              │
│                                                              │
│  ┌──────────────────┐    ┌──────────────────┐              │
│  │  Device          │    │  System          │              │
│  │  - Storage I/O   │    │  - CPU           │              │
│  │  - Driver quality│    │  - Memory        │              │
│  │  - MTP impl.     │    │  - I/O scheduling│              │
│  └──────────────────┘    └──────────────────┘              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## USB Connection Optimization

### USB Version Performance

| USB Version | Max Speed | Practical Speed | Recommendation |
|-------------|-----------|-----------------|----------------|
| USB 2.0 | 480 Mbps | 20-35 MB/s | Minimum acceptable |
| USB 3.0 | 5 Gbps | 200-300 MB/s | Recommended |
| USB 3.1 | 10 Gbps | 300-500 MB/s | Optimal |
| USB 3.2 | 20 Gbps | 500-900 MB/s | Best available |

### Selecting Optimal USB Ports

```bash
# List USB topology
system_profiler SPUSBDataType -json | jq '.SPUSBDataType[].devices[]'

# Check USB controller info
system_profiler SPPCI 2>/dev/null | grep -i usb
```

### Cable Quality Matters

```swift
// Quality cable recommendations
let cableRecommendations = [
    "USB-IF certified cables",
    "Short cables (< 1m) for maximum speed",
    "Avoid charging-only cables",
    "Braided cables for durability"
]

// Detect cable quality issues
func diagnoseUSBIssues() async throws -> USBDiagnostics {
    var issues: [String] = []
    
    // Check if running at USB 2.0 speeds on USB 3.x port
    let speed = try await getUSBSpeed()
    if speed == .highSpeed {
        issues.append("Device connected at USB 2.0 speed - try different port/cable")
    }
    
    return USBDiagnostics(
        currentSpeed: speed,
        issues: issues,
        recommendations: generateRecommendations(for: speed)
    )
}
```

## Transfer Buffer Configuration

### Buffer Size Guidelines

| File Type | Recommended Buffer | Rationale |
|-----------|-------------------|-----------|
| Small (<1MB) | 16KB - 64KB | Smaller buffers reduce latency |
| Medium (1-100MB) | 64KB - 256KB | Balance of throughput/latency |
| Large (100MB-1GB) | 256KB - 1MB | Maximize throughput |
| Very Large (>1GB) | 1MB - 4MB | Best for bulk transfers |

### Buffer Configuration Examples

```swift
import SwiftMTPCore

// Optimized for many small files
let smallFileOptions = TransferOptions(
    transferChunkSize: 32 * 1024,        // 32KB
    maxConcurrentTransfers: 4,
    bufferCount: 16
)

// Optimized for large files
let largeFileOptions = TransferOptions(
    transferChunkSize: 1024 * 1024,      // 1MB
    maxConcurrentTransfers: 2,
    bufferCount: 8
)

// Balanced for mixed workloads
let balancedOptions = TransferOptions(
    transferChunkSize: 256 * 1024,        // 256KB
    maxConcurrentTransfers: 3,
    bufferCount: 12
)
```

## Parallel Transfer Optimization

### Determining Optimal Parallelism

```swift
/// Calculate optimal parallel transfer count based on hardware
func calculateOptimalParallelism(
    deviceSpeed: DeviceSpeed,
    availableMemory: UInt64
) -> Int {
    // Base parallelism on USB version
    let baseParallelism: Int
    switch deviceSpeed {
    case .lowSpeed, .fullSpeed:
        return 1  // USB 2.0 - serial is better
    case .highSpeed:
        return 2  // USB 2.0 High Speed
    case .superSpeed:
        return 4  // USB 3.0
    case .superSpeedPlus:
        return 8  // USB 3.1+
    }
    
    // Adjust based on available memory
    // Each parallel transfer needs ~64MB buffer
    let memoryBasedParallelism = Int(availableMemory / (64 * 1024 * 1024))
    
    return min(baseParallelism, memoryBasedParallelism)
}
```

### Parallel vs Sequential Tradeoffs

```
┌─────────────────────────────────────────────────────────────┐
│         Parallel vs Sequential Transfer                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Sequential (1 file at a time):                             │
│  ┌──────┬──────┬──────┬──────┬──────┬──────┐               │
│  │ File │ File │ File │ File │ File │ File │               │
│  │  1   │  2   │  3   │  4   │  5   │  6   │               │
│  └──────┴──────┴──────┴──────┴──────┴──────┘               │
│  Total: T1 + T2 + T3 + T4 + T5 + T6                         │
│  Overhead: Low                                              │
│  Success rate: High                                         │
│                                                              │
│  Parallel (3 concurrent):                                   │
│  ┌──────┬──────┬──────┐                                     │
│  │File 1│File 2│File 3│  ← Batch 1                          │
│  └──────┴──────┴──────┘                                     │
│  ┌──────┬──────┬──────┐                                     │
│  │File 4│File 5│File 6│  ← Batch 2                          │
│  └──────┴──────┴──────┘                                     │
│  Total: max(T1,T2,T3) + max(T4,T5,T6)                      │
│  Overhead: Medium (coordination)                            │
│  Success rate: Lower (more failure points)                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Adaptive Parallelism

```swift
class AdaptiveTransferManager {
    private var currentParallelism: Int = 3
    private var recentThroughputs: [Double] = []
    
    func optimizeParallelism(during transfer: TransferProgress) {
        recentThroughputs.append(transfer.bytesPerSecond)
        
        // Keep last 10 measurements
        if recentThroughputs.count > 10 {
            recentThroughputs.removeFirst()
        }
        
        // Calculate trend
        let avgThroughput = recentThroughputs.reduce(0, +) / Double(recentThroughputs.count)
        
        // Adjust based on throughput
        if avgThroughput > 50 * 1024 * 1024 && currentParallelism < 8 {
            // High throughput - can handle more parallelism
            currentParallelism += 1
        } else if avgThroughput < 10 * 1024 * 1024 && currentParallelism > 1 {
            // Low throughput - reduce parallelism
            currentParallelism -= 1
        }
    }
}
```

## Device-Specific Optimization

### Querying Device Capabilities

```swift
func getDeviceCapabilities(device: MTPDevice) async throws -> DeviceCapabilities {
    let info = try await device.getDeviceInfo()
    
    return DeviceCapabilities(
        supportsGetPartialObject: info.capabilities.contains(.getPartialObject),
        supportsGetPartialObject64: info.capabilities.contains(.getPartialObject64),
        supportsSendObjectInfo: info.capabilities.contains(.sendObjectInfo),
        supportsSendObject: info.capabilities.contains(.sendObject),
        maxBufferSize: info.maxBufferSize,
        optimalTransferSize: info.optimalTransferSize
    )
}
```

### Device-Specific Configurations

```swift
let deviceOptimizations: [String: TransferOptions] = [
    // Google Pixel devices
    "Google_Pixel": TransferOptions(
        transferChunkSize: 512 * 1024,
        maxConcurrentTransfers: 4,
        useSendObject: true
    ),
    
    // Samsung devices
    "Samsung": TransferOptions(
        transferChunkSize: 256 * 1024,
        maxConcurrentTransfers: 3,
        useSendObject: true,
        retryAttempts: 5  // Samsung can be flaky
    ),
    
    // Xiaomi devices
    "Xiaomi": TransferOptions(
        transferChunkSize: 256 * 1024,
        maxConcurrentTransfers: 2,
        useSendObject: false,  // May have issues
        retryAttempts: 3
    )
]

func optionsForDevice(_ device: MTPDevice) -> TransferOptions {
    let vendor = device.info.vendorName ?? "Unknown"
    return deviceOptimizations[vendor] ?? TransferOptions()
}
```

## Memory Optimization

### Memory Usage Profiling

```swift
import Darwin

struct MemoryStats {
    var used: UInt64
    var free: UInt64
    var total: UInt64
    
    var usagePercentage: Double {
        Double(used) / Double(total) * 100
    }
}

func getMemoryStats() -> MemoryStats {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    
    let pageSize = UInt64(vm_kernel_page_size)
    
    return MemoryStats(
        used: UInt64(stats.active_count) * pageSize,
        free: UInt64(stats.free_count) * pageSize,
        total: ProcessInfo.processInfo.physicalMemory
    )
}
```

### Adaptive Memory Usage

```swift
class AdaptiveMemoryManager {
    private let maxMemoryUsageRatio: Double = 0.5  // Use max 50% of available memory
    
    func optimalBufferCount() -> Int {
        let available = ProcessInfo.processInfo.physicalMemory
        let usableMemory = UInt64(Double(available) * maxMemoryUsageRatio)
        
        // Each buffer is 256KB by default
        let bufferSize: UInt64 = 256 * 1024
        let maxBuffers = Int(usableMemory / bufferSize)
        
        // Return reasonable default with cap
        return min(max(4, maxBuffers), 32)
    }
    
    func adjustForMemoryPressure() {
        let stats = getMemoryStats()
        
        if stats.usagePercentage > 80 {
            // Reduce buffer count under memory pressure
            reduceBuffers()
        }
    }
}
```

## I/O Scheduling

### Optimizing for Different Workloads

```swift
enum TransferWorkload {
    case interactive  // User waiting, prioritize responsiveness
    case batch       // Background, prioritize throughput
    case sync        // Sync operations, balance both
}

func configureForWorkload(_ workload: TransferWorkload) -> TransferOptions {
    switch workload {
    case .interactive:
        return TransferOptions(
            maxConcurrentTransfers: 1,
            transferChunkSize: 64 * 1024,
            priority: .high,
            timeout: 30_000  // 30s timeout for responsiveness
        )
        
    case .batch:
        return TransferOptions(
            maxConcurrentTransfers: 8,
            transferChunkSize: 1024 * 1024,
            priority: .low,
            timeout: 600_000  // 10min timeout for bulk
        )
        
    case .sync:
        return TransferOptions(
            maxConcurrentTransfers: 3,
            transferChunkSize: 256 * 1024,
            priority: .normal,
            timeout: 120_000  // 2min timeout
        )
    }
}
```

## Benchmark-Driven Optimization

### Running Performance Tests

```bash
# Run benchmark suite
swift run swiftmtp benchmark --output benchmark-results.json

# Test specific device
swift run swiftmtp benchmark --device "Pixel 7" --iterations 5

# Compare transfer modes
swift run swiftmtp benchmark --compare-transfer-modes
```

### Interpreting Results

```swift
struct BenchmarkResults: Codable {
    let deviceName: String
    let testDate: Date
    let tests: [TransferBenchmark]
}

struct TransferBenchmark: Codable {
    let name: String
    let fileSize: UInt64
    let duration: TimeInterval
    let bytesPerSecond: Double
    let peakMemoryMB: Double
    let successRate: Double
}

func analyzeResults(_ results: BenchmarkResults) -> OptimizationSuggestion {
    let avgThroughput = results.tests.map { $0.bytesPerSecond }.reduce(0, +) / Double(results.tests.count)
    
    if avgThroughput < 10 * 1024 * 1024 {
        return OptimizationSuggestion(
            priority: .high,
            message: "Throughput below expected - check USB connection",
            actions: [
                "Verify USB 3.0+ connection",
                "Try different USB port",
                "Replace USB cable"
            ]
        )
    }
    
    return OptimizationSuggestion(
        priority: .low,
        message: "Performance is optimal",
        actions: []
    )
}
```

## Quick Performance Checklist

Use this checklist to verify optimal configuration:

```bash
# 1. Check USB version
system_profiler SPUSBDataType | grep -i "USB"

# 2. Verify cable is USB 3.x capable
#    (check for blue plastic in USB-A connector or USB-C)

# 3. Test different ports (prefer USB 3.x blue ports)

# 4. Disable other USB devices to reduce bus contention

# 5. Close other apps using the device

# 6. Ensure device screen is unlocked (some devices throttle when locked)
```

## Environment Variables for Performance

```bash
# Buffer size (in bytes)
export SWIFTMTP_BUFFER_SIZE=262144

# Number of concurrent transfers
export SWIFTMTP_PARALLEL=4

# Timeout settings (milliseconds)
export SWIFTMTP_IO_TIMEOUT_MS=30000
export SWIFTMTP_CONNECT_TIMEOUT_MS=10000

# Disable verification for speed (not recommended for production)
export SWIFTMTP_SKIP_VERIFY=false

# Enable performance logging
export SWIFTMTP_PERF_LOG=true
```

## Troubleshooting Slow Transfers

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| <5 MB/s | USB 2.0 connection | Use USB 3.0 port/cable |
| Variable speed | Cable quality | Replace cable |
| Slow on large files | Device storage | Device limitation |
| Slow after a while | Memory pressure | Reduce parallelism |
| Slow after errors | Retry overhead | Check device health |

## Related Documentation

- 📋 [Advanced Transfer Strategies](../tutorials/advanced-transfer.md) - Parallel and resumable transfers
- 📋 [Run Benchmarks](run-benchmarks.md) - Test your device performance
- 📋 [Device Quirks](device-quirks.md) - Device-specific behavior
- 📋 [Run Benchmarks](../howto/run-benchmarks.md) - Benchmarking guide

## Summary

Key performance optimization techniques:

1. ✅ Use USB 3.0+ ports and quality cables
2. ✅ Configure appropriate buffer sizes for your workload
3. ✅ Use parallelism wisely based on hardware capabilities
4. ✅ Apply device-specific optimizations when available
5. ✅ Monitor memory usage and adjust accordingly
6. ✅ Benchmark to measure improvements
7. ✅ Consider workload type when configuring transfers
