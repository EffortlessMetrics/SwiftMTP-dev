## What changed

- [ ] New/edited quirk: `<quirk-id>` (or N/A for non-quirk changes)
- [ ] Evidence artifacts added under `Docs/benchmarks/{probes,csv,logs}`
- [ ] DocC regenerated with `./scripts/validate-quirks.sh`
- [ ] Tests added/updated for new functionality

## Why it's safe

- [ ] Probe JSON attached shows device capabilities and quirks match
- [ ] Bench CSV meets gates (read ≥ X MB/s, write ≥ Y MB/s declared in quirk)
- [ ] Hooks scoped to specific phases (no blanket delays or retries)
- [ ] Learned profiles use exponential moving averages with schema bounds
- [ ] Backward compatibility maintained (semver appropriate)

## Checklist

- [ ] `./scripts/validate-quirks.sh` passes
- [ ] `swift run swiftmtp quirks --explain` shows expected layers and deltas
- [ ] `swift run swiftmtp health` passes (for operational changes)
- [ ] CI green on all gates (evidence, bench, docc, lint)
- [ ] Manual testing with target device(s)

## Risk & Rollback

**Risk Level:** Low / Medium / High

**Rollback Plan:**
- Revert this PR
- Or use `SWIFTMTP_DENY_QUIRKS=<quirk-id>` to disable problematic quirks
- Or use `--strict` mode to bypass learned/quirk layers entirely

## Evidence

### Benchmark Results
```
Device: <device-name>
Read: X.X MB/s (gate: ≥ Y.Y MB/s) ✅
Write: Z.Z MB/s (gate: ≥ W.W MB/s) ✅
```

### Probe Output
```json
{
  "schemaVersion": "1.0.0",
  "type": "probeResult",
  "fingerprint": {...},
  "capabilities": {...},
  "effective": {...},
  "quirks": [...]
}
```

### Layers Applied
```
Layers:
  defaults
  capabilityProbe (partialRead=yes, partialWrite=yes)
  learnedProfile (chunk=2MiB, ioTimeout=12s)
  quirk <quirk-id> (postOpenSession +400ms, busyBackoff 3×200ms)
  userOverrides (none)
```

## Docs
- [ ] Updated DocC with new device guide
- [ ] Exit codes documented in CLI help
- [ ] USB invariants documented for future maintainers
- [ ] PR template updated if needed

## ADR
Link or new ADR ID for architecture-impacting changes: [ADR-XXX](link)