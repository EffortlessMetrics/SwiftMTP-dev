# SwiftMTP Benchmark Report
Device: oneplus-3t
Model: ONEPLUS A3010
Timestamp: Sat Feb  7 03:58:00 EST 2026
Mode: PENDING (waiting for real device)

## Device Information
```
📱 Device Information:
   Manufacturer: OnePlus
   Model: ONEPLUS A3010
   Version: 1.0
   Serial Number: 5dfe2dc2
```

## ⚠️ Benchmark Pending

This report is a template pending real device benchmarks.

### Expected Performance Characteristics

The OnePlus 3T is expected to show typical mid-2010s Android device performance:
- USB 2.0 High-Speed interface
- MTP/PTP protocol support
- No external SD card slot

### Benchmark Schedule

| Test | Status | Expected | Actual |
|------|--------|----------|--------|
| 100m Transfer | ⏳ Pending | ~5-10 MB/s | TBD |
| 500m Transfer | ⏳ Pending | ~5-10 MB/s | TBD |
| 1g Transfer | ⏳ Pending | ~5-10 MB/s | TBD |
| Mirror Test | ⏳ Pending | Baseline | TBD |

### Known Quirks (from snapshot analysis)

Based on the device snapshot, the OnePlus 3T shows:
- 37 supported MTP operations
- Standard MTP event support
- Vendor-specific operations present (0x95C1-0x95CD)

### To Run Benchmarks

```bash
./scripts/benchmark-device.sh oneplus-3t
```

### After Running Benchmarks

Update `latest/` symlink to point to the new benchmark directory:
```bash
cd Docs/benchmarks/oneplus-3t
rm latest
ln -s YYYYMMDD-HHMMSS/ latest
```

---

*Generated from snapshot-OnePlus-ONEPLUS_A3010.json*
*Real benchmarks required to complete this report*
