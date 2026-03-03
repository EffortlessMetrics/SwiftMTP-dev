# Canon Eos R3 32B5

@Metadata {
    @DisplayName: "Canon Eos R3 32B5"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos R3 32B5 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x32b5 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | default | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Canon EOS R3. Full-frame mirrorless flagship, 24.1 MP with stacked CMOS sensor.
- PTP vendor extension: canon.com:1.0 with EOS digital extensions.
- Confirmed by gphoto2: Image Capture, Trigger Capture, Liveview, Configuration.
- Supports Canon EOS 64-bit operations: GetObject64 (0x9170), GetPartialObject64 (0x9172).
- Fast continuous shooting (30fps) generates many ObjectAdded events rapidly.
- Event pump delay should be low (50ms) to keep up with burst capture events.