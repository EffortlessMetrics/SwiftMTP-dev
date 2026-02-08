# SwiftMTP Testing Guide

This document covers testing infrastructure, coverage status, and guidelines for adding new tests.

## Coverage Status

### Current Coverage Metrics (as of 2026-02-08)

| Target | Current | Target | Status |
|--------|---------|--------|--------|
| **SwiftMTPCore** | ~80% | ≥80% | ✅ Pass |
| **SwiftMTPIndex** | ~75% | ≥75% | ✅ Pass |
| **SwiftMTPObservability** | N/A | ≥70% | ⏳ Pending |
| **SwiftMTPQuirks** | N/A | ≥70% | ⏳ Pending |
| **SwiftMTPFileProvider** | N/A | ≥65% | ⏳ Pending |
| **Overall** | ~75% | ≥75% | ✅ Pass |

### Coverage by Component

```
SwiftMTPKit/Sources/
├── SwiftMTPCore/              ~80%
│   ├── CLI/                   90%
│   ├── Internal/              75%
│   └── Public/                85%
├── SwiftMTPIndex/             ~75%
│   ├── Cache/                 70%
│   ├── Crawler/               80%
│   ├── DB/                    75%
│   └── LiveIndex/             70%
├── SwiftMTPFileProvider/      ~65%
│   ├── DomainEnumerator/      60%
│   └── FileProviderManager/   70%
└── SwiftMTPCLI/               N/A
```

## Running Tests

### Local Testing

```bash
# Run all tests
cd SwiftMTPKit
./run-all-tests.sh

# Run with code coverage
swift test --enable-code-coverage

# Run specific test target
swift test --filter SwiftMTPCore

# Run tests in parallel
swift test --parallel
```

### CI Pipeline Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftMTP CI Pipeline                      │
├─────────────────────────────────────────────────────────────┤
│ Stage 1: Build                                               │
│   ├── swift build --configuration release                   │
│   ├── Build libusb xcframework                               │
│   └── Verify toolchain compatibility                        │
├─────────────────────────────────────────────────────────────┤
│ Stage 2: Unit Tests                                          │
│   ├── swift test --enable-code-coverage                     │
│   ├── Coverage threshold check                              │
│   └── Per-target coverage validation                        │
├─────────────────────────────────────────────────────────────┤
│ Stage 3: Integration                                         │
│   ├── Fuzz testing (smoke run)                              │
│   ├── Storybook demo                                        │
│   └── Quirks validation                                     │
├─────────────────────────────────────────────────────────────┤
│ Stage 4: Real Device (Manual Trigger)                       │
│   ├── Device probe tests                                    │
│   ├── Benchmark validation                                  │
│   └── Quirks evidence verification                         │
└─────────────────────────────────────────────────────────────┘
```

### TSAN Requirements

Thread Sanitizer (TSAN) is **required** for all new code that uses concurrency.

```bash
# Run tests with TSAN
swift test --sanitize thread

# TSAN requirements:
# - No data races in SwiftMTPCore
# - No data races in SwiftMTPIndex
# - All actors properly isolated
# - No @Sendable violations
```

**TSAN-specific guidelines:**

1. **Actor Isolation**: All mutable state in actors
2. **Sendable**: Mark all cross-actor transfers with `@Sendable`
3. **Nonisolated**: Use sparingly for truly immutable data
4. **Testing**: Run TSAN in CI for all PRs

### Real-Device Testing Guide

#### Prerequisites

```bash
# Hardware requirements
- MTP/PTP-compatible device
- USB cable (data-capable)
- Device in developer mode with USB debugging

# Software requirements
- SwiftMTP built from source
- Device connected: swift run swiftmtp --real-only probe
```

#### Test Categories

##### 1. Connection Tests

```bash
# Probe device
swift run swiftmtp --real-only probe

# Expected output:
# ✅ Device detected
# ✅ Interface claimed
# ✅ Session opened
# ✅ Storage enumerated
```

##### 2. Transfer Tests

```bash
# Read benchmark
swift run swiftmtp --real-only bench 100M --repeat 3

# Write benchmark
swift run swiftmtp --real-only bench 100M --repeat 3 --direction write

