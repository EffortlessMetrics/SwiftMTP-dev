# Device Quirks System

This document explains SwiftMTP's device quirks system for handling device-specific behaviors.

## Why Quirks?

MTP devices vary significantly in their implementation:

- **Different timeout requirements** - Some devices are slower
- **Maximum transfer sizes** - Chunk size limits
- **Special commands** - Device-specific operations
- **Behavior quirks** - Workarounds for bugs

The quirks system handles these variations gracefully.

## Quirk Configuration

### Basic Structure

```json
{
  "vid": "0x18d1",
  "pid": "0x4ee1",
  "description": "Google Pixel 7",
  "quirks": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 30000,
    "stabilizeMs": 2000
  }
}
```

### Quirk Options

| Quirk | Type | Description | Default |
|-------|------|-------------|---------|
| `maxChunkBytes` | Int | Maximum transfer chunk | 4 MB |
| `handshakeTimeoutMs` | Int | Session open timeout | 10000 |
| `ioTimeoutMs` | Int | Transfer timeout | 15000 |
| `stabilizeMs` | Int | Post-open delay | 0 |
| `resetOnOpen` | Bool | Reset device on open | false |
| `hooks` | Array | Custom delay hooks | [] |

### Hooks

Hooks allow custom behavior at specific phases:

```json
{
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 500 },
    { "phase": "preGetStorageIDs", "busyBackoff": { "retries": 3, "baseMs": 200 } }
  ]
}
```

### Hook Phases

| Phase | Description |
|-------|-------------|
| `postOpenSession` | After opening session |
| `preGetStorageIDs` | Before storage enumeration |
| `postGetStorageIDs` | After storage enumeration |
| `preGetObjectHandles` | Before listing objects |
| `postGetObjectHandles` | After listing objects |

### Busy Backoff

Handle `DEVICE_BUSY` errors with retry:

```json
{
  "busyBackoff": {
    "retries": 3,
    "baseMs": 200,
    "jitterPct": 0.2
  }
}
```

## Quirk Resolution

### Automatic Detection

```swift
let resolver = QuirkResolver()

// Resolve based on VID/PID
let quirks = try await resolver.resolve(
    vid: 0x18d1,
    pid: 0x4ee1
)

// Or use learned profile
let learned = try await resolver.resolveLearned(
    deviceId: "unique-device-id"
)
```

### Resolution Priority

1. **Exact match** - VID + PID (highest priority)
2. **Learned profile** - From previous sessions
3. **Defaults** - Built-in fallback

## Static vs Learned Quirks

### Static Quirks

Pre-configured in `Specs/quirks.json`:

```json
{
  "vid": "0x2a70",
  "pid": "0xf003",
  "description": "OnePlus 3T",
  "quirks": {
    "maxChunkBytes": 1048576,
    "stabilizeMs": 200
  }
}
```

### Learned Profiles

Auto-generated from device behavior:

```json
{
  "deviceId": "unique-serial",
  "learnedAt": "2026-02-16T10:00:00Z",
  "observed": {
    "avgResponseTimeMs": 150,
    "maxChunkUsed": 2097152,
    "supportsPartial": true
  }
}
```

## Adding Custom Quirks

### Via Configuration File

Edit `Specs/quirks.json`:

```json
{
  "vid": "0x1234",
  "pid": "0x5678",
  "description": "My Custom Device",
  "quirks": {
    "maxChunkBytes": 1048576,
    "handshakeTimeoutMs": 15000,
    "ioTimeoutMs": 30000,
    "stabilizeMs": 500
  }
}
```

### Via API

```swift
var config = SwiftMTPConfig()
config.quirks = DeviceQuirks(
    maxChunkBytes: 2 * 1024 * 1024,
    ioTimeoutMs: 20000,
    stabilizeMs: 500
)

try await manager.startDiscovery(config: config)
```

## Known Device Quirks

### Google Pixel 7

```json
{
  "maxChunkBytes": 2097152,
  "handshakeTimeoutMs": 20000,
  "ioTimeoutMs": 30000,
  "stabilizeMs": 2000
}
```

### OnePlus 3T

```json
{
  "maxChunkBytes": 1048576,
  "handshakeTimeoutMs": 6000,
  "ioTimeoutMs": 8000,
  "stabilizeMs": 200,
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 1000 }
  ]
}
```

### Xiaomi Mi Note 2

```json
{
  "maxChunkBytes": 2097152,
  "handshakeTimeoutMs": 6000,
  "ioTimeoutMs": 15000,
  "stabilizeMs": 400,
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 400 },
    { "phase": "preGetStorageIDs", "busyBackoff": { "retries": 3, "baseMs": 200 } }
  ]
}
```

## Troubleshooting

### Symptoms

| Symptom | Likely Quirk |
|---------|--------------|
| Timeout on open | Increase `handshakeTimeoutMs` |
| Timeout on transfer | Increase `ioTimeoutMs` |
| Intermittent failures | Add `stabilizeMs` |
| DEVICE_BUSY errors | Add busy backoff |

### Tuning Steps

1. Start with defaults
2. Test with small transfers
3. Increase timeouts if needed
4. Add stabilization delays
5. Record quirks for future use

## See Also

- [Add Device Support](../howto/add-device-support.md)
- [Device Tuning Guide](../../SwiftMTP.docc/DeviceTuningGuide.md)
- [Benchmarks Overview](../../benchmarks.md)
