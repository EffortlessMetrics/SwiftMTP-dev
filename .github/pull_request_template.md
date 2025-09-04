<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (c) 2025 Effortless Metrics, Inc. -->

## Why
Context + problem statement. Explain the device-specific issue this PR addresses and why the current behavior is inadequate.

## What
Summary of changes. Describe what was modified in the codebase.

## Device Impact
- [ ] **New device support**: Added quirk for `<device-model>` with VID:PID `<vid:pid>`
- [ ] **Existing device fix**: Updated tuning for `<device-model>` to address `<specific-issue>`
- [ ] **Performance improvement**: `<X>`% faster transfer speeds for `<device-model>`
- [ ] **Compatibility fix**: Resolved `<issue>` affecting `<device-model>` on `<OS/version>`

## Evidence Required
- [ ] **Quirk validation passed**: `./scripts/validate-quirks.sh`
- [ ] **Benchmarks meet gates**: All declared performance thresholds satisfied
- [ ] **Device probe artifacts**: `Docs/benchmarks/probes/<device>-probe.txt` updated
- [ ] **Benchmark results**: `Docs/benchmarks/csv/<device>-<size>.csv` added/updated
- [ ] **Mirror log**: `Docs/benchmarks/logs/<device>-mirror.log` captured
- [ ] **USB dump**: `Docs/benchmarks/probes/<device>-usb-dump.txt` updated
- [ ] **DocC updated**: `./scripts/validate-quirks.sh` confirms documentation freshness

## Testing
- [ ] Unit tests pass for new quirk logic
- [ ] Integration tests pass with device attached
- [ ] CLI `--json` output validated for new device
- [ ] `swift run swiftmtp quirks --explain` shows expected layer configuration
- [ ] Manual testing completed on target device

## Schema Changes
- [ ] **No breaking changes**: Fully backward compatible
- [ ] **New optional fields**: Added `<field>` with default `<value>`
- [ ] **New required fields**: Added `<field>` (breaks existing configs)
- [ ] **Schema version bump**: Updated to `<version>` with migration guide

## Risk & Rollback
**Risk Level**: [ ] Low [ ] Medium [ ] High [ ] Critical

**Feature Flags**: [ ] Available [ ] Not applicable [ ] Required for safe deploy

**Rollback Steps**:
1. Revert commit `<hash>`
2. Remove quirk entry `<id>` from `Specs/quirks.json`
3. Regenerate DocC: `./scripts/validate-quirks.sh`

**Monitoring**: [ ] Add metrics for `<device-performance>` [ ] Update SLOs [ ] No changes needed

## Performance Impact
**Benchmark Results**:
- Read throughput: `<before>` → `<after>` MB/s (`<+/-X%>` change)
- Write throughput: `<before>` → `<after>` MB/s (`<+/-X%>` change)
- Stability: `<error-rate-before>` → `<error-rate-after>` (`<+/-X%>` change)

**Gate Compliance**: [ ] All declared gates met [ ] Gates updated for new baseline [ ] Gates waived (explain why)

## Documentation
- [ ] DocC pages regenerated for `<device-model>`
- [ ] Troubleshooting guide updated if needed
- [ ] CLI help updated for new flags/options
- [ ] Release notes include device-specific behavior changes

## ADR
Link or new ADR ID: [ADR-XXX](link-to-adr) - `<brief-description>`

**Architecture Impact**: [ ] None [ ] Minor [ ] Major [ ] Breaking

## Checklist
- [ ] `./scripts/validate-quirks.sh` passes (run with `CI=true` for strict validation)
- [ ] `swift run swiftmtp quirks --explain` shows correct layer merge order
- [ ] All evidence artifacts committed and referenced
- [ ] Schema validation passes with updated JSON Schema
- [ ] No lint errors introduced
- [ ] Tests updated and passing
- [ ] Documentation reviewed and approved

---

**Evidence Links** (auto-populated by CI):
- Benchmark CSV: [link]
- Probe JSON: [link]
- Validation Report: [link]

---

*This PR follows the [SwiftMTP Device Tuning Guide](Docs/SwiftMTP.docc/DeviceTuningGuide.md) and includes all required evidence for device-specific changes.*
