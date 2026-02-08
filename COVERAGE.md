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

- **Track coverage** across all core modules (SwiftMTPCore, SwiftMTPIndex, SwiftMTPObservability, SwiftMTPQuirks, SwiftMTPFileProvider)
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
| **SwiftMTPCore** | 80% | Core MTP protocol and device communication |
| **SwiftMTPIndex** | 75% | SQLite indexing and caching logic |
| **SwiftMTPObservability** | 70% | Logging and metrics utilities |
| **SwiftMTPQuirks** | 70% | Device quirk configurations |
| **SwiftMTPFileProvider** | 65% | macOS/iOS File Provider extension |

### Overall Project Goals

| Metric | Target | Description |
|--------|--------|-------------|
| **Line Coverage** | 75% | Percentage of executable lines covered |
| **Function Coverage** | 70% | Percentage of functions with test coverage |
| **Branch Coverage** | 60% | Percentage of conditional branches covered |
| **Per-File Coverage** | 60% | Minimum coverage for any single file |

### Threshold Behavior

- **Hard Fail**: Overall coverage below 75% fails the build
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
- **Target**: 75% overall coverage
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
- Overall coverage drops below 75%
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

1. **Don't chase 100%**: Focus on meaningful tests, not coverage metrics
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
