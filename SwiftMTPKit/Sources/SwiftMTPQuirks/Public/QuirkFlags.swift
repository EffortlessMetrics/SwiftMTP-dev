// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Typed boolean/enum knobs replacing untyped `operations` maps.
/// Each flag controls a specific device behavior at a well-defined layer.
public struct QuirkFlags: Sendable, Codable, Equatable {

  // MARK: - Transport-level

  /// Issue `libusb_reset_device` after opening the handle.
  public var resetOnOpen: Bool = false

  /// Detach macOS kernel driver before claiming the interface.
  public var requiresKernelDetach: Bool = true

  /// Use longer handshake timeout for slow-to-respond devices.
  public var needsLongerOpenTimeout: Bool = false

  // MARK: - Protocol-level

  /// Device requires an open session before GetDeviceInfo responds.
  public var requiresSessionBeforeDeviceInfo: Bool = false

  /// Device resets its transaction-ID counter when a new session opens.
  public var transactionIdResetsOnSession: Bool = false

  // MARK: - Transfer-level

  /// Device supports GetPartialObject64 (0x95C4).
  public var supportsPartialRead64: Bool = true

  /// Device supports GetPartialObject (0x101B).
  public var supportsPartialRead32: Bool = true

  /// Device supports SendPartialObject (0x95C1).
  public var supportsPartialWrite: Bool = true

  /// Prefer GetObjectPropList (batch) over GetObjectInfo (per-handle).
  public var prefersPropListEnumeration: Bool = true

  /// Device stalls on reads larger than its internal buffer.
  public var needsShortReads: Bool = false

  /// Device stalls on large bulk reads (limit chunk size).
  public var stallOnLargeReads: Bool = false

  // MARK: - Session-level

  /// Suppress the interrupt-endpoint event pump.
  public var disableEventPump: Bool = false

  /// Insert a post-open stabilization delay.
  public var requireStabilization: Bool = false

  /// Skip PTP Device Reset (0x66) control transfer on open.
  public var skipPTPReset: Bool = false

  public init() {}
}
