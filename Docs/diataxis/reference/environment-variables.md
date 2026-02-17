# Environment Variables Reference

Complete reference for all SwiftMTP environment variables.

## General Configuration

### `SWIFTMTP_VERBOSE`

Enable verbose logging output.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |
| CLI Flag | `--verbose` |

```bash
# Enable verbose logging
export SWIFTMTP_VERBOSE=1
swift run swiftmtp ls
```

### `SWIFTMTP_LOG_LEVEL`

Set the logging level.

| Property | Value |
|----------|-------|
| Type | String |
| Default | `info` |
| Options | `trace`, `debug`, `info`, `warn`, `error` |

```bash
# Set to debug level
export SWIFTMTP_LOG_LEVEL=debug

# Set to error only
export SWIFTMTP_LOG_LEVEL=error
```

### `SWIFTMTP_LOG_FILE`

Write logs to a file.

| Property | Value |
|----------|-------|
| Type | Path |
| Default | None (stdout only) |

```bash
# Log to file
export SWIFTMTP_LOG_FILE=/tmp/swiftmtp.log
```

## Connection Settings

### `SWIFTMTP_IO_TIMEOUT_MS`

I/O operation timeout in milliseconds.

| Property | Value |
|----------|-------|
| Type | Integer (milliseconds) |
| Default | `15000` (15 seconds) |
| Range | 1000 - 600000 |

```bash
# 30 second timeout
export SWIFTMTP_IO_TIMEOUT_MS=30000

# 1 minute timeout for slow devices
export SWIFTMTP_IO_TIMEOUT_MS=60000
```

### `SWIFTMTP_CONNECT_TIMEOUT_MS`

Connection establishment timeout.

| Property | Value |
|----------|-------|
| Type | Integer (milliseconds) |
| Default | `10000` (10 seconds) |

```bash
export SWIFTMTP_CONNECT_TIMEOUT_MS=20000
```

### `SWIFTMTP_SESSION_TIMEOUT_MS`

Session keep-alive timeout.

| Property | Value |
|----------|-------|
| Type | Integer (milliseconds) |
| Default | `300000` (5 minutes) |

```bash
export SWIFTMTP_SESSION_TIMEOUT_MS=600000
```

## Transfer Settings

### `SWIFTMTP_CHUNK_SIZE`

Transfer chunk size in bytes.

| Property | Value |
|----------|-------|
| Type | Integer (bytes) |
| Default | `2097152` (2 MB) |
| Range | 65536 - 16777216 |

```bash
# 4 MB chunks
export SWIFTMTP_CHUNK_SIZE=4194304

# 1 MB chunks (for slow devices)
export SWIFTMTP_CHUNK_SIZE=1048576
```

### `SWIFTMTP_MAX_CHUNK_BYTES`

Maximum chunk size for fallbacks.

| Property | Value |
|----------|-------|
| Type | Integer (bytes) |
| Default | `4194304` (4 MB) |

```bash
export SWIFTMTP_MAX_CHUNK_BYTES=8388608
```

### `SWIFTMTP_BUFFER_SIZE`

Internal buffer size.

| Property | Value |
|----------|-------|
| Type | Integer (bytes) |
| Default | `65536` (64 KB) |

```bash
# Larger buffer
export SWIFTMTP_BUFFER_SIZE=131072
```

### `SWIFTMTP_PARALLEL_TRANSFERS`

Number of parallel transfer operations.

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `2` |
| Range | 1 - 16 |

```bash
# Single transfer
export SWIFTMTP_PARALLEL_TRANSFERS=1

# Parallel transfers
export SWIFTMTP_PARALLEL_TRANSFERS=4
```

### `SWIFTMTP_PARALLEL_DIRECTORIES`

Number of parallel directory scans.

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `2` |

```bash
export SWIFTMTP_PARALLEL_DIRECTORIES=4
```

## Retry Settings

### `SWIFTMTP_MAX_RETRIES`

Maximum number of retry attempts.

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `3` |
| Range | 0 - 10 |

```bash
# No retries
export SWIFTMTP_MAX_RETRIES=0

# More retries
export SWIFTMTP_MAX_RETRIES=5
```

### `SWIFTMTP_RETRY_DELAY_MS`

Delay between retries in milliseconds.

| Property | Value |
|----------|-------|
| Type | Integer (milliseconds) |
| Default | `1000` (1 second) |

```bash
# 2 second delay
export SWIFTMTP_RETRY_DELAY_MS=2000
```

### `SWIFTMTP_RETRY_BACKOFF`

Exponential backoff multiplier.

| Property | Value |
|----------|-------|
| Type | Float |
| Default | `2.0` |

```bash
# Exponential backoff
export SWIFTMTP_RETRY_BACKOFF=2.0
```

## Demo and Testing

### `SWIFTMTP_DEMO_MODE`

