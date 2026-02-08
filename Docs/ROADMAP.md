# SwiftMTP Roadmap

This document outlines the comprehensive release plan for SwiftMTP, including phased milestones, release criteria, and device submission guidelines.

## Version 2.x - Tahoe Era

### Phase 1: NOW (Current Focus) 🔴

**Focus:** Pixel 7 stabilization, CI fixes, quick wins

#### Goals
- [x] macOS Tahoe 26 native support
- [x] SwiftPM 6.2+ toolchain
- [x] IOUSBHost framework adoption
- [x] Comprehensive macOS Tahoe 26 documentation
- [x] Swift-DocC metadata fixes

#### In Progress
- [ ] **Pixel 7 bulk transfer fix** - Resolve macOS Tahoe 26 timeout issue
- [ ] **CI pipeline stabilization** - Fix libusb xcframework builds
- [ ] **OnePlus 3T SendObject fix** - Resolve `Object_Too_Large` (0x201D) error

#### Quick Wins (This Sprint)
- [ ] Update quirk confidence scores based on real device testing
- [ ] Add stabilization delay recommendations for Xiaomi devices
- [ ] Document USB privacy authorization steps
- [ ] Improve error messages for common connection issues

---

### Phase 2: NEXT (Next Quarter) 🟡

**Focus:** Testing infrastructure, device submission workflow, docs

#### Goals
- [ ] **Testing Infrastructure**
  - [ ] TSAN (Thread Sanitizer) integration in CI
  - [ ] SwiftMTPCore coverage: 85% (currently 80%)
  - [ ] SwiftMTPIndex coverage: 80% (currently 75%)
  - [ ] Automated regression testing for device quirks

- [ ] **Device Submission Workflow**
  - [ ] `swiftmtp collect` command for device data collection
  - [ ] Automated quirk suggestion generation
  - [ ] Privacy-redacted USB dump validation
  - [ ] See [Device Submission Guide](ROADMAP.device-submission.md)

- [ ] **Documentation**
  - [ ] Complete [Testing Guide](ROADMAP.testing.md)
  - [ ] Device-specific tuning guides
  - [ ] Troubleshooting decision trees
  - [ ] Video tutorial series

---

### Phase 3: LATER (Future) 🟢

**Focus:** Device coverage expansion, performance, App Store prep

#### Goals
- [ ] **Device Coverage Expansion**
  - [ ] Samsung Galaxy S25 quirk entry
  - [ ] Sony Xperia device quirks database expansion
  - [ ] Camera device RAW transfer optimization
  - [ ] Nintendo Switch MTP support investigation
  - [ ] iOS device support (requires external helper)

- [ ] **Performance**
  - [ ] Transfer throughput benchmarks (>100 MB/s on USB 3.2)
  - [ ] Parallel multi-device enumeration
  - [ ] Memory-mapped I/O for large files
  - [ ] GPU-accelerated thumbnail generation

- [ ] **App Store Preparation**
  - [ ] Sandbox-compatible design
  - [ ] Notarization workflow documentation
  - [ ] File Provider Extension for Files app
  - [ ] See [FileProvider Tech Preview](FileProvider-TechPreview.md)

---

## Version 3.x - Future Explorations

### Long-term Goals

- **Network MTP (MTP/IP)**: Support for remote device access over IP
- **WebUSB Integration**: Browser-based device access via WebUSB
- **Rust Transport Layer**: Alternative high-performance transport in Rust
- **Embedded Device Support**: RTOS-based MTP device development kit
- **Cross-platform USB stack**: libusb 2.0 backend for Linux/Windows
- **Cloud Device Bridge**: Cloud-based device mirroring
- **ML-powered Device Detection**: Intelligent device quirk prediction
- **Plugin Architecture**: Extensible transfer handlers for specialized devices

---

## Release Cadence

| Version | Target | Schedule | Status |
|---------|--------|----------|--------|
| v2.0.0 | macOS 26 Core | Q1 2026 | ✅ Released |
| v2.1.0 | Testing & Docs | Q2 2026 | 🔄 In Progress |
| v2.2.0 | Performance & Benchmarks | Q3 2026 | ⏳ Planned |
| v2.3.0 | Device Coverage Expansion | Q4 2026 | ⏳ Planned |
| v3.0.0 | Cross-platform | 2027 | 🔭 Exploratory |

---

## Release Criteria

### Current Metrics (as of 2026-02-08)

| Criterion | Target | Current | Status |
|-----------|--------|---------|--------|
| **SwiftMTPCore Coverage** | ≥80% | ~80% | ✅ Pass |
| **SwiftMTPIndex Coverage** | ≥75% | ~75% | ✅ Pass |
| **Overall Coverage** | ≥75% | ~75% | ✅ Pass |
| **Unit Tests** | All passing | All passing | ✅ Pass |
| **Benchmarks** | ≥1 device | 3 devices | ✅ Pass |
| **Quirks Validated** | All entries | 3 entries | ✅ Pass |
| **DocC Fresh** | All current | All current | ✅ Pass |
| **TSAN Clean** | No warnings | N/A | ⏳ Not Run |

### Release Requirements

Before any minor release (v2.x.0), all criteria must be met:

- [ ] All unit tests pass (`swift test`)
- [ ] Coverage thresholds met (see above)
- [ ] Benchmarks run on at least one real device
- [ ] quirks.json validation passes (`./scripts/validate-quirks.sh`)
- [ ] CHANGELOG.md updated
- [ ] Version bump in Package.swift
- [ ] Release tag created
- [ ] DocC documentation current

---

## Quick-Start: Submitting Device Profiles

### Prerequisites

1. **Hardware**: Device with MTP/PTP support
2. **Software**: SwiftMTP built from source
3. **Permissions**: USB debugging/developer mode enabled on device

### Step-by-Step Guide

1. **Collect Device Data**
   ```bash
   # Build and run probe
   swift run swiftmtp --real-only probe > probes/my-device.txt
   
   # Run benchmarks
   ./scripts/benchmark-device.sh my-device
   ```

2. **Validate Submission**
   ```bash
   # Check quirks format
   ./scripts/validate-quirks.sh
   
   # Validate submission bundle
   ./scripts/validate-submission.sh Contrib/submissions/my-device/
   ```

3. **Submit for Review**
   - Create pull request with:
     - Updated `Specs/quirks.json`
     - New benchmark artifacts in `Docs/benchmarks/`
     - Device documentation in `Docs/SwiftMTP.docc/Devices/`

4. **See Also**
   - [Device Submission Guide](ROADMAP.device-submission.md)
   - [Testing Guide](ROADMAP.testing.md)
   - [Release Checklist](ROADMAP.release-checklist.md)

---

## Deprecation Schedule

| Feature | Deprecated | Removed |
|---------|------------|---------|
| macOS 15 support | v2.0.0 | v3.0.0 |
| IOUSBLib (legacy) | v2.0.0 | v3.0.0 |
| Swift 5 compatibility | v2.0.0 | v2.5.0 |

---

## Contributing

See [Contribution Guide](ContributionGuide.md) for how to contribute to the roadmap.

## Issue Tracking

Use GitHub Issues for:
- **Feature Requests**: Tag with `enhancement`
- **Bug Reports**: Tag with `bug`
- **Device Quirks**: Tag with `device-support`
- **Documentation**: Tag with `documentation`
- **Testing**: Tag with `testing`
- **Release**: Tag with `release`

---

*Last updated: 2026-02-08*
*SwiftMTP Version: 2.0.0*
