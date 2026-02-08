# SwiftMTP Release Checklist

This checklist covers all tasks required for a complete release.

## Pre-Release Checklist

### Code Quality

- [ ] **All tests pass** (`swift test`)
- [ ] **Coverage thresholds met**
  - [ ] Overall ≥75%
  - [ ] SwiftMTPCore ≥80%
  - [ ] SwiftMTPIndex ≥75%
- [ ] **TSAN clean** (`swift test --sanitize thread`)
- [ ] **No compiler warnings** (`swift build -Xfrontend -warnings-as-errors`)
- [ ] **Formatting compliance** (`swift-format -i .`)

### Documentation

- [ ] **CHANGELOG.md updated**
  - [ ] All changes documented
  - [ ] Breaking changes clearly marked
  - [ ] New features documented
  - [ ] Bug fixes listed
- [ ] **API documentation current** (DocC)
- [ ] **Device quirks validated** (`./scripts/validate-quirks.sh`)
- [ ] **Benchmarks run on real device**
- [ ] **Known issues documented**

### Testing

- [ ] **Smoke tests pass** (`./scripts/smoke.sh`)
- [ ] **Storybook demo runs**
- [ ] **Fuzzer completed** (optional for minor releases)
- [ ] **Real device tested** (at least one device)
- [ ] **Performance regression check**

## Version Bump Procedure

### 1. Determine Version Type

| Type | Example | When |
|------|---------|------|
| **Major** | v1.0.0 → v2.0.0 | Breaking changes |
| **Minor** | v2.0.0 → v2.1.0 | New features |
| **Patch** | v2.1.0 → v2.1.1 | Bug fixes only |

### 2. Update Version Files

#### Package.swift

```swift
// Before
let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v15)],
    version: .init("2.0.0"),
    // ...
)

// After
let package = Package(
    name: "SwiftMTP",
    platforms: [.macOS(.v15)],
    version: .init("2.1.0"),
    // ...
)
```

#### swiftmtp-cli info.plist (if applicable)

Update `CFBundleShortVersionString` and `CFBundleVersion`.

#### RELEASE.md

Update version and date at the top.

### 3. Tag the Release

```bash
# Create tag
git tag -a v2.1.0 -m "Release v2.1.0"

# Push tag
git push origin v2.1.0
```

### 4. Verify Tag

```bash
# Check tag exists
git tag -l "v2.1.0"

# Verify commit
git rev-parse v2.1.0^{commit}
```

## CHANGELOG.md Update Process

### Required Sections

```markdown
# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [v2.1.0] - 2026-02-08

### Added
- Feature A
- Feature B

### Changed
- Changed behavior X

### Deprecated
- Deprecated feature Y

### Removed
- Removed feature Z

### Fixed
- Bug fix A
- Bug fix B

### Security
- Security fix A

### Performance
- Performance improvement A

## [v2.0.0] - 2026-01-01
// ... previous releases
```

### Generating Changelog Entries

```bash
# View commits since last release
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# View merged PRs
gh pr list --state merged --base main --since "2026-01-01"
```

### Changelog Style

- Use imperative mood ("Added" not "Adding")
- Group by type (Added, Changed, Fixed, etc.)
- Sort entries alphabetically
- Reference issues/PRs when relevant

## Release Tag Requirements

### Tag Format

```
v<MAJOR>.<MINOR>.<PATCH>
```

Examples:
- `v2.0.0`
- `v2.1.0`
- `v2.1.1`

### Tag Message Format

```markdown
# Release v2.1.0

## Summary
Brief description of release

## What's New
- Feature A
- Feature B

## Bug Fixes
- Fix X
- Fix Y

## Breaking Changes
- Change Z (migration required)

## Upgrade Notes
Instructions for upgrading

## Full Changelog
https://github.com/effortless-metrics/SwiftMTP/compare/v2.0.0...v2.1.0
```

### Pre-release Tags

For beta/RC releases:

```
v2.1.0-beta.1
v2.1.0-rc.1
```

## Post-Release Tasks

### 1. GitHub Release

```bash
# Create GitHub release
gh release create v2.1.0 \
  --title "SwiftMTP v2.1.0" \
  --notes "$(cat CHANGELOG.md | head -100)" \
  --draft
```

Upload artifacts:
- [ ] Binary (if applicable)
- [ ] SHA256 checksums
- [ ] Signature (if applicable)

### 2. Update Homebrew Tap

```bash
# Update formula
# Edit homebrew-tap/Formula/swiftmtp.rb

# Test installation
brew install --build-from-source ./homebrew-tap/Formula/swiftmtp.rb
```

### 3. Notify Users

- [ ] Post to GitHub Discussions
- [ ] Update project website (if applicable)
- [ ] Send announcement email (for major releases)

### 4. Create Next Milestone

```bash
# Create next version milestone
gh milestone create v2.2.0 \
  --title "v2.2.0" \
  --due-date "2026-06-01"
```

### 5. Archive Completed Items

- [ ] Close completed issues
- [ ] Merge `main` into `develop` (if using Git Flow)
- [ ] Update documentation links

## Release Checklist Template

```markdown
## Release v<X>.<Y>.<Z> Checklist

### Pre-Release
- [ ] All tests passing
- [ ] Coverage thresholds met
- [ ] TSAN clean
- [ ] No warnings
- [ ] Formatting compliant
- [ ] CHANGELOG.md updated
- [ ] DocC generated
- [ ] Quirks validated
- [ ] Benchmarks complete

### Version Bump
- [ ] Package.swift updated
- [ ] Version tag created
- [ ] Tag pushed

### Post-Release
- [ ] GitHub release created
- [ ] Artifacts uploaded
- [ ] Homebrew tap updated
- [ ] Users notified
- [ ] Next milestone created
```

---

*See also: [ROADMAP.md](ROADMAP.md) | [Testing Guide](ROADMAP.testing.md) | [Device Submission](ROADMAP.device-submission.md)*
