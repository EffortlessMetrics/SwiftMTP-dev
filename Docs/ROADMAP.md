# SwiftMTP Roadmap

*Last updated: 2026-02-25*

*Last updated: 2026-02-16*

This roadmap is the execution plan for the next implementation sprints in the 2.x release train.

## Current Operating Goal

Ship `v2.1.0` with improved real-device stability, better operator troubleshooting paths, and submission pipeline hardening, while keeping release gates green.

## Recently Shipped (PR #8 — feat/device-robustness-and-docs-overhaul)

- [x] **GetObjectPropValue / SetObjectPropValue** — `MTPLink` protocol property APIs with default implementations
- [x] **MTPObjectPropCode enum** — all standard MTP object property codes (0xDC01–0xDC48)
- [x] **MTPDateString** — encode/decode MTP ISO 8601 compact date format
- [x] **MTPObjectInfo.modified** — populated from GetObjectInfo ModificationDate field
- [x] **ObjectSize U64 fallback** — GetObjectPropValue(0xDC04) for files > 4 GB
- [x] **GetObjectPropsSupported (0x9801)** — list device-supported properties per format
- [x] **Extended MTPEvent** — storageAdded, storageRemoved, objectInfoChanged, deviceInfoChanged, unknown(code:params:)
- [x] **FileProvider write operations** — createItem, modifyItem, deleteItem with XPC bridge
- [x] **Multi-device parallel transfers** — 8 scenario tests, DeviceServiceRegistry routing
- [x] **FallbackAllFailedError** — carries full attempt history (name, duration, error per rung)
- [x] **Automatic documentation** — `swiftmtp-docs` SPM executable target for hands-off DocC generation
- [x] **1849 tests, 0 failures** (up from 1799 with preexisting failures)

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
| 2.1-A | Transport stability + error clarity | In progress | Real-device timeout reproduction drift | `./scripts/smoke.sh` + targeted device artifacts |
| 2.1-B | Submission workflow hardening | Planned | Privacy/redaction false positives or misses | `./scripts/validate-submission.sh` |
| 2.1-C | CI + verification consolidation | Planned | Ambiguous required checks across workflows | CI workflow mapping + TSAN parity |

## Implementation Sprint Queue (Next 3)

### Sprint 2.1-A: Transport Stability and Error Clarity

Primary outcome: reduce high-severity real-device failures and make first-line failures actionable.

- [x] Resolve Pixel 7 Tahoe 26 bulk-transfer timeout path (control-plane succeeds, bulk path times out)
- [x] Stabilize OnePlus 3T `SendObject` / `0x201D` large-write behavior
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

### 2.1 Focus: Stabilization and Reliability

- [x] macOS Tahoe 26 native support
- [x] SwiftPM 6.2+ tooling alignment
- [x] IOUSBHost integration as primary USB interface
- [x] MTP object property APIs (GetObjectPropValue, SetObjectPropValue)
- [x] Multi-device parallel transfer support
- [x] FileProvider write operations (macOS 26 Finder integration)
- [x] Extended MTP event handling (storageAdded/Removed, objectInfoChanged, unknown)
- [x] Pixel 7 and OnePlus write/open-path stabilization complete
- [x] Submission and troubleshooting workflow hardening complete
- [x] CI/test gate documentation and execution consolidated

### 2.2 Focus: Testing and Submission Depth

- [x] GetObjectPropsSupported for format-aware property discovery
- [x] ObjectSize U64 fallback for files > 4 GB
- [x] Increase mutation and edge-case coverage for transport error handling
- [x] Expand real-device troubleshooting trees for top support issues
- [ ] Improve benchmark report consistency and release evidence packaging

### 2.3 Focus: Growth and Performance

- [x] Expand supported device profile coverage (new vendor classes) — Canon EOS (04A9:3139), Nikon DSLR (04B0:0410) added as experimental profiles with full troubleshooting docs
- [x] Investigate parallel multi-device enumeration — implemented Task-per-attach dispatch in DeviceServiceRegistry.startMonitoring; O(1) startup regardless of N devices
- [ ] Improve large-file throughput on USB 3.x controllers
- [x] Add transfer resume telemetry to benchmark reports

### 3.x Exploratory Themes

- Network-assisted MTP workflows (MTP/IP)
- Additional transport backend options
- Expanded app-platform support for File Provider-like experiences
- ML-assisted quirk suggestion and risk scoring

## Release Cadence

| Version | Target window | Goal | Status |
|---------|---------------|------|--------|
| v2.0.0  | 2026-02 | Tahoe 26 core + architecture upgrade | Released |
| v2.1.0  | 2026-Q2 | Stability + submission hardening + docs readiness | In Progress |
| v2.2.0  | 2026-Q3 | Performance and benchmark reliability | Planned |
| v2.3.0  | 2026-Q4 | Device coverage expansion | Planned |
| v3.0.0  | 2027 | Cross-platform and strategic re-architecture | Exploratory |

## Minor Release Criteria (2.x)

Any minor release (`v2.x.0`) should satisfy all of the following:

- [ ] Full matrix run (`./run-all-tests.sh`) completes without regressions
- [ ] Filtered coverage gate passes (`SwiftMTPQuirks`, `SwiftMTPStore`, `SwiftMTPSync`, `SwiftMTPObservability`)
- [ ] TSAN path is clean for required concurrency-heavy targets this cycle
- [ ] At least one real-device evidence run is attached in release artifacts
- [ ] `./scripts/validate-quirks.sh` and submission validation checks pass
- [ ] `CHANGELOG.md`, roadmap docs, and release notes are aligned

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
