# SwiftMTP Friction Log

Ongoing record of issues, paper cuts, and improvement opportunities encountered during development, testing, and device onboarding. Items here should be triaged into GitHub issues or addressed directly when capacity allows.

---

## Legend

| Severity | Meaning |
|----------|---------|
| 🔴 P0 | Blocks users or CI — fix immediately |
| 🟠 P1 | Significant friction — fix soon |
| 🟡 P2 | Annoying but workable — fix when convenient |
| 🟢 P3 | Nice-to-have improvement |

---

## Worktree / Parallel Development

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🟡 P2 | `/tmp` directory not always writable from tool sessions — worktrees had to be created in `~/worktrees/` instead. Inconsistent filesystem permissions. | Workaround: use `~/worktrees/` |
| 2026-02-27 | 🟡 P2 | Merging quirks.json from multiple worktrees requires custom Python dedup script every time. No reusable merge tool. | **TODO**: create `scripts/merge-quirks.py` as a proper CLI tool |
| 2026-02-27 | 🟢 P3 | Worktree cleanup (removing branches + worktree dirs) is manual and error-prone. Could accumulate stale worktrees. | **TODO**: add `scripts/cleanup-worktrees.sh` helper |

## CI / Build

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🔴 P0 | CI workflows pinned to `xcode-version: "16"` but Package.swift requires Swift 6.2 (`swift-tools-version: 6.2`). All build/test/TSAN jobs fail. | ✅ Fixed — updated to `xcode-version: "latest"` |
| 2026-02-27 | 🟠 P1 | `validate-quirks.sh` fails because `Docs/benchmarks/probes/oneplus3t-probe.txt` is referenced in quirk entry but file never existed. Artifact references aren't validated at entry-creation time. | ✅ Fixed — created probe file. **TODO**: add pre-commit hook or entry-creation tooling that validates artifact references exist. |
| 2026-02-27 | 🟡 P2 | `validate-submission.yml` workflow lacks `permissions:` block, causing 403 on PR comment posting. Workflow silently looks broken to contributors. | ✅ Fixed — added permissions block. |
| 2026-02-27 | 🟡 P2 | `smoke.yml` still targeted `macos-14` runner, which may not have latest SDK. | ✅ Fixed — updated to `macos-15`. |
| 2026-02-27 | 🟡 P2 | SPDX license header check fails for new files — easy to forget when adding Swift files manually. | ✅ Fixed one file. **TODO**: add Xcode file template or pre-commit hook that auto-inserts SPDX header. |
| 2026-02-27 | 🟠 P1 | `Docs/benchmarks/probes/` is gitignored but quirk entries reference artifacts in it. `git add -f` required. Fragile. | ✅ Fixed probe files. **TODO**: un-gitignore `Docs/benchmarks/probes/` or add a CI check that artifact refs map to tracked files. |
| 2026-02-27 | 🟠 P1 | `scripts/check-changelog.sh` fails on shallow clones (CI) because `git describe --tags` can't find tags. | ✅ Fixed — added fallback to accept `[Unreleased]` section. |
| 2026-02-27 | 🟢 P3 | `generate-compat-matrix.sh` output drifts from committed `Docs/compat-matrix.md` after every quirks addition. No automation to keep them in sync. | **TODO**: add a `post-commit` or CI step that auto-regenerates and commits, or make the CI check advisory-only. |
| 2026-02-27 | 🔴 P0 | `Package.swift` set `platforms: [.macOS(.v26), .iOS(.v26)]` but CI runners are macOS 15. Binaries built for macOS 26 cannot execute on macOS 15 — `Library not loaded: libswift_DarwinFoundation2.dylib`. | ✅ Fixed — lowered to `.macOS(.v15), .iOS(.v18)`. No macOS-26-only APIs were in use. |

| 2026-02-27 | 🔴 P0 | CI docs workflow requires compat matrix regen after every device merge — need auto-regen in CI. Matrix drifts silently otherwise. | **TODO**: add `generate-compat-matrix.sh` step to CI docs workflow, or a post-merge hook. |
| 2026-02-27 | 🟠 P1 | Agents frequently create quirks.json conflicts when working in parallel worktrees — need automated dedup CI step to catch and resolve duplicates. | **TODO**: add `scripts/dedup-quirks.py` as a CI pre-merge check. |
| 2026-02-27 | 🟠 P1 | `validate-quirks.sh` reports 8000+ schema errors due to missing tuning fields on bulk-imported entries — either relax schema to allow optional tuning or add sensible defaults during import. | **TODO**: decide on schema strictness policy; add defaults in import tooling or make tuning fields optional in `quirks.schema.json`. |

## Device Onboarding

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🟠 P1 | No tooling to validate a single new quirk entry *before* adding to the full database. Contributors must manually construct JSON and hope it passes `validate-quirks.sh`. | **TODO**: `swiftmtp validate-entry < entry.json` CLI command. |
| 2026-02-27 | 🟠 P1 | Researching USB VID:PID values for new devices requires manual web lookups. No automated cross-reference against usb-ids databases. | **TODO**: `swiftmtp lookup-vid 0x28de` command that queries embedded USB-IF database. |
| 2026-02-27 | 🟡 P2 | Two quirk JSON schemas coexist (old format: top-level status/evidence; new format: governance block). Makes tooling and validation more complex. | **TODO**: migrate all entries to governance-block format in a dedicated PR. |
| 2026-02-27 | 🟡 P2 | `QuirkFlags` Swift struct does not surface `useAndroidExtensions` flag. Property tests can't verify it's set correctly. | **TODO**: add `useAndroidExtensions` to `QuirkFlags` or create a parallel `QuirkOpsFlags` struct. |
| 2026-02-27 | 🟡 P2 | Many wave-8+ entries use estimated/sequential PIDs rather than verified values. No way to distinguish "known good PID" from "placeholder PID". | **TODO**: add `pidSource: "verified" | "estimated"` field to provenance block. |
| 2026-02-27 | 🟢 P3 | Device submission workflow (`validate-submission.yml`) could auto-extract VID:PID from `swiftmtp probe` output and pre-populate a quirk entry template. | Backlog |

