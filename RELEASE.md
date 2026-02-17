# SwiftMTP Release Runbook (2.x)

*Last updated: 2026-02-16*

This runbook describes how to prepare and ship SwiftMTP releases in the current 2.x train.

## Scope

- Applies to `v2.x.y` patch releases and `v2.x.0` minor releases.
- Assumes release artifacts are produced by GitHub Actions (`.github/workflows/release.yml`).

## Pre-Release Readiness

Before cutting a tag, complete `Docs/ROADMAP.release-checklist.md`.
Confirm sprint completion/carry-over state in `Docs/SPRINT-PLAYBOOK.md` and `Docs/ROADMAP.md`.

Minimum readiness gates:

- Local full gate passes: `./run-all-tests.sh`
- Smoke gate passes: `./scripts/smoke.sh`
- Quirk and submission validators pass for touched evidence paths
- Changelog and roadmap docs are up to date
- Required CI workflows are green for the release commit (`ci`, `Smoke`, `validate-quirks`, `validate-submission`)

## Version Preparation

1. Decide release type (patch/minor).
2. Update release metadata and any version surfaces used by tooling.
3. Update `CHANGELOG.md` with final release heading and date.
4. Ensure roadmap + sprint playbook reflect closed items and carry-over items.
5. Create a release prep commit.

Example:

```bash
git add CHANGELOG.md Docs/ROADMAP.md Docs/SPRINT-PLAYBOOK.md Docs/ROADMAP.release-checklist.md
# Add any version/build metadata files you changed
git commit -m "chore: prepare v2.1.0"
```

## Tag and Trigger Release Pipeline

Create and push an annotated tag:

```bash
git tag -a v2.1.0 -m "Release v2.1.0"
git push origin v2.1.0
```

This triggers `.github/workflows/release.yml`, which builds and validates:

- macOS artifact (`swiftmtp-macos-arm64.tar.gz` + checksum)
- Linux artifact (`swiftmtp-linux-x86_64-<tag>.tar.gz` + checksum)
- SPDX SBOM artifact
- Draft GitHub release with artifacts attached

## Release Artifact Validation

Validate artifacts before publishing the draft release:

- Tarballs contain the expected `swiftmtp` binary
- Checksums verify successfully
- SBOM is present and readable
- Release notes match `CHANGELOG.md`

Optional local package sanity check:

```bash
swift build -c release --package-path SwiftMTPKit --product swiftmtp
BIN="$(swift build -c release --package-path SwiftMTPKit --product swiftmtp --show-bin-path)/swiftmtp"
"$BIN" version --json
```

## Publish

1. Open the draft release in GitHub.
2. Verify title/body/tag consistency.
3. Publish the release.
4. Announce in project channels.

## Post-Release

- Open the next milestone/sprint issue set.
- Move unfinished items from `Unreleased` to next sprint backlog.
- Reset `Unreleased` headings for next cycle and refresh roadmap sprint queue.
- Backport urgent documentation fixes if needed.

## Hotfix Flow

For urgent patches after release:

1. Branch from the release tag.
2. Apply minimal fix + tests.
3. Update changelog for `v2.x.(y+1)`.
4. Tag and publish patch release through same pipeline.

## Historical Notes

Legacy 1.0/1.1 checklist content was replaced by this 2.x runbook. See git history for archival release procedures.
