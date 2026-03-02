# SwiftMTP Runbook

*Last updated: 2025-07-25*

## Current State

| Metric | Value |
|--------|-------|
| Registered tests | 4,134+ across 20 test targets |
| Runtime tests | ~4,800+ (including parameterized expansions) |
| Test failures | 0 |
| Device quirks entries | 20,020 research-based entries |
| Quirks categories | 38 categories, ~1,150 vendor IDs |
| Real-device validated | 1 device (Xiaomi Mi Note 2) |
| Gated coverage (100%) | SwiftMTPQuirks, SwiftMTPStore, SwiftMTPSync, SwiftMTPObservability |

### Test Targets (20)

CoreTests, IndexTests, TransportTests, BDDTests, PropertyTests, SnapshotTests,
TestKitTests, FileProviderTests, XPCTests, IntegrationTests, StoreTests,
SyncTests, QuirksTests, ObservabilityTests, ErrorHandlingTests, ScenarioTests,
ToolingTests, UITests, MTPEndianCodecTests, SwiftMTPCLITests

---

## Quick Reference — Essential Commands

All package-level commands run from `SwiftMTPKit/`:

```bash
cd SwiftMTPKit

# Build
swift build -v                              # Debug build
swift build -c release                      # Release build
swift build --build-tests                   # Compile all tests

# Test
swift test -v --enable-code-coverage        # Full suite with coverage
swift test --filter CoreTests               # Single target
swift test --filter TestClassName/testName   # Single test method

# Sanitizer
swift test -Xswiftc -sanitize=thread \
  --filter CoreTests --filter IndexTests --filter ScenarioTests

# Format & lint (required before commits)
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# CLI
swift run swiftmtp --help
swift run swiftmtp probe                    # Discover devices
swift run swiftmtp ls                       # List device contents
swift run swiftmtp bench                    # Benchmark transfers

# Full verification
./run-all-tests.sh                          # All gates
./run-fuzz.sh                               # Fuzzing
```

---

## Build Gates

Run these before moving on:

- `swift build --build-tests`
- `swift build --target MTPEndianCodecFuzz`
- `swift build --product MTPEndianCodecFuzz`

If any command fails, stop at the first compilation failure and record it in `FIXUP_QUEUE.md`.

## Execution Commands

### Unit/spec + integration test suites

- `swift test --skip-build --filter MTPEndianCodecTests`
- `swift test --skip-build --filter SwiftMTPCLITests`

### Snapshot checks

- `SWIFTMTP_SNAPSHOT_TESTS=1 swift test --skip-build --filter MTPEndianCodecTests`
- `SWIFTMTP_SNAPSHOT_TESTS=1 swift test --skip-build --filter SnapshotTests`

### Fuzzing

- `swift run MTPEndianCodecFuzz --seed=1A11C0DEBAADF00D --iterations=4096 SwiftMTPKit/Tests/MTPEndianCodecTests/Corpus/event-buffer.hex`
- `swift test --skip-build --filter PTPCodecFuzzTests`

### Sanitizers / coverage

- `swift test --skip-build -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests`
- `swift test --enable-code-coverage`

## Fuzz seeds and corpus

- Seed file for deterministic reproduction: `SwiftMTPKit/Tests/MTPEndianCodecTests/Corpus/event-buffer.hex`
- Commandline seed override is supported via `--seed=<hex>` (default `1A11C0DEBAADF00D`).

---

## CI Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | All pushes & PRs | Build, full tests, TSAN, fuzz, SBOM on tags |
| `swiftmtp-ci.yml` | main + nightly | Full coverage report, CLI smoke, DocC docs |
| `smoke.yml` | All pushes | Minimal sanity build (`swiftmtp` product) |
| `validate-quirks.yml` | quirks.json changes | Validates quirks database integrity |
| `validate-submission.yml` | Submission PRs | Validates device submission evidence |
| `release.yml` | Tag push | Build release artifacts, draft GitHub release |

---

## Development Workflow for Contributors

1. **Setup**: Clone the repo and build the libusb XCFramework once:
   ```bash
   ./scripts/build-libusb-xcframework.sh
   ```

