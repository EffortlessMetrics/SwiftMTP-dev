# Connected Device Lab Report

- Generated: 2026-02-09T10:53:26Z
- Output: `/Users/steven/Code/Mac/Swift/SwiftMTP/Docs/benchmarks/connected-lab/20260209-055224`
- Devices: 4 (passed: 1, partial: 1, blocked: 1, failed: 1)

| VID:PID | Device | Expected | Outcome | Read | Write | Notes |
|---|---|---|---|---|---|---|
| 04e8:6860 | SAMSUNG SAMSUNG_Android | read-best-effort | failed | partial | skipped | open failed: io("no MTP interface responded to probe") |
| 18d1:4ee1 | Google Pixel 7 | blocker-expected | blocked | partial | skipped | Expected blocker observed; diagnostics captured without crash.; open failed: io("no MTP interface responded to probe") |
| 2717:ff40 | Xiaomi Mi Note 2 | full-exercise | partial | ok | failed | createFolder failed: protocolError(code: 8221, message: Optional("InvalidParameter (0x201d)")) |
| 2a70:f003 | Android Android | probe-no-crash | passed | ok | failed | createFolder failed: protocolError(code: 8221, message: Optional("InvalidParameter (0x201d)")) |
