# Connected Device Lab Report

- Generated: 2026-02-10T08:30:26Z
- Output: `/Users/steven/Code/Mac/Swift/SwiftMTP/Docs/benchmarks/connected-lab/20260210-032839`
- Devices: 3 (passed: 1, partial: 0, blocked: 1, failed: 1)
- Missing expected VID:PID: 2717:ff40

| VID:PID | Device | Expected | Outcome | Read | Write | Notes |
|---|---|---|---|---|---|---|
| 04e8:6860 | SAMSUNG SAMSUNG_Android | read-best-effort | failed | partial | skipped | open failed: io("no MTP interface responded to probe") |
| 18d1:4ee1 | Google Pixel 7 | blocker-expected | blocked | partial | skipped | Expected blocker observed; diagnostics captured without crash.; open failed: io("no MTP interface responded to probe") |
| 2a70:f003 | Android Android | probe-no-crash | passed | ok | failed | write to Download failed: protocolError(code: 8221, message: Optional("InvalidParameter (0x201d)")) |
