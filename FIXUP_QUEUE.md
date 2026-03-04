# FIXUP_QUEUE

> Last updated: wave 41 cleanup. Resolved items archived at bottom.

## Active items

### Runtime / build

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-1 | **IOUSBHost transport is scaffold-only** — `SwiftMTPTransportIOUSBHost` has 22 `TODO` stubs and every method throws `notImplemented`. | Cannot use native IOUSBHost path; libusb transport is the only working backend. | Implement methods incrementally starting with `openUSBIfNeeded` → `openSession` → `getDeviceInfo`. Track in a dedicated epic. |
| A-2 | **swift-format lint warnings (cosmetic)** — ~530 remaining warnings (line length, spacing) mostly in `SystemCommands.swift`. | Noisy lint output; CI does not block on warnings. | Batch-fix with `swift-format -i` in a dedicated PR. |

### CI / testing

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-3 | **TSAN blocked on macOS 26 locally** — Xcode 26.x TSAN runtime conflicts with DTXConnectionServices (`signal 5 / SIGTRAP`). CI mitigated with Xcode 16.2 pin + `continue-on-error`. | Local TSAN runs crash; runtime analysis only works on CI with pinned Xcode. | Monitor Xcode 26.x betas for fix. No local workaround yet. |
| A-4 | **macOS 26 Signal 5 on combined XCTest + Swift Testing** — Tests mixing XCTest and Swift Testing in the same process crash with signal 5 on macOS 26. | SwiftCheck property tests required migration to pure `#expect`. Future test additions must avoid mixing. | Keep all new tests on Swift Testing (`#expect`). Audit remaining XCTest-only targets. |
| A-5 | **Flaky timing tests** (F-T-1) — Tests depending on wall-clock time flake on loaded CI runners. | Occasional spurious failures. | Use generous timeouts; add `continue-on-error` where needed. |
| A-6 | **Snapshot tests require env var** (F-T-3) — `SWIFTMTP_SNAPSHOT_TESTS=1` must be set; missing silently skips tests. | Easy to miss regressions. | By design — add to pre-release checklist. |
| A-7 | **Coverage job re-runs full test suite** (F-CI-4) — `swiftmtp-ci.yml` `coverage` job re-runs everything instead of reusing artifacts. | Doubles CI time on main pushes. | Share coverage data from `test` job via artifacts. |
| A-8 | **Duplicate TSAN job** (F-CI-2) — `ci.yml` and `tsan-and-compat.yml` both define nearly identical TSAN jobs. | Wasted CI minutes. | Consolidate into one workflow with reusable job. |
| A-9 | **`fuzz-test` uses `macos-latest`** (F-CI-5) — All other jobs pin `macos-15`. | Inconsistent runner image. | Pin to `macos-15`. |
| A-10 | **DocC generation has no Xcode/Swift pin** (F-CI-6) | DocC output may vary across runner images. | Add version pins if docs become flaky. |

### Data issues (quirks.json)

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-11 | **Entries without `evidenceRequired`** (F-D-1) — Some entries lack the field. | Inconsistent data quality. | Backfill missing fields; validate in `validate-quirks.sh`. |
| A-12 | **Proposed entries needing verification** (F-D-2) — `"status": "proposed"` entries have no real-device evidence. | Cannot promote to `stable`. | Track in device-lab pipeline; flag in PR reviews. |

### Developer experience

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-13 | **First-time setup friction** (F-DX-1) — New contributors must: install libusb, build XCFramework, set mock profile env vars, `cd SwiftMTPKit`. | High onboarding barrier. | Create `scripts/bootstrap.sh` one-liner. |
| A-14 | **Mock profile docs scattered** (F-DX-2) — Profiles (`pixel7`, `galaxy`, `iphone`, `canon`) documented in multiple places. | Developers grep across docs. | Consolidate in `Docs/MockProfiles.md`. |
| A-15 | **20 test targets with no discovery guide** (F-DX-3) | Developers run all tests or guess. | Add test-target map to CLAUDE.md. |
| A-16 | **Pre-PR gate not automated** (F-DX-4) — 5-step gate is documented but not scriptable. | Developers may skip steps. | Add format+lint to `run-all-tests.sh` or create `scripts/pre-pr.sh`. |

