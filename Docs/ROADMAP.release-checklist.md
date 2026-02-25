# SwiftMTP Release Checklist

*Last updated: 2026-02-16*

This checklist is the operational companion to `Docs/ROADMAP.md` and is intended to be used throughout each sprint, not only at tag time.

## How to Use This Checklist

- Use **Sprint Checkpoints** during implementation (weekly or at sprint end).
- Use **Release Cut Gates** when preparing `v2.x.0`/`v2.x.y` tags.
- Use **Post-Release** after artifacts and notes are published.
- Use `Docs/SPRINT-PLAYBOOK.md` for DoR/DoD and carry-over rules.

## Sprint Checkpoints

Complete these continuously during the sprint to reduce release-day risk.

### Code Health

- [ ] New behavior includes tests for success and failure paths
- [ ] No unresolved release-blocking TODO/FIXME in touched modules
- [ ] User-visible errors include actionable first-line guidance
- [ ] Sprint items marked complete satisfy DoD from `Docs/SPRINT-PLAYBOOK.md`

### Test and CI Health

- [ ] `swift build --package-path SwiftMTPKit` succeeds locally
- [ ] Relevant targeted test filters run for touched modules
- [ ] TSAN-focused run completed for concurrency-affecting changes
- [ ] `./scripts/smoke.sh` still passes for CLI contract changes
- [ ] Required workflow surfaces remain green (`ci`, `Smoke`, `validate-quirks`, `validate-submission`)

### Docs and Operator Guidance

- [ ] `README.md` and troubleshooting docs reflect changed behavior
- [ ] Roadmap status in `Docs/ROADMAP.md` is updated for closed/open sprint items
- [ ] Device-specific notes updated when quirk behavior changes
- [ ] `CHANGELOG.md` `Unreleased` section reflects merged sprint outcomes

## Release Cut Gates

Run these before creating a release tag.

### 1) Verification Gates

- [ ] `./run-all-tests.sh` passes
- [ ] Filtered coverage gate passes
- [ ] Required TSAN checks are green in CI
- [ ] `./scripts/validate-quirks.sh` passes
- [ ] `./scripts/validate-submission.sh` passes for any included/new submission bundles
- [ ] Required GitHub workflow runs are present for release commit

### 2) Packaging and Distribution Gates

- [ ] `./scripts/build-libusb-xcframework.sh` succeeds on supported hosts
- [ ] `swift build -c release --package-path SwiftMTPKit --product swiftmtp` succeeds
- [ ] Release artifact packaging validated (`.tar.gz` contents and checksums)
- [ ] Homebrew formula updates prepared if the release changes install behavior

### 3) Documentation and Metadata Gates

- [ ] `CHANGELOG.md` includes all notable changes and release date
- [ ] `README.md` and roadmap docs match shipped behavior
- [ ] DocC/device pages are refreshed for changed quirks or behaviors
- [ ] `RELEASE.md` sequence is followed and still accurate
- [ ] `Docs/SPRINT-PLAYBOOK.md` and roadmap sprint state agree on closed/carry-over items

### 4) Version and Tagging Gates

- [ ] Version files reviewed/updated:
  - `SwiftMTPKit/Sources/Tools/swiftmtp-cli/Autogen/BuildInfo.swift`
  - `RELEASE.md` metadata references
  - Any package metadata updated for release train consistency
- [ ] Release commit created with clear message (for example `chore: prepare v2.1.0`)
- [ ] Annotated tag created and pushed (for example `v2.1.0`)

## Suggested Validation Commands

```bash
# From repo root:
cd SwiftMTPKit

# Build
swift build

# Full test suite with coverage
swift test --enable-code-coverage

# TSAN (required for concurrency changes)
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# Coverage gate (enforced by CI; must pass for all four modules)
python3 scripts/coverage_gate.py .build/debug/codecov/

# Format + lint (required before every PR)
swift-format -i -r Sources Tests
swift-format lint -r Sources Tests

# Quirks validation
cd .. && ./scripts/validate-quirks.sh

# Full matrix (release prep)
cd .. && ./run-all-tests.sh
```

## Minimal Release Artifact Checklist

- [ ] Tagged commit in git
- [ ] Checksums generated and verified
- [ ] Release notes drafted (GitHub + changelog)
- [ ] Install path validated (`swift run` or packaged binary)
- [ ] `CHANGELOG.md` compare links updated

## Post-Release

- [ ] Publish/verify GitHub release draft
- [ ] Upload artifacts (macOS/Linux as applicable)
- [ ] Confirm follow-up milestone and open carry-over issues
- [ ] Backport urgent doc fixes if needed
- [ ] Reset `Unreleased` and update roadmap sprint queue for the next cycle

## Related Docs

- [Roadmap](ROADMAP.md)
- [Sprint Playbook](SPRINT-PLAYBOOK.md)
- [Testing Guide](ROADMAP.testing.md)
- [Device Submission Guide](ROADMAP.device-submission.md)
- [Release Runbook](../RELEASE.md)
