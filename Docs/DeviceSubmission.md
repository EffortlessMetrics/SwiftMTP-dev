# Device Submission Guide

Help us make SwiftMTP plug-and-play for your device!

## Quick Start

1. Find your device's USB VID and PID:
   - **macOS**: System Information → USB, look for your device
   - **Linux**: `lsusb | grep -i "your device"`
   - The VID:PID format is shown as `idVendor:idProduct`

2. Generate a template:
   ```bash
   swiftmtp add-device --vid 0x1234 --pid 0x5678 --name "My Device" --class android
   ```

3. Test it:
   - Add the entry to `Specs/quirks.json`
   - Copy to `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`
   - Run `./scripts/validate-quirks.sh`
   - Test connection: `swiftmtp probe`

4. Submit a PR with your changes.

## Device Classes

| Class | When to use | `--class` flag |
|-------|------------|----------------|
| Android MTP | Phones/tablets (Android/Samsung/Google/etc) | `android` |
| PTP Camera | Digital cameras (Canon/Nikon/Sony/etc) | `ptp` |

## Testing Your Submission

Run the full test suite:
```bash
cd SwiftMTPKit && swift test --filter QuirkMatchingTests
```

## What Makes a Good Submission?

- Real VID/PID from a physical device or authoritative source (libmtp/libgphoto2)
- Correct interface class (0xff for Android, 0x06 for PTP)
- Tested on actual hardware preferred
- Include device model name in provenance.notes

## Authoritative Sources

- Android/MTP: https://github.com/libmtp/libmtp/blob/master/src/music-players.h
- PTP Cameras: https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/library.c
