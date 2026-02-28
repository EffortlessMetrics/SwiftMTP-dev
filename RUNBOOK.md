# Swift microcrate buildbook

## Microcrate targets

- `SwiftMTPCLI` (CLI parsing + JSON + spinner)
- `MTPEndianCodec` (MTP little-endian codec primitives and stream encoder/decoder)
- `MTPEndianCodecTests` (unit/spec + seeded property + integration + snapshot surface)
- `MTPEndianCodecFuzz` (fuzz executable harness)

## Build gates

Run these before moving on:

- `swift build --build-tests`
- `swift build --target MTPEndianCodecFuzz`
- `swift build --product MTPEndianCodecFuzz`
- `xcodebuild -project SwiftMTPKit.xcodeproj -scheme SwiftMTPKit -configuration Debug build-for-testing`

If any command fails, stop at the first compilation failure and record it in `FIXUP_QUEUE.md`.

## Execution commands

### Unit/spec + integration test suites

- `swift test --skip-build --filter MTPEndianCodecTests`
- `swift test --skip-build --filter SwiftMTPCLITests`

### Snapshot checks

- `SWIFTMTP_SNAPSHOT_TESTS=1 swift test --skip-build --filter MTPEndianCodecTests`
- `SWIFTMTP_SNAPSHOT_TESTS=1 swift test --skip-build --filter SnapshotTests`

### Fuzzing

- `swift run MTPEndianCodecFuzz --seed=1A11C0DEBAADF00D --iterations=4096 SwiftMTPKit/Tests/MTPEndianCodecTests/Corpus/event-buffer.hex`
- `swift test --skip-build --filter PTPCodecFuzzTests`

### Sanitizers / coverage

- `swift test --skip-build --sanitize=thread`
- `swift test --enable-code-coverage`

## Fuzz seeds and corpus

- Seed file for deterministic reproduction: `SwiftMTPKit/Tests/MTPEndianCodecTests/Corpus/event-buffer.hex`
- Commandline seed override is supported via `--seed=<hex>` (default `1A11C0DEBAADF00D`).

## Merging Device Waves

When multiple parallel branches add entries to `quirks.json`, merge conflicts are
inevitable. Use the **dedup rebase** pattern:

1. Checkout the wave branch and rebase onto `main`.
2. On conflict, accept **main's** version of `quirks.json`.
3. Extract new entries from the wave branch by diffing entry IDs:
   ```bash
   # List IDs only present in the wave branch
   diff <(jq -r '.entries[].id' quirks-main.json | sort) \
        <(jq -r '.entries[].id' quirks-wave.json | sort) \
     | grep '^>' | sed 's/^> //'
   ```
4. Append those entries to main's `entries` array (preserve sort order by category).
5. Handle **category corrections**: if an entry exists in both but under a different
   category, prefer the wave branch's category (it was intentionally re-classified).
6. Run `swift test --filter QuirkMatchingTests` to validate the merged file.

## Adding entries via scripts

Use `scripts/add-device.sh` to add a single device entry to `quirks.json` interactively.
The script handles:

- Prompting for VID, PID, device name, manufacturer, category, and status
- Generating a canonical quirk ID
- Validating no VID:PID duplicates exist
- Appending the entry in the correct category section
- Running `validate-quirks` checks automatically

Usage:
```bash
./scripts/add-device.sh
```
