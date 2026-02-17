# SwiftMTP Documentation (Diátaxis)

This directory contains SwiftMTP documentation organized according to the [Diátaxis](https://diataxis.fr/) documentation framework.

## Documentation Types

The Diátaxis framework organizes documentation into four types based on the user's intent:

| Type | Intent | Description |
|------|--------|-------------|
| **Tutorials** | Learning | Step-by-step guides for beginners to learn SwiftMTP |
| **How-to Guides** | Task | Practical steps to accomplish specific goals |
| **Reference** | Information | Technical descriptions of APIs, commands, and components |
| **Explanation** | Understanding | Background concepts, architecture, and rationale |

## Quick Navigation

### 🎓 Tutorials
- [Getting Started](tutorials/getting-started.md) - Your first SwiftMTP project
- [Your First Device Transfer](tutorials/first-transfer.md) - Connect and transfer files
- [Advanced Transfer Strategies](tutorials/advanced-transfer.md) - Parallel transfers, resume, batch operations
- [Device Probing and Analysis](tutorials/device-probing.md) - Probe and analyze new devices
- [Debugging MTP Issues](tutorials/debugging-mtp.md) - Debug MTP connection and transfer issues
- [Batch Operations](tutorials/batch-operations.md) - Bulk transfers, folder synchronization
- [Platform Integration](tutorials/platform-integration.md) - iOS, macOS, Catalyst integration

### 📋 How-to Guides
- [Connect a New Device](howto/connect-device.md)
- [Troubleshoot Connection Issues](howto/troubleshoot-connection.md)
- [Transfer Files](howto/transfer-files.md) - Detailed file transfer operations
- [Work with Device Quirks](howto/device-quirks.md) - Configure device-specific quirks
- [File Provider Integration](howto/file-provider.md) - Using Finder/Files app integration
- [Run Benchmarks](howto/run-benchmarks.md)
- [Add Device Support](howto/add-device-support.md)
- [Security and Privacy](howto/security-privacy.md) - Security best practices
- [Performance Tuning](howto/performance-tuning.md) - Optimize transfer speeds
- [Testing MTP Devices](howto/testing-devices.md) - Comprehensive device testing
- [Error Recovery](howto/error-recovery.md) - Error handling and recovery strategies
- [Logging and Debugging](howto/logging-debugging.md) - Logging and debugging guide
- [CLI Automation](howto/cli-automation.md) - CLI automation and scripting

### 📖 Reference
- [CLI Command Reference](reference/cli-commands.md)
- [Error Codes](reference/error-codes.md)
- [API Overview](reference/api-overview.md)
- [Public Types Reference](reference/public-types.md) - Detailed type documentation
- [Configuration Reference](reference/configuration.md) - Configuration options
- [Events Reference](reference/events.md) - Event types and handling
- [Quirks JSON Schema](reference/quirks-schema.md) - Quirks configuration schema
- [Environment Variables](reference/environment-variables.md) - Complete environment variable reference
- [Device Capabilities](reference/device-capabilities.md) - Device capabilities reference

### 💡 Explanation
- [Understanding MTP Protocol](explanation/mtp-protocol.md)
- [Architecture Overview](explanation/architecture.md)
- [Device Quirks System](explanation/device-quirks.md)
- [Transport Layers](explanation/transport-layers.md) - Understanding USB/IOKit transports
- [Transfer Modes](explanation/transfer-modes.md) - Transfer modes explained
- [Session Management](explanation/session-management.md) - Session lifecycle
- [Data Persistence](explanation/persistence.md) - Caching and storage
- [Version History](explanation/version-history.md) - Version history and migration
- [Concurrency Model](explanation/concurrency-model.md) - Concurrency and threading model

## Choosing the Right Documentation

**I'm new to SwiftMTP** → Start with [Tutorials](tutorials/getting-started.md)

**I need to accomplish a specific task** → Use [How-to Guides](howto/connect-device.md)

**I need to look up API or command details** → Check [Reference](reference/cli-commands.md)

**I want to understand how things work** → Read [Explanation](explanation/architecture.md)

## Contributing

When adding documentation:
1. Determine which Diátaxis type fits best
2. Place in the appropriate subdirectory
3. Update this README with links to new content
4. Follow the style guide in the contribution docs

See also: [Contribution Guide](../ContributionGuide.md)
