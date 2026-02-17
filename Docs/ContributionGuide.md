# SwiftMTP Contribution Guide

*Last updated: 2026-02-16*

This guide covers how to contribute during the active implementation sprints, including code changes, device evidence, and documentation updates.

## Contribution Lanes

Choose the lane that matches your work:

- **Core/transport code:** behavior fixes, stability, performance
- **Device support:** submission bundles and quirk updates
- **Testing/CI:** test coverage, TSAN, workflow reliability
- **Docs/runbooks:** roadmap, troubleshooting, release process

## Sprint Workflow (Recommended)

1. Pick an item from `Docs/ROADMAP.md`.
2. Confirm DoR in `Docs/SPRINT-PLAYBOOK.md`.
3. Open a focused branch from current mainline.
4. Implement and test with targeted commands.
5. Run sprint checkpoint gates (below).
6. Open PR with evidence links and a short risk note.

### Sprint Checkpoint Gates

```bash
swift build --package-path SwiftMTPKit
./scripts/smoke.sh
swift test --package-path SwiftMTPKit --filter <RelevantSuite>
```

For milestone merges and release prep:

```bash
./run-all-tests.sh
```

If concurrency-related code changes:

```bash
swift test --package-path SwiftMTPKit -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests
```

## Branch and PR Naming

Use sprint-prefixed names for active roadmap work.

- Branch: `feat/2.1-A-<short-topic>` or `fix/2.1-B-<short-topic>`
- PR title: `[2.1-A] <behavior change summary>`
- If work is not tied to sprint scope, use `[infra]` or `[docs]` prefixes

## PR Expectations

Each PR should include:

- Summary of behavior change
- Test evidence (commands run + result)
- Any real-device artifacts (if transport/quirk behavior changed)
- Docs updates for operator-facing behavior changes
- Changelog update under `Unreleased` when behavior is user-visible
- Roadmap checkbox/risk-table update when a sprint item closes or changes scope

For quirks/submission PRs, also include:

- `Specs/quirks.json` diff rationale
- Bundle validation output
- Privacy/redaction confirmation

## Device Contribution Quick Start

### 1) Prepare device

- USB connected, unlocked, File Transfer (MTP) mode enabled
- Prefer direct USB port over hub

### 2) Collect bundle

```bash
swift run --package-path SwiftMTPKit swiftmtp collect \
  --device-name "Your Device Name" \
  --noninteractive --strict --run-bench 100M,1G --json
```

### 3) Validate bundle

```bash
./scripts/validate-submission.sh Contrib/submissions/<bundle-dir>
./scripts/validate-quirks.sh
```

### 4) Submit

```bash
git checkout -b device/<device-name>
git add Contrib/submissions/<bundle-dir> Specs/quirks.json
git commit -s -m "Device submission: <device-name>"
git push -u origin HEAD
```

## Device Submission Privacy Checklist

- [ ] No personal paths, hostnames, or emails in artifacts
- [ ] No raw serials in committed files
- [ ] `.salt` is not committed
- [ ] Bundle validated locally with `validate-submission.sh`

## Troubleshooting During Contribution

- Device not found: `swift run --package-path SwiftMTPKit swiftmtp --real-only probe`
- Collect flow issues: rerun with `--strict --json` and inspect stderr
- CI mismatch: run `./scripts/smoke.sh` then `./run-all-tests.sh`
- Quirk schema issues: run `./scripts/validate-quirks.sh`

For mode-specific bring-up evidence:

```bash
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1
```

## Suggested Commit Scope

Keep PRs single-purpose when possible:

- one bug fix + its tests
- one quirk update + evidence
- one docs/runbook update set

This keeps review and rollback manageable in sprint cadence.

## Recognition

Contributors are recognized through:

- `Specs/quirks.json` provenance entries
- `CHANGELOG.md` for notable contributions
- GitHub release notes and PR history

## Related Docs

- [Roadmap](ROADMAP.md)
- [Sprint Playbook](SPRINT-PLAYBOOK.md)
- [Testing Guide](ROADMAP.testing.md)
- [Device Submission Guide](ROADMAP.device-submission.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Troubleshooting](Troubleshooting.md)
