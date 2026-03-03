# Samsung Galaxy Kies 6877

@Metadata {
    @DisplayName: "Samsung Galaxy Kies 6877"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Samsung Galaxy Kies 6877 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e8 |
| Product ID | 0x6877 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Samsung Kies mode MTP endpoint. Legacy mode used by older Samsung PC sync software.
- libmtp flags: LONG_TIMEOUT, PROPLIST_OVERRIDES_OI, SAMSUNG_OFFSET_BUG.
- May appear when device is set to Kies mode instead of standard MTP mode.
- Same underlying Samsung MTP stack as 0x6860/0x685c/0x6866 endpoints.