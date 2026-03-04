# FIXUP_QUEUE

## Runtime and post-build follow-ups

1. ~~`SwiftMTPKit/Sources/SwiftMTPCore/Internal/Protocol/PTPCodec.swift`~~  
   **DONE** — `PTPObjectInfoDataset.encode()` migrated to `MTPDataEncoder`; all
   byte-copy helpers in PTPContainer now use `MTPEndianCodec` paths.

2. ~~`SwiftMTPKit/Sources/Tools/MTPEndianCodecFuzz/main.swift`~~  
   **DONE** — harness now prints per-iteration failure counters + crash corpus hex dump.

3. ~~`SwiftMTPKit/Tests/MTPEndianCodecTests/MTPEndianCodecTests.swift`~~
   **DONE** — MTPEndianCodecTests uses only `#expect` assertions (Swift Testing);
   no snapshot assertions exist in this target. `SWIFTMTP_SNAPSHOT_TESTS=1` applies
   only to the separate `SnapshotTests` target. No action needed here.

4. ~~`Package.swift`~~
   **DONE** — MTPEndianCodecTests does not depend on `SnapshotTesting` (deps:
   `MTPEndianCodec`, `SwiftMTPCore`, `SwiftCheck`). The empty
   `__Snapshots__/MTPEndianCodecSnapshot/` directory is inert scaffolding.
   No baseline files are needed since no snapshot assertions exist.

5. ~~`SwiftMTPKit/Sources/MTPEndianCodec/MTPEndianCodec.swift`~~  
   **DONE** — `encodeSendObjectPropListDataset` in `Proto+Transfer.swift` now uses
   `MTPDataEncoder` instead of raw `withUnsafeBytes(of:littleEndian)` calls.
   `import MTPEndianCodec` added to `Proto+Transfer.swift`.

6. ~~`SwiftMTPKit/Sources/Tools/learn-promote/` *(excluded from Package.swift)*~~  
   **DONE** — Fixed all broken API calls; re-added as `learn-promote` executable target.

7. ~~`MTPEvent` missing cases~~  
   **DONE** — Added `storageAdded`, `storageRemoved`, `objectInfoChanged`,
   `deviceInfoChanged`, and `unknown(code:params:)` cases to `MTPEvent` with
   full `fromRaw()` parsing. All switch sites updated.

8. ~~`MTPLink` missing object property operations~~  
   **DONE** — Added `getObjectPropValue` / `setObjectPropValue` / `getObjectPropsSupported`
   to `MTPLink` protocol with default implementations via `executeStreamingCommand`.
   `VirtualMTPLink` implements them backed by `VirtualObjectConfig`.
   `PTPLayer` exposes `getObjectModificationDate`, `setObjectModificationDate`,
   `getObjectFileName`, `getObjectPropsSupported`, `getObjectSizeU64` helpers.
   `MTPObjectPropCode` and `MTPDateString` enums added. ObjectSize U64 fallback
   wired into `getObjectInfoStrict`. `skipGetObjectPropValue` QuirkFlag added.

9. ~~`FallbackAllFailedError` not tested~~  
   **DONE** — `FallbackAllFailedErrorTests` (8 tests) in `ErrorHandlingTests`.

10. ~~SwiftCheck signal-5 crash in `UInt64 idempotence` test~~
    **DONE** — Replaced `property/forAll` with explicit boundary value loop
    using Swift Testing `#expect`. Root cause: XCTest+Swift-Testing mixing.

## Device expansion epic — friction items

