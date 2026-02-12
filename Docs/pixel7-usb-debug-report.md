# Pixel 7 USB Debugging Report

## Summary

The Pixel 7 is not exposing MTP interfaces to macOS, which explains why the "Trust this computer" prompt doesn't appear.

---

## Device Comparison

### Pixel 7
```
USB Product Name:  Pixel 7
USB Vendor Name:   Google
idVendor:          6353 (0x18D1)
idProduct:          20193 (0x4EE1)
bcdUSB:            528 (USB 2.1)
bNumConfigurations: 1
USB Serial:        2A221FDH200G2Q
USB Address:       3
Device Speed:      2 (USB 2.0 High Speed)
bDeviceClass:      0 (Per-device class)
bDeviceProtocol:   0
locationID:        34668544
sessionID:         7110016624483
```

### SAMSUNG_Android
```
USB Product Name:  SAMSUNG_Android
USB Vendor Name:   SAMSUNG
idVendor:          1256 (0x04E8)
idProduct:         26720 (0x6860)
bcdUSB:            512 (USB 2.0)
bNumConfigurations: 2  ← HAS 2 CONFIGURATIONS
USB Serial:        9886734b3530443253
USB Address:       11
Device Speed:      2 (USB 2.0 High Speed)
kUSBPreferredConfiguration: 2  ← PREFERS CONFIG 2
```

### Mi Note 2
```
USB Product Name:  Mi Note 2
USB Vendor Name:   Xiaomi
idVendor:          10007 (0x2717)
idProduct:         65344 (0xFF00)
bcdUSB:            512 (USB 2.0)
bNumConfigurations: 1
USB Serial:        637b9471
USB Address:       4
Device Speed:      2
```

---

## Critical Finding: No IOUSBInterface Children

**NONE of the Android devices show IOUSBInterface child devices in ioreg**

```
USB Tree (relevant section):
├── AppleT8132USBXHCI@02000000
│   ├── USB3 Gen2 Hub@02200000
│   └── USB2 Hub@02100000
│       ├── Pixel 7@02110000        ← NO CHILD INTERFACES
│       └── Mi Note 2@02120000      ← NO CHILD INTERFACES
├── AppleT8132USBXHCI@01000000
│   └── 4-Port USB 2.0 Hub@01100000
│       └── SAMSUNG_Android@01134300 ← NO CHILD INTERFACES
└── AppleT8132USBXHCI@03000000
    └── Android@03100000             ← NO CHILD INTERFACES
```

---

## Key Differences

| Property | Pixel 7 | SAMSUNG_Android | Mi Note 2 |
|----------|---------|-----------------|-----------|
| idVendor | 0x18D1 (Google) | 0x04E8 (Samsung) | 0x2717 (Xiaomi) |
| idProduct | 0x4EE1 | 0x6860 | 0xFF00 |
| bNumConfigurations | 1 | 2 | 1 |
| bcdUSB | 528 | 512 | 512 |
| Child Interfaces | **NONE** | **NONE** | **NONE** |
| USBPortType | 5 | 0 | 5 |

---

## Root Cause Analysis

### Why No Interfaces Appear

1. **Device in Charging-Only Mode**: The Pixel 7 may be in a mode where only the base USB device is enumerated but no interfaces are exposed.

2. **USB Descriptor Issue**: The device may be sending USB descriptors that macOS cannot parse correctly, causing the interface enumeration to fail silently.

3. **Security/RSA Key Issue**: The "Trust this computer" prompt is handled by Android's USB accessory protocol. If the device:
   - Hasn't been trusted before
   - Is in a mode that doesn't trigger the prompt
   - Has USB debugging disabled
   
   ...then the MTP interfaces won't be exposed.

4. **bDeviceClass = 0**: Pixel 7 has `bDeviceClass = 0` (vendor-specific), which means it doesn't use standard USB class declarations.

---

## Recommended Actions

### 1. Verify USB Mode on Pixel 7
```bash
# Check if MTP is enabled
adb shell getprop sys.usb.config
adb shell getprop sys.usb.state
```

Expected values for MTP:
- `sys.usb.config`: `mtp`
- `sys.usb.state`: `mtp`

### 2. Check USB Debugging Status
```bash
adb devices
# Should show: "unauthorized" if trust prompt needed
# Should show: "device" if trusted
```

### 3. Enable USB Debugging
1. Settings → About Phone → Build Number (tap 7 times)
2. Settings → System → Developer options → USB debugging
3. Reconnect USB cable
4. Check for trust prompt on Pixel 7

### 4. Force PTP Mode Test
Try switching to PTP (Picture Transfer Protocol) to see if interfaces appear:
```bash
adb usb ptp
```

### 5. Check Actual USB Descriptors
Use a USB analyzer or `usbutils` on Linux to see the raw descriptors:
```bash
# On Linux
lsusb -v -d 18d1:4ee1
```

---

## Conclusion

The Pixel 7 (0x18D1:0x4EE1) is connected via USB 2.0 High Speed but **no MTP/PTP interfaces are being enumerated by macOS**. This is the root cause of:

1. No "Trust this computer" prompt appearing
2. SwiftMTP cannot discover the device
3. The device appears as a raw USB device with no child interfaces

**The solution requires ensuring the Pixel 7 is in proper MTP/PTP mode with USB debugging enabled and has been authorized ("trusted") by the host.**

---

## Data Collection Date
2026-02-12 02:11 UTC

## System
macOS with Apple Silicon (T8132 USB controllers)
