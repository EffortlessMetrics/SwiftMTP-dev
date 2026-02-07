// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Records which strategy succeeded during capability probing
/// so subsequent operations skip directly to the known-good path.
public struct FallbackSelections: Sendable, Codable, Equatable {

  /// How to enumerate objects in a storage/folder.
  public enum EnumerationStrategy: String, Sendable, Codable {
    /// GetObjectPropList with 5 params (storage-aware).
    case propList5
    /// GetObjectPropList with 3 params (legacy).
    case propList3
    /// GetObjectHandles then GetObjectInfo per-handle.
    case handlesThenInfo
    /// Not yet probed.
    case unknown
  }

  /// How to read file data from the device.
  public enum ReadStrategy: String, Sendable, Codable {
    /// GetPartialObject64 (0x95C4) — 64-bit offsets.
    case partial64
    /// GetPartialObject (0x101B) — 32-bit offsets.
    case partial32
    /// GetObject (0x1009) — whole-file only.
    case wholeObject
    /// Not yet probed.
    case unknown
  }

  /// How to write file data to the device.
  public enum WriteStrategy: String, Sendable, Codable {
    /// SendPartialObject (0x95C1) — resumable.
    case partial
    /// SendObjectInfo + SendObject — whole-file only.
    case wholeObject
    /// Not yet probed.
    case unknown
  }

  public var enumeration: EnumerationStrategy = .unknown
  public var read: ReadStrategy = .unknown
  public var write: WriteStrategy = .unknown

  public init() {}
}
