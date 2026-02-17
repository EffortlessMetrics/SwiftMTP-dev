# CLI Command Reference

Complete reference for the SwiftMTP command-line tool.

## Synopsis

```bash
swift run swiftmtp <command> [options]
```

## Global Options

| Option | Description |
|--------|-------------|
| `--help` | Show help message |
| `--version` | Show version |
| `--verbose` | Enable verbose output |
| `--real-only` | Fail if no real device connected |

## Commands

### probe

Discover and list connected MTP devices.

```bash
swift run swiftmtp probe [options]
```

**Options:**
- `--verbose` - Show detailed device info

**Example:**
```bash
swift run swiftmtp probe
# Output:
# [INFO] Found device: Google Pixel 7 (18d1:4ee1)
```

---

### ls

List files on device.

```bash
swift run swiftmtp ls [path] [options]
```

**Arguments:**
- `path` - Device path (default: root)

**Options:**
- `--json` - JSON output

**Example:**
```bash
swift run swiftmtp ls /DCIM
swift run swiftmtp ls /Download --json
```

---

### pull

Download files from device.

```bash
swift run swiftmtp pull <device-path> [options]
```

**Arguments:**
- `device-path` - Path on device

**Options:**
- `-o, --output <dir>` - Output directory
- `-v, --verbose` - Show progress

**Example:**
```bash
swift run swiftmtp pull /DCIM/photo.jpg
swift run swiftmtp pull /DCIM/photo.jpg --output ~/Desktop/
```

---

### push

Upload files to device.

```bash
swift run swiftmtp push <local-path> [options]
```

**Arguments:**
- `local-path` - Local file path

**Options:**
- `-t, --to <path>` - Destination folder
- `-n, --name <name>` - Destination filename

**Example:**
```bash
swift run swiftmtp push ~/photo.jpg
swift run swiftmtp push ~/photo.jpg --to /Download
```

---

### rm

Delete file from device.

```bash
swift run swiftmtp rm <device-path>
```

**Example:**
```bash
swift run swiftmtp rm /Download/test.txt
```

---

### mirror

Mirror device folder to local directory.

```bash
swift run swiftmtp mirror <device-path> [options]
```

**Arguments:**
- `device-path` - Source folder on device
- `local-path` - Destination local folder

**Options:**
- `-i, --include <pattern>` - Include pattern (can repeat)
- `-e, --exclude <pattern>` - Exclude pattern (can repeat)

**Example:**
```bash
swift run swiftmtp mirror /DCIM --to ~/MTP-Backup/DCIM
swift run swiftmtp mirror /Pictures --to ~/Backup --include "*.jpg"
```

---

### bench

Run transfer benchmarks.

```bash
swift run swiftmtp bench <size> [options]
```

**Arguments:**
- `size` - Test size (100M, 500M, 1G)

**Options:**
- `-d, --direction <read|write>` - Direction (default: read)
- `-r, --repeat <n>` - Number of runs (default: 1)
- `-o, --out <file>` - Output CSV file

**Example:**
```bash
swift run swiftmtp bench 1G
swift run swiftmtp bench 1G --direction write --repeat 3
swift run swiftmtp bench 500M --out results.csv
```

---

### snapshot

Create device snapshot.

```bash
swift run swiftmtp snapshot [options]
```

**Options:**
- `-o, --output <dir>` - Output directory

**Example:**
```bash
swift run swiftmtp snapshot --output ~/snapshots/
```

---

### device-info

Show detailed device information.

```bash
swift run swiftmtp device-info
```

**Example:**
```bash
swift run swiftmtp device-info
# Output:
# Manufacturer: Google
# Model: Pixel 7
# Serial: <redacted>
# Version: 1.0
```

---

### quirks

Show device quirks configuration.

```bash
swift run swiftmtp quirks [options]
```

**Options:**
- `--explain` - Show detailed explanation

**Example:**
```bash
swift run swiftmtp quirks --explain
```

---

### events

Monitor device events.

```bash
swift run swiftmtp events [options]
```

**Options:**
- `--json` - JSON output

**Example:**
```bash
swift run swiftmtp events
```

---

### usb-dump

Dump USB device information.

```bash
swift run swiftmtp usb-dump
```

**Example:**
```bash
swift run swiftmtp usb-dump > usb-info.txt
```

---

### device-lab

Run automated device testing matrix.

```bash
swift run swiftmtp device-lab [command] [options]
```

**Commands:**
- `connected` - Test all connected devices

**Options:**
- `--json` - JSON output

**Example:**
```bash
swift run swiftmtp device-lab connected --json
```

---

### collect

Collect device evidence for submission.

```bash
swift run swiftmtp collect [options]
```

**Options:**
- `--strict` - Enable strict redaction checks
- `--noninteractive` - Non-interactive mode
- `--bundle <path>` - Output bundle path

**Example:**
```bash
swift run swiftmtp collect --strict --noninteractive
swift run swiftmtp collect --bundle ../Contrib/submissions/my-device
```

---

### wizard

Interactive guided device setup.

```bash
swift run swiftmtp wizard
```

**Example:**
```bash
swift run swiftmtp wizard
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 69 | No device found |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SWIFTMTP_DEMO_MODE` | Enable demo mode | - |
| `SWIFTMTP_MOCK_PROFILE` | Mock device profile | - |
| `SWIFTMTP_IO_TIMEOUT_MS` | Transfer timeout (ms) | 15000 |
| `SWIFTMTP_MAX_CHUNK_BYTES` | Max chunk size | 4194304 |

## See Also

- [API Overview](api-overview.md)
- [Error Codes](error-codes.md)
- [Benchmarks Guide](../howto/run-benchmarks.md)
