// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// These helpers provide the CLI-friendly names without changing core behavior.
// They forward to whatever your current API is (properties/methods).

public extension MTPDevice {
  /// CLI calls `getDeviceInfo()`; core exposes `info` as async property or method.
  func getDeviceInfo() async throws -> MTPDeviceInfo {
    // If your API is `func info() async throws -> MTPDeviceInfo`, call that instead:
    // return try await self.info()
    return try await self.info
  }

  /// CLI calls `openIfNeeded()` before first op. If your core already auto-opens on first
  /// operation, this stays cheap; otherwise it forces a benign op that opens the session.
  func openIfNeeded() async throws {
    // If you already have actor-isolated `openIfNeeded()` in core, prefer that instead.
    // This fallback forces light-weight access that triggers session open in current design.
    _ = try await self.storages()
  }
}
