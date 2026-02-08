# SwiftMTP 1.0 Release Steps

## 1. Freeze API Surface
- Audit public symbols in `SwiftMTPCore/Public/` and `SwiftMTPTransportLibUSB/`
- Add `internal` or `fileprivate` to implementation details
- Expose test-only APIs under `@_spi(Testing)` if needed
- Update CHANGELOG.md with final API surface

## 2. Real-Device Smoke Tests
Run these commands on at least **two different devices** (e.g., Pixel + Samsung camera):

```bash
# Build the CLI tool
cd SwiftMTPKit
swift build -c release
export PATH="$PWD/.build/release:$PATH"

# Probe devices
swiftmtp probe

# Benchmark 1GB transfer (adjust path for your device)
swiftmtp bench 1G --device "Your Device Name" --path "/DCIM" --output benchmark_results.json

# Mirror test (optional, smaller scope)
swiftmtp mirror ~/TestBackup --include "DCIM/Camera/*.jpg" --max-files 5
```

Capture results for `Docs/benchmarks.md` including:
- Device model and OS version
- Transfer speeds (p50/p95/p99)
- Chunk size used
- Timeout settings
- Any errors encountered

## 3. Update Device Quirk Registry
- Add concrete entries to `Specs/quirks.json` based on benchmark results
- Include at least one entry from real device testing
- Document device-specific workarounds or optimizations

## 4. Tag Release Candidate
```bash
# Ensure all changes are committed
git status
git add .
git commit -m "Prepare v1.0.0-rc1"

# Tag the release candidate
git tag v1.0.0-rc1
git push --tags
```

## 5. Validate CI Pipeline
- Monitor GitHub Actions for the tag
- Verify SBOM generation completes
- Download and test the XCFramework artifact
- Ensure all tests pass in CI environment

## 6. Cut Final Release (after RC validation)
```bash
# If RC looks good, cut final release
git tag v1.0.0
git push --tags

# Publish documentation
# - DocC site builds automatically via CI
# - Update README install snippet if needed
```

## Rollback Plan
If issues discovered in RC:
```bash
# Delete the problematic tag
git tag -d v1.0.0-rc1
git push origin :refs/tags/v1.0.0-rc1

# Address issues and re-tag
git tag v1.0.0-rc1
git push --tags
```

## Acceptance Criteria for GA
- [ ] API frozen and documented
- [ ] Real-device testing completed on ≥2 devices
- [ ] CI passes with green TSAN job
- [ ] SBOM generated successfully
- [ ] XCFramework builds and links correctly
- [ ] Documentation published and accessible
- [ ] CHANGELOG.md updated with release notes

---

# SwiftMTP 1.1.0 Release Checklist

## Pre-Release
- [ ] Finalize File Provider XPC integration testing
- [ ] Verify transfer journaling works across interruptions
- [ ] Test mirror/sync conflict resolution
- [ ] Complete OnePlus 3T quirk validation
- [ ] Update `Docs/benchmarks.md` with all device results
- [ ] Run full test suite (BDD, Property, Snapshot, Fuzzing)
- [ ] Validate CLI storybook mode

## Release Steps

```bash
# 1. Final audit
swift test
swift-format lint -r Sources Tests

# 2. Commit final changes
git add .
git commit -m "Release v1.1.0: File Provider, Transfer Journaling, Mirror/Sync"

# 3. Tag release
git tag v1.1.0
git push --tags

# 4. Verify CI
# - Monitor GitHub Actions
# - Check SBOM generation
# - Verify XCFramework artifact
```

## Acceptance Criteria for v1.1.0
- [ ] File Provider extension builds and loads on macOS
- [ ] Transfer journal survives app restart
- [ ] Mirror operations complete without data loss
- [ ] OnePlus 3T quirk works with device trust flow
- [ ] All BDD scenarios pass
- [ ] Thread sanitizer clean on Core/Index tests
- [ ] Benchmarks documented in `Docs/benchmarks.md`
- [ ] CHANGELOG.md complete with v1.1.0 entry
- [ ] README.md reflects new features

## Rollback for v1.1.0
If issues discovered post-release:
```bash
git tag -d v1.1.0
git push origin :refs/tags/v1.1.0

# Create patch release
git commit -m "Revert <feature> for v1.1.1"
git tag v1.1.1
git push --tags
```
