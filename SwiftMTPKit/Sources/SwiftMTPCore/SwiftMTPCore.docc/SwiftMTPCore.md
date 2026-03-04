# ``SwiftMTPCore``

Swift 6-native, actor-isolated MTP (Media Transfer Protocol) library for macOS and iOS.

@Metadata {
    @DisplayName("SwiftMTPCore")
}

## Overview

SwiftMTPCore provides a modern Swift interface for communicating with MTP devices
over USB. It uses actor-based concurrency for thread safety and supports the full
MTP 1.1 specification including Android extensions.

> Warning: SwiftMTP is in pre-alpha. Most features have been validated only
> against in-memory mock devices.

### Key Features

- **Actor-isolated device access** via ``MTPDeviceActor``
- **Async/await** throughout all I/O paths
- **Adaptive chunk tuning** that auto-sizes transfers per device
- **Error recovery** with session reset, stall recovery, and timeout retry
- **MTP 1.1 coverage**: 50+ object formats, 50+ property codes, all 14 events

## Topics

### Essentials

- ``MTPDevice``
- ``MTPDeviceActor``

### Transfer Operations

- ``AdaptiveChunkTuner``

### Error Handling

- ``ErrorRecoveryLayer``

### Device Management

- ``DeviceLabHarness``
- ``DeviceServiceRegistry``
