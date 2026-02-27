# iOS / Apple Device Compatibility

## Why iOS devices don't work with full MTP

Apple iOS devices do **not** use the MTP (Media Transfer Protocol) standard for general file access. Instead, Apple implements its own proprietary **AFC (Apple File Conduit)** protocol, which is accessible through [libimobiledevice](https://libimobiledevice.org/) on macOS and Linux. Because SwiftMTP speaks MTP/PTP, it cannot access the full iOS file system.

## What IS supported: PTP camera roll access

When you connect an iPhone or iPad to a Mac and select "Trust This Computer," the device exposes a limited **PTP (Picture Transfer Protocol)** interface over USB (interface class `0x06`). This is the same interface used by macOS Image Capture and Photos.app for photo import.

SwiftMTP includes **informational** quirks entries for these PIDs so the device is recognized rather than silently ignored:

| Device | VID:PID | Access |
|--------|---------|--------|
| iPhone (generic) | 05ac:12a8 | PTP camera roll only |
| iPad (generic) | 05ac:12ab | PTP camera roll only |
| iPod nano | 05ac:12ac | PTP camera roll only |
| Apple TV | 05ac:12aa | PTP camera roll only |

> **Note:** These entries have `confidence: low` and `status: proposed`. They enable recognition, but full MTP operations (push, mirror, snapshot) will not succeed on iOS devices.

## What's NOT supported

- Full file-system access (Documents, Downloads, arbitrary app sandboxes)
- Pushing files to arbitrary locations
- Accessing any folder outside DCIM/camera roll

## Getting full access with libimobiledevice

To access the full iOS file system on macOS or Linux, use [libimobiledevice](https://libimobiledevice.org/) and [ifuse](https://github.com/libimobiledevice/ifuse):

```bash
# Install via Homebrew
brew install libimobiledevice ifuse

# Mount the device
ifuse ~/mnt/iphone

# Browse files
ls ~/mnt/iphone/DCIM/
ls ~/mnt/iphone/Documents/

# Unmount
umount ~/mnt/iphone
```

## iPod classic / nano (legacy MTP)

Older iPod devices (classic and nano) **do** support MTP on certain firmware versions and are included in the quirks database with full MTP entries. See the [Device Quirks reference](ContributionGuide.md) for details.

## Further reading

- [libimobiledevice](https://libimobiledevice.org/) — open-source protocol library for iOS devices
- [ifuse](https://github.com/libimobiledevice/ifuse) — FUSE filesystem driver for iOS
- [PTP/IP specification](https://www.usb.org/sites/default/files/documents/usbdifoptp11.pdf) — USB Still Image Capture Device Class spec