Enable demo mode with mock devices.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |
| CLI Flag | `--demo` |

```bash
# Enable demo mode
export SWIFTMTP_DEMO_MODE=1
swift run swiftmtp ls
```

### `SWIFTMTP_MOCK_PROFILE`

Use a specific mock device profile.

| Property | Value |
|----------|-------|
| Type | String |

```bash
# Use Pixel 7 mock
export SWIFTMTP_MOCK_PROFILE=pixel7

# Use Samsung mock
export SWIFTMTP_MOCK_PROFILE=samsung
```

### `SWIFTMTP_REAL_ONLY`

Fail if no real device is connected.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |
| CLI Flag | `--real-only` |

```bash
export SWIFTMTP_REAL_ONLY=1
```

## Debugging

### `SWIFTMTP_TRACE_USB`

Enable USB protocol tracing.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
# Enable USB tracing
export SWIFTMTP_TRACE_USB=1
swift run swiftmtp probe
```

### `SWIFTMTP_TRACE_MTP`

Enable MTP protocol tracing.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_TRACE_MTP=1
```

### `SWIFTMTP_TRACE_TRANSFER`

Enable transfer tracing.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_TRACE_TRANSFER=1
```

### `SWIFTMTP_DUMP_DIR`

Directory for debug dumps.

| Property | Value |
|----------|-------|
| Type | Path |

```bash
export SWIFTMTP_DUMP_DIR=/tmp/swiftmtp-dumps
```

## Device Quirks

### `SWIFTMTP_FORCE_CHUNKED`

Force chunked transfer mode.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_FORCE_CHUNKED=1
```

### `SWIFTMTP_DISABLE_PARTIAL`

Disable partial object transfers.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_DISABLE_PARTIAL=1
```

### `SWIFTMTP_VENDOR_OVERRIDE`

Override vendor ID detection.

| Property | Value |
|----------|-------|
| Type | Integer (hex) |

```bash
# Force vendor ID
export SWIFTMTP_VENDOR_OVERRIDE=0x18d1
```

### `SWIFTMTP_PRODUCT_OVERRIDE`

Override product ID detection.

| Property | Value |
|----------|-------|
| Type | Integer (hex) |

```bash
export SWIFTMTP_PRODUCT_OVERRIDE=0x4ee1
```

## Cache Settings

### `SWIFTMTP_CACHE_DIR`

Directory for cache files.

| Property | Value |
|----------|-------|
| Type | Path |
| Default | `~/Library/Caches/SwiftMTP` |

```bash
export SWIFTMTP_CACHE_DIR=/tmp/swiftmtp-cache
```

### `SWIFTMTP_CACHE_TTL`

Cache time-to-live in seconds.

| Property | Value |
|----------|-------|
| Type | Integer |
| Default | `3600` (1 hour) |

```bash
# 24 hour cache
export SWIFTMTP_CACHE_TTL=86400
```

### `SWIFTMTP_DISABLE_CACHE`

Disable all caching.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_DISABLE_CACHE=1
```

## Performance

### `SWIFTMTP_USE_SENDFILE`

Use sendfile for transfers (macOS).

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `true` |

```bash
# Disable sendfile
export SWIFTMTP_USE_SENDFILE=0
```

### `SWIFTMTP_DIRECT_IO`

Use direct I/O (bypass buffer cache).

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `false` |

```bash
export SWIFTMTP_DIRECT_IO=1
```

### `SWIFTMTP_PREFETCH`

Enable directory prefetching.

| Property | Value |
|----------|-------|
| Type | Boolean |
| Default | `true` |

```bash
export SWIFTMTP_PREFETCH=0
```

## Summary Table

| Variable | Default | Type |
|----------|---------|------|
| `SWIFTMTP_VERBOSE` | `false` | Boolean |
| `SWIFTMTP_LOG_LEVEL` | `info` | String |
| `SWIFTMTP_LOG_FILE` | - | Path |
| `SWIFTMTP_IO_TIMEOUT_MS` | `15000` | Integer |
| `SWIFTMTP_CHUNK_SIZE` | `2097152` | Integer |
| `SWIFTMTP_PARALLEL_TRANSFERS` | `2` | Integer |
| `SWIFTMTP_MAX_RETRIES` | `3` | Integer |
| `SWIFTMTP_DEMO_MODE` | `false` | Boolean |
| `SWIFTMTP_TRACE_USB` | `false` | Boolean |
| `SWIFTMTP_TRACE_MTP` | `false` | Boolean |
| `SWIFTMTP_CACHE_DIR` | `~/Library/Caches/SwiftMTP` | Path |

## Related Documentation

- [CLI Commands Reference](cli-commands.md)
- [Configuration Reference](configuration.md)
- [Performance Tuning](../howto/performance-tuning.md)
- [Logging and Debugging](../howto/logging-debugging.md)
