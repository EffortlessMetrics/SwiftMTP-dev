# FIXUP_QUEUE

## Runtime and post-build follow-ups

1. ~~`SwiftMTPKit/Sources/SwiftMTPCore/Internal/Protocol/PTPCodec.swift`~~  
   **DONE** — `PTPObjectInfoDataset.encode()` migrated to `MTPDataEncoder`; all
   byte-copy helpers in PTPContainer now use `MTPEndianCodec` paths.

2. ~~`SwiftMTPKit/Sources/Tools/MTPEndianCodecFuzz/main.swift`~~  
   **DONE** — harness now prints per-iteration failure counters + crash corpus hex dump.

3. `SwiftMTPKit/Tests/MTPEndianCodecTests/MTPEndianCodecTests.swift`
   - Snapshot assertion currently runs only when `SWIFTMTP_SNAPSHOT_TESTS=1`. If snapshot drift appears in CI, regenerate fixtures and run with recording once, then rerun with `SWIFTMTP_SNAPSHOT_TESTS=1`.

4. `Package.swift`
   - `MTPEndianCodecTests` currently depends on `SnapshotTesting` but does not yet persist checked-in snapshots. If snapshot-based CI is enforced, add committed baseline files in `SwiftMTPKit/Tests/MTPEndianCodecTests/__Snapshots__`.

5. `SwiftMTPKit/Sources/MTPEndianCodec/MTPEndianCodec.swift`
   - Ensure any downstream protocol structs that rely on little-endian framing also use the shared encoder/decoder paths to prevent divergence between protocol stacks and fuzz inputs.

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
