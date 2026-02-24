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
