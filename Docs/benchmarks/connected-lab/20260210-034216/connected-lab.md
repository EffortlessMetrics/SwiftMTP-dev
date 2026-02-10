# Connected Device Lab Report

- Generated: 2026-02-10T08:42:39Z
- Output: `/Users/steven/Code/Mac/Swift/SwiftMTP/Docs/benchmarks/connected-lab/20260210-034216`
- Devices: 3 (passed: 0, partial: 1, blocked: 1, failed: 1)
- Missing expected VID:PID: 2717:ff40

| VID:PID | Device | Expected | Outcome | Read | Write | Notes |
|---|---|---|---|---|---|---|
| 04e8:6860 | SAMSUNG SAMSUNG_Android | read-best-effort | failed | partial | skipped | open failed: io("no MTP interface responded to probe") |
| 18d1:4ee1 | Google Pixel 7 | blocker-expected | blocked | partial | skipped | Expected blocker observed; diagnostics captured without crash.; open failed: io("no MTP interface responded to probe") |
| 2a70:f003 | Android Android | probe-no-crash | partial | partial | skipped | No fatal trap observed; interface probe remained non-crashing.; open failed: io("no MTP interface responded to probe") |
