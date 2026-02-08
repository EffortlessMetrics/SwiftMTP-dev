# OnePlus 3T (ONEPLUS A3010)

@Metadata {
    @DisplayName: "OnePlus 3T (ONEPLUS A3010)"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for the OnePlus 3T (ONEPLUS A3010) MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Manufacturer | OnePlus |
| Model | ONEPLUS A3010 |
| Vendor ID | 0x2a70 |
| Product ID | 0xf003 |
| Quirk ID | `oneplus-3t-f003` |
| Status | Stable |
| Confidence | High |

## Interfaces

### Interface 0 -- MTP

| Property | Value |
|----------|-------|
| Class | 0x06 (Still Image / PTP) |
| Subclass | 0x01 |
| Protocol | 0x01 |
| Endpoint In | 0x81 |
| Endpoint Out | 0x01 |
| Endpoint Event | 0x82 |

### Interface 1 -- Mass Storage

| Property | Value |
|----------|-------|
| Class | 0x08 (Mass Storage) |
| Subclass | 0x06 |
| Protocol | 0x50 |

## Capabilities

| Capability | Supported |
|------------|-----------|
| Partial Read | Yes |
| Partial Write | Yes |
| Events | Yes |
| PTP Device Reset (0x66) | No (rc=-9) |

### Fallbacks

| Fallback | Strategy |
|----------|----------|
| Enumeration | propList5 |
| Read | partial64 |
| Write | partial |

### MTP Operations

- 33 operations supported
- 6 events supported

## Storage

| Property | Value |
|----------|-------|
| Count | 1 (internal) |
| Total Capacity | 113.1 GB |

## Session Management

- **resetOnOpen**: false (new claim sequence eliminates need for USB reset)
- CloseSession fallback used to clear stale sessions
- Session establishment: 0ms, no retry needed

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 8000 | ms |
| Stabilization Delay | 200 | ms |

## Probe Performance

| Metric | Value |
|--------|-------|
| Pass 1 Probe Time | ~115ms |

## Benchmark Notes

- `SendObject` returns `0x201D` (`Object_Too_Large`) for bench writes -- needs investigation.
- Benchmark data for write throughput is not yet available due to this issue.

## Notes

- Device presents dual interfaces: MTP (iface 0) and Mass Storage (iface 1).
- No USB reset required; the new claim sequence handles session recovery via CloseSession fallback.
- Stabilization delay reduced from 1000ms to 200ms based on real device testing.
- Timeouts reduced significantly from initial conservative values (handshake 15s -> 6s, I/O 30s -> 8s).

## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-08
- **Commit**: HEAD

### Evidence Artifacts

- `Docs/benchmarks/probes/oneplus3t-probe-debug.txt` -- Full debug probe output
- `Docs/benchmarks/probes/oneplus3t-probe.json` -- Structured probe data (JSON)
- `Docs/benchmarks/probes/oneplus3t-ls.txt` -- Device file listing
