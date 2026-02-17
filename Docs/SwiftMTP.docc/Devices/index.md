# Device Guides

@Metadata {
    @TitleHeading("Device Guides")
    @PageKind(article)
}

Mode-by-mode bring-up status for currently profiled devices.

## Latest Evidence Bundles

- `Docs/benchmarks/connected-lab/20260216-015505` (2026-02-16, current attached devices)
- `Docs/benchmarks/connected-lab/20260216-013705` (2026-02-16, prior same-day baseline)
- `Docs/benchmarks/connected-lab/20260212-053429` (2026-02-12, includes OnePlus and Xiaomi write `0x201D` case)

## Device Matrix

| Device | VID:PID | Current Result | Guide |
|---|---|---|---|
| Google Pixel 7 | `18d1:4ee1` | `class3-handshake` (open fails after claim) | [Pixel 7](google-pixel-7-4ee1.md) |
| Samsung Android | `04e8:6860` | `storage_gated` when open succeeds (`GetStorageIDs` returns zero) | [Samsung 6860](samsung-android-6860.md) |
| Xiaomi Mi Note 2 | `2717:ff40` | `storage_gated` in latest run (`storageCount=0`), historical write `0x201D` case documented | [Xiaomi ff40](xiaomi-mi-note-2-ff40.md) |
| OnePlus 3T | `2a70:f003` | Not present in latest run; last captured as `class3-handshake` | [OnePlus f003](oneplus-3t-f003.md) |

## Mode Labels Used in Guides

- `MTP (storage exposed)`: MTP session opens and at least one storage ID is returned.
- `MTP (storage gated)`: MTP session may open but `GetStorageIDs` returns none.
- `MTP (handshake blocked)`: interface is claimed but first command exchange fails.
- `PTP`: camera mode selected on device.
- `Charge-only`: no usable MTP/PTP interface.
