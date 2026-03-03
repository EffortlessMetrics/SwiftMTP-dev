# Samsung Galaxy S20 S21 6866

@Metadata {
    @DisplayName: "Samsung Galaxy S20 S21 6866"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Samsung Galaxy S20 S21 6866 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e8 |
| Product ID | 0x6866 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Samsung Galaxy S20/S21/S22/S23/S24 series MTP variant PID.
- Uses Samsung's custom MTP stack, not stock Android MTP.
- Same tuning as 0x6860 primary MTP PID; Samsung may present either PID depending on firmware.
- Requires 500ms post-claim stabilization for Samsung MTP readiness.
- Samsung OFFSET_BUG: object property values may be offset by a few bytes.
- GetObjectPropList supported but may return incomplete results for large libraries.
- Samsung Knox or ODIN mode may temporarily disable MTP; reconnect in normal mode if unresponsive.
- Samsung 512-byte USB packet boundary bug: avoid reads of exactly 512 bytes to prevent device hang.