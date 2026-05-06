# Broker / Driver Architecture Roadmap

> Status: Foundation scaffold landed. Implementation migrations pending.
> Owner: SwiftMTP core team.

## Why a broker layer

SwiftMTP is moving toward an ephemeral broker/driver model:

> MTP/PTP is only between SwiftMTP and the device. Finder talks to File Provider.
> Apps talk through XPC/SDK to a broker. Only the broker owns the USB session.
> The broker multiplexes logical clients over one serialized device session.
> The cache/index makes browsing fast even when transfers are slow.

`SwiftMTPCore` should remain a reusable PTP/MTP protocol library: device actor,
transaction state, retry ladders, codecs. Session ownership, scheduling, and
orchestrator wiring are higher-level concerns that today live inside
`SwiftMTPCore` for historical reasons. `DeviceServiceRegistry` even stores
orchestrators as `AnyObject` to dodge importing `SwiftMTPIndex` — a strong
signal that this code wants its own home.

## Target end state

| Module                                                    | Responsibility                                                                                     |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `SwiftMTPCore`                                            | PTP/MTP protocol, device actor, transaction state, retry ladders, codecs                           |
| `SwiftMTPTransportLibUSB` / `SwiftMTPTransportIOUSBHost`  | USB backends                                                                                       |
| `SwiftMTPIndex`                                           | SQLite live index, crawler, content cache                                                          |
| `SwiftMTPXPC`                                             | IPC protocol DTOs                                                                                  |
| **`SwiftMTPBroker`** (new)                                | Session ownership, registry, lifecycle, scheduling, orchestrator wiring                            |
| `SwiftMTPFileProvider`                                    | Finder projection only; no USB or session ownership                                                |
| `SwiftMTPTestKit`                                         | Virtual devices, fault injection, transcript replay                                                |

## What landed in this scaffold

- New library product and target: `SwiftMTPBroker` (depends on `SwiftMTPCore`).
- Re-exports under broker-flavored names so call sites can switch their imports
  before the source move:
  - `Broker` → `DeviceServiceRegistry`
  - `BrokerDeviceService` → `DeviceService`
  - `BrokerOperationHandle` → `DeviceOperationHandle`
  - `BrokerOperationPriority` → `DeviceOperationPriority`
  - `BrokerOperationDeadline` → `OperationDeadline`
- New test target: `BrokerTests` exercises registry domain mapping and priority
  ordering through the broker import surface.

## Migration plan

### Phase 1 — Source migration (next PR)

The order below avoids a circular dependency between `SwiftMTPCore` and
`SwiftMTPBroker`: SPM does not permit cycles, and `SwiftMTPBroker` already
depends on `SwiftMTPCore` for base protocols (`MTPDevice`, `MTPError`, …).
We therefore migrate *callers first*, then move the source.

1. **Caller migration.** Update every in-repo caller of
   `DeviceService` / `DeviceServiceRegistry` (in `swiftmtp-cli`,
   `SwiftMTPXPC`, `SwiftMTPFileProvider`, `SwiftMTPUI`, and tests) to
   `import SwiftMTPBroker` and to use the broker-flavored names
   (`Broker`, `BrokerDeviceService`, …). The typealiases shipped by this
   scaffold PR make that migration a no-op at runtime.
2. **Source move.** Once no in-repo caller refers to these types via
   `SwiftMTPCore`, move `DeviceService.swift` and
   `DeviceServiceRegistry.swift` into `Sources/SwiftMTPBroker/`. In the
   same PR, replace the typealiases in `SwiftMTPBroker.swift` with the
   real declarations and drop the `@_exported import SwiftMTPCore` shim
   (callers explicitly import what they need).
3. **No back-typealiases in Core.** We deliberately do *not* add reverse
   typealiases inside `SwiftMTPCore` after the move — that would require
   `SwiftMTPCore` to depend on `SwiftMTPBroker` and create the cycle.
   External (out-of-repo) consumers, if any, take a one-time import
   change documented in the migration guide.
