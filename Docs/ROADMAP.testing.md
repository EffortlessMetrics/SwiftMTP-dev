# SwiftMTP Testing Guide

*Last updated: 2026-07-11*

> **Pre-Alpha Testing Reality**: SwiftMTP has ~9,191+ test cases across 20 targets, but nearly all coverage uses `VirtualMTPDevice` (in-memory mock). Real-device validation is minimal (1 device with working transfers). Use `--filter` to target specific suites. The test infrastructure below represents the gate model for day-to-day development and release readiness.

This document defines the test gates used for development and sprint/release readiness.

## Test Gate Baseline

SwiftMTP uses a layered gate model:

1. Local quick confidence (`swift build`, targeted test filters)
2. Pre-PR automated gate (`./scripts/pre-pr.sh`)
3. Full local matrix (`./run-all-tests.sh`)
4. CI matrix (build, test, smoke, fuzz, TSAN path)
5. Real-device validation (manual/bring-up artifacts) — **currently limited to Xiaomi Mi Note 2**

## Source of Truth Commands

Primary local gate from repo root:

```bash
./run-all-tests.sh
```

This orchestrates:

- `SwiftMTPKit/run-all-tests.sh`
- Filtered coverage gate for `SwiftMTPQuirks`, `SwiftMTPStore`, `SwiftMTPSync`, `SwiftMTPObservability`
- Optional fuzz smoke (`PTPCodecFuzzTests`)
- Optional storybook smoke (default profiles: `pixel7,galaxy,iphone,canon`)
- Xcode app tests (`RUN_XCODE_UI_TESTS=0` to skip UI tests)

## Test Discovery — Which Tests to Run

There are **20 test targets**. Run the one matching your change area:

| Change area | Test command |
|-------------|-------------|
| Core protocol (operations, codecs, actor) | `swift test --filter CoreTests` |
| Transport layer (USB, libusb, IOUSBHost) | `swift test --filter TransportTests` |
| Index / SQLite (live index, snapshots) | `swift test --filter IndexTests` |
| Sync / mirror (diff, conflict resolution, format filter) | `swift test --filter SyncTests` |
| CLI commands and argument parsing | `swift test --filter ToolingTests` |
| CLI module tests | `swift test --filter SwiftMTPCLITests` |
| File Provider (Finder integration) | `swift test --filter FileProviderTests` |
| Quirks (device profiles, schema) | `swift test --filter QuirksTests` |
| Error handling (recovery layer, fallback) | `swift test --filter ErrorHandlingTests` |
| Observability (logging, recovery log) | `swift test --filter ObservabilityTests` |
| Store / persistence (transfer journal) | `swift test --filter StoreTests` |
| XPC service | `swift test --filter XPCTests` |
| Binary codec | `swift test --filter MTPEndianCodecTests` |
| TestKit self-tests | `swift test --filter TestKitTests` |
| End-to-end scenarios | `swift test --filter ScenarioTests` |
| Cross-module integration | `swift test --filter IntegrationTests` |
| BDD / Gherkin scenarios | `swift test --filter BDDTests` |
| Property-based tests | `swift test --filter PropertyTests` |
| Visual regression | `swift test --filter SnapshotTests` |
| UI tests | `swift test --filter UITests` |
| **Full suite with coverage** | `swift test -v --enable-code-coverage` |

All test commands run from the `SwiftMTPKit/` directory.

## Local Command Matrix

Run from repository root unless noted.

```bash
# Build package
cd SwiftMTPKit && swift build -v

# Pre-PR automated gate (format, lint, build, test, quirks)
./scripts/pre-pr.sh

# Full package tests + coverage artifacts + smoke slices
./SwiftMTPKit/run-all-tests.sh

# Full repo gates (package + Xcode)
./run-all-tests.sh

# Focused suites
cd SwiftMTPKit
swift test --filter BDDTests
swift test --filter PropertyTests
swift test --filter SnapshotTests
swift test --filter ScenarioTests
swift test --filter IntegrationTests

# TSAN focused pass (excludes USB transport tests)
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# Non-hardware smoke flow
./scripts/smoke.sh
```

## Mock Testing

