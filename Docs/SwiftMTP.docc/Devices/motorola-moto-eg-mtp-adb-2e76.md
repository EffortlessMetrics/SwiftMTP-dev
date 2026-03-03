# Motorola Moto Eg Mtp Adb 2E76

@Metadata {
    @DisplayName: "Motorola Moto Eg Mtp Adb 2E76"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Motorola Moto Eg Mtp Adb 2E76 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22b8 |
| Product ID | 0x2e76 |
| Device Info Pattern | `None` |
| Status | Verified |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Motorola Moto E/G series MTP+ADB composite mode.
- Same standard Android MTP stack as PID 0x2e82 but with ADB interface active.
- Near-stock Android MTP; GetObjectPropList supported.
- Kernel detach required on macOS.