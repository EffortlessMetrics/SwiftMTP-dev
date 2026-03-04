// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - MTP Extension Opcodes

/// MTP-specific operation codes beyond the PTP standard (0x1001–0x101B).
/// These are vendor extensions defined by the MTP specification.
public enum MTPOp: UInt16, Sendable {
  /// GetObjectPropsSupported — list all property codes supported for a given format.
  case getObjectPropsSupported = 0x9801

  /// GetObjectPropList — batch property retrieval.
  case getObjectPropList = 0x9805

  /// SendObjectPropList — create object metadata via property list prior to SendObject.
  case sendObjectPropList = 0x9808

  /// GetPartialObject64 (0x95C1) — 64-bit offset partial read (Android MTP extension).
  case getPartialObject64 = 0x95C1

  /// SendPartialObject (0x95C2) — resumable partial write (Android MTP extension).
  case sendPartialObject = 0x95C2

  /// TruncateObject (0x95C3) — Android extension to truncate an object to a given offset.
  case truncateObject = 0x95C3

  /// BeginEditObject (0x95C4) — Android extension to begin in-place editing of an object.
  case beginEditObject = 0x95C4

  /// EndEditObject (0x95C5) — Android extension to commit in-place edits.
  case endEditObject = 0x95C5

  /// GetObjectPropDesc — describe a single object property.
  case getObjectPropDesc = 0x9802

  /// GetObjectPropValue — read a single object property.
  case getObjectPropValue = 0x9803

  /// SetObjectPropValue — write a single object property.
  case setObjectPropValue = 0x9804

  /// GetObjectReferences — list references from an object.
  case getObjectReferences = 0x9810

  /// SetObjectReferences — set references on an object.
  case setObjectReferences = 0x9811
}

// MARK: - Backward-Compat Typealiases

/// Backward-compatible access via PTPOp for MTP extension opcodes.
public extension PTPOp {
  /// Alias for MTPOp.getPartialObject64 (0x95C1).
  static var getPartialObject64Value: UInt16 { MTPOp.getPartialObject64.rawValue }
  /// Alias for MTPOp.sendPartialObject (0x95C2).
  static var sendPartialObjectValue: UInt16 { MTPOp.sendPartialObject.rawValue }
  /// Alias for MTPOp.getObjectPropList.
  static var getObjectPropListValue: UInt16 { MTPOp.getObjectPropList.rawValue }
  /// Alias for MTPOp.beginEditObject.
  static var beginEditObjectValue: UInt16 { MTPOp.beginEditObject.rawValue }
  /// Alias for MTPOp.endEditObject.
  static var endEditObjectValue: UInt16 { MTPOp.endEditObject.rawValue }
  /// Alias for MTPOp.truncateObject.
  static var truncateObjectValue: UInt16 { MTPOp.truncateObject.rawValue }
}
