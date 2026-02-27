# SwiftMTP Contribution Guide

*Last updated: 2026-02-16*

This guide covers how to contribute during the active implementation sprints, including code changes, device evidence, and documentation updates.

## Legal Requirements

All contributions to SwiftMTP require a signed Contributor License Agreement (CLA).

- **Individuals:** Sign the [Individual CLA](../legal/inbound/CLA-INDIVIDUAL.md) before your first PR.
- **Entities:** Have an authorized signatory complete the [Entity CLA](../legal/inbound/CLA-ENTITY.md).

All commits must also include a [Developer Certificate of Origin](../legal/inbound/DCO.txt) sign-off. Use `git commit -s` to add the `Signed-off-by` trailer automatically.

PRs without a signed CLA and DCO sign-off cannot be merged.

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

Minimal pre-PR gate (must pass before every PR):

```bash
# Format (CI requires)
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# Build + targeted tests
swift build --package-path SwiftMTPKit
swift test --package-path SwiftMTPKit --filter <RelevantSuite>

# Quirks validation (required if quirks.json changed)
./scripts/validate-quirks.sh
```

For milestone merges and release prep:

```bash
./run-all-tests.sh
```

If concurrency-related code changes:

```bash
swift test --package-path SwiftMTPKit -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests
```

See `Docs/Troubleshooting.md#pre-pr-local-gate` for the full canonical sequence.

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

## CI Workflows

| Workflow | Trigger | Required for merge | What it checks |
|----------|---------|-------------------|----------------|
| `ci.yml` | All branches/PRs | ✅ Yes | Build, full test suite, coverage gate, TSAN, fuzz harness, SBOM (tags) |
| `swiftmtp-ci.yml` | main merges | No (supplemental) | Deeper coverage reporting, docs build, CLI smoke |
| `smoke.yml` | Schedule + PRs | No (advisory) | Real-device smoke check |
| `validate-quirks.yml` | PRs touching quirks | ✅ Yes (if quirks changed) | JSON schema + required fields |
| `validate-submission.yml` | Device submission PRs | ✅ Yes | Bundle completeness + redaction |
| `release.yml` | Tags | Release gate | Changelog, artifacts, SBOM |
| `nightly-real-device-ux-smoke.yml` | Nightly | No (advisory) | End-to-end with physical device |

**The only required check for merging a PR is `ci.yml`.** All other workflows are supplemental or advisory. Device submission PRs also require `validate-submission.yml`.

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

## Contributing Device Data

The easiest way to add support for a new device is via the `add-device` command:

```bash
swiftmtp add-device --vid 0x1234 --pid 0x5678 --name "My Device" --class android
```

This generates a ready-to-use quirk entry template. Copy the output into
`Specs/quirks.json` and `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`,
validate with `./scripts/validate-quirks.sh`, then open a PR.

See [Device Submission Guide](DeviceSubmission.md) for full instructions, device
class descriptions, and authoritative VID/PID sources.

## Related Docs

- [Roadmap](ROADMAP.md)
- [Sprint Playbook](SPRINT-PLAYBOOK.md)
- [Testing Guide](ROADMAP.testing.md)
- [Device Submission Guide](DeviceSubmission.md)
- [Release Checklist](ROADMAP.release-checklist.md)
- [Troubleshooting](Troubleshooting.md)
