# SwiftMTP

Swift 6-native, actor-isolated MTP backend for macOS Sequoia / iOS 18.

## Getting Started

1. Add the package via SwiftPM.
2. macOS app: (if sandboxed) add `com.apple.security.device.usb = true`.
3. Start discovery, open device, enumerate storages, mirror files.

## Transfers & Resume

- Reads resume automatically on devices that support `GetPartialObject64`.
- Writes are single-pass unless `SendPartialObject` is available.

## Performance

- Chunk auto-tuning per device (512KiB–8MiB).
- Signposts for enumeration and transfers; use Instruments.
