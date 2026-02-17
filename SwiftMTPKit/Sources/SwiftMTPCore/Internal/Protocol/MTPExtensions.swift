// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - MTP Extension Opcodes

/// MTP-specific operation codes beyond the PTP standard (0x1001–0x101B).
/// These are vendor extensions defined by the MTP specification.
public enum MTPOp: UInt16, Sendable {
  /// GetObjectPropList — batch property retrieval.
  case getObjectPropList = 0x9805

  /// SendObjectPropList — create object metadata via property list prior to SendObject.
  case sendObjectPropList = 0x9808

  /// GetPartialObject64 — 64-bit offset partial read (MTP extension).
  case getPartialObject64 = 0x95C4

  /// SendPartialObject — resumable partial write (MTP extension).
  case sendPartialObject = 0x95C1

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
  /// Alias for MTPOp.getPartialObject64.
  static var getPartialObject64Value: UInt16 { MTPOp.getPartialObject64.rawValue }
  /// Alias for MTPOp.sendPartialObject.
  static var sendPartialObjectValue: UInt16 { MTPOp.sendPartialObject.rawValue }
  /// Alias for MTPOp.getObjectPropList.
  static var getObjectPropListValue: UInt16 { MTPOp.getObjectPropList.rawValue }
}