4. **Typed orchestrator.** Replace the `AnyObject` orchestrator handle
   on `Broker` with a typed `BrokerOrchestrator` protocol (or a concrete
   generic) so the registry no longer leaks an `AnyObject` escape hatch.
   `SwiftMTPIndex` conforms its orchestrator type to that protocol.

### Phase 2 — Lifecycle and scheduling

1. Promote attach/detach orchestration from ad-hoc app glue into a
   `Broker.start(manager:onAttach:onDetach:)` entry point that owns the
   monitor task lifetime.
2. Centralize operation deadlines, retry policy, and back-pressure decisions
   inside the broker so transports stay dumb pipes.
3. Provide a single `Broker.openSession(device:)` API that wraps
   `ensureSession`, error recovery, and quirk-driven init.

### Phase 3 — XPC/CLI wiring

1. CLI default route: broker/XPC. Keep `--direct` for transport debugging.
2. XPC service layer constructs and owns a single broker instance and
   surfaces broker handles to clients.
3. Multi-client scheduling tests: Finder enumeration + materialization +
   background crawl interleave correctly under one broker.

### Phase 4 — File Provider materialization through the broker

1. `XPC.readObject` routes through `ContentCache.materialize` (already
   scaffolded in `SwiftMTPIndex`).
2. Cached content lives in the shared app-group cache with pin/unpin
   semantics while Finder has the file open.
3. `MTPFileProviderExtension.fetchContents` returns stable cached URLs from
   the cache rather than ephemeral temp paths.

### Phase 5 — Crawler and delete-anchor correctness

1. `CrawlScheduler` keeps its worker alive across queue-drain → enqueue
   transitions (today the loop returns when the queue empties).
2. `live_changes` rows for deletes carry enough identity (`deviceId`,
   `storageId`, `handle`, `parentHandle`) to emit `didDeleteItems` without
   joining back to `live_objects` after stale rows are purged.
3. App-group container fallback in `SQLiteLiveIndex.appGroupIndex` becomes a
   hard diagnostic in production; tests inject an explicit base URL.

### Phase 6 — Android/PTP state classification

1. `DeviceAvailability` enum surfaced through CLI `probe --json`, XPC
   `deviceStatus`, and File Provider unavailable errors.
2. Distinguish: no MTP/PTP interface, PTP-only mode, MTP busy, GetDeviceInfo
   timeout, OpenSession timeout, stale-session-recovered.
3. CLI and File Provider produce actionable user-facing messages
   ("Select File Transfer mode on the phone", "Another macOS process is
   using this device", etc.).

## Compatibility guarantees

- No public API renames in this scaffold PR. Existing `import SwiftMTPCore`
  call sites keep working.
- The scaffold's `@_exported import SwiftMTPCore` means a caller can switch
  to `import SwiftMTPBroker` *before* the source move and still call methods
  on `Broker`, `BrokerDeviceService`, etc. without an extra Core import.
- The Phase 1 source move drops the `@_exported` shim and replaces the
  typealiases with the real declarations; in-repo call sites that already
  switched their imports keep compiling unchanged.
- Out-of-repo consumers (if any) take a one-time import change at the
  source-move PR; we do not add reverse typealiases inside `SwiftMTPCore`
  because that would require `SwiftMTPCore → SwiftMTPBroker` and form a
  cycle with the existing `SwiftMTPBroker → SwiftMTPCore` dependency.

## Done criteria for "the broker exists"

- All broker-related types and entry points live in `SwiftMTPBroker`.
- `SwiftMTPCore` no longer imports `Foundation` only to host queue/lifecycle
  code.
- `DeviceServiceRegistry` no longer needs an `AnyObject` orchestrator slot.
- CLI, XPC, FileProvider, and UI all depend on `SwiftMTPBroker`, not on
  internal Core types, for session/lifecycle work.
- Multi-client scheduling tests pass under broker ownership.
