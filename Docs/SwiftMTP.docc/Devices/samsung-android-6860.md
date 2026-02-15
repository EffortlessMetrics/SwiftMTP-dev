# Samsung Android 6860

@Metadata {
    @DisplayName: "Samsung Android 6860"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Samsung Android 6860 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04e8 |
| Product ID | 0x6860 |
| Device Info Pattern | `.*SAMSUNG.*` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff (Vendor-Specific) |
| Subclass | Unknown |
| Protocol | Unknown |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms |
| Stabilization Delay | 500 | ms |
| Post-Claim Stabilize | 250 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|
| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Probe Ladder

Samsung devices use a vendor-specific USB interface class (0xff) that may not respond to standard sessionless GetDeviceInfo. The probe ladder tries multiple methods:

1. **Sessionless GetDeviceInfo** (0x1001) - Standard probe
2. **OpenSession + GetDeviceInfo** - Establish session first, then query
3. **GetStorageIDs** (0x1004) - Fallback for vendor-specific stacks

## Warnings

| Condition | Message | Severity |
|------------|---------|----------|
| noInterfaceResponded | Samsung device did not respond on expected MTP interface. Trying alternate interfaces. | warning |

## Notes

- Vendor-specific interface class (0xff) discovered by shared MTP heuristic.
- Increased stabilization delays (500ms post-open, 250ms post-claim) for Samsung MTP stack readiness.
- Probe ladder ensures compatibility with Samsung's unique MTP implementation.
- Read validation is reliable; write smoke is best-effort.
- Use conservative chunking (1MB) for stability.

## Known Limitations

### MTP Interface Not Responding

Some Samsung devices expose multiple USB interfaces, and the MTP interface may not be the first one enumerated. SwiftMTP handles this with:

- `alternateInterfaceSelection=true` to try alternative USB interfaces
- Probe ladder to handle vendor-specific MTP stacks

**If connection fails:**
1. Try a different USB cable or port
2. Change the device's USB mode (PTP vs MTP) in system settings
3. Restart the device's USB daemon by toggling developer options
4. Ensure no other applications (Image Capture, Android File Transfer) are accessing the device

## Troubleshooting

### Device Not Detected

1. Unlock the device
2. Swipe down from top and tap "USB for charging" → "File Transfer (MTP)"
3. Close other applications that might claim the device
4. Try a different USB port or cable

### Probe Fails After Timeout

Samsung devices may need additional stabilization time. The device-lab will automatically:
1. Try sessionless GetDeviceInfo
2. Fall back to OpenSession + GetDeviceInfo
3. Finally try GetStorageIDs as a last resort

If all steps fail, the device is likely in PTP mode or has a USB configuration issue.

## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-10
- **Commit**: Updated with probe ladder and increased stabilization

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/samsung-probe.txt)
- [USB Dump](Docs/benchmarks/probes/samsung-usb-dump.txt)

## Lab Test Results (2026-02-11)

### Test Environment

| Property | Value |
|----------|-------|
| OS | macOS |
| USB Mode | File Transfer (MTP) |
| Device State | Unlocked, screen on |
| Test Command | `swiftmtp device-lab connected --vid 0x04E8 --pid 0x6860` |

### Test Results

| Metric | Value | Status |
|--------|-------|--------|
| Device Detection | VID=0x04E8 PID=0x6860 | ✅ PASSED |
| Claim Interface | `libusb_claim_interface rc=0` | ✅ PASSED |
| Storage Enumeration | GetStorageIDs returned storage handles | ✅ PASSED |
| Probe Ladder | Step 3 successful (GetStorageIDs) | ✅ PASSED |
| GetStorageIDs Latency | 1003ms (first attempt) | ✅ ACCEPTABLE |
| Overall Status | **PASSED** | |

### Key Observations

1. **Storage Enumeration**: The device successfully returned storage IDs on the first probe attempt via the probe ladder's Step 3 (GetStorageIDs). The readiness retry logic was not triggered during this test, indicating the MTP stack was responsive.

2. **Vendor-Specific Interface**: The device uses interface class 0xff (vendor-specific) which required the probe ladder to succeed. Standard sessionless GetDeviceInfo (Step 1) returned `code=0x2006` (OperationNotSupported), but the ladder handled this gracefully.

3. **Post-Claim Stabilization**: The 500ms post-claim stabilization delay allowed the USB pipes to activate properly.

4. **PTP Device Reset**: Successfully executed (`rc=0`), indicating the device supports the reset operation.

### Quirks Validation

The following quirks were validated during the test:

| Quirk | Value | Validation |
|-------|-------|------------|
| `getStorageIDsReadinessRetries` | 5 | Configured but not triggered |
| `getStorageIDsReadinessBackoffMs` | [250, 500, 1000, 2000, 3000] | Configured but not triggered |
| `postOpenSessionStabilizeMs` | 750 | Applied after session open |
| `alternateInterfaceSelection` | true | Used for vendor-specific iface |
| `requiresKernelDetach` | true | `detach_kernel_driver rc=-3` handled |

### Recommendations

Based on test results, the current quirk configuration is **working correctly**. No tuning adjustments are required for this device.
