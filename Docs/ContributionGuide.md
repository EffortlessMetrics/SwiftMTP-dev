# SwiftMTP Contribution Guide

*Last updated: 2026-07-11*

> **Pre-Alpha Context**: SwiftMTP is in pre-alpha. The project has extensive scaffolding (~9,191+ tests across 20 targets, 20,026 quirks entries, CI workflows) but minimal real-device validation. Most test coverage uses `VirtualMTPDevice` (in-memory mock). Real-device testing contributions are the single highest-impact way to help the project.

This guide covers how to contribute to SwiftMTP, including code changes, device evidence, and documentation updates.

---

## Getting Started

### Prerequisites

Run the bootstrap script to install dependencies and verify your environment:

```bash
./scripts/bootstrap.sh
```

This checks for Xcode, Swift, and libusb, builds the libusb XCFramework if needed, and performs an initial build.

If you need to rebuild the libusb XCFramework separately:

```bash
./scripts/build-libusb-xcframework.sh
```

### First build

```bash
cd SwiftMTPKit
swift build -v
```

All package-level commands (build, test, run) should be executed from the `SwiftMTPKit/` directory.

---

## Legal Requirements

All contributions require a signed Contributor License Agreement (CLA).

- **Individuals:** Sign the [Individual CLA](../legal/inbound/CLA-INDIVIDUAL.md) before your first PR.
- **Entities:** Have an authorized signatory complete the [Entity CLA](../legal/inbound/CLA-ENTITY.md).

All commits must include a [Developer Certificate of Origin](../legal/inbound/DCO.txt) sign-off. Use `git commit -s` to add the `Signed-off-by` trailer automatically.

---

## Code Zones

The codebase is organized into focused modules under `SwiftMTPKit/Sources/`:

| Zone | Directory | Purpose |
|------|-----------|---------|
| **Core** | `SwiftMTPCore/` | Actor-isolated MTP protocol, public APIs, CLI utilities |
| **Transport (libusb)** | `SwiftMTPTransportLibUSB/` | libusb-based USB transport layer |
| **Transport (IOUSBHost)** | `SwiftMTPTransportIOUSBHost/` | Native macOS USB transport (scaffold, throws `notImplemented`) |
| **Index** | `SwiftMTPIndex/` | SQLite-based device content indexing, snapshots, `SQLiteLiveIndex` |
| **Sync** | `SwiftMTPSync/` | Mirror, diff, sync operations, conflict resolution, format filtering |
| **Quirks** | `SwiftMTPQuirks/` | Device quirks database and learned profiles |
| **Observability** | `SwiftMTPObservability/` | Structured logging, performance monitoring, `RecoveryLog` |
| **Store** | `SwiftMTPStore/` | Persistence — transfer journals, metadata |
| **UI** | `SwiftMTPUI/` | SwiftUI views and GUI application |
| **FileProvider** | `SwiftMTPFileProvider/` | macOS File Provider extension for Finder integration |
| **XPC** | `SwiftMTPXPC/` | XPC service bridging File Provider and main app |
| **TestKit** | `SwiftMTPTestKit/` | Test utilities — `VirtualMTPDevice`, `FaultInjectingLink` |
| **CLI** | `Tools/swiftmtp-cli/` | CLI entry point (`swiftmtp`) |
| **Codec** | `MTPEndianCodec/` | MTP binary encoding/decoding |
| **Types** | `MTPCoreTypes/` | Shared type definitions |

---

## Development Workflow

### 1. Branch from main

```bash
git checkout -b feat/<short-topic>
# or: fix/<short-topic>, docs/<short-topic>
```

### 2. Make changes and run targeted tests

