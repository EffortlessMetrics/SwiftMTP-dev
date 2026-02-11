# Troubleshooting

## Device not detected

- Unlock device and set USB mode to **File Transfer (MTP)**.
- Try a different cable/port (avoid unpowered hubs).

## Slow transfers

- Check USB2 vs USB3 connection.
- See `swift run swiftmtp bench 1G`; tuner should step up chunk size.

## Resume not working

- Your device may not advertise `GetPartialObject64`; reads restart by design.

## `events` exits with code 69

- No matching device present or filter did not match. Ensure device is connected and set to **File Transfer (MTP)**, or specify targeting flags like `--vid/--pid`.
- Prefer explicit hex for targeting flags (for example `--vid 0x2717 --pid 0xff40`).

## Connected-lab diagnostics

- Run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json` to produce per-device diagnostics.
- Artifacts are written to `Docs/benchmarks/connected-lab/<timestamp>/`.
- Pixel 7 (`18d1:4ee1`) is currently expected to report as a blocker in this workflow (diagnostic evidence only).
