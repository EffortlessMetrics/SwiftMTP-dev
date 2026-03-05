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
      return
        "USB access denied. Check System Settings > Privacy & Security and re-approve device access."
    case .objectWriteProtected:
      return "Device storage is write-protected. Remove protection on the device and retry."
    case .readOnly:
      return
        "The storage is read-only. Check for a physical write-protect switch or device setting."
    case .timeout:
      return "The operation timed out. Check that the device is still connected and unlocked."
    case .deviceDisconnected:
      return "Device disconnected. Reconnect the cable and ensure the device is unlocked."
    case .storageFull:
      return "Device storage is full. Free space on the device, then retry the transfer."
    case .transport(let t):
      return t.actionableDescription
    case .objectNotFound:
      return
        "The requested object was not found on the device. It may have been deleted or moved."
    case .notSupported(let msg):
      return "Not supported: \(msg). Check device firmware or try a different approach."
    case .protocolError(let code, let message):
      return actionableProtocolDescription(code: code, message: message)
    case .sessionBusy:
      return "An MTP operation is already in progress. Wait briefly and retry."
    case .preconditionFailed(let reason):
      return "Precondition failed: \(reason)"
    case .verificationFailed:
      return
        "Write verification failed: remote file size does not match expected size. The file may be corrupted — re-send to ensure integrity."
    case .etagMismatch:
      return
        "The remote file changed since the partial download began. Discard the partial and restart."
    }
  }

  private func actionableProtocolDescription(code: UInt16, message: String?) -> String {
    let desc = message ?? String(format: "0x%04X", code)
    switch code {
    case 0x201D:
      return
        "Device rejected write parameters (\(desc)). Try writing to a subfolder (Download, DCIM) instead of root."
    case 0x2003:
      return "MTP session is not open (\(desc)). Reconnect the device and retry."
    case 0x2008:
      return "Invalid storage ID (\(desc)). Refresh the storage list and retry."
    case 0x2009:
      return "Invalid object handle (\(desc)). Refresh the file listing and retry."
    case 0x2019:
      return "Device is busy (\(desc)). Wait a moment and retry."
    case 0x201E:
      return "Session already open (\(desc)). Disconnect and reconnect the device."
    default:
      return "Device returned a protocol error: \(desc)"
    }
  }
}

extension TransportError: ActionableError {
  public var actionableDescription: String {
    switch self {
    case .accessDenied:
      return
        "USB access denied. Close Android File Transfer, adb, or Smart Switch, then check System Settings > Privacy & Security."
    case .timeout:
      return
        "USB transfer timed out. Ensure the device screen is on and unlocked, then check the cable."
    case .noDevice:
      return
        "No MTP device found. Ensure the device is connected, unlocked, and set to File Transfer mode."
    case .busy:
      return "USB access is busy. Close competing USB tools and retry."
    case .stall:
      return
        "USB endpoint stalled. Disconnect and reconnect the device. Try a different USB port if it persists."
    case .timeoutInPhase(let phase):
      return
        "USB transfer timed out (\(phase.description) phase). Ensure the device is unlocked and check the cable."
    case .io(let msg):
      return "USB I/O error: \(msg). Try a different USB port or cable."
    }
  }
}
