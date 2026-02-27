# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **DeviceSessionActor `withTransaction<R>`**: Exclusive protocol transaction lock on `MTPDeviceActor`. Concurrent callers queue in arrival order; the lock is always released even if the body throws. Prevents MTP command interleaving at actor reentrancy points.
- **`MTPError.sessionBusy`**: New error case for transaction contention detection.
- **Transport recovery — classified errors**: `TransportPhase` enum (`.bulkOut`, `.bulkIn`, `.responseWait`); `TransportError.stall` maps `LIBUSB_ERROR_PIPE` with automatic `clear_halt` + one retry in `bulkWriteAll`/`bulkReadOnce`; `TransportError.timeoutInPhase(TransportPhase)` for phase-specific timeout classification with actionable messages.
- **Write-path durability**: `TransferJournal.recordRemoteHandle(id:handle:)` and `addContentHash(id:hash:)` (default no-ops for backward compat). `TransferRecord.remoteHandle` and `contentHash` fields. On retry after reset, partial remote objects are detected and deleted before re-upload. `MTPDeviceActor.reconcilePartials()` cleans up partial objects on session open.
- **BufferPool + 2-stage pipeline**: `BufferPool` actor with preallocated `PooledBuffer` (@unchecked Sendable) pool. `PipelinedUpload`/`PipelinedDownload` provide depth-2 concurrent read/send pipeline with `PipelineMetrics` (bytes, duration, throughput MB/s).
- **FileProvider incremental change notifications**: `signalRootContainer()` called after every `createItem`/`modifyItem`/`deleteItem` success. `enumerateChanges` and `currentSyncAnchor` implemented with SQLite change log; sync anchors encode Int64 change counter as 8-byte Data.
- **Quirk governance lifecycle**: `QuirkStatus` enum (`proposed | verified | promoted`) on `DeviceQuirk`. `evidenceRequired`, `lastVerifiedDate`, `lastVerifiedBy` fields. All existing profiles promoted to `promoted`. `scripts/validate-quirks.sh` enforces status presence and evidence requirements. `scripts/generate-compat-matrix.sh` generates markdown compatibility table.
- **Per-transaction observability timeline**: `TransactionLog` actor (ring-buffered at 1000) with `TransactionRecord` (opcode, txid, bytes, duration, outcome). `MTPOpcodeLabel` with 21 common opcode labels. `ActionableErrors` protocol with user-friendly descriptions for all `MTPError`/`TransportError` cases.
- **libmtp compatibility harness** (`scripts/compat-harness.py`): Python script comparing SwiftMTP vs `mtp-tools` output. Structured JSON evidence, diff classification, expectation overlays per device (`compat/expectations/<vidpid>.yml`).
- **Test count: 1920** (up from 1891), 0 failures, 0 lint warnings.
- **Expanded device quirk database** from 7 → 26 → **50 entries** (wave 1 + wave 2), adding profiles for Samsung S20/S21/Kies, LG V20/G5/G6/G4/V10, HTC U11/U12/One M8/M9, Huawei P9/P20/P30 series, ASUS ZenFone 5/6, Acer Iconia A500/A700, Oppo/Realme, Google Nexus One/7, Sony Xperia Z1/Z5/XZ, Sony Alpha a7III/a7RIV, Panasonic Lumix G, Olympus E-series, and Ricoh/Pentax K-series.
- **VirtualDeviceConfig factory presets** for 13 device families: `samsungGalaxy`, `samsungGalaxyMtpAdb`, `googlePixelAdb`, `motorolaMotoG`, `sonyXperiaZ`, `canonEOSR5`, `nikonZ6`, `onePlus9`, `lgAndroid`, `lgAndroidOlder`, `htcAndroid`, `huaweiAndroid`, `fujifilmX`.
- **QuirkMatchingTests**: 77+ tests covering all 50 quirk entries, no-match guards, timeout spot-checks, and policy-consistency tests.
- **PTPCodec comprehensive tests**: 7 new tests covering `value(dt: 0xFFFF)` regression (bit-14 collision bug), all scalar types, UINT128, array decode, bounds checking, and MTPDateString edge cases.
- **PTPReader property tests**: `PTPReaderValuePropertyTests.swift` — 7 SwiftCheck property tests (100 checks each) for scalar round-trips, 0xFFFF regression, UINT32 array, and truncated-data nil safety.
- **FaultInjectionTests**: 7 new `ErrorHandlingTests` covering FaultInjectingLink disconnect/timeout/busy propagation, repeatCount exhaustion, sequential faults, passthrough, and executeCommand fault injection.

