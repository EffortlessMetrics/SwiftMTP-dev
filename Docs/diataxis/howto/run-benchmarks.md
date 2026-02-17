# How to Run Benchmarks

This guide shows you how to measure SwiftMTP transfer performance on your devices.

## Why Benchmark?

Benchmarks help you:
- Measure actual transfer speeds
- Tune device-specific settings
- Compare devices
- Verify performance improvements

## Quick Start

### Using the Benchmark Script

```bash
# Run comprehensive benchmark
./scripts/benchmark-device.sh pixel7

# Or use CLI directly
swift run swiftmtp bench 1G
```

### Simple Benchmark

```bash
# Probe device first
swift run swiftmtp probe

# Run 1GB benchmark
swift run swiftmtp bench 1G --repeat 3
```

## Benchmark Commands

### Read Benchmark

```bash
# Test read speed
swift run swiftmtp bench 100M --direction read
swift run swiftmtp bench 500M --direction read
swift run swiftmtp bench 1G --direction read
```

### Write Benchmark

```bash
# Test write speed
swift run swiftmtp bench 100M --direction write
swift run swiftmtp bench 500M --direction write
swift run swiftmtp bench 1G --direction write
```

### Mirror Benchmark

```bash
# Test folder sync
swift run swiftmtp mirror ~/PhoneBackup --include "DCIM/**"
```

## Interpreting Results

### CSV Output Format

```csv
timestamp,operation,size_bytes,duration_seconds,speed_mbps
2026-02-08T10:30:00Z,read,1073741824,21.9,45.6
2026-02-08T10:30:30Z,read,1073741824,22.1,45.2
```

### Performance Metrics

| Metric | Description |
|--------|-------------|
| p50 | 50th percentile (median) speed |
| p95 | 95th percentile speed |
| Warmup | First run may be slower |

### Expected Performance

| USB Version | Expected Read | Expected Write |
|-------------|---------------|----------------|
| USB 2.0 | 12-20 MB/s | 10-15 MB/s |
| USB 3.0+ | 35-50 MB/s | 25-40 MB/s |

## Tuning Performance

### Adjust Chunk Size

```bash
# Try different chunk sizes
swift run swiftmtp bench 1G --chunk-size 1M
swift run swiftmtp bench 1G --chunk-size 4M
swift run swiftmtp bench 1G --chunk-size 16M
```

### Adjust Timeouts

```bash
# Increase timeouts for slow devices
export SWIFTMTP_IO_TIMEOUT_MS=60000
swift run swiftmtp bench 1G
```

### Device Quirks

Configure quirks in `Specs/quirks.json`:

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "quirks": {
    "maxChunkBytes": 4194304,
    "ioTimeoutMs": 30000,
    "stabilizeMs": 500
  }
}
```

## Full Test Protocol

For contribution-ready benchmarks:

1. **Run probe first**:
   ```bash
   swift run swiftmtp --real-only probe > probes/my-device.txt
   ```

2. **Collect device evidence**:
   ```bash
   swift run swiftmtp collect --strict --noninteractive
   ```

3. **Run smoke benchmark**:
   ```bash
   swift run swiftmtp bench 100M --repeat 3 --out benches/my-device-100m.csv
   ```

4. **Run full benchmarks**:
   ```bash
   for size in 100M 500M 1G; do
     swift run swiftmtp bench $size --repeat 3 --out benches/my-device-$size.csv
   done
   ```

5. **Verify redaction**:
   ```bash
   rg -n "Serial|/Users/|iSerial" benches/
   ```

## Troubleshooting

### Benchmark Fails to Start

- Verify device is connected: `swiftmtp probe`
- Check device is unlocked
- Ensure MTP mode is enabled

### Results Lower Than Expected

1. Use USB 3.0 port directly
2. Use a high-quality cable
3. Close other USB apps
4. Disable USB power saving

### Results Vary Wildly

- Run 3+ iterations
- Skip first run (warmup)
- Average p50 from runs 2-3

## Related Documentation

- [Benchmarks Overview](../../benchmarks.md)
- [Device Tuning Guide](../reference/../SwiftMTP.docc/DeviceTuningGuide.md)
- [Error Codes Reference](../reference/error-codes.md)

## Summary

You now know how to:
1. ✅ Run basic read/write benchmarks
2. ✅ Interpret benchmark results
3. ✅ Tune performance settings
4. ✅ Follow contribution-ready protocols
