# SwiftMTP Device Compatibility Matrix

Generated: 2026-02-27  
**Total: 2002 device profiles** across **97 unique USB vendor IDs**

> This matrix is generated automatically from `Specs/quirks.json`.  
> Status: `proposed` entries are based on community research and need validation.
> `promoted` entries have been validated with real hardware.

## Brands by entry count

| Brand | USB VID | Entries |
|---|---|---:|
| Sony PlayStation/IC/PSP | `0x054c` | 145 |
| Canon | `0x04a9` | 126 |
| Xiaomi/Redmi/POCO | `0x2717` | 121 |
| Samsung | `0x04e8` | 104 |
| Nikon | `0x04b0` | 96 |
| Sony (Xperia+Alpha+SE) | `0x0fce` | 71 |
| Fujifilm | `0x04cb` | 66 |
| Olympus/OM System | `0x07b4` | 66 |
| Nokia/HMD | `0x0421` | 58 |
| LG | `0x1004` | 57 |
| Amazon Fire | `0x1949` | 49 |
| Huawei | `0x12d1` | 48 |
| Panasonic | `0x04da` | 47 |
| Garmin | `0x091e` | 41 |
| Google/Pixel/Nexus | `0x18d1` | 35 |
| Motorola | `0x22b8` | 35 |
| ASUS | `0x0b05` | 34 |
| OPPO/Realme | `0x22d9` | 34 |
| ZTE/nubia | `0x19d2` | 29 |
| OnePlus | `0x2a70` | 28 |
| HTC | `0x0bb4` | 28 |
| Vendor 0x040d | `0x040d` | 27 |
| Lenovo | `0x17ef` | 25 |
| BlackBerry | `0x0fca` | 25 |
| GoPro | `0x2672` | 25 |
| vivo | `0x2d95` | 24 |
| Leica | `0x1a98` | 22 |
| Coolpad | `0x1ebf` | 22 |
| Vendor 0x1bbb | `0x1bbb` | 21 |
| Fitbit | `0x2687` | 21 |
| SanDisk | `0x0781` | 18 |
| Kyocera | `0x0482` | 17 |
| Honor | `0x339b` | 16 |
| Creative Labs | `0x041e` | 16 |
| Vendor 0x05ca | `0x05ca` | 16 |
| Vendor 0x2237 | `0x2237` | 15 |
| Pentax | `0x25fb` | 14 |
| Meizu | `0x2a45` | 14 |
| DJI | `0x2ca3` | 14 |
| Sharp | `0x04dd` | 13 |
| Vendor 0x2e1a | `0x2e1a` | 13 |
| Sigma | `0x0b0e` | 13 |
| Vendor 0x0e8d | `0x0e8d` | 12 |
| Vendor 0x2a49 | `0x2a49` | 12 |
| Roland | `0x0582` | 12 |
| Apple iPod/iPhone | `0x05ac` | 11 |
| Casio | `0x07cf` | 10 |
| Realme C-series | `0xda09` | 10 |
| Vendor 0x1d5b | `0x1d5b` | 9 |
| Epson | `0x04b8` | 9 |
| Vendor 0x040a | `0x040a` | 8 |
| Vendor 0x4102 | `0x4102` | 8 |
| Microsoft | `0x045e` | 8 |
| Vendor 0x3538 | `0x3538` | 8 |
| Vendor 0x1d4d | `0x1d4d` | 8 |
| Vendor 0x2b24 | `0x2b24` | 8 |
| Vendor 0x0da4 | `0x0da4` | 8 |
| Vendor 0x4566 | `0x4566` | 8 |
| Nothing | `0x2b0e` | 7 |
| Vendor 0x1d5c | `0x1d5c` | 7 |
| Vendor 0x1493 | `0x1493` | 7 |
| Zoom Audio | `0x1686` | 7 |
| TASCAM | `0x06ef` | 7 |
| HP | `0x03f0` | 7 |
| Vendor 0x0e21 | `0x0e21` | 6 |
| Vendor 0x0c45 | `0x0c45` | 6 |
| Vendor 0x0502 | `0x0502` | 5 |
| Vendor 0x0471 | `0x0471` | 5 |
| Vendor 0x2207 | `0x2207` | 5 |
| Vendor 0x05dc | `0x05dc` | 5 |
| *(other 27 vendors)* | various | 70 |

## Coverage by USB class

| USB Class | Description | Count | Notes |
|---|---|---:|---|
| 0xFF | Android MTP | 1094 | Requires kernel detach |
| 0x06 | PTP/Camera | 908 | Plug-and-play |
| Other | Legacy/Mixed | 0 | Variable behavior |

## Submitting a new device

```bash
# Option 1: guided wizard
swift run swiftmtp wizard

# Option 2: probe and add manually
swift run swiftmtp probe | swift run swiftmtp add-device

# Option 3: device lab automated harness
swift run swiftmtp device-lab
```

See [Docs/ContributionGuide.md](ContributionGuide.md) for the full device submission workflow.
See [Docs/iOS-Compatibility.md](iOS-Compatibility.md) for Apple iOS device notes.