# Expected output:
# - Read: ~35 MB/s (USB 3.0) or ~15 MB/s (USB 2.0)
# - Write: ~25 MB/s (USB 3.0) or ~12 MB/s (USB 2.0)
```

##### 3. Resume Tests

```bash
# Interrupt and resume
swift run swiftmtp --real-only bench 500M --interrupt 50 --resume
```

##### 4. Mirror Tests

```bash
# Test mirror functionality
swift run swiftmtp --real-only mirror ~/PhoneBackup \
  --include "DCIM/**" \
  --out mirror-log.txt
```

#### Device-Specific Notes

| Device | Known Issues | Workarounds |
|--------|--------------|-------------|
| Pixel 7 | Bulk transfer timeout on macOS 26 | Use older macOS or different hub |
| OnePlus 3T | SendObject size limit | Split large files |
| Xiaomi | DEVICE_BUSY on first attempt | Add 250-500ms delay |
| Samsung | USB 2.0 speed limitation | Direct port connection |

## Adding New Tests

### Test Structure

```
SwiftMTPKit/Tests/
├── SwiftMTPCoreTests/
│   ├── DeviceActorTests.swift
│   ├── TransferTests.swift
│   └── ProtocolTests.swift
├── SwiftMTPIndexTests/
│   ├── IndexManagerTests.swift
│   └── DiffEngineTests.swift
└── SwiftMTPUtilTests/
    └── QuirkResolverTests.swift
```

### Example: Adding a Transfer Test

```swift
import XCTest
@testable import SwiftMTPCore

final class TransferTests: XCTestCase {
    
    func testPartialObjectTransfer() throws {
        // Given
        let device = TestDevice.connected()
        let data = Data(repeating: 0xAA, count: 1024 * 1024) // 1MB
        
        // When
        let receipt = try device.sendObject(data: data)
        
        // Then
        XCTAssertEqual(receipt.status, .success)
        XCTAssertEqual(receipt.bytesWritten, data.count)
    }
    
    func testLargeFileTransfer() throws {
        // Given
        let device = TestDevice.connected()
        let size = 100 * 1024 * 1024 // 100MB
        
        // When
        let receipt = try device.sendObject(size: size)
        
        // Then
        XCTAssertEqual(receipt.status, .success)
        XCTAssertGreaterThan(receipt.speedMBps, 10.0)
    }
}
```

### Test Best Practices

1. **Use Test Fixtures**: Reuse common setup code
2. **Mock External Dependencies**: Use protocols for device interactions
3. **Isolate Tests**: Each test should be independent
4. **Test Edge Cases**: Timeouts, interruptions, errors
5. **Measure Performance**: Include timing assertions
6. **Document Expectations**: Comment on expected behavior

### Test Coverage Requirements

| Category | Minimum Coverage | Examples |
|----------|------------------|----------|
| Error Paths | 100% | All error cases must be tested |
| Public API | 100% | All public methods/functions |
| Actors | 90% | All actor methods |
| Async Operations | 95% | All async functions |

## Continuous Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macOS-14
    steps:
      - uses: actions/checkout@v4
      - uses: swiftwasm/setup-swift@v1
        with:
          swift-version: "6.0"
      - name: Build
        run: swift build
      - name: Test
        run: swift test --enable-code-coverage
      - name: Coverage Report
        run: ./run-all-tests.sh
      - name: TSAN
        if: matrix.sanitize == 'thread'
        run: swift test --sanitize thread
```

### Coverage Enforcement

Coverage thresholds are enforced in CI:

```bash
# From run-all-tests.sh
THRESHOLD_OVERALL=75
THRESHOLD_SWIFTCORE=80
THRESHOLD_INDEX=75
```

If coverage falls below threshold:
1. CI job fails
2. PR cannot be merged
3. Add tests to increase coverage

## Troubleshooting Tests

### Common Issues

#### "Test timed out"
- Increase timeout for slow devices
- Use mock devices for CI

#### "Coverage decreased"
- Check which lines are now uncovered
- Add tests for new code paths

#### "TSAN data race"
- Ensure proper actor isolation
- Use `@Sendable` annotations

### Getting Help

- See [Troubleshooting](Troubleshooting.md)
- Search existing tests for similar scenarios
- Ask in GitHub Discussions

---

*See also: [ROADMAP.md](ROADMAP.md) | [Device Submission](ROADMAP.device-submission.md) | [Release Checklist](ROADMAP.release-checklist.md)*
