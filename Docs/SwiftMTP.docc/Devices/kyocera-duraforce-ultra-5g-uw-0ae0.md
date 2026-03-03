# Kyocera Duraforce Ultra 5G Uw 0Ae0

@Metadata {
    @DisplayName: "Kyocera Duraforce Ultra 5G Uw 0Ae0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kyocera Duraforce Ultra 5G Uw 0Ae0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0482 |
| Product ID | 0x0ae0 |
| Device Info Pattern | `.*Kyocera.*DuraForce.*Ultra.*5G.*UW.*` |
| Status | Experimental |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