### VirtualMTPDevice

`SwiftMTPTestKit` provides `VirtualMTPDevice`, an in-memory MTP device for testing without hardware:

```swift
import SwiftMTPTestKit

let device = VirtualMTPDevice()
// Use through the MTPDevice protocol
```

### FaultInjectingLink

Enables deterministic failure injection for testing error recovery paths (timeouts, disconnects, I/O errors).

### Mock profiles

Enable simulated device profiles via environment variables:

```bash
export SWIFTMTP_DEMO_MODE=1
export SWIFTMTP_MOCK_PROFILE=pixel7   # Options: pixel7, galaxy, iphone, canon
```

Failure scenarios: `timeout`, `busy`, `disconnected`.

## Coverage Gate

`SwiftMTPKit/run-all-tests.sh` enforces a filtered coverage threshold through `SwiftMTPKit/scripts/coverage_gate.py`.

Defaults:

- Threshold: `100`
- Modules: `SwiftMTPQuirks,SwiftMTPStore,SwiftMTPSync,SwiftMTPObservability`

Override knobs:

- `COVERAGE_THRESHOLD`
- `COVERAGE_MODULES`
- `RUN_FUZZ_SMOKE`
- `RUN_STORYBOOK_SMOKE`
- `RUN_SNAPSHOT_REFERENCE`

Artifacts are emitted under `SwiftMTPKit/coverage/`.

## CI Workflows

| Workflow | Trigger | Required for merge | What it checks |
|----------|---------|-------------------|----------------|
| `ci.yml` | All pushes/PRs | ✅ Yes | Build, full test suite, coverage gate, TSAN, fuzz harness, SBOM (tags) |
| `swiftmtp-ci.yml` | main + nightly | No (supplemental) | Coverage reporting, DocC docs, CLI smoke |
| `smoke.yml` | Schedule + PRs | No (advisory) | Minimal sanity build |
| `validate-quirks.yml` | PRs touching quirks | ✅ Yes (if quirks changed) | JSON schema + required fields |
| `validate-submission.yml` | Device submission PRs | ✅ Yes | Bundle completeness + redaction |
| `release.yml` | Tags | Release gate | Changelog, artifacts, SBOM |
| `nightly-real-device-ux-smoke.yml` | Nightly | No (advisory) | End-to-end with physical device |

**`ci.yml` is the only required check for merging.** Device submission PRs also require `validate-submission.yml`.

## Real-Device Validation

Use this sequence when changes touch transport behavior, quirks, or submission flow:

```bash
cd SwiftMTPKit

# Probe and baseline
swift run swiftmtp --real-only probe

# Connected device matrix report
swift run swiftmtp device-lab connected --json

# Bring-up capture for a concrete mode
../scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1

# Collect strict submission bundle
swift run swiftmtp collect --strict --noninteractive --json
```

See [Troubleshooting](Troubleshooting.md) for mode-level failure taxonomy and recovery guidance.

## Test Requirements for New Changes

- Add or update tests in the most specific suite possible (unit/integration/scenario/property).
- Cover both success path and at least one failure path.
- For concurrency-affecting changes, run TSAN-focused suite locally before opening PR.
- For quirks/transport changes, attach real-device artifact or state why mock-only is sufficient.

## Pre-PR Checklist

- [ ] `cd SwiftMTPKit && swift build -v`
- [ ] Targeted tests for touched area (see [Test Discovery](#test-discovery--which-tests-to-run))
- [ ] TSAN-focused pass (if concurrency touched)
- [ ] `./scripts/pre-pr.sh` (automated pre-PR gate)
- [ ] `./run-all-tests.sh` for milestone merges
- [ ] Docs/changelog updated when behavior changed

## PR Evidence Snippet

Include in the PR body:

```text
Commands:
  ./scripts/pre-pr.sh
  swift test --filter CoreTests

Result:
  Pass (macOS 15.x, Xcode 16.x)
```

## Related Docs

- [Contribution Guide](ContributionGuide.md)
- [Roadmap](ROADMAP.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Device Submission Guide](DeviceSubmission.md)
- [Troubleshooting](Troubleshooting.md)
