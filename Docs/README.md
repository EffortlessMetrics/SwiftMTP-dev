# SwiftMTP Documentation Index

*Last updated: 2026-02-16*

Welcome to SwiftMTP documentation. Use this page as the entry point for finding the right documentation for your needs.

## Quick Links

| What you need... | Go to... |
|-----------------|----------|
| API reference and getting started | [SwiftMTP](SwiftMTP.docc/SwiftMTP.md) |
| macOS Tahoe 26 specific features | [macOS Tahoe 26 Guide](SwiftMTP.docc/macOS26.md) |
| Device-specific tuning | [Device Tuning Guide](SwiftMTP.docc/DeviceTuningGuide.md) |
| Supported devices | [Device Guides](SwiftMTP.docc/Devices/) |
| Performance benchmarks | [Benchmarks](benchmarks.md) |

## Platform Requirements

- **macOS 26.0+** / **iOS 26.0+**
- **Xcode 16.0+** with Swift 6 (`6.2` recommended)

## Installation

### Swift Package Manager

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/EffortlessMetrics/SwiftMTP.git", from: "1.0.0")
    ]
)
```

### Homebrew

```bash
brew tap effortlessmetrics/swiftmtp
brew install swiftmtp
```

## Sprint and Delivery Docs

- [Roadmap](ROADMAP.md): sprint queue, release cadence, risk register
- [Sprint Playbook](SPRINT-PLAYBOOK.md): DoR/DoD, weekly rhythm, carry-over rules
- [Testing Guide](ROADMAP.testing.md): local and CI gates, evidence expectations
- [Release Checklist](ROADMAP.release-checklist.md): checkpoint and tag-cut gates
- [Release Runbook](../RELEASE.md): version prep, tagging, artifact validation

## Contribution and Device Docs

- [Contribution Guide](ContributionGuide.md): branch/PR flow and sprint evidence expectations
- [Device Submission Guide](ROADMAP.device-submission.md): quirk submission and validation steps
- [Troubleshooting](Troubleshooting.md): failure taxonomy and recovery sequences
- [Device Bring-Up Matrix](device-bringup.md): `(device × mode × operation)` certification model

## Product and Technical Docs

- [Benchmarks](benchmarks.md)
- [File Provider Tech Preview](FileProvider-TechPreview.md)
- [Notarization Notes](Notarization.md)

## Change Tracking

- [Changelog](../CHANGELOG.md)

> **Note:** When documentation and behavior diverge, treat scripts and CI outputs as source of truth and update docs in the same PR.