- **Transfer throughput telemetry**: `TransferJournal.recordThroughput(id:throughputMBps:)` protocol method captures measured MB/s on read and write completion. `TransferEntity.throughputMBps` persists to SwiftData. Default no-op implementation preserves backward compatibility.
- **Actionable CLI error messages**: `actionableMessage(for:)` helper in `CLIState.swift` maps all `MTPError` and `TransportError` cases to concise fix-guidance strings. `probe`, `pull`, `push`, and `bench` now emit actionable hints instead of raw error descriptions.
- **Canon EOS and Nikon DSLR device profiles**: Added `canon-eos-rebel-3139` (PTP conflict guidance) and `nikon-dslr-0410` (NEF vendor extension) experimental quirk entries with full device guides.
- **Parallel multi-device enumeration**: `DeviceServiceRegistry.startMonitoring` now dispatches each `onAttach` handler in an independent `Task {}`, so N simultaneously-connected devices are initialized concurrently instead of serially.
- **BDD test coverage expanded** from 1 to 8 implemented Gherkin scenarios covering session open, error propagation (disconnect/busy/timeout), folder create, file delete, file move, and file integrity.
- **Canonical collect+benchmark troubleshooting sequence** in `Docs/Troubleshooting.md` with failure branches for each step and artifact descriptions.
- **Pre-PR local gate** documented in `Docs/Troubleshooting.md` and `Docs/ContributionGuide.md` (format → lint → test → TSAN → quirks validation).
- **CI Workflows reference table** in `Docs/ContributionGuide.md` clarifying required vs supplemental checks.
- **Per-device troubleshooting notes** expanded in `Docs/Troubleshooting.md`: Pixel 7/Tahoe 26 bulk-transfer root cause, OnePlus 3T large-write workaround, Canon EOS PTP conflict, Nikon NEF vendor extension.
- **validate-submission.sh** now checks `submission.json` itself for `/Users/`, Windows, and Linux path leaks (not only `usb-dump.txt`).
- **USB 3.x adaptive chunk sizing**: `MTPLinkDescriptor.usbSpeedMBps` field (populated from `libusb_get_device_speed`) auto-scales `maxChunkBytes` floor — 4 MiB for USB 2.0 Hi-Speed, 8 MiB for USB 3.0 SuperSpeed — when no quirk override is present.
- **MTPDataEncoder fully adopted**: All `withUnsafeBytes(of:littleEndian)` raw encoding in `Proto+Transfer.swift`, `MockTransport.swift`, and `StorybookCommand.swift` migrated to `MTPDataEncoder`, eliminating divergence between protocol stacks and fuzz inputs (FIXUP_QUEUE item 5 complete).
- **100% line coverage** on all gated modules: `SwiftMTPObservability` (57/57), `SwiftMTPQuirks` (492/492), `SwiftMTPStore` (628/628), `SwiftMTPSync` (244/244). New tests cover `recordThroughput` adapter path and `shouldSkipDownload` size/timestamp mismatch branches.
- **Test count: 1891** (up from 1888 after this sprint).

### Changed

- `TransferRecord` gains optional `throughputMBps: Double?` field (backward-compatible, defaults to `nil`).
- Device submission PR template commands updated to canonical `cd SwiftMTPKit && swift run swiftmtp ...` form and to sync both `Specs/quirks.json` and `SwiftMTPQuirks/Resources/quirks.json`.
- Release checklist Suggested Validation Commands use `cd SwiftMTPKit` pattern and include `coverage_gate.py` step.
- JSON probe error output now includes a `hint` field with the actionable fix message.

### Fixed

- Schema gaps in `xiaomi-mi-note-2-ff40` (missing `confidence`) and `google-pixel-7-4ee1` (missing `ops` block) corrected in `Specs/quirks.json`.
- Removed debug `print()` statements from `DeviceActor+PropList.swift`.

