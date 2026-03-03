# Google Nexus Pixel Mtp Adb 4Ee2

@Metadata {
    @DisplayName: "Google Nexus Pixel Mtp Adb 4Ee2"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Google Nexus Pixel Mtp Adb 4Ee2 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x18d1 |
| Product ID | 0x4ee2 |
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

- Google Nexus/Pixel MTP+ADB composite mode. Used when USB debugging is enabled.
- Standard Android MTP stack with Google extensions.
- Pixel devices may require Developer Options enabled and USB debugging trusted.
- GetObjectPropList supported on Pixel 3+ with Android 10+.
- On macOS, kernel detach required to claim USB interface from Apple PTP driver.