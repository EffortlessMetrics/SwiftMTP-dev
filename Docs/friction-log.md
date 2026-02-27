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
| 2026-02-27 | 🟢 P3 | `generate-compat-matrix.sh` output drifts from committed `Docs/compat-matrix.md` after every quirks addition. No automation to keep them in sync. | **TODO**: add a `post-commit` or CI step that auto-regenerates and commits, or make the CI check advisory-only. |

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
| 2026-02-27 | 🟡 P2 | 2,000+ entries in a single JSON file (~180KB+) is becoming unwieldy. Load time, diff noise, and merge conflicts increase with size. | **TODO**: evaluate splitting quirks.json by VID prefix (e.g., `quirks/04e8-samsung.json`) with a build-time concatenation step. |
| 2026-02-27 | 🟢 P3 | No runtime telemetry for which quirk entries actually get matched in the wild. Can't prioritize verification efforts. | **TODO**: opt-in anonymous usage reporting of matched VID:PID (no PII). |

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