- **FileProvider write operations**: `createItem`, `modifyItem`, `deleteItem` now fully wired to XPC backend (`MTPFileProviderExtension.swift`).
- **XPC write protocol**: `WriteRequest`, `DeleteRequest`, `CreateFolderRequest`, `WriteResponse` — all NSSecureCoding with round-trip tests.
- **`swiftmtp-docs` tool**: Hands-off DocC device page generator. Reads `Specs/quirks.json` and emits per-device `.md` pages to `Docs/SwiftMTP.docc/Devices/`. Run: `swift run swiftmtp-docs Specs/quirks.json Docs/SwiftMTP.docc/Devices/`.
- **`learn-promote` tool** re-added to Package.swift and fixed: now uses correct `QuirkDatabase.match(vid:pid:...)` API and `DeviceQuirk` field names.
- **Multi-device `DeviceServiceRegistry` tests**: 4 new tests covering concurrent registration of 3 devices, isolated detach/reconnect, domain remapping, and remove-one-keeps-others.
- **FileProvider integration tests**: Replaced 12 all-skipped stubs with 10 real mock-based tests (`FileProviderWriteIntegrationTests`, `MTPFileProviderItemIntegrationTests`) plus 3 correctly-documented sandbox-only skips.

- **Quirk database: 50 → 576 → **1,189+ entries** (waves 3–7)**. New VIDs added progressively:
  - Wave 3/4: Alcatel/TCL (0x1bbb), Sharp Aquos (0x04dd), Kyocera (0x0482), Fairphone (0x2ae5), Honor (0x339b), Casio Exilim (0x07cf), Kodak EasyShare (0x040a), OM System (0x33a2), GoPro (0x2672 more), Garmin (0x091e)
  - Wave 5: SanDisk media players (0x0781), Creative ZEN (0x041e), iRiver (0x4102), Cowon iAudio (0x0e21), Microsoft Zune (0x045e), Philips GoGear (0x0471), Samsung YP-series media players, Sony NWZ Walkman more, Archos (0x0e79), Amazon Kindle/Fire (0x1949), Barnes & Noble Nook (0x2080), Kobo e-readers (0x2237), MediaTek Android (0x0e8d), Spreadtrum/Transsion (0x1782), LeTV/LeEco (0x2b0e), BLU (0x271d)
  - Wave 6: Fujifilm X/GFX full lineup, Nokia Symbian/HMD Android/Lumia, Microsoft KIN/Windows Phone, BlackBerry BB10/DTEK/KEYone, Lenovo MIX/Tab, Sony NWZ more, Garmin wearables more, DJI drones
  - Wave 7: LG G2-Velvet full series, HTC One/Desire/U-series full, ZTE Blade/Axon/Max, OPPO/Realme/OnePlus N10, vivo/iQOO all models, Xiaomi Mi/Redmi/POCO, BlackBerry BB OS legacy, Insta360 ONE/X/RS/X3/X4/Ace, AKASO EK7000-Brave, DJI Osmo/Pocket/mini drones, Ricoh Theta S/V/Z1/SC2/X, Kodak DC/EasyShare/PIXPRO full, Garmin Dash Cam series, Viofo/Nextbase dashcams, TCL/Alcatel/Wiko/Itel/Tecno/Infinix Android brands
  - Total VIDs now covered: 50+
