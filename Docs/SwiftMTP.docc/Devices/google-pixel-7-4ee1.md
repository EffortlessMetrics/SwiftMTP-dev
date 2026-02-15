# Google Pixel 7 4Ee1

@Metadata {
    @DisplayName: "Google Pixel 7 4Ee1"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Google Pixel 7 4Ee1 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x18d1 |
| Product ID | 0x4ee1 |
| Device Info Pattern | `None` |
| Status | **BLOCKED** |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 20000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 180000 | ms |
| Stabilization Delay | 3000 | ms |

## Status: BLOCKED

**Reason:** Chrome/WebUSB has exclusive access to this device.

The Pixel 7 is blocked by Chrome's WebUSB API which holds exclusive access to the device. SwiftMTP cannot access the device while Chrome has it open.

### Symptoms

- LIBUSB_ERROR_TIMEOUT on bulk transfers
- Device appears in Chrome but not in SwiftMTP
- `SWIFTMTP_DEBUG=1` shows "external owner detected"

### Resolution

1. **Quit all Chromium-based browsers:**
   - Chrome, Chrome Canary
   - Microsoft Edge
   - Brave
   - Any other browser using WebUSB
2. **Unplug and replug the device**
3. **Ensure phone is unlocked**
4. **Set USB mode to "File Transfer (MTP)"**

After completing these steps, retry the operation. The device should be accessible.

## Warnings

| Condition | Message | Severity |
|------------|---------|----------|
| chromeWebUSBDetected | Chrome/WebUSB is holding this device. Quit all Chromium-based browsers (Chrome, Edge, Brave) and unplug/replug the device. | **error** |

## Notes

- Bulk transfers time out (write rc=-7, LIBUSB_ERROR_TIMEOUT) on macOS when Chrome holds device.
- **Kernel detach does NOT solve this issue on macOS** — Chrome is a user-space process, not a kernel driver.
- The only solution is to quit Chrome and replug the device.
- libmtp-aligned claim (set_configuration + set_alt_setting) reinitializes pipes without USB reset.
- Fallback USB reset uses stabilizeMs=3000 as poll budget for waitForMTPReady.

## Troubleshooting

### Chrome Is Still Running

Even if Chrome windows are closed, Chrome may still be running in the background:

1. Open Activity Monitor (Activity.app)
2. Search for "Chrome" or "Chromium"
3. Force quit any remaining Chrome processes
4. Unplug and replug the Pixel 7

### Device Still Not Accessible After Quitting Chrome

1. Check `ioreg` for AppleUSBHostDeviceUserClient owners:
   ```bash
   ioreg -p IOUSB -l -b | grep -A5 "Pixel 7"
   ```
2. Ensure no other applications are accessing the device:
   - Image Capture
   - Android File Transfer
   - Photos app
   - adb (Android Debug Bridge)

### USB Debugging (ADB) May Also Block Access

If you have USB debugging enabled:
1. Disconnect the device from ADB: `adb kill-server`
2. Or disable USB debugging in Developer Options on the device

## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-10
- **Commit**: Documented as BLOCKED with Chrome/WebUSB resolution steps

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/pixel7-probe.txt)
- [USB Dump](Docs/benchmarks/probes/pixel7-usb-dump.txt)

## Lab Test Status

**Test Date:** 2026-02-11  
**Status:** DEFERRED - Device not connected

The Pixel 7 device was not available for physical tuning during this test session. The device was not detected via `system_profiler SPUSBDataType` or `swiftmtp device-lab connected`.

### Required Actions for Future Testing

1. Connect the Pixel 7 via USB
2. Ensure USB mode is set to "File Transfer (MTP)"
3. Quit all Chrome/Chromium processes before testing
4. Unlock the device and keep screen on

### Expected Test Commands

```bash
# Kill conflicting processes
killall PTPCamera 2>/dev/null || true
osascript -e 'tell app "Google Chrome" to quit' 2>/dev/null || true

# Run device lab test
SWIFTMTP_DEBUG=1 swiftmtp device-lab connected --vid 0x18D1 --pid 0x4EE1
```
