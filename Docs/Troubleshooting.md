# Troubleshooting

## Device not detected

- Unlock device and set USB mode to **File Transfer (MTP)**.
- Try a different cable/port (avoid unpowered hubs).

## Slow transfers

- Check USB2 vs USB3 connection.
- See `swift run --package-path SwiftMTPKit swiftmtp bench 1G`; tuner should step up chunk size.

## Resume not working

- Your device may not advertise `GetPartialObject64`; reads restart by design.

## `events` exits with code 69

- No matching device present or filter did not match. Ensure device is connected and set to **File Transfer (MTP)**, or specify targeting flags like `--vid/--pid`.
- Prefer explicit hex for targeting flags (for example `--vid 0x2717 --pid 0xff40`).

## Connected-lab diagnostics

- Run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json` to produce per-device diagnostics.
- Artifacts are written to `Docs/benchmarks/connected-lab/<timestamp>/`.
- Use `./scripts/device-bringup.sh --mode <label>` to capture `system_profiler`, `usb-dump`, and `device-lab` artifacts in one run folder.
- See `Docs/device-bringup.md` for the `(device × mode × operation)` certification matrix and failure taxonomy.

## Troubleshooting decision trees

### 1) No device is detected

- Run `swift run --package-path SwiftMTPKit swiftmtp --real-only probe`.
- If probe output is "No MTP device connected", then:
  - Keep the device unlocked and on **File Transfer (MTP)**.
  - Verify USB cable/port and disable hub/charging-only adapters.
  - Re-run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json` to confirm discovery.
- If it still fails, close competing USB apps (`Android File Transfer`, browser USB stacks, adb), disconnect/replug, then retry.

### 2) `Write`/`push` returns `0x201D` or `Object_Too_Large`

- Retry the same command with safe folder selection.
  - For CLI `push`, specify `0` or a folder name rather than a root handle.
  - For benchmarks, ensure the run logs show `SwiftMTPBench` creation under `Download`/`DCIM`.
- If `0x201D` repeats:
  - Capture `swift run --package-path SwiftMTPKit swiftmtp --real-only collect --strict` and confirm `usb-dump.txt` is valid.
  - Check the target's quirk notes for folder-only write requirements (`WriteTargetLadder`).

### 3) `usb-dump`/`collect` contains obvious serial or path data

- Re-run with `--strict`.
- Inspect artifact patterns:
  - `Serial Number`, `iSerial`, `/Users/<...>`, UUID/mac/IP, email-like tokens.
- If found, treat as a redaction failure and rerun from scratch on an updated branch.

### 4) Mirror or bench stops after first pass

- Expect pass #1 to be warmup in bench workflows.
- Re-run with longer timeout and explicit repeat:
  - `swift run --package-path SwiftMTPKit swiftmtp --real-only bench 1G --repeat 3 --out benches/<name>-1g.csv`
- If only second pass fails, compare `swift run ... usb-dump` output around timeout path.

### 5) Pixel 7 Tahoe 26 behavior

- Known blocker: macOS Tahoe USB stack timing on this hardware path.
- Keep `stabilizeMs` elevated and treat `LIBUSB_ERROR_TIMEOUT` as a transport layer symptom.
- Use a direct port and run `swift run --package-path SwiftMTPKit swiftmtp --real-only probe` before benchmarking.

## collect + benchmark troubleshooting flow

Use this order whenever debugging a failing submission workflow:

1. Run probe: `swift run --package-path SwiftMTPKit swiftmtp --real-only probe`.
2. Capture evidence: `swift run --package-path SwiftMTPKit swiftmtp collect --strict --json --noninteractive`.
3. Verify artifacts:
   - `submission.json` exists.
   - `usb-dump.txt` contains only redacted placeholders.
4. Run single-size check: `swift run --package-path SwiftMTPKit swiftmtp --real-only bench 100M --out /tmp/bench-100m.csv`.
5. If check passes, run `500M` then `1G` with `--repeat 3`.
6. If either flow fails, attach `probe`, `usb-dump`, and command output to the issue/PR.

## Sprint issue evidence minimum

When opening or updating a sprint issue for transport/submission failures, include:

- failing command and exact exit code
- one artifact folder path under `Docs/benchmarks/device-bringup/` or `Docs/benchmarks/connected-lab/`
- one sentence describing expected behavior vs actual behavior