- **PTP class heuristic**: Unrecognized USB interface-class 0x06 devices automatically receive proplist-enabled PTP policy — cameras connect without a quirk entry. Auto-disable fallback: `GetObjectPropList` returning `OperationNotSupported` is silently suppressed and the device is downgraded to object-info enumeration.
- **`swiftmtp quirks lookup --vid 0xXXXX --pid 0xXXXX`**: New CLI subcommand to look up a device by VID/PID and print its quirk ID, governance status, and proplist capability.
- **`swiftmtp add-device --brand … --model … --vid … --pid … --class android|ptp|unknown`**: Generates a fully-formed quirk entry JSON template for community submission.
- **`swiftmtp info`**: New CLI command showing database stats (entry count, unique VIDs, proplist-capable count, kernel-detach count, by-status breakdown; `--json` output supported).
- **`swiftmtp wizard` auto-suggests `add-device`**: When wizard detects an unrecognized device, it now shows the exact `swiftmtp add-device` command to run, with device class inferred from manufacturer/model name.
- **Contributor tooling**: `Docs/DeviceSubmission.md` step-by-step guide, `Docs/ContributionGuide.md` "Contributing Device Data" section. `validate-quirks.sh` now shows which specific IDs/VID:PID pairs are duplicated instead of a generic error.
- **BDD scenarios**: 3 new Gherkin feature files — `ptp-class-heuristic.feature`, `auto-disable-proplist.feature`, `device-families-wave4.feature` (17 new scenarios total).
- **Property tests** (`QuirksDatabasePropertyTests.swift`): 14 new SwiftCheck property tests validating DB integrity invariants (unique IDs, unique VID:PID pairs, consistent PTP/Android flag relationships, EffectiveTuningBuilder monotonicity).
- **Snapshot tests** (`QuirkPolicySnapshotTests.swift`): 7 policy-regression snapshot tests with stored JSON baselines preventing accidental heuristic/flag regressions.
- **Heuristic integration tests** (`HeuristicIntegrationTests.swift`): 8 integration tests exercising QuirkResolver + DevicePolicy + VirtualMTPDevice for PTP heuristic trigger and auto-disable paths.
- **Compat matrix** (`Docs/compat-matrix.md`): Auto-generated markdown table of all 395 quirk entries with status, VID:PID, and key flags.
- `SendableBox<T>` helper for bridging ObjC completion handlers into Swift 6.2 `sending Task` closures.
- Sprint execution playbook with DoR/DoD, weekly cadence, carry-over rules, and evidence contracts (`Docs/SPRINT-PLAYBOOK.md`).
- Central documentation hub for sprint/release workflows and technical references (`Docs/README.md`).
- Sprint kickoff routing in `README.md` so contributors can find roadmap, playbook, gates, and troubleshooting flows quickly.

### Changed

- **`Package.swift`**: swift-tools-version upgraded to 6.2; platforms upgraded to macOS 26 / iOS 26; added `SwiftMTPCLI`, `SwiftMTPUI`, `SwiftMTPApp`, `MTPEndianCodecFuzz`, `SwiftMTPFuzz`, `simple-probe`, `test-xiaomi`, `learn-promote`, `swiftmtp-docs`, `SwiftMTPCLITests` targets.
- **`SwiftMTPFileProvider` / `SwiftMTPXPC`**: Removed `.swiftLanguageMode(.v5)`; now strict Swift 6. `MTPFileProviderItem.ItemComponents` is now `Sendable`.
- **`parseUSBIdentifier` test**: Corrected expectation — unprefixed bare numbers are treated as hex per USB convention (`"4660"` → `0x4660`, not decimal 4660).
- `MTPEndianCodecFuzz` harness now emits per-iteration failure counters and crash corpus hex dump.
- Snapshot baselines regenerated for 5 stale probe/quirks snapshots.
- Roadmap now includes explicit sprint execution rules, active sprint snapshot, and 2.1 dependency/risk register (`Docs/ROADMAP.md`).
- Release checklist and runbook now require docs/changelog sync, required workflow health, and sprint carry-over alignment before tag cut (`Docs/ROADMAP.release-checklist.md`, `RELEASE.md`).
- Testing guide now separates required merge workflows from optional/nightly surfaces and includes a standard PR evidence snippet (`Docs/ROADMAP.testing.md`).
- Contribution and submission docs now include sprint-prefixed naming conventions, DoR alignment, and sprint fast-path submission guidance (`Docs/ContributionGuide.md`, `Docs/ROADMAP.device-submission.md`).
- PR templates now use repository-root command examples with `--package-path SwiftMTPKit` for operational consistency (`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/device-submission.md`).
- Troubleshooting now defines minimum evidence expected when opening/updating sprint issues (`Docs/Troubleshooting.md`).

### Fixed

- Build blocker: `SwiftMTPCLI` module existed on disk but had no Package.swift target declaration.
- `MTPEndianCodec` missing as linker dep of `SwiftMTPCore` (linker failure in protocol codec paths).
- Swift 6 `let` property ordering: `indexReader` now initialized before `super.init()` in `MTPFileProviderExtension`.
- `FuzzTests.swift`: static member access qualified with `Self.` for Swift 6 strict-mode `@Suite` structs.
- `DeviceFilterBehaviorTests.swift`: ambiguous `parseUSBIdentifier`/`selectDevice` qualified with `SwiftMTPCLI.` module prefix.
- `learn-promote/main.swift`: replaced non-existent `DeviceFingerprint` type and `bestMatch(for:)` / `.overrides.` accessors with correct `QuirkDatabase.match(vid:pid:...)` and `DeviceQuirk` field names.