2. **Branch**: Create a feature branch from `main`.

3. **Build & iterate** from `SwiftMTPKit/`:
   ```bash
   cd SwiftMTPKit
   swift build --build-tests   # Verify compilation
   swift test --filter <Target> # Run relevant tests
   ```

4. **Format before committing**:
   ```bash
   swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests
   ```

5. **Run full gates** before pushing:
   ```bash
   ./run-all-tests.sh
   ```

6. **Mock device testing**: No real device required for most tests:
   ```bash
   export SWIFTMTP_DEMO_MODE=1
   export SWIFTMTP_MOCK_PROFILE=pixel7  # options: pixel7, galaxy, iphone, canon
   ```

7. **Device quirks**: Edit `Specs/quirks.json` (source of truth), then copy to
   `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`. Both must stay in sync.
   Use `scripts/add-device.sh` for interactive entry addition.

---

## Troubleshooting

### Common Build Errors

**"Missing module 'libusb'"**
The libusb XCFramework has not been built. Run:
```bash
./scripts/build-libusb-xcframework.sh
```

**Swift 6 concurrency errors ("Sending … risks causing data races")**
All device-facing code must go through `MTPDeviceActor`. Mark closures as `@Sendable`
and ensure cross-actor calls use `await`.

**"No such module 'SQLite'" or similar SPM resolution failures**
```bash
cd SwiftMTPKit
swift package resolve
swift package reset && swift package resolve   # if the above fails
```

### Common Test Failures

**Snapshot test failures after code changes**
Regenerate snapshots:
```bash
SWIFTMTP_SNAPSHOT_TESTS=1 SWIFTMTP_UPDATE_SNAPSHOTS=1 swift test --filter SnapshotTests
```

**TSAN failures in TransportTests**
TransportTests are excluded from TSAN runs because USB I/O is inherently
single-threaded at the libusb level. Use the correct filter:
```bash
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests
```

**Property tests timing out**
Property tests use randomized inputs. If a test times out, check for infinite loops
in generators. Set `SWIFTMTP_PROPERTY_TEST_ITERATIONS=100` to reduce iteration count
during debugging.

### macOS Sandbox Issues with DocC Generator

The `SwiftMTPBuildTool` plugin may fail with sandbox violations when generating
documentation. Workaround:
```bash
swift package --disable-sandbox generate-documentation
```
Or build documentation manually:
```bash
swift package generate-documentation --target SwiftMTPCore
```

### libusb Version Mismatch Warnings

If you see warnings about libusb version mismatch between the XCFramework and system
libusb, rebuild the XCFramework:
```bash
./scripts/build-libusb-xcframework.sh
```
The XCFramework is pinned to a specific libusb version; mixing with a different
system-installed version (e.g., from Homebrew) can cause symbol conflicts.

---

## Merging Device Waves

When multiple parallel branches add entries to `quirks.json`, merge conflicts are
inevitable. Use the **dedup rebase** pattern:

1. Checkout the wave branch and rebase onto `main`.
2. On conflict, accept **main's** version of `quirks.json`.
3. Extract new entries from the wave branch by diffing entry IDs:
   ```bash
   diff <(jq -r '.entries[].id' quirks-main.json | sort) \
        <(jq -r '.entries[].id' quirks-wave.json | sort) \
     | grep '^>' | sed 's/^> //'
   ```
4. Append those entries to main's `entries` array (preserve sort order by category).
5. Handle **category corrections**: if an entry exists in both but under a different
   category, prefer the wave branch's category (it was intentionally re-classified).
6. Run `swift test --filter QuirkMatchingTests` to validate the merged file.

## Adding Entries via Scripts

Use `scripts/add-device.sh` to add a single device entry to `quirks.json` interactively.
The script handles:

- Prompting for VID, PID, device name, manufacturer, category, and status
- Generating a canonical quirk ID
- Validating no VID:PID duplicates exist
- Appending the entry in the correct category section
- Running `validate-quirks` checks automatically

Usage:
```bash
./scripts/add-device.sh
```
