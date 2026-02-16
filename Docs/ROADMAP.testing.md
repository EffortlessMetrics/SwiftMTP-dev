# SwiftMTP Testing Guide

*Last updated: 2026-02-16*

This document defines the test gates used for day-to-day development and for sprint/release readiness.

## Test Gate Baseline

SwiftMTP uses a layered gate model:

1. Local quick confidence (`swift build`, targeted test filters)
2. Full local matrix (`./run-all-tests.sh`)
3. CI matrix (build, test, smoke, fuzz, TSAN path)
4. Real-device validation (manual/bring-up artifacts)

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

## Local Command Matrix

Run from repository root unless noted.

```bash
# Build package
swift build --package-path SwiftMTPKit

# Full package tests + coverage artifacts + smoke slices
./SwiftMTPKit/run-all-tests.sh

# Full repo gates (package + Xcode)
./run-all-tests.sh

# Focused suites
swift test --package-path SwiftMTPKit --filter BDDTests
swift test --package-path SwiftMTPKit --filter PropertyTests
swift test --package-path SwiftMTPKit --filter SnapshotTests
swift test --package-path SwiftMTPKit --filter ScenarioTests
swift test --package-path SwiftMTPKit --filter IntegrationTests

# TSAN focused pass
swift test --package-path SwiftMTPKit -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# Non-hardware smoke flow
./scripts/smoke.sh
```

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

## CI Reality (Current)

The repository currently contains multiple CI workflow definitions. For sprint execution, treat these as the required surfaces to keep healthy:

- `.github/workflows/ci.yml`: build/test, TSAN slice, fuzz quick check, optional tag-time SBOM
- `.github/workflows/smoke.yml`: no-hardware smoke validation and learned-store hygiene check
- `.github/workflows/release.yml`: tag-driven artifact packaging/release draft flow
- `.github/workflows/validate-quirks.yml`: quirks/evidence validator on quirks-related PRs
- `.github/workflows/validate-submission.yml`: submission bundle validation and privacy checks

`swiftmtp-ci.yml` exists as an expanded matrix variant; sprint 2.1-C includes CI consolidation so docs and required checks stay unambiguous.

Required-for-merge workflow surfaces:

- `ci.yml`
- `smoke.yml`
- `validate-quirks.yml` (when quirks/evidence paths change)
- `validate-submission.yml` (when submission bundles or validation paths change)

Optional/nightly surfaces:

- `swiftmtp-ci.yml` schedule jobs and expanded matrix slices

## Real-Device Validation

Use this sequence when a sprint item touches transport behavior, quirks, or submission flow.

```bash
# Probe and baseline
swift run --package-path SwiftMTPKit swiftmtp --real-only probe

# Connected device matrix report
swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json

# Bring-up capture for a concrete mode
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1

# Collect strict submission bundle
swift run --package-path SwiftMTPKit swiftmtp collect --strict --noninteractive --json
```

See `Docs/device-bringup.md` and `Docs/Troubleshooting.md` for mode-level failure taxonomy and recovery guidance.

## Test Requirements for New Changes

For code merged into active sprint work:

- Add or update tests in the most specific suite possible (unit/integration/scenario/property).
- Cover both success path and at least one failure path.
- For concurrency-affecting changes, run TSAN-focused suite locally before opening PR.
- For quirks/transport changes, attach at least one real-device artifact path or state why mock-only validation is sufficient.

## Sprint Test Focus (v2.1.0)

### Sprint 2.1-A

- Transport write/open regressions (Pixel 7 + OnePlus 3T)
- Error clarity assertions for user-visible failures

### Sprint 2.1-B

- `collect` strict-mode reliability
- Submission validator redaction checks

### Sprint 2.1-C

- CI workflow consistency and required check stability
- Local-to-CI command parity documentation

## Pre-PR Checklist

- [ ] `swift build --package-path SwiftMTPKit`
- [ ] Targeted tests for touched area
- [ ] TSAN-focused pass (if concurrency touched)
- [ ] `./scripts/smoke.sh` for CLI/JSON contract changes
- [ ] `./run-all-tests.sh` for sprint milestone merges
- [ ] Docs/changelog updated when behavior or operator flow changed

## Suggested PR Evidence Snippet

Include a short command/result block in the PR body:

```text
Commands:
- swift build --package-path SwiftMTPKit
- swift test --package-path SwiftMTPKit --filter CoreTests
- ./scripts/smoke.sh

Result:
- Pass (macOS 15.3, Xcode 16)
Artifacts:
- Docs/benchmarks/device-bringup/20260216-101530-mtp-unlocked/
```

## Related Docs

- [Roadmap](ROADMAP.md)
- [Sprint Playbook](SPRINT-PLAYBOOK.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Device Submission Guide](ROADMAP.device-submission.md)
- [Troubleshooting](Troubleshooting.md)