## [2.0.0] - 2026-02-08

### Added

- macOS Tahoe 26 native support with SwiftPM 6.2+
- iOS 26 support
- macOS Tahoe 26 Guide documentation
- Swift 6.2 toolchain with latest concurrency features

### Changed

- Minimum platform: macOS 15 / iOS 18 deprecated; macOS 26 / iOS 26 required
- Swift 6 native with full actor isolation and strict concurrency
- IOUSBHost framework adopted as primary USB interface
- All DocC documentation updated with correct metadata syntax

### Removed

- macOS 15 backward compatibility
- Legacy USB entitlements (simplified to modern model)
- **Linux support**: IOUSBHost dependency is macOS-only. Linux users should remain on v1.x.

### Documentation

- New comprehensive macOS Tahoe 26 Guide
- Main SwiftMTP.md documentation refreshed
- Device Tuning Guide with corrected metadata

## [1.1.0] - 2026-02-07

### Added

- File Provider Integration: XPC service and extension for Finder sidebar
- Transfer Journaling: Resumable operations with automatic recovery
- Mirror & Sync: Bidirectional synchronization with conflict resolution
- Benchmarking Suite: Performance profiling with p50/p95 metrics
- OnePlus 3T support with experimental quirk entry
- Storybook Mode: Interactive CLI demo with simulated devices

### Changed

- Unified Swift Package with modular targets
- Thread Sanitizer runs only Core/Index/Scenario tests
- Structured JSON error envelopes with enhanced context
- Improved USB enumeration with fallback handling

### Fixed

- Race conditions via actor isolation
- Memory leaks in long-running transfers
- USB timeouts for slow devices with adaptive backoff
- Trust prompt workflow on macOS

### Performance

- Chunk auto-tuning: 512KB–8MB dynamic adjustment
- Batch operations for large file throughput
- SQLite indexing optimization

## [1.0.2] - 2025-09-07

### Fixed

- Events/delete/move commands use shared DeviceOpen.swift
- Events exits correctly with code 69 when no device present

### Notes

- Supersedes v1.0.1 artifacts; no API changes

## [1.0.1] - 2025-09-03

### Fixed

- Events command crash resolved with proper device enumeration
- Unified device open across delete, move, events commands

### Behavior

- Standardized exit codes: 64 (usage), 69 (unavailable), 70 (software)
- JSON outputs include schemaVersion, timestamp, event.code, event.parameters

### Compatibility

- No API changes; patch release is safe to adopt

## [1.0.0] - 2025-01-09

### Added

- Privacy-safe collect: Read-only device data collection
- Device quirks system with learned profiles and static entries
- Targeting flags: --vid/--pid/--bus/--address
- Core operations: probe, storages, ls, events, delete, move
- Version command with --version [--json] and build info
- Cross-platform support: macOS (Intel/Apple Silicon) and Linux
- Homebrew tap installation
- SBOM generation with SPDX format
- Comprehensive test suite with CI validation
- DocC documentation for devices and API

### Reliability

- Layered timeouts: I/O, handshake, inactivity
- Xiaomi stabilization with backoff and retry
- TTY guard for non-interactive environments
- Standardized exit codes

### Docs & CI

- DocC device pages generated from quirks.json
- CI pipeline with smoke tests and quirks validation
- Evidence gates for reliability (≥12.0 MB/s read, ≥10.0 MB/s write)

### Security

- HMAC-SHA256 redaction for serial numbers
- Input validation for device communications
- Atomic file operations
- Path traversal protection

### Changed

- API stabilization with internal implementation details
- JSON schema versioning in all outputs
- Build system with auto-generated BuildInfo.swift

### Privacy

- No personal data collection in submissions
- Safe defaults for privacy-preserving operations
- Full SBOM and build attestation

[Unreleased]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/EffortlessMetrics/SwiftMTP/releases/tag/v1.0.0