### Build issues

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-17 | **libusb deployment target warning** (F-B-1) | Noisy build output. | Update XCFramework min deployment target. |
| A-18 | **macOS sandbox permissions** (F-B-2) — File Provider/XPC require entitlements incompatible with App Sandbox. | Must run without sandbox for dev. | By design — documented in `Docs/FileProvider-TechPreview.md`. |
| A-19 | **First build requires libusb XCFramework** (F-B-3) — Not enforced by build system. | Confusing errors for new contributors. | Add Package.swift build plugin check or `scripts/bootstrap.sh`. |

### Device expansion epic — open items

| # | Issue | Impact | Next step |
|---|-------|--------|-----------|
| A-20 | **Dedup rebase pattern for device waves** — Parallel agents modifying quirks.json cause merge conflicts. | Slows device-wave PRs. | Extract entries by ID diff against main, append to main's array. Handle category corrections. |
| A-21 | **Gaming handheld/VR entries already in main** — Wave 84 ended up with 0 new entries after dedup. | Wasted agent work. | Agents should query main branch state before generating entries. |
| A-22 | **macOS runner queuing** (F-CI-7) — macos-15 runners queue 5–15 min at peak. | Slows PR feedback. | Unavoidable on GitHub-hosted runners; `smoke.yml` helps. |

---

## Resolved (waves 37–40) — archived

Items below are confirmed fixed. Kept for historical reference.

### Runtime and post-build follow-ups

1. ✅ `PTPCodec.swift` migration — `PTPObjectInfoDataset.encode()` migrated to `MTPDataEncoder`; byte-copy helpers use `MTPEndianCodec`.
2. ✅ `MTPEndianCodecFuzz/main.swift` — Harness prints per-iteration failure counters + crash corpus hex dump.
3. ✅ `MTPEndianCodecTests` — Uses only `#expect` assertions (Swift Testing). No snapshot assertions in this target.
4. ✅ `Package.swift` — MTPEndianCodecTests does not depend on `SnapshotTesting`. Empty `__Snapshots__` dir is inert scaffolding.
5. ✅ `MTPEndianCodec` — `encodeSendObjectPropListDataset` uses `MTPDataEncoder`. `import MTPEndianCodec` added to `Proto+Transfer.swift`.
6. ✅ `learn-promote` tool — Fixed broken API calls; re-added as executable target.
7. ✅ `MTPEvent` missing cases — PR #432. Added `storageAdded`, `storageRemoved`, `objectInfoChanged`, `deviceInfoChanged`, `unknown(code:params:)` with full `fromRaw()` parsing.
8. ✅ `MTPLink` object property operations — PR #452. Added `getObjectPropValue` / `setObjectPropValue` / `getObjectPropsSupported` to `MTPLink` protocol. `SetObjectPropList` support.
9. ✅ `FallbackAllFailedError` testing — `FallbackAllFailedErrorTests` (8 tests) in `ErrorHandlingTests`.
10. ✅ SwiftCheck signal-5 crash — PR #424. Replaced `property/forAll` with explicit boundary value loop using `#expect`. Root cause: XCTest+Swift-Testing mixing.

### Device expansion epic — resolved

- ✅ **hooks encoding (dict vs array)** — PR #66. Normalized 57 entries from `{}` to `[]`; format validation added to CI.
- ✅ **VID:PID duplicate detection** — `validate-quirks.sh` enforces unique VID:PID pairs (lines 111-124); Python validator checks format + uniqueness.

### CI — resolved

- ✅ **F-CI-3: Missing SPM cache on TSAN and smoke jobs** — Added `actions/cache` for `.build` directory.
- ✅ **F-T-2: SwiftCheck signal-5 crash** — PR #424. Replaced with explicit boundary loop.
- ✅ **F-T-4: MTPEndianCodecTests snapshots** — Resolved: target does not use snapshot assertions.
- ✅ **F-D-3: hooks encoding** — PR #66. Format validation added to CI.
- ✅ **F-D-4: VID:PID duplicates** — `validate-quirks.sh` + Python validator enforce uniqueness.
- ✅ **swift-format blocking warnings** — PR #416. CI-blocking format issues resolved.
