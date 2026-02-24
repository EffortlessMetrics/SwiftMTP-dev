# FIXUP_QUEUE

## Runtime and post-build follow-ups

1. `SwiftMTPKit/Sources/SwiftMTPCore/Internal/Protocol/PTPCodec.swift`
   - Some direct byte-copy helpers in `PTPContainer` and `PTPObjectInfoDataset` still use local `withUnsafeBytes` append paths. The new `MTPEndianCodec` module is now the canonical little-endian API, but these call sites have not all been migrated yet.
   - Follow-up: migrate remaining writers to `MTPEndianCodec` where practical and keep behavior parity.

2. ~~`SwiftMTPKit/Sources/Tools/MTPEndianCodecFuzz/main.swift`~~  
   **DONE** — harness now prints per-iteration failure counters + crash corpus hex dump.

3. `SwiftMTPKit/Tests/MTPEndianCodecTests/MTPEndianCodecTests.swift`
   - Snapshot assertion currently runs only when `SWIFTMTP_SNAPSHOT_TESTS=1`. If snapshot drift appears in CI, regenerate fixtures and run with recording once, then rerun with `SWIFTMTP_SNAPSHOT_TESTS=1`.

4. `Package.swift`
   - `MTPEndianCodecTests` currently depends on `SnapshotTesting` but does not yet persist checked-in snapshots. If snapshot-based CI is enforced, add committed baseline files in `SwiftMTPKit/Tests/MTPEndianCodecTests/__Snapshots__`.

5. `SwiftMTPKit/Sources/MTPEndianCodec/MTPEndianCodec.swift`
   - Ensure any downstream protocol structs that rely on little-endian framing also use the shared encoder/decoder paths to prevent divergence between protocol stacks and fuzz inputs.

6. `SwiftMTPKit/Sources/Tools/learn-promote/` *(excluded from Package.swift)*
   - Uses `DeviceFingerprint` (should be `MTPDeviceFingerprint`) and incorrect `QuirkDatabase` API.
   - Follow-up: audit correct type names in `SwiftMTPQuirks`, fix call sites, re-add target to Package.swift.
