# SwiftMTP CLI Command Map

> Comprehensive reference for all `swiftmtp` CLI commands, global flags, and usage patterns.
> Last updated: Wave 44

---

## Quick Start

```bash
cd SwiftMTPKit
swift run swiftmtp --help        # Show all commands
swift run swiftmtp probe         # Discover connected devices
swift run swiftmtp ls 65537      # List files on storage
```

---

## Device Discovery & Diagnostics

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `probe` | `swiftmtp probe` | Detect and display MTP device info | ✅ Implemented |
| `usb-dump` | `swiftmtp usb-dump` | Dump raw USB interface descriptors | ✅ Implemented |
| `diag` | `swiftmtp diag` | Run probe + usb-dump combined diagnostics | ✅ Implemented |
| `health` | `swiftmtp health` | Quick USB/MTP connectivity check | ✅ Implemented |
| `info` | `swiftmtp info` | Show quirks database summary | ✅ Implemented |
| `info` | `swiftmtp info <handle>` | Show rich metadata for a specific object | ✅ Implemented |

## File Operations

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `storages` | `swiftmtp storages` | List available storage volumes | ✅ Implemented |
| `ls` | `swiftmtp ls <storage>` | List files in a storage | ✅ Implemented |
| `ls` | `swiftmtp ls <storage> --detail` | List files with rich metadata | ✅ Implemented |
| `pull` | `swiftmtp pull <handle> <dest>` | Download a file by handle | ✅ Implemented |
| `push` | `swiftmtp push <src> <dest>` | Upload a file to a folder | ✅ Implemented |
| `thumb` | `swiftmtp thumb <handle>` | Download object thumbnail | ✅ Implemented |
| `delete` | `swiftmtp delete <handle>` | Delete an object on the device | ✅ Implemented |
| `move` | `swiftmtp move <handle> <parent>` | Move an object to a new parent folder | ✅ Implemented |
| `cp` / `copy` | `swiftmtp cp <handle> <storage>` | Copy an object server-side (no download) | ✅ Implemented |

## Sync & Mirror

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `mirror` | `swiftmtp mirror <dest>` | Mirror device contents locally | ✅ Implemented |
| `snapshot` | `swiftmtp snapshot` | Capture full device content snapshot | ✅ Implemented |

### Mirror Options

| Flag | Description |
|------|-------------|
| `--photos-only` | Only mirror image files |
| `--format ext[,ext...]` | Only mirror specified formats |
| `--exclude-format ext[,ext...]` | Exclude specified formats |
| `--on-conflict <strategy>` | Conflict strategy: `newer-wins`, `local-wins`, `device-wins`, `keep-both`, `skip` |

## Edit Extensions (Android)

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `edit begin` | `swiftmtp edit begin <handle>` | Begin in-place editing of an object | ✅ Implemented |
| `edit end` | `swiftmtp edit end <handle>` | Commit in-place edits for an object | ✅ Implemented |
| `edit truncate` | `swiftmtp edit truncate <handle> <size>` | Truncate a file to given size | ✅ Implemented |

## Performance & Benchmarking

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `bench` | `swiftmtp bench <size>` | Benchmark transfer speed | ✅ Implemented |
| `profile` | `swiftmtp profile` | Profile device transfer characteristics | ✅ Implemented |
| `profile` | `swiftmtp profile --collect` | Collect profiling data | ✅ Implemented |

## Device Database & Quirks

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `quirks` | `swiftmtp quirks` | Query/explain device quirk profiles | ✅ Implemented |
| `add-device` | `swiftmtp add-device` | Generate a new device quirk template | ✅ Implemented |
| `learn-promote` | `swiftmtp learn-promote` | Promote a learned profile to quirks DB | ✅ Experimental |

## Device Contribution

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `collect` | `swiftmtp collect` | Collect device evidence for submission | ✅ Implemented |
| `submit` | `swiftmtp submit <bundle> [--gh]` | Submit a device profile bundle | ✅ Implemented |
| `wizard` | `swiftmtp wizard` | Interactive guided device setup | ✅ Implemented |
| `device-lab` | `swiftmtp device-lab` | Automated device testing matrix | ✅ Implemented |

## Events & Monitoring

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `events` | `swiftmtp events [secs]` | Monitor MTP device events in real-time | ✅ Implemented |

## Other

| Command | Syntax | Description | Status |
|---------|--------|-------------|--------|
| `version` | `swiftmtp version` | Show version and build info | ✅ Implemented |
| `bdd` | `swiftmtp bdd` | Run BDD scenario tests on a device | ✅ Implemented |
| `storybook` | `swiftmtp storybook` | Run demo storybook scenarios | ✅ Implemented |

