# SwiftMTP Documentation Index

*Last updated: 2026-02-17*

Welcome to SwiftMTP documentation. Use this page as the entry point for finding the right documentation for your needs.

## Diátaxis Documentation Structure

We use the [Diátaxis](https://diataxis.fr/) framework to organize our documentation by user intent. See the [Diátaxis Overview](diataxis/README.md) for details.

### By Intent

| What you need... | Go to... |
|------------------|----------|
| Learning SwiftMTP (beginner) | [Tutorials](diataxis/tutorials/getting-started.md) |
| Accomplishing a specific task | [How-to Guides](diataxis/howto/connect-device.md) |
| Looking up API/command details | [Reference](diataxis/reference/cli-commands.md) |
| Understanding how things work | [Explanation](diataxis/explanation/architecture.md) |

### Expanded Diátaxis Documentation

#### 🎓 Tutorials
- [Getting Started](diataxis/tutorials/getting-started.md) - Your first SwiftMTP project
- [Your First Device Transfer](diataxis/tutorials/first-transfer.md) - Connect and transfer files
- [Advanced Transfer Strategies](diataxis/tutorials/advanced-transfer.md) - Parallel transfers, resume, batch operations
- [Device Probing and Analysis](diataxis/tutorials/device-probing.md) - Probe and analyze new devices
- [Debugging MTP Issues](diataxis/tutorials/debugging-mtp.md) - Debug MTP connection and transfer issues
- [Batch Operations](diataxis/tutorials/batch-operations.md) - Bulk transfers, folder synchronization
- [Platform Integration](diataxis/tutorials/platform-integration.md) - iOS, macOS, Catalyst integration

#### 📋 How-to Guides
- [Connect a New Device](diataxis/howto/connect-device.md)
- [Troubleshoot Connection Issues](diataxis/howto/troubleshoot-connection.md)
- [Transfer Files](diataxis/howto/transfer-files.md) - Detailed file transfer operations
- [Work with Device Quirks](diataxis/howto/device-quirks.md) - Configure device-specific quirks
- [File Provider Integration](diataxis/howto/file-provider.md) - Using Finder/Files app integration
- [Run Benchmarks](diataxis/howto/run-benchmarks.md)
- [Add Device Support](diataxis/howto/add-device-support.md)
- [Security and Privacy](diataxis/howto/security-privacy.md) - Security best practices
- [Performance Tuning](diataxis/howto/performance-tuning.md) - Optimize transfer speeds
- [Testing MTP Devices](diataxis/howto/testing-devices.md) - Comprehensive device testing
- [Error Recovery](diataxis/howto/error-recovery.md) - Error handling and recovery strategies
- [Logging and Debugging](diataxis/howto/logging-debugging.md) - Logging and debugging guide
- [CLI Automation](diataxis/howto/cli-automation.md) - CLI automation and scripting

#### 📖 Reference
- [CLI Command Reference](diataxis/reference/cli-commands.md)
- [Error Codes](diataxis/reference/error-codes.md)
- [API Overview](diataxis/reference/api-overview.md)
- [Public Types Reference](diataxis/reference/public-types.md) - Detailed type documentation
- [Configuration Reference](diataxis/reference/configuration.md) - Configuration options
- [Events Reference](diataxis/reference/events.md) - Event types and handling
- [Quirks JSON Schema](diataxis/reference/quirks-schema.md) - Quirks configuration schema
- [Environment Variables](diataxis/reference/environment-variables.md) - Complete environment variable reference
- [Device Capabilities](diataxis/reference/device-capabilities.md) - Device capabilities reference

#### 💡 Explanation
- [Understanding MTP Protocol](diataxis/explanation/mtp-protocol.md)
- [Architecture Overview](diataxis/explanation/architecture.md)
- [Device Quirks System](diataxis/explanation/device-quirks.md)
- [Transport Layers](diataxis/explanation/transport-layers.md) - Understanding USB/IOKit transports
- [Transfer Modes](diataxis/explanation/transfer-modes.md) - Transfer modes explained
- [Session Management](diataxis/explanation/session-management.md) - Session lifecycle
- [Data Persistence](diataxis/explanation/persistence.md) - Caching and storage
- [Version History](diataxis/explanation/version-history.md) - Version history and migration
- [Concurrency Model](diataxis/explanation/concurrency-model.md) - Concurrency and threading model

## Quick Links

| What you need... | Go to... |
|------------------|----------|
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
- [Migration Guide](MigrationGuide.md)
- [Error Codes Reference](ErrorCodes.md)
- [Notarization Notes](Notarization.md)

## Change Tracking

- [Changelog](../CHANGELOG.md)

> **Note:** When documentation and behavior diverge, treat scripts and CI outputs as source of truth and update docs in the same PR.
