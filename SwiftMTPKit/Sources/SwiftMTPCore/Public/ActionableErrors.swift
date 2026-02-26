// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPObservability

extension MTPError: ActionableError {
  public var actionableDescription: String {
    switch self {
    case .busy:
      return
        "Device appears to be in charging mode. Unlock your device and select 'File Transfer'."
    case .permissionDenied:
      return "USB access denied. Check System Settings > Privacy & Security."
    case .objectWriteProtected:
      return "Device storage is write-protected."
    case .readOnly:
      return "The storage is read-only."
    case .timeout:
      return "The operation timed out. Check that the device is still connected and unlocked."
    case .deviceDisconnected:
      return "Device disconnected. Reconnect the cable and ensure the device is unlocked."
    case .storageFull:
      return "Device storage is full."
    case .transport(let t):
      return t.actionableDescription
    case .objectNotFound:
      return "The requested object was not found on the device."
    case .notSupported(let msg):
      return "Not supported: \(msg)"
    case .protocolError(let code, let message):
      let desc = message ?? String(format: "0x%04X", code)
      return "Device returned a protocol error: \(desc)"
    case .sessionBusy:
      return "An MTP operation is already in progress. Wait briefly and retry."
    case .preconditionFailed(let reason):
      return "Precondition failed: \(reason)"
    case .verificationFailed:
      return
        "Write verification failed: remote file size does not match expected size. The file may be corrupted on the device."
    }
  }
}

extension TransportError: ActionableError {
  public var actionableDescription: String {
    switch self {
    case .accessDenied:
      return "USB access denied. Check System Settings > Privacy & Security."
    case .timeout:
      return "USB transfer timed out. Check the cable connection and retry."
    case .noDevice:
      return "No MTP device found. Ensure the device is connected and in File Transfer mode."
    case .busy:
      return "USB access is busy. Close competing USB tools and retry."
    case .stall:
      return "USB endpoint stalled; recovered via clear-halt. Reconnect if the issue persists."
    case .timeoutInPhase(let phase):
      return "USB transfer timed out (\(phase.description) phase). Check cable and retry."
    case .io(let msg):
      return "USB I/O error: \(msg)"
    }
  }
}