---

## Global Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--json` | Output results as JSON | `swiftmtp probe --json` |
| `--jsonl` | Output results as JSON Lines | `swiftmtp events --jsonl` |
| `--vid <hex>` | Filter by USB Vendor ID | `--vid 0x18d1` |
| `--pid <hex>` | Filter by USB Product ID | `--pid 0x4ee1` |
| `--bus <n>` | Filter by USB bus number | `--bus 1` |
| `--address <n>` | Filter by USB device address | `--address 4` |
| `--mock` | Use simulated demo device | `swiftmtp probe --mock` |
| `--mock-profile=<name>` | Use a specific mock profile (`pixel7`, `galaxy`, `iphone`, `canon`) | `--mock-profile=pixel7` |
| `--safe` | Enable safe mode (extra validation checks) | `swiftmtp push file.txt dest --safe` |
| `--strict` | Enable strict mode (fail on warnings) | `swiftmtp probe --strict` |
| `--real-only` | Skip mock/demo devices | `swiftmtp probe --real-only` |
| `--trace-usb` | Enable USB trace logging | `swiftmtp probe --trace-usb` |
| `--trace-usb-details` | Enable detailed USB trace logging | `swiftmtp probe --trace-usb-details` |

---

## Command Count Summary

| Category | Commands |
|----------|----------|
| Device Discovery & Diagnostics | 5 |
| File Operations | 9 |
| Sync & Mirror | 2 |
| Edit Extensions (Android) | 3 |
| Performance & Benchmarking | 2 |
| Device Database & Quirks | 3 |
| Device Contribution | 4 |
| Events & Monitoring | 1 |
| Other | 3 |
| **Total** | **32 command forms** |

---

## Examples

```bash
# Device discovery
swiftmtp probe
swiftmtp probe --json
swiftmtp diag --vid 0x18d1

# Browse files
swiftmtp storages
swiftmtp ls 65537
swiftmtp ls 65537 --detail

# Transfer files
swiftmtp pull 42 ./photo.jpg
swiftmtp push ./file.txt Download

# Server-side copy
swiftmtp cp 42 65537

# Mirror with filtering
swiftmtp mirror ./backup --photos-only
swiftmtp mirror ./backup --format jpg,png --on-conflict newer-wins

# Thumbnails
swiftmtp thumb 42

# Android edit
swiftmtp edit begin 42
swiftmtp edit end 42

# Benchmarking
swiftmtp bench 10M --repeat 3 --out results.csv

# Quirks lookup
swiftmtp quirks lookup --vid 0x18d1 --pid 0x4ee1

# Device contribution workflow
swiftmtp collect
swiftmtp submit ./my-device-bundle --gh

# Demo mode
swiftmtp probe --mock
swiftmtp ls 65537 --mock-profile=pixel7
```

---

## Architecture Note

The CLI uses manual argument parsing (not ArgumentParser) in `Sources/Tools/swiftmtp-cli/main.swift`. Command dispatch is a `switch` on the first positional argument. Each command is implemented in a dedicated file under `Sources/Tools/swiftmtp-cli/Commands/`.

### Command Source Files

| File | Commands |
|------|----------|
| `ProbeCommand.swift` | `probe`, `usb-dump`, `diag` |
| `StorageListCommands.swift` | `storages`, `ls` |
| `TransferCommands.swift` | `pull`, `push`, `bench`, `mirror` |
| `DeleteMoveEventsCommands.swift` | `delete`, `move`, `events` |
| `CopyCommand.swift` | `cp`, `copy` |
| `EditCommand.swift` | `edit` |
| `ThumbCommand.swift` | `thumb` |
| `InfoCommand.swift` | `info <handle>` |
| `SnapshotCommand.swift` | `snapshot` |
| `SystemCommands.swift` | `quirks`, `health`, `info`, `version` |
| `ProfileCommand.swift` | `profile` |
| `CollectCLICommand.swift` | `collect` |
| `SubmitCommand.swift` | `submit` |
| `WizardCommand.swift` | `wizard` |
| `DeviceLabCommand.swift` | `device-lab` |
| `AddDeviceCommand.swift` | `add-device` |
| `LearnPromoteCommand.swift` | `learn-promote` |
| `BDDScenarios.swift` / `BDDCommand.swift` | `bdd` |
| `StorybookCommand.swift` | `storybook` |
