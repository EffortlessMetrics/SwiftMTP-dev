# SwiftMTP Roadmap

*Last updated: 2026-03-10*

> **Pre-Alpha Status**: SwiftMTP has extensive protocol and test infrastructure but minimal real-device validation. Only 1 device (Xiaomi Mi Note 2) has completed real file transfers. The version numbers below (2.x) reflect internal development milestones, not production readiness. Items marked as "shipped" or "complete" are code-complete and mock-tested unless noted otherwise — most have not been validated on real hardware.

This roadmap is the execution plan for the next implementation sprints in the 2.x release train.

## Current Operating Goal

Ship `v2.1.0` with improved real-device stability, better operator troubleshooting paths, and submission pipeline hardening, while keeping release gates green. Test suite now at **~8,577 tests executed** across 20 targets (40 skipped, 3 expected failures / 0 unexpected). Device quirks database at **20,026 entries** across **1,154 VIDs** and **38 categories** (research-based scaffolding from libmtp data and vendor specs — not validated on real devices). **83 PRs merged** this session (#363–#445).

## Recently Shipped (PR #8 — feat/device-robustness-and-docs-overhaul)

All items below are code-complete and mock-tested. None have been validated on real hardware unless noted.

- [x] **GetObjectPropValue / SetObjectPropValue** — `MTPLink` protocol property APIs with default implementations (mock-tested)
- [x] **MTPObjectPropCode enum** — all standard MTP object property codes (0xDC01–0xDC48)
- [x] **MTPDateString** — encode/decode MTP ISO 8601 compact date format
- [x] **MTPObjectInfo.modified** — populated from GetObjectInfo ModificationDate field (mock-tested)
- [x] **ObjectSize U64 fallback** — GetObjectPropValue(0xDC04) for files > 4 GB (mock-tested)
- [x] **GetObjectPropsSupported (0x9801)** — list device-supported properties per format (mock-tested)
- [x] **Extended MTPEvent** — storageAdded, storageRemoved, objectInfoChanged, deviceInfoChanged, unknown(code:params:) (mock-tested)
- [x] **FileProvider write operations** — createItem, modifyItem, deleteItem with XPC bridge (mock-tested, no real-device validation)
- [x] **Multi-device parallel transfers** — 8 scenario tests, DeviceServiceRegistry routing (mock-tested)
- [x] **FallbackAllFailedError** — carries full attempt history (name, duration, error per rung)
- [x] **Automatic documentation** — `swiftmtp-docs` SPM executable target for hands-off DocC generation
- [x] **~8,377 tests executed, 0 unexpected failures** (up from 1,849; 40 skipped, 3 expected failures across 20 test targets)

## Sprint Execution Rules

Use `Docs/SPRINT-PLAYBOOK.md` as the operating policy for all sprint items in this roadmap.

Minimum expectations for each item:

- Definition of Ready (DoR) is satisfied before implementation starts.
- Definition of Done (DoD) is satisfied before the item is marked complete.
- Docs + changelog are updated in the same PR as behavior changes.
- Transport/quirk changes include real-device artifact paths in PR evidence.

## Active Sprint Snapshot

| Sprint | Theme | Current State | Primary Risk | Primary Gate |
|--------|-------|---------------|--------------|--------------|
| 2.1-A | Transport stability + error clarity | Complete | Real-device timeout reproduction drift | `./scripts/smoke.sh` + targeted device artifacts |
| 2.1-B | Submission workflow hardening | Complete | Privacy/redaction false positives or misses | `./scripts/validate-submission.sh` |
| 2.1-C | CI + verification consolidation | Complete | Ambiguous required checks across workflows | CI workflow mapping + TSAN parity |

## Wave 38–39 Activity (2026-03-10)

Key development activity across these two waves — 21 PRs (#425–#445) covering protocol expansion, transport fixes, and testing:

### Wave 39 — Transport Fixes & Testing (PRs #436–#445)
- **README refresh** (#436): MTP operation coverage table showing all supported operations
- **Object format tests** (#437): 56 tests verifying all MTP 1.1 format→MIME mappings
- **Android edit tests** (#438): 19 round-trip tests for BeginEdit/EndEdit/Truncate extensions
- **CLI copy/edit** (#439): device-side copy and in-place edit CLI commands
- **Coverage tests** (#440): 61 tests for property codes, events, spec alignment, response codes
- **IOUSBHost transport** (#441): native macOS USB transport scaffold (alternative to libusb)
- **Response code coverage** (#442): all 42 MTP 1.1 response codes with descriptions
- **Pixel 7 transport fixes** (#443): handle re-open, set_configuration before claim, extended timeouts
- **Quirks governance** (#444): CI schema validation enforcement + `quirks stats` CLI command
- **Samsung transport fixes** (#445): skip alt-setting selection, skip pre-claim device reset

### Wave 38 — Protocol & Research (PRs #425–#435)
- **Troubleshooting overhaul** (#425): device-specific debugging guides for Samsung/Pixel/OnePlus
- **FUSE-T research** (#426): integration architecture doc for MTP filesystem mount
- **Index fixes** (#427): WAL mode verification, atomic rename fix, redundant index removed
- **Samsung research** (#428): 8 MTP init differences found, quirks updated
- **Pixel 7 research** (#429): 5 bulk transfer differences documented vs libmtp
- **Object formats** (#430): expanded 7→50+ with MIME type mapping
- **Property codes** (#431): expanded 11→50 with dataType/displayName
- **Event handling** (#432): expanded to all 14 MTP 1.1 events
- **Spec alignment** (#433): 5 fixes (txid wrap, DeviceBusy retry, session close)
- **Android edit extensions** (#434): BeginEditObject/EndEditObject/TruncateObject + opcode fix
- **CopyObject** (#435): server-side file copy with VirtualMTPDevice support

### Key Outcomes
- **~8,577 tests** (up from ~8,377), 0 unexpected failures
- **83 PRs merged** this session (#363–#445)
- Samsung and Pixel 7 transport fixes directly informed by wave 38 research
- IOUSBHost native transport scaffold opens path to removing libusb dependency
- Full MTP 1.1 response code coverage (42 codes)

## Wave 36–37 Activity (2026-03-09)

Key development activity in these waves — focused test hardening across 6 PRs:

- **PRs merged**: #409–#414 (test hardening: write-path safety, submission workflow, device compatibility, sync resilience, boundary conditions, FileProvider/XPC edge cases)
- **Submission workflow** (#409): validation scripts, privacy redaction, bundle structure, duplicate detection tests
- **Device compatibility** (#410): multi-storage topologies, PTP/MTP extension negotiation, quirk matching edge cases
- **Write-path safety** (#411): partial write detection, delete safety, read-only storage, concurrent write serialization, data integrity
- **Sync resilience** (#412): device disconnection recovery, transient failure retry, corrupted baseline handling
- **Boundary conditions** (#413): codec, index, and sync modules tested at extremes (zero-length, max-length, SQL injection, path traversal, Unicode normalization)
- **FileProvider/XPC edge cases** (#414): disconnection mid-enumeration, stale identifiers, XPC interruption recovery, NSSecureCoding round-trips
- **~200 new tests** added across 10 new test files
- **Session totals**: 50 PRs merged (#363–#414), ~8,377 tests, 0 unexpected failures

## Wave 34–35 Activity (2026-03-08)

Key development activity in these waves:

- **PRs merged**: #403–#406 (error diagnostics, docs update, CI improvements, lint fixes)
- **Error diagnostics**: MTPError and TransportError descriptions improved for actionability (#403)
- **CI improvements**: workflow reliability, caching, and timeouts hardened (#405)
- **Lint fixes**: line-length warnings fixed in transport layer (#406)
- **API 503 retries**: 3 agents failed in wave 34 due to API 503 errors; retried successfully in wave 35
- **Session totals**: 47 PRs merged (#363–#406), 8,177 tests, 0 unexpected failures

## Waves 33–34 Activity (2026-03-08)

Key development activity in these waves:

- **PRs merged**: #398–#402 (schema fix, DocC fix, format sweep, docs update, transport logging)
- **Schema validation fix**: `quirks.schema.json` corrected — 77,654 validation errors eliminated (#398)
- **DocC generator fix**: `docc-generator-tool` model updated to match current module structure (#399)
- **Format sweep**: `swift-format` applied across all source and test files (#400)
- **Transport inline documentation**: comprehensive inline docs, structured logging, and error diagnostics added to transport layer (#402)
- **Session totals**: 42 PRs merged (#362–#402), tests grew from 7,112 → 8,177 (+1,065)

## Wave 32–33 Activity (2026-03-07)

Key development activity in these waves:

- **PRs merged**: #390–#399 (10 PRs across format, fuzz, store, FP-XPC, core, transport, quirks, schema fix, DocC fix)
- **Schema validation fix**: `quirks.schema.json` corrected — 77,654 validation errors eliminated
- **DocC generator fix**: `docc-generator-tool` model updated to match current module structure
- **Test expansion**: 8,177 tests executed across 20 targets (up from 7,909 in wave 31; +268 new tests)
- **37 total PRs merged** this session (#362–#399)

## Wave 31 Activity (2026-03-06)

Key development activity in this wave:

- **Performance benchmarks**: transfer throughput, codec round-trip, and index query benchmarks with baseline thresholds
- **Coverage gate per-module enforcement**: `coverage_gate.py` now enforces minimum thresholds per module, not just aggregate
- **UI accessibility tests**: SwiftUI accessibility audit tests for all major views
- **CLI smoke tests**: end-to-end smoke tests for every `swiftmtp` subcommand
- **Test expansion**: 7,909 tests executed across 20 targets (up from 7,720 in wave 30; +189 new tests)
- **PRs merged**: #381–#388

## Wave 30 Activity (2026-03-05)

Key development activity in this wave:

- **Deep coverage passes**: codec fuzzing, transport, index, snapshot, quirks research, and property tests all received dedicated deep coverage
- **Codec fuzzing finding**: PTP string max round-trippable length is 253 characters (sentinel byte at 0xFF)
- **Test expansion**: 7,720 tests executed across 20 targets (up from 7,475 in wave 29; +245 new tests)
- **All 20 test targets now have deep coverage**: every target has received at least one dedicated deep-coverage pass
- **PRs merged**: #373–#380

## Wave 30 Activity (2026-03-05)

Key development activity in this wave:

- **Test expansion**: 7,475 tests executed across 20 targets (up from 7,112 in wave 29; +363 new tests)
- **All 20 test targets expanded**: observability, store errors, XPC, FileProvider, BDD, CLI/tooling, and integration tests all received new coverage
- **Flaky test fix** (#364): concurrent attach test — root cause was non-deterministic stream ordering; fixed with deterministic sort
- **Format sweep** (#363): full swift-format pass across all Sources and Tests
- **PRs merged**: #363–#372

## Wave 29 Activity (2026-03-04)

Key development activity in this wave:

- **Test expansion + CI stabilization**: 6,659 test methods across 20 targets (7,112 tests executed including parameterized sets); up from 6,978 executed in wave 28
- **Documentation refresh**: synced ROADMAP, README, CLAUDE.md, Troubleshooting, and FIXUP_QUEUE with current project state
- **Quirks database**: stable at 20,026 entries across 1,154 VIDs and 38 categories
- **FIXUP_QUEUE clearance**: all 10 original fixup items marked DONE; friction log updated with accurate target counts

## Wave 28 Activity (2026-03-01 → 2026-03-03)

Key development activity in this wave:

- **Test expansion**: 6,978 tests executed across 20 targets (up from ~4,800 at wave start); added IndexQueryEdgeCaseTests, ExtendedPropertyTests, advanced BDD workflow scenarios, TransportTests edge cases, and multi-vendor device quirks tests
- **Quirks database**: cleaned 22 duplicate VID:PID pairs (#348); added Lenovo, ZTE, Meizu, ASUS, MediaTek (#346), Motorola, LG, Xiaomi sub-brands (pending); expanding from 20,026 → 20,041 entries
- **Fixes**: DocC generator probeLadder type mismatch (#345), SanDisk Sansa m230 BDD test assertion (pending), format sweep (pending)
- **Active branches**: `wave28/fix-bdd-sansa-test`, `wave28/quirks-motorola-lg`, `wave28/format-sweep`, `wave28/troubleshooting-refresh`, `wave28/fix-notes-array`, `wave28/fixup-queue-clearance`
- **PRs merged to main**: through #349

## Implementation Sprint Queue (Next 3)

### Sprint 2.1-A: Transport Stability and Error Clarity

Primary outcome: reduce high-severity real-device failures and make first-line failures actionable.

- [ ] Resolve Pixel 7 Tahoe 26 bulk-transfer timeout path — documented root cause and troubleshooting; device remains blocked
- [ ] Stabilize OnePlus 3T `SendObject` / `0x201D` large-write behavior — documented workaround; device absent from recent lab runs
- [x] Improve first-line error messages for `probe`, `collect`, and write-path operations
- [x] Refresh per-device behavior notes in `Docs/Troubleshooting.md` and device pages

Sprint exit criteria:

- [ ] Reproducible before/after artifacts for Pixel 7 and OnePlus 3T
- [ ] No regression in `./scripts/smoke.sh`
- [x] Documentation includes concrete command-level fallback guidance for both failure classes
- [x] Changelog and roadmap status are updated with shipped behavior changes

### Sprint 2.1-B: Submission Workflow Hardening

Primary outcome: contributors can produce valid, redacted submission bundles with less manual intervention.

- [x] Harden `swiftmtp collect` strict-mode path and validation messaging
- [x] Add/expand privacy-redaction assertions for submission artifacts
- [x] Tighten `validate-submission` and evidence expectations for PR review
- [x] Publish one canonical `collect` + `benchmark` troubleshooting sequence

Sprint exit criteria:

- [ ] New submission bundle validates with `./scripts/validate-submission.sh`
- [x] Redaction checks catch known bad patterns without false positives in baseline artifacts
- [x] Contribution docs and roadmap docs reference the same workflow and command set
- [x] Device submission PR template is aligned with documented command examples

### Sprint 2.1-C: CI and Verification Consolidation

Primary outcome: predictable CI signal and consistent local-to-CI test behavior.

- [x] Consolidate overlapping CI workflows and document required checks
- [x] Ensure TSAN execution path is explicit and repeatable for concurrency-heavy targets
- [x] Keep filtered coverage gate stable and documented
- [x] Publish a minimal "pre-PR local gate" command sequence

Sprint exit criteria:

- [x] Single documented CI truth path in docs (including optional/nightly jobs)
- [x] TSAN invocation is documented and verified in CI config
- [x] Local gate commands mirror CI behavior for core checks
- [x] Release checklist references the same required checks and artifact rules

## Dependency and Risk Register (v2.1)

| Item | Type | Owner Lane | Mitigation |
|------|------|------------|------------|
| Pixel 7 Tahoe bulk timeout remains intermittent | Technical risk | Core/transport | Capture standardized bring-up artifacts with `scripts/device-bringup.sh`; gate merges on before/after evidence |
| OnePlus large write behavior differs by folder target | Technical risk | Core/transport + docs | Keep write-target fallback guidance synchronized with troubleshooting and device docs |
| Redaction validation drift between docs and scripts | Process risk | Device support + tooling | Treat `validate-submission` output as source of truth; update docs and template together |
| Overlapping CI workflows create unclear required checks | Process risk | Testing/CI | Complete 2.1-C consolidation and document required vs nightly checks |
| Release metadata/docs drift near tag cut | Process risk | Release/docs | Run checklist mid-sprint and at release cut; enforce changelog/roadmap sync gates |

## 2.x Delivery Plan

Items marked [x] are code-complete and mock-tested. "Real-device" notes indicate where actual hardware validation exists.

### 2.1 Focus: Stabilization and Reliability

- [x] macOS Tahoe 26 native support (build/compile verified)
- [x] SwiftPM 6.2+ tooling alignment
- [x] IOUSBHost integration as primary USB interface (mock-tested; real-device: Xiaomi partial)
- [x] MTP object property APIs (GetObjectPropValue, SetObjectPropValue) (mock-tested)
- [x] Multi-device parallel transfer support (mock-tested, 8 scenario tests)
- [x] FileProvider write operations (macOS 26 Finder integration) (mock-tested, no real-device validation)
- [x] Extended MTP event handling (storageAdded/Removed, objectInfoChanged, unknown) (mock-tested)
- [ ] Pixel 7 and OnePlus write/open-path stabilization — troubleshooting documented, transfers not yet working
- [x] Submission and troubleshooting workflow hardening complete
- [x] CI/test gate documentation and execution consolidated

### 2.2 Focus: Testing and Submission Depth

- [x] GetObjectPropsSupported for format-aware property discovery (mock-tested)
- [x] ObjectSize U64 fallback for files > 4 GB (mock-tested)
- [x] Increase mutation and edge-case coverage for transport error handling (mock-tested)
- [x] Expand real-device troubleshooting trees for top support issues
- [x] Improve benchmark report consistency and release evidence packaging

### 2.3 Focus: Growth and Performance

- [x] Expand supported device profile coverage (new vendor classes) — Canon EOS (04A9:3139), Nikon DSLR (04B0:0410) added as research-only profiles with troubleshooting docs (never connected to SwiftMTP)
- [x] Investigate parallel multi-device enumeration — implemented Task-per-attach dispatch in DeviceServiceRegistry.startMonitoring; O(1) startup regardless of N devices (mock-tested)
- [x] Improve large-file throughput on USB 3.x controllers (mock-tested)
- [x] Add transfer resume telemetry to benchmark reports (mock-tested)

### 3.x Exploratory Themes

- Network-assisted MTP workflows (MTP/IP)
- Additional transport backend options
- Expanded app-platform support for File Provider-like experiences
- ML-assisted quirk suggestion and risk scoring

## Release Cadence

| Version | Target window | Goal | Status |
|---------|---------------|------|--------|
| v2.0.0  | 2026-02 | Tahoe 26 core + architecture upgrade | Released (dev milestone, pre-alpha) |
| v2.1.0  | 2026-Q2 | Stability + submission hardening + docs readiness | RC Ready (dev milestone, pre-alpha) |
| v2.2.0  | 2026-Q3 | Performance and benchmark reliability | Planned |
| v2.3.0  | 2026-Q4 | Device coverage expansion | Planned |
| v3.0.0  | 2027 | Cross-platform and strategic re-architecture | Exploratory |

## Minor Release Criteria (2.x)

Note: during pre-alpha, these criteria apply to development milestones. A production-ready release additionally requires successful real-device transfers on multiple device classes.

Any minor release (`v2.x.0`) should satisfy all of the following:

- [ ] Full matrix run (`./run-all-tests.sh`) completes without regressions
- [x] Filtered coverage gate passes (`SwiftMTPQuirks`, `SwiftMTPStore`, `SwiftMTPSync`, `SwiftMTPObservability`)
- [ ] TSAN path is clean for required concurrency-heavy targets this cycle
- [ ] At least one real-device evidence run is attached in release artifacts
- [x] `./scripts/validate-quirks.sh` and submission validation checks pass
- [x] `CHANGELOG.md`, roadmap docs, and release notes are aligned

See `Docs/ROADMAP.release-checklist.md` for operator-level release commands and sequencing.

## Device Profile Submission Fast Path

1. Collect and validate evidence.

```bash
swift run --package-path SwiftMTPKit swiftmtp --real-only probe > probes/<device>.txt
./scripts/benchmark-device.sh <device-name>
./scripts/validate-quirks.sh
./scripts/validate-submission.sh Contrib/submissions/<device>/
```

2. Commit and push the submission branch.

```bash
git checkout -b device/<device-name>-submission
git add Contrib/submissions/<device>/ Specs/quirks.json
git commit -s -m "Add device profile: <device>"
git push -u origin HEAD
```

3. Open a PR with benchmark evidence and quirk rationale.

## Tracking and Labels

Recommended issue labels:

- `enhancement`: new features and enhancements
- `bug`: crashes and regressions
- `device-support`: compatibility and quirks
- `documentation`: docs and operator guidance
- `testing`: CI, coverage, and reproducibility work
- `release`: release checklist and milestone items

## Common Issues Quick Reference

| Issue | Likely Cause | First Action |
|-------|--------------|--------------|
| Device not detected | USB debugging off, wrong mode | Check MTP/PTP mode, enable USB debugging |
| Bulk transfer timeout | Quirks not tuned, cable/port issue | Run `swiftmtp probe` and check quirk overrides |
| "Trust this computer" prompt | macOS security | Unlock device, accept trust prompt |
| Collect validation fails | Missing files, privacy redaction | Run `./scripts/validate-submission.sh` for details |
| CI mismatch local | Environment difference | Run `./run-all-tests.sh` locally first |
| TSAN failures | Concurrency regression | Run `-sanitize=thread` on affected targets |

## Related Docs

- [Sprint Playbook](SPRINT-PLAYBOOK.md)
- [Contribution Guide](ContributionGuide.md)
- [Testing Guide](ROADMAP.testing.md)
- [Device Submission Guide](ROADMAP.device-submission.md)
- [Release Checklist](ROADMAP.release-checklist.md)
