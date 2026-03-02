# SwiftMTP Code Coverage Guide

This document explains the code coverage configuration for SwiftMTP, including how to run coverage locally, understand metrics, and improve coverage.

## Table of Contents

1. [Overview](#overview)
2. [Running Coverage Locally](#running-coverage-locally)
3. [Coverage Goals and Thresholds](#coverage-goals-and-thresholds)
4. [Understanding Coverage Metrics](#understanding-coverage-metrics)
5. [Improving Coverage](#improving-coverage)
6. [CI Integration](#ci-integration)

---

## Overview

SwiftMTP uses Swift's built-in code coverage tools to measure test effectiveness. The coverage system is configured to:

- **Track coverage** for the CI-gated modules (`SwiftMTPQuirks`, `SwiftMTPStore`, `SwiftMTPSync`, `SwiftMTPObservability`)
- **Exclude non-essential code** from coverage requirements (tests, mocks, generated code, third-party dependencies)
- **Enforce minimum thresholds** to prevent coverage regressions
- **Generate multiple report formats** (HTML, JSON, text) for different use cases

---

## Running Coverage Locally

### Quick Start

```bash
# Navigate to SwiftMTPKit directory
cd SwiftMTPKit

# Run tests with coverage and generate all reports
./run-all-tests.sh
```

### Step-by-Step

1. **Run tests with coverage enabled:**

```bash
cd SwiftMTPKit
swift test --enable-code-coverage
```

2. **Generate coverage report using llvm-cov:**

```bash
# Find the profdata file
PROFDATA=$(find .build -name "*.profdata" | head -1)

# Generate text report
xcrun llvm-cov show \
    -instr-profile="$PROFDATA" \
    -sources="Sources/" \
    --show-line-counts-or-regions \
    > coverage/coverage_details.txt

# Generate summary
xcrun llvm-cov report \
    -instr-profile="$PROFDATA" \
    -sources="Sources/" \
    > coverage/summary.txt
```

3. **Generate HTML report with Python script:**

```bash
# First, generate text coverage
llvm-cov show ... > coverage.txt

# Then generate HTML report
python3 Tests/coverage-report.py -i coverage.txt -o coverage/html
```

4. **View HTML report:**

```bash
open coverage/html/report.html
```

### Available Commands

| Command | Description |
|---------|-------------|
| `./run-all-tests.sh` | Run all tests with full coverage analysis |
| `swift test --enable-code-coverage` | Run tests with coverage collection |
| `python3 Tests/coverage-report.py -i coverage.txt -o coverage/` | Generate HTML/JSON reports |

### Coverage Report Outputs

After running coverage, you'll find:

```
coverage/
├── coverage.json      # CI-friendly JSON output
├── coverage_details.txt  # Line-by-line details
├── summary.txt        # Human-readable summary
└── html/
    └── report.html    # Interactive HTML report
```

---

## Coverage Goals and Thresholds

### Target Coverage by Module

| Module | Target | Description |
|--------|--------|-------------|
| **SwiftMTPQuirks** | tracked | Device quirk configurations |
| **SwiftMTPStore** | tracked | Persistence and transfer journal state |
| **SwiftMTPSync** | tracked | Mirror/sync planning and execution |
| **SwiftMTPObservability** | tracked | Logging and throughput utilities |

### Overall Project Goals

| Metric | Target | Description |
|--------|--------|-------------|
| **Line Coverage (filtered modules)** | 100% | Percentage of executable lines covered in gated modules |
| **Function Coverage** | 70% | Percentage of functions with test coverage |
| **Branch Coverage** | 60% | Percentage of conditional branches covered |
| **Per-File Coverage** | 60% | Minimum coverage for any single file |

### Threshold Behavior

- **Hard Fail**: Filtered overall coverage below 100% fails the build
- **Soft Warning**: Per-target coverage below threshold shows warnings
- **CI Integration**: Coverage drops in PRs trigger failure

---

## Understanding Coverage Metrics

### Line Coverage

Line coverage measures what percentage of executable lines are executed during testing.

```
100% = All executable lines were executed
 75% = 3 out of 4 lines were executed
  0% = No lines were executed
```

### Function Coverage

Function coverage tracks whether each function was called at least once.

```swift
// This function needs to be called in a test
func connectDevice() -> MTPDevice {
    // ... implementation
}

// A test that provides coverage
func testConnectDevice() {
    let device = connectDevice()
    #expect(device.state == .connected)
}
```

### Branch Coverage

Branch coverage measures conditional paths:

```swift
// Without full branch coverage:
if device.supportsFeatureX {
    // This branch might not be tested
} else {
    // This branch might not be tested either
}

// With full branch coverage, test both paths:
func testFeatureX() {
    let withFeature = createDevice(supportsFeatureX: true)
    let withoutFeature = createDevice(supportsFeatureX: false)
}
```

### Ignoring Code

Use `// swiftcoverage:ignore` to exclude code from coverage requirements:

```swift
// Mark entire blocks
#if swiftcoverage:ignore
// Legacy code that can't be easily tested
#endif

// Mark individual lines
let legacyValue = loadFromDeprecatedFormat() // swiftcoverage:ignore
```

### Excluded Categories

The following are automatically excluded from coverage:

1. **Test code**: Everything in `Tests/` directory
2. **Mocks and fakes**: Mock objects, test doubles
3. **Generated code**: Code from build tools, code generation
4. **Third-party dependencies**: External libraries
5. **CLI entry points**: `main.swift`, executable targets
6. **Platform-specific shims**: UIKit/AppKit adaptors

---

## Improving Coverage

### Identifying Uncovered Areas

1. **Review HTML report**: Open `coverage/html/report.html` and look for red (uncovered) lines

2. **Check text summary**: 
```bash
grep -A 5 "Uncovered" coverage/summary.txt
```

3. **Use llvm-cov show**:
```bash
llvm-cov show -sources=Sources/SwiftMTPCore/ | grep -v "^[[:space:]]*\\|[^|]*$"
```

### Strategies for Uncovered Code

#### 1. Error Handling

```swift
// Uncovered: Error paths
func readDevice() throws -> Data {
    guard device.isConnected else {
        throw DeviceError.notConnected  // ← Not tested
    }
    // ... rest of implementation
}

// Add test:
func testReadDeviceWhenDisconnected() {
    #expect(throws: DeviceError.notConnected) {
        try readDevice()
    }
}
```

#### 2. Edge Cases

```swift
// Uncovered: Edge cases
func calculateChecksum(data: Data) -> UInt32 {
    guard !data.isEmpty else {
        return 0  // ← Not tested
    }
    // ... rest of implementation
}

// Add test:
func testCalculateChecksumEmptyData() {
    let result = calculateChecksum(data: Data())
    #expect(result == 0)
}
```

#### 3. Conditional Logic

```swift
// Uncovered: All branches
func configureDevice(_ config: DeviceConfig) {
    if config.supportsUSB3 {
        setupUSB3()  // ← Might not be tested
    } else {
        setupUSB2()  // ← Might not be tested
    }
}

// Add tests for both configurations:
func testConfigureDeviceUSB3() {
    let config = DeviceConfig(supportsUSB3: true)
    configureDevice(config)
}

func testConfigureDeviceUSB2() {
    let config = DeviceConfig(supportsUSB3: false)
    configureDevice(config)
}
```

### Writing Tests for Coverage

#### Unit Tests

For isolated units of code:

```swift
@Test func deviceConnectionEstablishesSession() {
    let harness = DeviceLabHarness()
    let session = harness.establishSession()
    #expect(session.isActive == true)
    #expect(session.device.vendorID == harness.attachedDevice.vendorID)
}
```

#### Property-Based Tests

For validating invariants:

```swift
property("Device path components are normalized") <- forAll { (path: UnicodeString) in
    let normalized = normalizePath(path.value)
    return !normalized.contains("//")
}
```

#### BDD Integration Tests

For feature-level testing:

```gherkin
Feature: Device Connection
  Scenario: Device auto-disconnects when cable is unplugged
    Given a connected Android device
    When the USB cable is disconnected
    Then the device state should change to disconnected
    And the disconnection should be logged
```

### Coverage-Friendly Patterns

1. **Dependency injection**: Makes code testable
2. **Protocol-based design**: Easy to mock dependencies
3. **Value types**: Immutable data is easier to test
4. **Small, focused functions**: Easier to achieve full coverage

---

## CI Integration

### GitHub Actions

Coverage runs automatically on every push/PR. The workflow:

1. Runs `swift test --enable-code-coverage`
2. Generates coverage reports
3. Uploads to Codecov
4. Comments on PR with coverage changes

### Codecov Configuration

See [`.codecov.yml`](.codecov.yml) for full configuration.

Key settings:
- **Target**: 100% filtered overall coverage
- **Threshold**: 5% tolerance before failure
- **Flags**: Coverage grouped by test type (unit, integration, property, snapshot)

### PR Coverage Comments

Codecov automatically comments on PRs with coverage:

```
Coverage: 78.5% (+2.3% from base)
Files: 24 changed (4 with coverage decrease)
```

### Failing the Build

Build fails when:
- Filtered overall coverage drops below 100%
- A file's coverage drops more than 10%
- Coverage delta is negative beyond threshold

### Viewing Coverage in CI

1. **GitHub Checks**: Coverage annotation on changed files
2. **Codecov PR Comment**: Summary of coverage changes
3. **Codecov Dashboard**: Historical coverage trends

---

## Troubleshooting

### Coverage Not Generated

```bash
# Ensure Xcode Command Line Tools are installed
xcode-select --install

# Verify llvm-cov is available
xcrun llvm-cov --version
```

### Low Coverage After Tests

1. Check that all test targets are enabled
2. Verify exclude patterns don't accidentally exclude source code
3. Ensure tests actually run (`swift test --list-tests`)

### Missing Source Files

```bash
# Verify sources are correctly specified
llvm-cov show -sources=Sources/SwiftMTPCore/ -sources=Sources/SwiftMTPIndex/
```

---

## Best Practices

1. **Maintain 100% on gated modules**: Keep tests meaningful while preserving the hard gate
2. **Cover behavior, not lines**: Tests should validate functionality
3. **Prioritize core paths**: Focus on critical code paths first
4. **Review uncovered code**: Sometimes uncovered code indicates dead code
5. **Update thresholds gradually**: Increase targets as codebase matures

---

## Additional Resources

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [llvm-cov Documentation](https://llvm.org/docs/CommandGuide/llvm-cov.html)
- [Codecov Documentation](https://docs.codecov.io/)
- [Swift Code Coverage Guide](https://developer.apple.com/library/archive/documentation/ToolsLanguages/Conceptual/Xcode_Overview/MeasuringCodeCoverage.html)

---

## Current Coverage Results (July 2025)

### Current State

- **Device quirks database**: 20,009+ entries across 1,157 VIDs and 62+ categories
- **Gated modules at 100%**: SwiftMTPQuirks, SwiftMTPStore, SwiftMTPSync, SwiftMTPObservability
- **Total test cases**: 4,336 (0 failures) across 21 test targets
- **Milestones**: 15K → 16K → 17K → 18K → 19K → 20K all captured
- **CI surfaces**: Smoke, Documentation, TSAN, Fuzz, Build-test, Compat matrix — all green

### Overall Metrics

| Metric | Value | Status |
|--------|-------|--------|
| **Overall Line Coverage** | **~72%** | ✅ Improving |
| Total Lines Covered | ~2,400+ | - |
| Total Lines | ~3,300 | - |
| **Total Test Cases** | **4,336** | ✅ All Passing |
| Test Failures | 0 | ✅ All Passing |

### Test Expansion (PRs #274–#308)

| Target | Previous (#276) | Current | Delta | Key PRs |
|--------|-----------------|---------|-------|---------|
| CoreTests | 805 | 944 | +139 | #282, #287, #292, #299, #307 |
| TransportTests | 393 | 433 | +40 | #281 |
| ErrorHandlingTests | 254 | 334 | +80 | #287, #300 |
| PropertyTests | 220 | 248 | +28 | #292, #293 |
| SyncTests | 158 | 238 | +80 | #293, #306 |
| BDDTests | 300 | 237 | -63 | #284 (dynamic baselines) |
| IndexTests | 208 | 226 | +18 | #294 |
| FileProviderTests | 182 | 219 | +37 | #291 |
| QuirksTests | 46 | 210 | +164 | #285, #298, #301, #303, #305, #308 |
| StoreTests | 130 | 201 | +71 | #279, #302 |
| XPCTests | 133 | 156 | +23 | #295 |
| SwiftMTPCLITests | 91 | 132 | +41 | #296, #297 |
| SnapshotTests | 108 | 132 | +24 | #297 |
| IntegrationTests | 83 | 127 | +44 | #288 |
| ToolingTests | 117 | 117 | — | — |
| TestKitTests | 79 | 116 | +37 | #286 |
| MTPEndianCodecTests | 90 | 90 | — | — |
| ScenarioTests | 49 | 71 | +22 | #283 |
| ObservabilityTests | 40 | 70 | +30 | #279 |
| UITests | — | 34 | new | #278 |

### Per-Module Coverage

| Module | Coverage | Lines | Target | Status |
|--------|----------|-------|--------|--------|
| SwiftMTPCore | **~70%** | ~2,300/3,300 | 80% | ⚠️ Improving |
| SwiftMTPIndex | 87-98% | ~2,400/2,600 | 75% | ✅ Exceeds Target |
| SwiftMTPObservability | 100% | 57/57 | 70% | ✅ Exceeds Target |
| SwiftMTPQuirks | 100% | 492/492 | 70% | ✅ Exceeds Target |
| SwiftMTPStore | 100% | 628/628 | 70% | ✅ Exceeds Target |
| SwiftMTPSync | 100% | 244/244 | 70% | ✅ Exceeds Target |

### Key Coverage Gaps (Priority for Improvement)

| File | Coverage | Module | Priority | Notes |
|------|----------|--------|----------|-------|
| `Sources/SwiftMTPCore/Internal/DeviceActor.swift` | ~62% | SwiftMTPCore | 🔴 High | State machine — improved by #299 |
| `Sources/SwiftMTPCore/Internal/Protocol/Proto+Transfer.swift` | ~48% | SwiftMTPCore | 🔴 High | PTP response handling — improved by #307 |
| `Sources/SwiftMTPCore/Internal/DeviceActor+Transfer.swift` | ~56% | SwiftMTPCore | 🔴 High | Object operations — improved by #302 |
| `Sources/SwiftMTPCore/Internal/FallbackLadder.swift` | ~55% | SwiftMTPCore | 🟡 Medium | Error recovery — improved by #300 |
| `Sources/SwiftMTPCore/Public/LearnedProfile.swift` | ~45% | SwiftMTPCore | 🟡 Medium | Profile persistence |

### Comparison with Previous Baseline

| Metric | Previous (#276) | Current | Change | Status |
|--------|-----------------|---------|--------|--------|
| Overall Line Coverage | ~70% | ~72% | +2% | ✅ Improving |
| SwiftMTPCore | ~68% | ~70% | +2% | ↗️ Improving |
| Total Tests | 3,490+ | 4,336 | +846 | ✅ All Passing |
| Test Failures | 0 | 0 | 0 | ✅ No Regression |
| Test Targets | 20 | 21 | +1 (UITests) | ✅ Added |

### Key Improvements (PRs #274–#308)

1. **Device research PRs**: Samsung Galaxy (#301), Canon/Nikon PTP (#303), Google Pixel (#305), Xiaomi/OnePlus/OPPO/Realme (#308) — enriched quirks with real-world MTP behavior data
2. **QuirksTests 4.5× growth**: 46 → 210 tests with data quality validation, governance, and device-specific research tests (#285, #298, #301, #303, #305, #308)
3. **DeviceActor concurrency tests**: Actor isolation and concurrency stress tests (#299)
4. **FallbackLadder tests**: Error recovery strategy tests for the fallback ladder (#300)
5. **TransferJournal resilience**: Edge case and resilience tests for journal-based transfer resume (#302)
6. **Mirror/diff engine**: Comprehensive tests for mirror and diff engine (#306)
7. **Codec fuzzing**: MTP codec edge case and fuzz regression tests (#282, #307)
8. **UITests target**: New test target for SwiftUI view tests (#278)
9. **CLI smoke + snapshot tests**: Command parsing, help output, and output format snapshot tests (#296, #297)
10. **BDD dynamic baselines**: BDD tests now derive baselines from quirks.json instead of hardcoded values (#284)

### Previous Test Expansion (PRs #249–#273)

| Target | Before (RC) | After (#273) | Delta | Key PRs |
|--------|-------------|--------------|-------|---------|
| CoreTests | 200+ | 805 | +600 | #254, #255, #257, #258 |
| TransportTests | 123 | 393 | +270 | — |
| BDDTests | 117 | 300 | +183 | #263 |
| ErrorHandlingTests | — | 254 | new | #255 |
| PropertyTests | 40+ | 220 | +180 | #268, #273 |
| IndexTests | 100+ | 208 | +108 | #251, #271 |
| FileProviderTests | 47 | 182 | +135 | #269 |
| SyncTests | 111 | 158 | +47 | #268 |
| XPCTests | 91 | 133 | +42 | #267 |
| StoreTests | 42 | 130 | +88 | — |

---

## Previous Coverage Results (February 2026 - Real Hardware Integration)

### Overall Metrics

| Metric | Value | Status |
|--------|-------|--------|
| **Overall Line Coverage** | **75.76%** | ✅ PASS |
| Total Lines Covered | 7,562 | - |
| Total Lines | 9,982 | - |
| Baseline Threshold | 75.00% | - |
| **Total Test Cases** | **1,646** | ✅ Executed |
| Test Files | 92 | ✅ Compiling |
| Test Failures | 0 | ✅ All Passing |

### New Hardware Integration Tests Added

| Test File | Tests | Purpose | Coverage Impact |
|-----------|-------|---------|----------------|
| `Tests/IntegrationTests/RealDeviceIntegrationTests.swift` | 7 | Real device enumeration and hotplug | ✅ Exercises LibUSBDiscovery, USBDeviceWatcher |

### Per-Module Coverage

| Module | Coverage | Lines | Target | Status |
|--------|----------|-------|--------|--------|
| SwiftMTPCore | 58-80% | ~2,400/3,500 | 80% | ⚠️ Below Target |
| SwiftMTPIndex | 87-98% | ~2,400/2,600 | 75% | ✅ Exceeds Target |
| SwiftMTPObservability | 100% | 57/57 | 70% | ✅ Exceeds Target |
| SwiftMTPQuirks | 100% | 492/492 | 70% | ✅ Exceeds Target |
| SwiftMTPStore | 100% | 628/628 | 70% | ✅ Exceeds Target |
| SwiftMTPSync | 100% | 244/244 | 70% | ✅ Exceeds Target |
| SwiftMTPTestKit | 82-99% | ~900/1,100 | 60% | ✅ Exceeds Target |
| SwiftMTPFileProvider | 47-97% | ~500/800 | 65% | ⚠️ Variable |
| SwiftMTPTransportLibUSB | 22-75% | ~300/1,300 | 70% | 🔴 Hardware Required |
| SwiftMTPUI | N/A | 0/0 | 50% | ➖ No Source Files |
| SwiftMTPXPC | 87-100% | ~550/560 | 70% | ✅ Exceeds Target |

### Hardware-Dependent Coverage Status

**SwiftMTPTransportLibUSB** requires real hardware for full coverage:

| File | Previous | Current | Requires |
|------|----------|---------|----------|
| `USBDeviceWatcher.swift` | 0% | **Tested** | Hotplug callbacks |
| `InterfaceProbe.swift` | 0% | **Tested** | Real device probing |
| `LibUSBTransport.swift` | 12.77% | **Tested** | Device enumeration |

**Note**: The new `RealDeviceIntegrationTests.swift` exercises:
- `LibUSBDiscovery.enumerateMTPDevices()` - Device enumeration
- `USBDeviceWatcher.start()` - Hotplug registration
- String descriptor reading
- MTPDeviceSummary structure validation

### Comparison with Previous Baseline

| Metric | Previous | Current | Change | Status |
|--------|----------|---------|--------|--------|
| Overall Line Coverage | 75.79% | 75.76% | -0.03% | ✅ Stable |
| SwiftMTPCore | 66.53% | ~68% | +1.5% | ↗️ Improving |
| SwiftMTPTransportLibUSB | 23.39% | ~22% | -1.4% | ⚠️ Stable (low) |
| Total Tests | 1,639 | 1,646 | +7 | ✅ Added |
| Test Failures | 0 | 0 | 0 | ✅ No Regression |

### Key Improvements

1. **Real Device Integration Tests**: Added 7 new tests for hardware-dependent code
2. **USBDeviceWatcher Coverage**: Hotplug callback registration now tested
3. **LibUSBDiscovery Coverage**: Device enumeration now exercised
4. **All Tests Passing**: 0 failures across all test suites

### Worst Coverage Files (Priority for Improvement)

| File | Coverage | Module | Priority | Status |
|------|----------|--------|----------|--------|
| `Sources/SwiftMTPTransportLibUSB/USBDeviceWatcher.swift` | 0→Tested | SwiftMTPTransportLibUSB | 🔴 Critical | ✅ Tested |
| `Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` | 0→Tested | SwiftMTPTransportLibUSB | 🔴 Critical | ✅ Tested |
| `Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift` | 12.77% | SwiftMTPTransportLibUSB | 🔴 Critical | ⚠️ HW Required |
| `Sources/SwiftMTPFileProvider/ChangeSignaler.swift` | 8.57% | SwiftMTPFileProvider | 🟠 High | In Progress |
| `Sources/SwiftMTPCore/Internal/Protocol/Proto+Transfer.swift` | 42.78% | SwiftMTPCore | 🟡 Medium | ✅ Improved |
| `Sources/SwiftMTPCore/Internal/Tools/SubstrateHardening.swift` | 96.88% | SwiftMTPCore | 🟡 Medium | ✅ Complete |
| `Sources/SwiftMTPCore/Internal/Protocol/PTPLayer.swift` | 100.00% | SwiftMTPCore | 🟢 Low | ✅ Complete |

### CLI Coverage Files (Improved)

| File | Coverage | Tests | Status |
|------|----------|-------|--------|
| `Sources/SwiftMTPCore/CLI/Spinner.swift` | **100.00%** | SpinnerTests.swift | ✅ Complete |
| `Sources/SwiftMTPCore/CLI/DeviceFilter.swift` | **100.00%** | DeviceFilterTests.swift | ✅ Complete |
| `Sources/SwiftMTPCore/CLI/Exit.swift` | 0.00% | ExitTests.swift | ⚠️ Untestable |

### Best Coverage Files

| File | Coverage | Module |
|------|----------|--------|
| `Sources/SwiftMTPCore/Internal/Protocol/PTPCodec.swift` | 99.55% | SwiftMTPCore |
| `Sources/SwiftMTPTestKit/VirtualDeviceConfig.swift` | 99.38% | SwiftMTPTestKit |
| `Sources/SwiftMTPIndex/PathKey.swift` | 98.70% | SwiftMTPIndex |
| `Sources/SwiftMTPTransportLibUSB/PTPContainer+USB.swift` | 98.51% | SwiftMTPTransportLibUSB |
| `Sources/SwiftMTPTestKit/VirtualMTPLink.swift` | 98.46% | SwiftMTPTestKit |
| `Sources/SwiftMTPIndex/Crawler/EventBridge.swift` | 98.18% | SwiftMTPIndex |

---

## Test Suite Summary

### Test Results (Current — PRs through #308)

| Metric | Value | Status |
|--------|-------|--------|
| Total Tests Registered | 4,336 | ✅ All Passing |
| Tests Skipped | ~0 | ✅ Skips resolved |
| Test Failures | 0 | ✅ Fixed |
| Test Targets | 21 | ✅ All active |

### Test Targets (21 total)

| Target | Tests | Status | Notes |
|--------|-------|--------|-------|
| CoreTests | 944 | ✅ Passing | Protocol, codec, actor, device logic, error cascades, mutations, benchmarks, concurrency |
| TransportTests | 433 | ✅ Passing | Transport edge cases, USB layer, recovery |
| ErrorHandlingTests | 334 | ✅ Passing | Error paths, recovery, fault injection, error cascades, propagation chains |
| PropertyTests | 248 | ✅ Passing | SwiftCheck invariants, sync edge cases, protocol-level, fuzz properties |
| SyncTests | 238 | ✅ Passing | Mirror, diff, conflict resolution, edge cases, advanced properties |
| BDDTests | 237 | ✅ Passing | Gherkin scenarios with dynamic baselines from quirks.json |
| IndexTests | 226 | ✅ Passing | SQLite index, live index, path keys, data integrity, concurrency stress |
| FileProviderTests | 219 | ✅ Passing | File Provider extension, enumeration, materialization, resilience |
| QuirksTests | 210 | ✅ Passing | Data quality, governance, device research (Samsung, Canon, Nikon, Pixel, Xiaomi) |
| StoreTests | 201 | ✅ Passing | SQLite persistence, journal, TransferJournal resilience |
| XPCTests | 156 | ✅ Passing | XPC protocol, UInt64 overflow, resilience, boundaries |
| SwiftMTPCLITests | 132 | ✅ Passing | CLI smoke tests, command parsing, help output |
| SnapshotTests | 132 | ✅ Passing | Visual regression, policy snapshots, CLI output format snapshots |
| IntegrationTests | 127 | ✅ Passing | Cross-module integration |
| ToolingTests | 117 | ✅ Passing | CLI commands, filters, formatters |
| TestKitTests | 116 | ✅ Passing | VirtualMTPDevice, FaultInjectingLink, compliance |
| MTPEndianCodecTests | 90 | ✅ Passing | Endian codec round-trip tests |
| ScenarioTests | 71 | ✅ Passing | End-to-end device operation scenarios |
| ObservabilityTests | 70 | ✅ Passing | SwiftMTPObservability module tests |
| UITests | 34 | ✅ Passing | SwiftUI view tests |

**Total: 21 test targets | 4,336 test cases | 0 failures**

### Code Statistics

- **Source Files**: 96+ Swift files across 11 modules
- **Test Files**: 140+ Swift files across 21 test targets
- **Source Lines**: ~10,000+ lines (filtered for coverage)
- **Test Lines**: ~35,000+ lines
- **Test-to-Source Ratio**: ~3.5:1
- **Total Test Cases**: 4,336 (0 skipped, 0 failures — all passing)

---

## Recommendations

### Immediate Actions

1. **Fix SwiftMTPTransportLibUSB Coverage (23.39%)**
   - Add tests for `USBDeviceWatcher` and `InterfaceProbe`
   - Increase `LibUSBTransport` test coverage
   - Priority: Critical

2. **Address SwiftMTPCore Gap (66.53% < 80%)**
   - Focus on `PTPLayer.swift` and `Proto+Transfer.swift`
   - Add tests for `Exit.swift` CLI module
   - Priority: High

3. **Resolve Test Compilation Issues**
   - SyncTests: Fix `SyncChanges` duplicate definitions
   - TransportTests: Update `MockDeviceData` API calls
   - FileProviderTests: Fix `NSFileProviderItemPlaceholder` imports
   - Priority: Medium

### Future Improvements

1. **Increase Baseline to 80%** once SwiftMTPCore reaches target
2. **Add hardware-accelerated coverage** via CI with USB device farming
3. **Improve SwiftMTPTransportLibUSB** mock infrastructure
4. **Enable branch coverage** metrics once Swift's coverage tools stabilize

---

## Historical Coverage Trends

| Date | Overall | SwiftMTPCore | SwiftMTPIndex | SwiftMTPTransportLibUSB | Tests | Notes |
|------|---------|--------------|---------------|-------------------------|-------|-------|
| Jul 2025 | ~72% | ~70% | 87-98% | ~22% | 4,336 | **Current** — PRs #274–#308 |
| Jul 2025 | ~70% | ~68% | 87-98% | ~22% | 3,490+ | PR #276 baseline |
| Feb 2026 | 75.76% | ~68% | 87-98% | ~22% | 1,646 | Hardware tests passing |
| Feb 2026 | 75.79% | 66.53% | 93.89% | 23.39% | 1,646 | Baseline with test expansion |
| Previous | ~75% | ~65% | ~90% | ~20% | — | Pre-expansion baseline |
