# Canon Eos Rebel 3139

@Metadata {
    @DisplayName: "Canon Eos Rebel 3139"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos Rebel 3139 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x3139 |
| Device Info Pattern | `.*Canon.*EOS.*` |
| Status | Promoted |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Canon EOS Rebel/Kiss series cameras use PTP (ISO 15740) over USB with Canon vendor extensions (0x9001-0x903F, 0x9101-0x91FF).
- Canon PTP vendor extension ID: 0x0000000B. Extension name reported as 'microsoft.com/MTP: 1.0; canon.com: 1.0'.
- Supports Canon EOS extensions: GetStorageIDs (0x9101), GetObject (0x9104), GetPartialObject (0x9107), GetEvent (0x9116).
- Liveview supported via InitiateViewfinder (0x9151) / GetViewFinderData (0x9153) / TerminateViewfinder (0x9152).
- Remote capture: RemoteRelease (0x910F), BulbStart (0x9125), BulbEnd (0x9126).
- Camera must be in PTP/MTP mode, not PC Connection mode. USB interface class 0x06/0x01/0x01 (Still Image).
- Large CR2/CR3 RAW files (20-50 MB) may require extended ioTimeoutMs. Event pump needed for ObjectAdded (0xC101).
- Battery level readable via GetDevicePropValue (Canon prop 0xD002). KeepDeviceOn (0x9003/0x911D) prevents auto-sleep.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-02-25
- **Commit**: <pending>

### Evidence Artifacts
