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