### hooks encoding (dict vs array)
- **Issue**: Some device waves added `"hooks": {}` (empty dict) instead of `"hooks": []` (empty array)
- **Impact**: 57 entries caused JSON decode failures; QuirkMatchingTests and BDD tests broke
- **Fix**: Normalized all `hooks` fields to arrays via python3 script (PR #66)
- **Prevention**: Add hooks format validation to validate-quirks CI step; add test that verifies all hooks are arrays

### Dedup rebase pattern for device waves
- **Issue**: Multiple parallel agents modifying quirks.json cause merge conflicts
- **Pattern**: Extract new entries by ID diffing against main, append to main's entries array
- **Note**: Must handle category corrections (entries exist in both but different categories)

### VID:PID duplicate detection
- ~~**Issue**: HiBy R6 III used estimated PID under Vivo's VID (PR #62)~~
- ~~**Prevention**: validate-quirks CI already checks; entries with estimated PIDs should be flagged~~
- **DONE** — `validate-quirks.sh` enforces unique VID:PID pairs (lines 111-124) and the embedded Python validator checks format + uniqueness. No further action needed.

### CI TSAN interceptor failure
- **Issue**: Xcode 26.3 RC2 breaks TSAN with "Interceptors are not working"
- **Fix**: Pin Xcode 16.2 + continue-on-error + setup-swift for Swift 6.2 toolchain
- **Note**: Monitor Xcode 26.x releases for fix

### Gaming handheld/VR entries already in main
- **Issue**: Wave 84 gaming handheld entries ended up with 0 new entries after dedup because they were already captured in main via prior waves
- **Prevention**: Agents should query main branch state before generating entries

---

## Developer friction log

Categorized list of known issues, rough edges, and improvement opportunities
discovered during development. Items are grouped by area.

### CI issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| F-CI-1 | **TSAN DTXConnectionServices interceptor crash** — Xcode 26.3 RC2 TSAN runtime conflicts with DTXConnectionServices on CI runners (signal 5 / SIGTRAP). | TSAN job uses `continue-on-error: true`; compile-time checks still run but runtime analysis is skipped. | Mitigated — pinned Xcode 16.2 + direct binary execution bypass. Monitor Xcode 26.x for fix. |
| F-CI-2 | **Duplicate TSAN job** — `ci.yml` and `tsan-and-compat.yml` both define nearly identical TSAN jobs with the same bypass script. | Wasted CI minutes on every push to `feat/**` and `main`. | **Resolved** — removed duplicate TSAN job from `ci.yml`; TSAN now runs only in `tsan-and-compat.yml`. |
| F-CI-3 | **Missing SPM cache on TSAN and smoke jobs** — `ci.yml` `tsan` job and `smoke.yml` lack SPM dependency caching while `build-test` job has it. | Slower CI runs; full SPM resolve on every run. | **Fixed** in this PR — added `actions/cache` for `.build` directory. |
| F-CI-4 | **Coverage job re-runs full test suite** — `swiftmtp-ci.yml` `coverage` job has `needs: test` but then runs `./run-all-tests.sh` again instead of reusing test artifacts. | Doubles CI time on main branch pushes. | **Resolved** — `test` job now uploads coverage artifacts; `coverage` job downloads and reuses them (runs on `ubuntu-latest` in ~1 min). |
| F-CI-5 | **`fuzz-test` in ci.yml uses `macos-latest`** while all other jobs pin `macos-15`. | Could hit DTXConnectionServices issues if `macos-latest` resolves to a different image. | **Resolved** — `fuzz-test` job already pinned to `macos-15`. |
| F-CI-6 | **DocC generation has no Xcode/Swift version pin** — `docs.yml` runs `generate-docs.sh` without `setup-xcode` or `setup-swift` actions. | DocC output may vary across runner image updates. | Documented — add version pins if docs become flaky. |
| F-CI-7 | **macOS runner queuing** — macos-15 runners can queue for 5–15 min during peak hours. | Slows PR feedback loop. | Unavoidable on GitHub-hosted runners. The `smoke.yml` fast-path helps. |

### Test issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| F-T-1 | **Flaky timing tests** — Tests that depend on wall-clock time (e.g., transfer timeout, benchmark timing assertions) can flake on loaded CI runners. | Occasional spurious failures. | Use generous timeouts and `continue-on-error` where appropriate. |
| F-T-2 | **SwiftCheck signal-5 crash** — `UInt64 idempotence` property test crashed when mixing XCTest + Swift Testing. | Blocked property tests. | **Fixed** — replaced `property/forAll` with explicit boundary value loop using `#expect`. |
| F-T-3 | **Snapshot tests require env var** — `SWIFTMTP_SNAPSHOT_TESTS=1` must be set; missing this silently skips tests. | Easy to miss regressions if not enabled. | By design — prevents CI failures when updating UI; add to pre-release checklist. |
| F-T-4 | **MTPEndianCodecTests snapshots not checked in** — Test target depends on SnapshotTesting but no baseline files exist in `__Snapshots__`. | Snapshot assertions always record, never fail. | **Resolved** — MTPEndianCodecTests does not depend on SnapshotTesting or use snapshot assertions. Empty `__Snapshots__` dir is inert scaffolding. |

### Build issues

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| F-B-1 | **libusb deployment target warning** — Building with `swift build` emits a deployment target mismatch warning for the libusb XCFramework. | Noisy build output. | Cosmetic only — suppress with `--disable-build-manifest-caching` or update XCFramework min deployment. |
| F-B-2 | **macOS sandbox permissions** — File Provider and XPC targets require entitlements that prevent building/testing under the default App Sandbox. | Must run without sandbox for development. | By design — documented in `Docs/FileProvider-TechPreview.md`. |
| F-B-3 | **First build requires libusb XCFramework** — `./scripts/build-libusb-xcframework.sh` must be run before the first build but is not enforced. | New contributors get confusing build errors. | Documented in CLAUDE.md and README; could add a Package.swift build plugin check. |

### Data issues (quirks.json)

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| F-D-1 | **Entries without `evidenceRequired`** — Some quirks entries lack the `evidenceRequired` field, making it unclear what validation is needed. | Inconsistent data quality. | Validate in `validate-quirks.sh`; backfill missing fields. |
| F-D-2 | **Proposed entries needing verification** — Entries with `"status": "proposed"` have no real-device evidence. | Cannot promote to `stable` without testing. | Track in device-lab pipeline; flag in PR reviews. |
| F-D-3 | **hooks encoding (dict vs array)** — 57 entries had `"hooks": {}` instead of `"hooks": []`, causing decode failures. | BDD and QuirkMatchingTests broke. | **Fixed** in PR #66 — add format validation to CI. |
| F-D-4 | **VID:PID duplicate/estimated PIDs** — Some entries use estimated PIDs that may collide with real devices. | False matches in quirk lookup. | **Resolved** — `validate-quirks.sh` enforces unique VID:PID pairs; Python validator checks format + uniqueness in CI. |

### Developer experience

| # | Issue | Impact | Status |
|---|-------|--------|--------|
| F-DX-1 | ~~**First-time setup friction**~~ | ~~High onboarding barrier.~~ | **Resolved** — `scripts/bootstrap.sh` automates libusb install, XCFramework build, initial build, and smoke test. |
| F-DX-2 | ~~**Mock profile documentation scattered**~~ | ~~Developers grep across docs.~~ | **Resolved** — Consolidated in `Docs/MockProfiles.md` with profiles, env vars, and failure scenarios. |
| F-DX-3 | **20 test targets with no discovery guide** — The test suite has 20 targets but no guidance on which to run for which change. | Developers run all tests or guess. | Add a test-target map to CLAUDE.md (e.g., "changed Core → run CoreTests + ScenarioTests"). |
| F-DX-4 | ~~**Pre-PR gate not automated**~~ | ~~Developers may skip steps.~~ | **Resolved** — `scripts/pre-pr.sh` runs format-lint, build, CoreTests, quirks validation, and large-file check in one command. |