Use the [Test Discovery Guide](#test-discovery-guide) below to run the right tests for your change.

### 3. Run the pre-PR gate

Before opening a pull request, run the automated gate script:

```bash
./scripts/pre-pr.sh
```

This runs formatting lint, build, targeted tests, quirks validation, and large-file scanning in one step.

Alternatively, run checks manually:

```bash
cd SwiftMTPKit

# Format
swift-format -i -r Sources Tests

# Lint
swift-format lint -r Sources Tests --strict

# Build
swift build -v

# Targeted tests (see Test Discovery below)
swift test --filter <RelevantSuite>

# Quirks validation (if quirks.json changed)
../scripts/validate-quirks.sh
```

For milestone merges, run the full suite:

```bash
./run-all-tests.sh
```

For concurrency-related changes, run with Thread Sanitizer:

```bash
cd SwiftMTPKit
swift test -Xswiftc -sanitize=thread \
  --filter CoreTests --filter IndexTests --filter ScenarioTests
```

---

## Test Discovery Guide

There are **20 test targets**. Run the one matching your change area:

| Change area | Test command |
|-------------|-------------|
| Core protocol (operations, codecs, actor) | `swift test --filter CoreTests` |
| Transport layer (USB, libusb, IOUSBHost) | `swift test --filter TransportTests` |
| Index / SQLite (live index, snapshots) | `swift test --filter IndexTests` |
| Sync / mirror (diff, conflict resolution, format filter) | `swift test --filter SyncTests` |
| CLI (commands, argument parsing) | `swift test --filter ToolingTests` |
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

---

## Code Style

SwiftMTP uses [swift-format](https://github.com/swiftlang/swift-format) with the repo's `.swift-format` config (2-space indentation, early exits, no parens around conditions).

```bash
# Auto-format before committing
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# Check for violations
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests --strict
```

CI enforces formatting — PRs with lint violations will fail.

---

## Mock Testing

### VirtualMTPDevice

`SwiftMTPTestKit` provides `VirtualMTPDevice`, an in-memory MTP device implementation for testing without hardware. Use it for unit and integration tests:

```swift
import SwiftMTPTestKit

let device = VirtualMTPDevice()
// Use device through the MTPDevice protocol
```

### FaultInjectingLink

`FaultInjectingLink` enables deterministic failure injection for testing error recovery paths.

### Mock profiles

Enable simulated device profiles via environment variables:

```bash
export SWIFTMTP_DEMO_MODE=1
export SWIFTMTP_MOCK_PROFILE=pixel7   # Options: pixel7, galaxy, iphone, canon
```

Failure scenarios: `timeout`, `busy`, `disconnected`.

---

## Device Testing

When hardware is available, use these commands to validate with a real device:

```bash
cd SwiftMTPKit

# Discover connected devices
swift run swiftmtp --real-only probe

# List device contents
swift run swiftmtp --real-only ls

# Benchmark transfers
swift run swiftmtp --real-only bench 100M --repeat 3

# Run automated device-lab test matrix
swift run swiftmtp device-lab connected --json

# Mode-specific bring-up capture
../scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1
```

See [Troubleshooting](Troubleshooting.md) for device connection issues.

---

## PR Requirements

Each PR must:

- **Build**: `swift build -v` succeeds (from `SwiftMTPKit/`)
- **Tests**: relevant test target(s) pass (see [Test Discovery](#test-discovery-guide))
- **Formatting**: `swift-format lint` passes with `--strict`
- **Docs**: updated if the change affects user-visible behavior or APIs
- **Changelog**: entry under `Unreleased` for user-visible changes
- **Single-purpose**: one bug fix + tests, one feature + tests, or one docs update

For quirks/submission PRs, also include:

- `Specs/quirks.json` diff rationale
- Validation output from `./scripts/validate-quirks.sh`
- Privacy/redaction confirmation

### PR evidence snippet

Include a short command/result block in the PR body:

```text
Commands:
  ./scripts/pre-pr.sh
  swift test --filter CoreTests

Result:
  Pass (macOS 15.x, Xcode 16.x)
```

---

## Documentation

### Generating DocC docs

```bash
./scripts/generate-docs.sh         # Generate
./scripts/generate-docs.sh --open  # Generate and open in browser
```

This builds DocC documentation for `SwiftMTPCore` and outputs to `Docs/SwiftMTP.doccarchive/`.

### Shell completions

Shell completions for the `swiftmtp` CLI are in the `completions/` directory:

| Shell | File | Installation |
|-------|------|-------------|
| Bash | `completions/swiftmtp.bash` | `source completions/swiftmtp.bash` |
| Fish | `completions/swiftmtp.fish` | Copy to `~/.config/fish/completions/` |
| Zsh | `completions/_swiftmtp` | Copy to a directory in `$fpath` |

---

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

---

## Device Contribution Quick Start

### Find your device's VID:PID

| Platform | How to find VID:PID |
|----------|---------------------|
| **macOS** |  → About This Mac → System Report → **USB** |
| **Linux** | `lsusb` — e.g., `ID 04e8:6860` |
| **Windows** | Device Manager → Properties → Hardware Ids → `USB\VID_04E8&PID_6860` |
| **SwiftMTP CLI** | `cd SwiftMTPKit && swift run swiftmtp --real-only probe` |

### Option A: Automated submission (recommended)

```bash
./scripts/submit-device.sh
```

Prompts for device info, generates the quirk entry, validates, and optionally creates a branch + PR.

### Option B: File an issue

Open a [Device Report issue](https://github.com/your-org/SwiftMTP/issues/new?template=device-report.yml) with VID:PID and observed behavior.

### Option C: Manual collection + PR

1. Connect device (USB, unlocked, MTP mode)
2. Collect: `swift run --package-path SwiftMTPKit swiftmtp collect --device-name "Device" --noninteractive --strict --json`
3. Validate: `./scripts/validate-submission.sh Contrib/submissions/<dir> && ./scripts/validate-quirks.sh`
4. Submit: branch, add files, `git commit -s`, push, PR

### Privacy checklist

- [ ] No personal paths, hostnames, or emails in artifacts
- [ ] No raw serials in committed files
- [ ] `.salt` is not committed
- [ ] Bundle validated with `validate-submission.sh`

---

## Contributing Device Quirks

### Adding a new entry

1. **Automated (recommended)**: `./scripts/submit-device.sh`
2. **Interactive builder**: `./scripts/add-device.sh`
3. **CLI**: `swiftmtp add-device --vid 0x1234 --pid 0x5678 --name "Device" --class android`
4. **Manual**: add to `Specs/quirks.json` per [`Specs/quirks.schema.json`](../Specs/quirks.schema.json)

### Minimal entry format

```json
{
  "id": "acme-widget-phone-abcd",
  "match": { "vid": "0x1234", "pid": "0xabcd" },
  "tuning": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 5000,
    "ioTimeoutMs": 10000
  },
  "ops": {
    "supportsGetPartialObject64": true,
    "supportsGetObjectPropList": true
  },
  "status": "proposed",
  "confidence": "low",
  "source": "community",
  "evidenceRequired": ["usb-dump", "probe-log"]
}
```

| Field | Description |
|-------|-------------|
| `id` | Unique kebab-case: `brand-model-pid` |
| `match.vid` / `match.pid` | USB Vendor/Product IDs (hex with `0x` prefix) |
| `tuning` | Timeout and chunk-size overrides |
| `ops` | Boolean capability flags (see schema) |
| `status` | `proposed`, `verified`, or `promoted` |
| `confidence` | `low`, `medium`, or `high` |

### Validating and submitting

```bash
cd SwiftMTPKit
../scripts/validate-quirks.sh
swift test --filter QuirkMatchingTests
```

Add your entry to **both** `Specs/quirks.json` and `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`, then open a PR with supporting evidence in `Contrib/submissions/<your-device>/`.

See [Device Submission Guide](DeviceSubmission.md) for full instructions.

---

## Recognition

Contributors are recognized through:

- `Specs/quirks.json` provenance entries
- `CHANGELOG.md` for notable contributions
- GitHub release notes and PR history

---

## Related Docs

- [Roadmap](ROADMAP.md)
- [Testing Guide](ROADMAP.testing.md)
- [Device Submission Guide](DeviceSubmission.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Troubleshooting](Troubleshooting.md)
- [File Provider Tech Preview](FileProvider-TechPreview.md)
- [Device Report Issue Template](https://github.com/your-org/SwiftMTP/issues/new?template=device-report.yml)