## Testing

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🟡 P2 | BDD tests require manually passing `ifaceClass:` parameter to `db.match()`. Easy to forget `0xff` vs `0x06` and get false negatives. | **TODO**: make BDD step definitions auto-detect iface class from entry data. |
| 2026-02-27 | 🟡 P2 | Property test baselines (currently 1900) must be manually bumped after every device expansion wave. | **TODO**: make baseline dynamic — read from `Specs/quirks.json` at test time. |
| 2026-02-27 | 🟢 P3 | No snapshot tests for quirk resolution output. A device-profile regression could silently change flag values. | **TODO**: add snapshot tests that pin resolved flags for key device profiles. |
| 2026-02-27 | 🟢 P3 | `VirtualDeviceConfig` presets use manually-incremented bus addresses (`@1:42`, `@1:43`...). Could collide if multiple contributors add presets. | **TODO**: auto-generate bus address from hash of VID:PID. |

| 2026-02-27 | 🟡 P2 | BDD tests don't use the `.feature` files for execution — CucumberTests are manual Swift test methods that duplicate Gherkin scenarios in code. Feature files exist but aren't parsed at runtime. | **TODO**: wire CucumberSwift to parse `.feature` files directly, or remove unused `.feature` files to reduce confusion. |

## Developer Experience

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🟡 P2 | Worktree-based parallel development requires manual merge of `quirks.json` with dedup script. No built-in merge driver for the JSON array format. | **TODO**: add a custom git merge driver for `quirks.json` or a `scripts/merge-quirks.sh` helper. |
| 2026-02-27 | 🟡 P2 | Must keep `Specs/quirks.json` and `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json` byte-identical manually. | **TODO**: symlink one to the other, or add a pre-commit hook that copies. |
| 2026-02-27 | 🟢 P3 | `CHANGELOG.md` entries for device waves are very long. Consider a separate `DEVICE-CHANGELOG.md` or auto-generated device-count summary. | Backlog |
| 2026-02-27 | 🟢 P3 | No contributor-facing "How to add a device" tutorial with screenshots/video. `Docs/ROADMAP.device-submission.md` exists but is process-focused, not tutorial-focused. | **TODO**: create `Docs/AddingADevice.md` step-by-step guide. |

## Architecture

| Date | Severity | Issue | Status |
|------|----------|-------|--------|
| 2026-02-27 | 🟡 P2 | 2,000+ entries in a single JSON file (~180KB+) is becoming unwieldy. Load time, diff noise, and merge conflicts increase with size. | **TODO**: evaluate splitting quirks.json by VID prefix (e.g., `quirks/04e8-samsung.json`) with a build-time concatenation step. Now 3,200+ entries (~350KB+). |
| 2026-02-27 | 🟢 P3 | No runtime telemetry for which quirk entries actually get matched in the wild. Can't prioritize verification efforts. | **TODO**: opt-in anonymous usage reporting of matched VID:PID (no PII). |
| 2026-02-27 | 🔴 P0 | Agents generating quirk entries use inconsistent JSON schemas: nested dict ops (e.g., `openSession: {maxRetries: 2}`), non-boolean flag values, string evidenceRequired instead of arrays. Requires post-merge normalization pass. | ✅ Resolved — JSON Schema validation added in wave-20 via `Specs/quirks.schema.json` and `validate-quirks.sh`. |
| 2026-02-27 | 🟡 P2 | `QuirkFlags` Swift struct doesn't surface `cameraClass` from JSON — BDD tests that check `.cameraClass` fail at compile time. JSON schema and Swift model are diverging. | ✅ Resolved — `QuirkFlags.cameraClass` added in wave-20; JSON schema and Swift model now aligned. |

---

## How to Add Entries

When you encounter friction during development:

1. Add a row to the appropriate section above
2. Assign a severity (P0–P3)
3. Describe the issue concisely
4. If you fix it immediately, mark ✅ Fixed with a brief note
5. If deferred, add a **TODO** tag so it's searchable
6. Periodically triage **TODO** items into GitHub issues

```bash
# Quick search for open items:
grep -c 'TODO' Docs/friction-log.md
```

### TSAN Interceptor Loading on Xcode 26.3+
- **Priority**: P1
- **Context**: Xcode 26.3 RC2 TSAN fails with "Interceptors are not working"
- **Workaround**: Set DYLD_INSERT_LIBRARIES to the TSAN runtime library path
- **Long-term**: Monitor Apple releases; may be fixed in GM or later Xcode versions

### xcodeproj Deployment Target Drift
- **Priority**: P1
- **Context**: Package.swift was fixed to .macOS(.v15) but SwiftMTP.xcodeproj still had 26.0
- **Workaround**: Manually lowered xcodeproj MACOSX_DEPLOYMENT_TARGET to 15.0
- **Long-term**: Add CI step to validate Package.swift and xcodeproj deployment targets match

### Category Field Not in DeviceQuirk Struct
- **Priority**: P2
- **Context**: quirks.json has `category` field but DeviceQuirk struct doesn't decode it
- **Impact**: Can't filter by category at runtime; only available in JSON tooling
- **Long-term**: Add `category` property to DeviceQuirk struct and CodingKeys
