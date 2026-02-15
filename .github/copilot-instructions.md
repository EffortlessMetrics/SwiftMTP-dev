# Copilot instructions — SwiftMTP

Purpose: help Copilot-style assistants (and future Copilot CLI sessions) quickly find authoritative build/test/lint commands, understand high-level architecture, and follow repository-specific conventions.

---

## 1) Build, test, and lint (authoritative commands)

Note: most package-level commands are intended to be run from the SwiftMTPKit directory unless noted.

- Build (dev):
  - cd SwiftMTPKit && swift build -v
- Build (release):
  - cd SwiftMTPKit && swift build -c release
- Build libusb XCFramework (required once / when updating libusb):
  - ./scripts/build-libusb-xcframework.sh

- Run CLI (help and common commands):
  - cd SwiftMTPKit && swift run swiftmtp --help
  - Examples: swift run swiftmtp probe | ls | pull | push | snapshot | mirror | bench | events | quirks | device-lab | wizard

- Run GUI app:
  - cd SwiftMTPKit && swift run SwiftMTPApp

- Tests (single and suite):
  - Run full test suite with coverage: swift test -v --enable-code-coverage
  - Run a single test by name: swift test --filter TestName
  - BDD scenarios: swift test --filter BDDTests
  - Property tests: swift test --filter PropertyTests
  - Snapshot tests: swift test --filter SnapshotTests
  - Thread Sanitizer run (excludes some USB transport tests):
    - swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests
  - Full verification suite: ./run-all-tests.sh
  - Fuzzing: ./run-fuzz.sh
  - Storybook/demo: ./run-storybook.sh

- Formatting & linting (required before commits):
  - Format: swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests
  - Lint: swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests

---

## 2) High-level architecture (big picture)

- Root package: SwiftMTPKit — this is the package root for builds, tests, and most developer workflows.
- Major modules and responsibilities:
  - SwiftMTPCore: actor-isolated MTP protocol implementation (core device logic, public APIs, CLI utilities)
  - SwiftMTPTransportLibUSB: libusb-based USB transport layer
  - SwiftMTPIndex: SQLite-based device content indexing and snapshots
  - SwiftMTPSync: mirror, diff, and sync operations with conflict resolution
  - SwiftMTPUI: SwiftUI views / GUI application
  - SwiftMTPQuirks: device quirks database & learned profiles
  - SwiftMTPObservability: structured logging and performance monitoring
  - SwiftMTPStore: persistence (transfer journals, metadata)
  - SwiftMTPTestKit: test utilities (VirtualMTPDevice, FaultInjectingLink)
  - SwiftMTPFileProvider: File Provider extension for macOS Finder integration
  - SwiftMTPXPC: XPC service bridging File Provider and main app
  - Tools/: CLI entrypoints (swiftmtp-cli), demo/test tools, fuzz harnesses

- Concurrency & testability:
  - Actor-based concurrency is central: device operations are routed through MTPDeviceActor for isolation and thread-safety.
  - Protocol-oriented design: the `MTPDevice` protocol is used to supply mock device implementations for tests and simulation.
  - Async/await throughout I/O and transfer code paths; TransferJournal provides resumable transfers.

- Where to look for authoritative files / resources:
  - Core protocol: SwiftMTPKit/Sources/SwiftMTPCore/Public/MTPDevice.swift
  - Actor: SwiftMTPKit/Sources/SwiftMTPCore/Internal/DeviceActor.swift
  - CLI: SwiftMTPKit/Sources/Tools/swiftmtp-cli/
  - Quirks: Specs/quirks.json and SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json
  - CI / validation workflows: .github/workflows/*.yml

---

## 3) Key repository conventions and patterns

- Always run package-level build/test commands from the SwiftMTPKit directory (paths and scripts assume that working directory).
- USB / libusb setup: the libusb XCFramework must be built/updated via ./scripts/build-libusb-xcframework.sh when setting up or changing libusb-related code.
- Actor isolation: device-facing code must be executed through MTPDeviceActor; avoid bypassing actor boundaries in new device logic.
- Mocking & demo mode: unit and verification tests use simulated profiles; enable with environment variables:
  - export SWIFTMTP_DEMO_MODE=1
  - export SWIFTMTP_MOCK_PROFILE=pixel7  # options: pixel7, galaxy, iphone, canon
- 15 test targets: CoreTests, TransportTests, IndexTests, FileProviderTests, ErrorHandlingTests, StoreTests, SyncTests, ScenarioTests, TestKitTests, IntegrationTests, XPCTests, ToolingTests, BDDTests, PropertyTests, SnapshotTests. Use --filter to run a single test or category in CI or locally.
- Coverage gating: `SwiftMTPKit/scripts/coverage_gate.py` enforces minimum thresholds in CI.
- Device quirks must be declared/edited in Specs/quirks.json (source of truth) and validated by the validate-quirks CI workflow.
- Formatting is enforced: run swift-format prior to commits; CI expects code to be formatted and lint-free.
- Use provided scripts for complex verification workflows: run-all-tests.sh, run-fuzz.sh, run-storybook.sh.

---

## 4) Assistant-specific notes

- CLAUDE.md (root) is the most complete machine-readable developer summary; consult it for comprehensive commands, architecture notes, and development practices.
- This repository already contains CI workflows (.github/workflows) that validate code, quirks, and releases; any automated changes should respect these checks.

---

## 5) Quick references

- README.md and CLAUDE.md (root) — high-level commands & architecture
- Docs/ContributionGuide.md — contribution and release workflows
- Specs/quirks.json and SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json — quirks data
- .github/workflows/* — CI and validation steps


---

If you want this file extended to include troubleshooting steps (common CI failures, test flakiness workarounds) or a short FAQ for Copilot prompts, say which area to cover and it will be added.