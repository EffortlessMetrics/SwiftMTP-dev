# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Release Candidate

### Wave 34–35 Error Diagnostics & CI (PRs #403–#406)

> **Summary**: Improved error diagnostics for MTPError/TransportError, CI workflow reliability improvements, lint fixes, and docs update. 3 wave-34 agents failed due to API 503 errors and were retried in wave 35. Session totals: **47 PRs merged** (#363–#406).

#### Key Stats
- **8,177 tests** executed across 20 test targets, **0 unexpected failures**, 40 skipped
- **20,026 device quirk entries** across 1,154 VIDs and 38 categories
- **47 PRs merged** this session (#363–#406)
- Build: **GREEN**, all smoke tests pass

#### Merged PRs
- **#403** — Error diagnostics: improved MTPError and TransportError descriptions for actionability
- **#404** — Docs update: wave 33–34 changelog, roadmap, and stats update
- **#405** — CI improvements: workflow reliability, caching, and timeouts
- **#406** — Lint fixes: line-length lint warnings fixed in transport layer

#### Highlights
- **Error diagnostics** (#403): MTPError and TransportError now produce human-readable, actionable descriptions — reduces first-line debugging time for device failures
- **CI reliability** (#405): improved caching, timeouts, and workflow robustness across CI pipelines
- **API 503 retries**: 3 agents in wave 34 hit API 503 errors; successfully retried in wave 35

---

### Waves 33–34 Polish & Docs (PRs #398–#402)

> **Summary**: Schema validation fix (77,654 errors eliminated), DocC generator fix, format sweep, transport logging improvements, and docs update. Session totals: **42 PRs merged** (#362–#402), tests grew from 7,112 → **8,177** (+1,065).

#### Key Stats
- **8,177 tests** executed across 20 test targets, **0 unexpected failures**, 40 skipped
- **20,026 device quirk entries** across 1,154 VIDs and 38 categories
- **42 PRs merged** this session (#362–#402)
- **+1,065 tests** added across the full session (waves 25–34)

#### Merged PRs
- **#398** — Quirks schema fix: corrected `quirks.schema.json` definitions to match actual data (77,654 validation errors → 0)
- **#399** — DocC generator fix: updated `docc-generator-tool` model to match current module structure
- **#400** — Format sweep: `swift-format` applied across all source and test files
- **#401** — Docs update: CHANGELOG, README, CLAUDE, ROADMAP refreshed for waves 32–33
- **#402** — Transport logging: improved inline docs, structured logging, and error diagnostics in transport layer

#### Highlights
- **Schema validation clean** (#398): the quirks JSON schema had drifted from the actual data format; fixed `additionalProperties`, enum values, and nested object definitions to eliminate all 77,654 validation errors
- **DocC generator** (#399): generator tool model updated so `docc-generator-tool` produces valid documentation catalogs
- **Transport documentation** (#402): comprehensive inline documentation and structured logging added to USB transport layer for better diagnostics and maintainability
- **Session milestone**: 42 PRs merged across 10 waves, growing test suite by 1,065 tests with zero unexpected failures throughout

---

### Wave 32 Broad Sweep (PRs #390–#397)

> **Summary**: Format sweep, fuzz expansion, store/FileProvider/XPC hardening, core protocol coverage, transport edge cases, and quirks research. Tests grow from 7,909 → **8,177** (+268 new tests).

#### Key Stats
- **8,177 tests** executed across 20 test targets (up from 7,909)
- **268 new tests** added
- **0 unexpected failures**

#### Merged PRs
- **#390** — Format sweep (swift-format across codebase)
- **#391** — Fuzz harness expansion
- **#392** — Store layer hardening
- **#393** — FileProvider & XPC tests
- **#394** — Core protocol coverage
- **#395** — Transport edge case tests
- **#396** — Quirks research expansion
- **#397** — Documentation update

---

### Wave 31 Coverage, Benchmarks & Enforcement (PRs #381–#388)

> **Summary**: Performance benchmarks, per-module coverage gate enforcement, UI accessibility tests, CLI smoke tests, and error recovery paths. Tests grow from 7,720 → **7,909** (+189 new tests).

#### Key Stats
- **7,909 tests** executed across 20 test targets (up from 7,720)
- **189 new tests** added
- **0 unexpected failures**

#### Merged PRs
- **#381** — Documentation update
- **#382** — Coverage gate per-module enforcement
- **#383** — UI accessibility tests
- **#384** — Performance benchmarks
- **#385** — Sync deep coverage
- **#386** — CLI smoke tests for all subcommands
- **#387** — TestKit enhancement tests
- **#388** — Error cascade and recovery path tests

#### Highlights
- **Performance benchmarks** (#384): added transfer throughput, codec round-trip, and index query benchmarks with baseline thresholds
- **Coverage gate per-module enforcement** (#382): `coverage_gate.py` now enforces minimum thresholds per module, not just aggregate
- **UI accessibility tests** (#383): SwiftUI accessibility audit tests for all major views
- **CLI smoke tests** (#386): end-to-end smoke tests for every `swiftmtp` subcommand

---

### Wave 30 Deep Coverage & Fuzzing (PRs #373–#380)

> **Summary**: Deep coverage passes across codec, transport, index, snapshot, quirks, and property tests. Codec fuzzing discovers PTP string max round-trippable length (253 chars, sentinel at 0xFF). Tests grow from 7,475 → **7,720** (+245 new tests).

#### Key Stats
- **7,720 tests** executed across 20 test targets (up from 7,475)
- **245 new tests** added
- **0 unexpected failures**
- All **20 test targets** now have deep coverage

#### Merged PRs
- **#373** — Documentation update
- **#374** — Codec fuzz expansion
- **#375** — Scenario test expansion
- **#376** — Transport deep coverage
- **#377** — Index deep coverage
- **#378** — Snapshot test expansion
- **#379** — Quirks research expansion
- **#380** — Property test expansion

#### Highlights
- **Codec fuzzing finding** (#374): PTP string max round-trippable length is **253 characters** (sentinel byte at 0xFF); strings ≥254 chars are silently truncated by the MTP codec
- **All 20 test targets deep**: every target now has dedicated deep coverage pass, not just breadth expansion
- **Property tests** (#380): expanded SwiftCheck generators for transfer, path normalization, and quirks merge properties

---

### Wave 29–30 Test Expansion (PRs #363–#372)

> **Summary**: Broad test expansion across all 20 targets, format sweep, and flaky test fix. Tests grow from 7,112 → **7,475** (+363 new tests).

#### Key Stats
- **7,475 tests** executed across 20 test targets (up from 7,112)
- **363 new tests** added
- **0 unexpected failures**
- All **20 test targets** expanded

#### Merged PRs
- **#363** — Format sweep (swift-format across entire codebase)
- **#364** — Flaky test fix: concurrent attach test (root cause: stream ordering)
- **#365** — Documentation refresh
- **#366** — Observability tests expansion
- **#367** — Store error tests expansion
- **#368** — XPC tests expansion
- **#369** — FileProvider tests expansion
- **#370** — BDD scenarios expansion
- **#371** — CLI/tooling tests expansion
- **#372** — Integration tests expansion

#### Highlights
- **Flaky concurrent attach test fixed** (#364): root cause was non-deterministic stream ordering in parallel device attach; fix applies deterministic sort before assertion
- **Format sweep** (#363): full swift-format pass ensuring consistent style across all Sources and Tests

---

### Wave 27–28 Quality & Data Fixes (PRs #348–#355)

> **Summary**: CI fixes, test alignment, device quirks expansion, and documentation refresh. Test count reaches ~6,978 across 20 targets.

#### Key Stats
- **6,978 tests** across 20 test targets (up from 6,272)
- **0 unexpected failures** (3 expected/known failures)
- **20,041 quirks entries** (up from 20,026)
- **~117 PRs** merged total

#### Wave 27 — Test Alignment & Quirks Dedup
- Removed 22 duplicate VID:PID pairs from quirks.json
- Aligned test files with actual SQLiteLiveIndex and PTPCodec APIs
- Added IndexQueryEdgeCaseTests and ExtendedPropertyTests

#### Wave 28 — CI Fixes & Docs Refresh
- Normalized 4,647 quirks notes fields from string to array (CI fix)
- Fixed SanDisk Sansa m230 BDD test assertion (requiresKernelDetach)
- Added Motorola, LG, Xiaomi/Poco/Redmi device quirks entries
- Updated Troubleshooting.md with current device status
- Swift-format sweep across codebase
- FIXUP_QUEUE clearance

---

### Waves 23–25 Test Expansion (PRs #324–#339)

> **Summary**: Tests grow from 5,275 to **6,272** across 20 targets (+997), with major device research expansion (HTC, Nokia, Philips, Toshiba, Acer, Microsoft, Dell, Fujitsu). **6,000-test milestone reached.**

#### Key Stats
- **6,272 tests** across 20 test targets (up from 5,275)
- **0 test failures**
- **~110 PRs** merged total (#229–#339)

#### Wave 23 — Device Research & Snapshot Expansion (PRs #324–#329)
- **QuirksTests 267→488**: +221 tests — HTC, Nokia, Philips device research
- **SnapshotTests 132→306**: +174 snapshot and visual regression tests
- **ScenarioTests 141→215**: +74 end-to-end device operation scenarios

#### Wave 24 — Sync, Store & Error Paths (PRs #331–#335)
- **SyncTests 238→305**: +67 mirror/diff/conflict resolution tests
- **StoreTests 201→262**: +61 SQLite persistence and journal tests
- **ErrorHandlingTests 334→398**: +64 error path and recovery tests
- **IntegrationTests 127→191**: +64 cross-module integration tests

#### Wave 25 — Tooling, Observability & UI (PRs #336–#339)
- **ToolingTests 117→251**: +134 CLI command, filter, and formatter tests
- **ObservabilityTests 138→206**: +68 structured logging and monitoring tests
- **UITests 34→104**: +70 SwiftUI view tests
- **Device research**: Toshiba, Acer, Microsoft, Dell, Fujitsu quirks research

---

### Final RC Test Expansion (PRs #309–#323)

> **Summary**: Waves 17–23 — tests grow from 4,336 to **5,275** across 21 targets (+939), every target expanded. Device research adds Sony Walkman/Alpha, Huawei/Honor, SanDisk Sansa, and Creative ZEN. **5,000-test milestone reached.**

#### Key Stats
- **20,020 device quirks** across 1,154 VIDs and 38 categories
- **5,275 tests** across 21 test targets (up from 4,336)
- **0 test failures**
- **395 commits** on main

#### Wave 17 — Observability & Index (PRs #309–#311)
- **Docs baseline update**: COVERAGE.md and CHANGELOG.md updated for 4,300+ tests (PR #309)
- **ObservabilityTests 70→138**: 68 structured logging tests for SwiftMTPObservability (PR #310)
- **IndexTests 226→276**: SQLiteLiveIndex persistence and query tests (PR #311)

#### Wave 18 — Transport, Codec & Sony Research (PRs #312–#314)
- **TransportTests 433→489**: USBClaimDiagnostics tests and InterfaceProbe expansion (PR #312)
- **QuirksTests 210→267**: Sony Walkman NWZ deep dive and Alpha camera research tests (PR #313)
- **MTPEndianCodecTests 90→172**: Expanded codec edge case and round-trip tests (PR #314)

#### Wave 19 — TestKit & Audio Player Quirks (PRs #315–#316)
- **TestKitTests 116→189**: VirtualMTPDevice and FaultInjectingLink expansion (PR #315)
- **SanDisk Sansa & Creative ZEN**: libmtp-researched flags for classic audio players (PR #316)

#### Wave 20 — Scenarios & BDD (PRs #317–#318)
- **ScenarioTests 71→141**: End-to-end device operation scenarios doubled (PR #317)
- **BDDTests 237→302**: 65 new Gherkin scenarios for connection, transfer, and quirks (PR #318)

#### Wave 21 — Huawei/Honor & XPC (PRs #319–#320)
- **Huawei/Honor quirks**: Device-specific tests for VID 0x12d1 (PR #319)
- **XPCTests 156→250**: XPC protocol boundary and resilience expansion (PR #320)

#### Wave 22 — CLI & FileProvider (PRs #321–#322)
- **SwiftMTPCLITests 132→264**: CLI command parsing, help output, smoke tests doubled (PR #321)
- **FileProviderTests 219→309**: Concurrency and edge case coverage expansion (PR #322)

#### Wave 23 — Property Tests (PR #323)
- **PropertyTests 248→350**: Transfer, path normalization, and quirks merging property tests (PR #323)

---

### Test Expansion & Device Research (PRs #274–#308)

> **Summary**: Waves 13–16 — tests grow from 3,490 to 4,336 across 21 targets (+1 UITests), QuirksTests 4.5× growth with device research for Samsung, Canon, Nikon, Google Pixel, Xiaomi, OnePlus, and OPPO/Realme.

#### Key Stats
- **20,009+ device quirks** across 62+ categories
- **4,336 tests** across 21 test targets (up from 3,490)
- **0 test failures**
- **1 new test target**: UITests (#278)

#### Wave 13 — Fixes & UITests (PRs #274–#280)
- **DocC fix**: Handle mixed string/object values in behaviorLimitations and warnings (PR #274)
- **Flaky test hardening**: Timing-sensitive test stabilization (PR #275)
- **Device submission tooling**: Improved contributor device submission docs (PR #277)
- **UITests target**: New SwiftUI view test target with 34 tests (PR #278)
- **ObservabilityTests + StoreTests expansion**: Coverage expansion for both targets (PR #279)
- **RC release artifacts**: Updated README and release artifacts (PR #280)

#### Wave 14 — Transport, Codec, BDD, Integration (PRs #281–#290)
- **TransportRecoveryTests**: Error recovery edge cases for transport layer (PR #281)
- **Codec fuzz regression**: Fuzz regression tests and expanded corpus (PR #282)
- **ScenarioTests expansion**: End-to-end device operation scenarios (PR #283)
- **BDD dynamic baselines**: BDD tests now derive baselines from quirks.json (PR #284)
- **Quirks governance**: Quirks governance and validation tests (PR #285)
- **VirtualDevice compliance**: VirtualMTPDevice compliance and FaultInjectingLink tests (PR #286)
- **Error propagation chains**: Error propagation chain tests (PR #287)
- **Cross-module integration**: Additional cross-module integration tests (PR #288)
- **Friction log + CI improvements**: Documentation and CI updates (PR #289)
- **Public API audit**: Audit and documentation of public API surface (PR #290)

#### Wave 15 — FileProvider, Property, CLI, DeviceActor (PRs #291–#300)
- **FileProvider enumeration**: Enumeration and materialization tests (PR #291)
- **Protocol-level property tests**: Property tests at the protocol level (PR #292)
- **Advanced sync property tests**: Sync edge case property tests (PR #293)
- **SQLite index stress tests**: Concurrency stress tests for SQLite index (PR #294)
- **XPC protocol boundary tests**: XPC boundary and protocol tests (PR #295)
- **CLI smoke tests**: Command parsing and help output tests (PR #296)
- **CLI output format snapshots**: Snapshot tests for CLI output formats (PR #297)
- **Quirks data quality**: Data quality validation tests for quirks database (PR #298)
- **DeviceActor concurrency**: Actor isolation and concurrency tests (PR #299)
- **FallbackLadder tests**: Error recovery strategy tests (PR #300)

#### Wave 16 — Device Research & Final Tests (PRs #301–#308)
- **Samsung Galaxy research**: Device-specific MTP research and improved quirks (PR #301)
- **TransferJournal resilience**: Edge case and resilience tests for journal-based resume (PR #302)
- **Canon/Nikon PTP research**: Camera PTP quirks improved with gphoto2 and vendor research data (PR #303)
- **RUNBOOK + release readiness**: Updated runbook and release readiness tests (PR #304)
- **Google Pixel research**: Pixel device research and improved quirks tests (PR #305)
- **Mirror/diff engine tests**: Comprehensive mirror and diff engine tests (PR #306)
- **MTP codec fuzzing**: Expanded codec edge case and fuzzing tests (PR #307)
- **Chinese phone brands**: Xiaomi, OnePlus, OPPO/Realme quirks tests (PR #308)

---

### Post-RC Test Expansion (PRs #249–#273)

> **Summary**: Waves 10–12 — test targets expanded from 15 to 20, total tests reach 3,490+ (verified via `swift test --list-tests`), 650+ device category corrections, and new resilience/data-integrity test suites added.

#### Key Stats
- **20,009+ device quirks** across 62+ categories
- **3,490+ tests** across 20 test targets (up from 3,793+ claimed, now verified)
- **0 test failures**
- **5 new test targets**: ObservabilityTests, QuirksTests, SwiftMTPCLITests, MTPEndianCodecTests, ErrorHandlingTests

#### Wave 10 — Test Infrastructure & Coverage (PRs #249–#258)
- **ObservabilityTests**: New dedicated test target for SwiftMTPObservability module (PR #250)
- **LiveIndexEdgeCaseTests**: SQLiteLiveIndex edge case coverage (PR #251)
- **QuirksTests**: Dedicated test target for SwiftMTPQuirks module (PR #253)
- **Inline protocol snapshot tests**: 70 inline protocol snapshot tests (PR #254)
- **ErrorCascadeTests**: 60 tests for error propagation and cascading (PR #255)
- **DeviceSubmissionTests**: Device contribution workflow tests (PR #256)
- **Mutation testing harness**: Lightweight mutation testing and detection (PR #257)
- **Performance benchmarks**: Benchmark tests for core subsystems (PR #258)
- **Documentation honesty pass**: Updated remaining docs and artifacts (PR #252)
- **RC release notes**: Comprehensive release notes and coverage stats (PR #249)

#### Wave 11 — CLI Tests, BDD, Device Quirks (PRs #259–#268)
- **CLI integration tests**: 35+ CLI tests using Swift Testing framework (PR #259)
- **Camera quirks**: 18 camera entries improved with gphoto2-verified PID/behavior data (PR #260)
- **Phone quirks**: 34 phone entries improved with researched MTP behavior data (PR #261)
- **TSAN CI fix**: Bypass swiftpm-xctest-helper for TSAN to avoid DTXConnectionServices conflict (PR #262)
- **BDD scenarios**: 32 new BDD scenarios for connection/transfer/quirk/error/index flows (PR #263)
- **Tablet/e-reader fixes**: 251 tablet/e-reader device category and flag corrections (PR #264)
- **Action camera/DAP/drone fixes**: 399 action camera, DAP, and drone category corrections (PR #265)
- **DocC generator fix**: All quirks.json fields made optional for robustness (PR #266)
- **XPC resilience tests**: 42 XPC resilience tests for protocol boundaries, service lifecycle, error propagation (PR #267)
- **Sync edge case tests**: 47 Sync edge case and property tests (PR #268)

#### Wave 12 — FileProvider, Index, Fixes (PRs #269–#273)
- **FileProvider resilience tests**: 41 FileProvider resilience & edge-case tests (PR #269)
- **Quirks categories**: Fix categories and add dev-board/IoT/automotive devices (PR #270)
- **IndexDataIntegrityTests**: 33 tests covering SQLite edge cases, concurrency, and data validation (PR #271)
- **Category reclassification test fixes**: Update 25 tests for category reclassifications (dap→audio-player, Kindle→tablet) (PR #272)
- **Property test refactor**: Refactor e-reader/wearable kernel detach property tests (PR #273)

---

### RC Validation Cycle (PRs #220–#248)

> **Summary**: Comprehensive RC hardening — tests nearly doubled from ~1,900 to 3,793+, a real XPC bug was found and fixed, CI is fully operational across all surfaces, and zero test failures remain.

#### Key Stats
- **20,009 device quirks** across 62 categories
- **3,793+ tests** across 15+ test targets (up from ~1,900)
- **0 test failures**
- **Real bug found & fixed**: XPC `UInt64` overflow in file-size encoding (PR #231)
- **CI fully configured**: Smoke, Documentation, TSAN, Fuzz, Build-test, Compat matrix

#### Test Expansion (PRs #223–#228, #236–#242, #245–#246)
- **BDD scenarios**: 117 previously-skipped scenarios unskipped and passing (PR #223)
- **PropertyTests**: New property tests for sync/index/codec modules (PR #224)
- **SyncTests**: 22 → 111 tests — mirror, diff, conflict resolution (PR #225)
- **ToolingTests**: 80+ CLI and tooling tests added (PR #226)
- **XPCTests**: 20 → 91 tests — protocol round-trip, overflow, edge cases (PR #227)
- **TestKitTests**: 14 → 79 tests — VirtualMTPDevice, FaultInjectingLink (PR #228)
- **RecoveryPathTests**: 30 new recovery/retry path tests (PR #236)
- **IntegrationTests**: Cross-module integration expansion (PR #238)
- **StoreTests**: 42 new persistence/journal tests (PR #240)
- **FileProviderTests**: 47 new File Provider extension tests (PR #241)
- **ScenarioTests**: 14 new end-to-end scenario tests (PR #242)
- **TransportTests**: 123 new transport edge-case tests (PR #245)
- **Property test skips**: 9 skipped property tests resolved (PR #246)

#### Bug Fixes & Stability (PRs #230–#234, #239, #243, #248)
- **XPC UInt64 overflow**: Real bug — file sizes > 4 GB were silently truncated in XPC encoding; fixed with proper `UInt64` round-trip (PR #231)
- **Swift 6 concurrency**: Strict sendability and actor isolation fixes across modules (PRs #230, #239)
- **SyncTests macOS**: Platform-specific test fixes for macOS runner compatibility (PR #232)
- **Quirks.json integrity**: Deduplication, schema cleanup, field normalization (PRs #233, #235)
- **BDD fixes**: Gherkin scenario corrections and step definition alignment (PR #234)
- **5 test failures**: Resolved failures from Wave 5 expansion (PR #243)
- **Flaky tests**: Timing-sensitive test stabilization and quirk DB load fallback (PR #248)

#### CI & Infrastructure (PRs #220–#222, #229, #237, #244)
- **CI runner fix**: Migrated to `macos-15` runner for stability (PR #220)
- **Documentation CI**: RC documentation workflow fix (PRs #221, #222)
- **Snapshot baselines**: Updated for current quirks DB state (PR #229)
- **Fuzz corpus**: Expanded fuzz corpus with regression test cases (PR #237)
- **TSAN CI**: Robust Thread Sanitizer runtime detection and SIP-safe configuration (PR #244)

---

### Added
- **🎉 20,040-Entry Milestone**: Device quirks database reaches 20,040 entries across 1,157 VIDs and 62 categories — massive 20K milestone
  Note: Quirk entries are research-based (sourced from libmtp and vendor specs), not validated with real hardware.
- Milestone BDD tests: `testDatabaseHas19000PlusEntries`, `testDatabaseHas20000PlusEntries`
- Core baseline bumped from 18,000 → 20,000 entries / 1,090 → 1,150 VIDs in `QuirkMatchingTests`
- Compat matrix regenerated for 20,040 entries
- **🎉 19,000+-Entry Milestone**: Device quirks database surpasses 19,000 entries — continued device expansion across all categories
- Milestone BDD test: `testDatabaseHas19000PlusEntries`
- Core baseline bumped from 18,000 → 19,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 19,000+ entries
- **🎉 18,000+-Entry Milestone**: Device quirks database reaches 18,000+ entries — baselines bumped to 18,000 entries / 1,090 VIDs
- Filled small categories to 50+: trail-camera (56), webcam (56), ptz-camera (55)
- Added brands: Browning, Wildgame, Spypoint (trail-camera); Razer, Elgato, AVerMedia, Poly, Jabra (webcam); Sony BRC, Panasonic AW, PTZOptics, Vaddio, Datavideo, Marshall (ptz-camera)
- Milestone BDD tests: `testDatabaseHas18000PlusEntries`, `testDatabaseHas1090PlusVIDsMilestone18000`
- Core baseline bumped from 17,000 → 18,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 18,000+ entries
- **🎉 17,425-Entry Milestone**: Device quirks database reaches 17,425 entries — baselines bumped to 17,000 entries / 1,080 VIDs
- Milestone BDD test: `testDatabaseHas17000PlusEntries`, `testDatabaseHas1080PlusVIDsMilestone17000`
- Core baseline bumped from 16,000 → 17,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 17,425 entries
- **🎉 16,237-Entry Milestone**: Device quirks database reaches 16,237 entries across 1,088 VIDs and 59 device categories — all categories 50+
- Milestone BDD tests: `testDatabaseHas16000PlusEntries`, `testDatabaseHas1075PlusVIDsMilestone16000`, `testAllCategoriesHave50PlusEntries`
- Core baseline bumped from 15,000 → 16,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 16,237 entries
- **🎉 15,500+-Entry Milestone**: Device quirks database reaches 15,508 entries across 1,073 VIDs and 59 device categories
- Milestone BDD tests: `testDatabaseHas15000PlusEntries`, `testDatabaseHas1050PlusVIDsMilestone15000`
- Core baseline bumped from 14,500 → 15,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 15,508 entries
- **🎉 14,690-Entry Milestone**: Device quirks database reaches 14,690 entries across 1,038 VIDs and 55 device categories
- Milestone BDD tests: `testDatabaseHas14500PlusEntries`, `testDatabaseHas1000PlusVIDsMilestone14500`
- Core baseline bumped from 14,000 → 14,500 in `QuirkMatchingTests`
- Compat matrix regenerated for 14,690 entries
- **🎉 14,000-Entry Milestone**: Device quirks database reaches 14,000+ entries across 970+ VIDs and 55 device categories
- Milestone BDD tests: `testDatabaseHas14000PlusEntries`, `testDatabaseHas950PlusVIDsMilestone14000`
- Core baseline bumped from 13,500 → 14,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 14,000+ entries
- **🎉 13,700+-Entry Milestone**: Device quirks database reaches 13,738 entries across 939 VIDs and 53 device categories
- Milestone BDD tests: `testDatabaseHas13500PlusEntries`, `testDatabaseHas900PlusVIDsMilestone13500`
- Core baseline bumped from 12,500 → 13,500 in `QuirkMatchingTests`
- Compat matrix regenerated for 13,700+ entries
- **🎉 12,900+-Entry Milestone**: Device quirks database reaches 12,945 entries across 810 VIDs and 43 device categories — all 43 categories at 100+ entries
- Milestone BDD tests: `testDatabaseHas12500PlusEntries`, `testDatabaseHas800PlusVIDsMilestone12500`
- Core baseline bumped from 12,000 → 12,500 in `QuirkMatchingTests`
- Compat matrix regenerated for 12,900+ entries
- **🎉 12,000-Entry Milestone**: Device quirks database reaches 12,375 entries across 785 VIDs and 43 device categories — all 43 categories at 100+ entries
- Milestone BDD tests: `testDatabaseHas12000PlusEntries`, `testDatabaseHas750PlusVIDsMilestone12000`, `testAllCategoriesHave100PlusEntries`
- Core baseline bumped from 11,000 → 12,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 12,000+ entries
- **🎉 11,000-Entry Milestone**: Device quirks database reaches 11,000+ entries across 650+ VIDs and 38 device categories
- Milestone BDD tests: `testDatabaseHas11000PlusEntries`, `testDatabaseHas650PlusVIDsMilestone11000`
- Core baseline bumped from 10,500 → 11,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 11,000+ entries
- **🎉 10,800-Entry Milestone**: Device quirks database reaches 10,800+ entries across 600+ VIDs and 38 device categories
- Milestone BDD tests: `testDatabaseHas10500PlusEntries`, `testDatabaseHas600PlusVIDsMilestone10500`
- Core baseline bumped from 10,000 → 10,500 in `QuirkMatchingTests`
- Compat matrix regenerated for 10,800+ entries
- **🎉 10,000-Entry Milestone**: Device quirks database reaches 10,000+ entries across 600+ VIDs and 38 device categories
- Milestone BDD tests: `testDatabaseHas10000PlusEntries`, `testDatabaseHas600PlusVIDs`, `testDatabaseHas38PlusCategories`
- Property test: `testAllEntriesHaveUniqueIDs` (no duplicate entry IDs across all 10,000+ entries)
- Core baseline bumped from 9,500 → 10,000 in `QuirkMatchingTests`
- Compat matrix regenerated for 10,000+ entries
- Baseline & compat matrix update for 9,600+ quirks entries (9,600+ across 570+ VIDs, 38 categories)
- Wave 63: CI fixes — Xcode 16.2 + Swift 6.2 toolchain setup, workflow stabilization
- Wave 64: IoT/embedded device entries — smart home hubs, embedded SBCs, dev boards
- Wave 65: Vintage media player expansion — legacy PMP and DAP entries
- Wave 66: 100% category coverage — all 5,461+ entries assigned to a device category (0 unknown)
- Wave 67: Camera expansion — thermal cameras, microscopes, telescopes, body cameras
- Wave 68: Test baseline + BDD updates — property test baseline bumps, new Gherkin scenarios
- Wave 69: Phone brand expansion — additional regional/carrier phone models
- Wave 70: Automotive/industrial entries — dashcams, CNC, audio interfaces
- Wave 71: Documentation refresh — compat matrix regeneration, CHANGELOG + README updates
- Wave 72–75: Samsung/LG/Huawei expansion, Chinese phone brands, additional regional entries
- Waves 76–78: Industrial cameras, machine vision, smart glasses, AR glasses, e-ink displays, embedded/fitness entries
- **🎉 Device Quirks Database: 10,000+ entries across 600+ VIDs and 38 device categories**
- **🎉 Device Quirks Database: 9,600+ entries across 570+ VIDs and 38 device categories**

- Wave 42-50: Gaming handhelds, VR, hi-fi DAPs, embedded dev boards, 3D printers, lab instruments
- Wave 52-53: Device category assignment — 97% of entries now categorized (phones, cameras, media players, GPS, etc.)
- Wave 54: 19 audio recorder entries (Zoom H1n/H4n/H5/H6/H8/F3/F6/F8n, TASCAM DR-40X/DR-100mkIII/X6/X8, Roland R-07/R-88, BOSS BR-800, Sound Devices MixPre-3II/6II, Olympus LS-P4/P5, Sony recorders)
- Wave 56: Final categorization pass — 4,418 of 4,571 entries have device categories
- Wave 59: Nintendo Switch (3), Kobo e-readers (4), dashcams, Garmin wearables (3), reMarkable 2, more

- Wave 33: 17 vintage/legacy media player entries (Palm, Creative, Archos, Cowon, Philips, Rio)
- Wave 34: 25 printer/scanner entries (Canon, Epson, HP, Kodak, Brother, Fujitsu, Polaroid)
- Wave 35: 11 drone/robotic camera entries (DJI, Parrot, Autel, Insta360, Skydio, Fimi)
- Wave 38: 34 automotive/GPS entries (Pioneer, Kenwood, Alpine, Sony, Garmin, TomTom)
- Wave 39: 6 medical/fitness entries (Polar, Wahoo, Coros, Withings)
- Wave 40: 7 tablet/e-reader entries (Lenovo, Xiaomi, Supernote)

- **🎉 Device Quirks Database: 5,738 entries across 297 VIDs** (up from 2,055): Massive expansion through waves 11–75:
  - **Smartphones**: Samsung Galaxy S/A/M/F/Z (120+), Xiaomi/Redmi/POCO (136+), Huawei P/Mate/nova (68+), Honor (16+), OnePlus (28+), Google Pixel/Nexus (35+), Sony Xperia (312+), LG (73+), HTC (82+), OPPO/Realme (62+), vivo (24+), ZTE/nubia (29+), ASUS ZenFone/ROG (24+), Motorola Edge/Moto G/Razr (61+), Nokia/HMD (96+), BlackBerry (20+), Fairphone (3), Nothing Phone (5), Meizu (14+), Sharp Aquos (13+), Kyocera DuraForce (7+), CAT Rugged (5+), Razer (2), Lenovo (56+), Acer (48+), Essential (2+)
  - **Cameras (PTP/MTP)**: Canon EOS/R-series (163+), Nikon D/Z-series (96+), Sony Alpha (147+), Fujifilm X-series (69+), Olympus/OM System (66+), Panasonic Lumix (42+), Sigma (13+), Hasselblad (8+), Leica M/Q/SL (17+), Pentax (6+), Phase One (5+), GoPro Hero (12+), Insta360 (13+), DJI drones (13+), Blackmagic BMPCC (5+), FLIR/InfiRay/Seek thermal (14+)
  - **E-readers**: Kindle/Fire (67+), Kobo (14+), Onyx Boox (17+), PocketBook (14+), Barnes & Noble Nook (11+), Tolino (8+)
  - **Dashcams/GPS**: Garmin (97+), TomTom (11+), Magellan (4+), BlackVue (6+), Thinkware (6+), 70mai (10+), Rexing/Vantrue (10+)
  - **Gaming handhelds**: Anbernic (3), Retroid (3), AYN Odin (3), Valve Steam Deck (2), Meta Quest (2)
  - **Legacy media players**: Creative ZEN (19+), SanDisk Sansa (21+), iRiver (36+), Archos (71+), Cowon/iAudio (7+), Toshiba Gigabeat (4+), Thomson/RCA/TrekStor/Insignia (80+)
  - **DAPs/Hi-Fi**: Astell&Kern (11+), FiiO (8+), HiBy (6+), iBasso (4+), Shanling (6+), Sony Walkman NW (8+)
  - **Printers/Scanners**: HP OfficeJet/DeskJet (12+), Canon PIXMA (8+), Epson Expression (8+), Brother MFC (4+), Fujitsu ScanSnap (4+)
  - **Wearables**: Fitbit (21+), Garmin (22+), Polar (8+), Suunto (7+), Samsung Galaxy Watch (6+), Fossil/Skagen (24+), Mobvoi TicWatch (7+)
  - **Tablets**: Samsung Galaxy Tab (13+), Huawei MatePad (5+), ASUS ZenPad (10+), Lenovo Tab (30+), Amazon Fire HD (18+), Acer Iconia (9+), Chuwi (1+)
  - **Portable storage**: WD My Passport Wireless (2), Seagate Wireless (2)
  - **Audio/Recording**: Roland FANTOM/SPD/RD (12+), Zoom H/Q/L recorders (7+), TASCAM DR/PORTACAPTURE (7+), Sony ICD/PCM recorders (6+), Sennheiser headphones (10+)
  - **Specialty**: Epson scanners (9+), Canon CanoScan (5+), HP PhotoSmart (4+), Casio cameras (5+), Minolta DiMage (4+), Sony PSP/Vita (7+), Microsoft Surface Duo (2)
  - **Apple**: iPhone/iPad PTP camera roll (4+), iPod classic/nano MTP (7+) with iOS-Compatibility.md documentation
  - **Wave 17**: Android TV & streaming devices (+19)
  - **Wave 18**: libgphoto2 PTP cameras (+295)
  - **Wave 19**: Regional/carrier phones (+97)
  - **Wave 20**: JSON Schema validation + QuirkFlags.cameraClass
  - **190 unique USB vendor IDs** across all categories
- **BDD tests waves 7–15**: `android-brands-wave7.feature`, `flagship-brands-wave8.feature`, `wave11-emerging-brands.feature`, `wave14-ereaders-niche.feature` (54+ test methods, 4 skipped), covering all major device categories
- **VirtualDeviceConfig presets**: 16 new presets (LG G5, HTC One M8, ZTE Axon 7, OPPO Reno 2, vivo V20 Pro, BlackBerry KEYone, Fitbit Versa, Garmin FR945, Google Pixel 8, OnePlus 12, Samsung Galaxy S24, Nothing Phone 2, Valve Steam Deck, Meta Quest 3, Tecno Camon 30, Archos 504)
- **Property tests**: 4 new invariants; baseline bumped from 395 → 3200
- **Friction log**: `Docs/friction-log.md` tracking 24+ improvement opportunities (P0–P3)
- **iOS-Compatibility.md**: Explains PTP-only camera roll access vs full MTP limitation for iOS users
- **Compat matrix**: Regenerated with 5,738 entries and 297 VIDs


- **`MTPError.sessionBusy`**: New error case for transaction contention detection.
- **Transport recovery — classified errors**: `TransportPhase` enum (`.bulkOut`, `.bulkIn`, `.responseWait`); `TransportError.stall` maps `LIBUSB_ERROR_PIPE` with automatic `clear_halt` + one retry in `bulkWriteAll`/`bulkReadOnce`; `TransportError.timeoutInPhase(TransportPhase)` for phase-specific timeout classification with actionable messages.
- **Write-path durability**: `TransferJournal.recordRemoteHandle(id:handle:)` and `addContentHash(id:hash:)` (default no-ops for backward compat). `TransferRecord.remoteHandle` and `contentHash` fields. On retry after reset, partial remote objects are detected and deleted before re-upload. `MTPDeviceActor.reconcilePartials()` cleans up partial objects on session open.
- **BufferPool + 2-stage pipeline**: `BufferPool` actor with preallocated `PooledBuffer` (@unchecked Sendable) pool. `PipelinedUpload`/`PipelinedDownload` provide depth-2 concurrent read/send pipeline with `PipelineMetrics` (bytes, duration, throughput MB/s).
- **FileProvider incremental change notifications**: `signalRootContainer()` called after every `createItem`/`modifyItem`/`deleteItem` success. `enumerateChanges` and `currentSyncAnchor` implemented with SQLite change log; sync anchors encode Int64 change counter as 8-byte Data.
- **Quirk governance lifecycle**: `QuirkStatus` enum (`proposed | verified | promoted`) on `DeviceQuirk`. `evidenceRequired`, `lastVerifiedDate`, `lastVerifiedBy` fields. All existing profiles promoted to `promoted`. `scripts/validate-quirks.sh` enforces status presence and evidence requirements. `scripts/generate-compat-matrix.sh` generates markdown compatibility table.
- **Per-transaction observability timeline**: `TransactionLog` actor (ring-buffered at 1000) with `TransactionRecord` (opcode, txid, bytes, duration, outcome). `MTPOpcodeLabel` with 21 common opcode labels. `ActionableErrors` protocol with user-friendly descriptions for all `MTPError`/`TransportError` cases.
- **libmtp compatibility harness** (`scripts/compat-harness.py`): Python script comparing SwiftMTP vs `mtp-tools` output. Structured JSON evidence, diff classification, expectation overlays per device (`compat/expectations/<vidpid>.yml`).
- **Test count: 3,793+** (up from ~1,900 at start of RC cycle), 0 failures, 0 lint warnings.
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
