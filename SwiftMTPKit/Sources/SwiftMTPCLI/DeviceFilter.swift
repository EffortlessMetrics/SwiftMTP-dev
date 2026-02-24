// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public protocol DeviceFilterCandidate {
  var vendorID: UInt16? { get }
  var productID: UInt16? { get }
  var bus: UInt8? { get }
  var address: UInt8? { get }
}

public struct DeviceFilter: Sendable {
  public let vid: UInt16?
  public let pid: UInt16?
  public let bus: Int?
  public let address: Int?

  public init(vid: UInt16?, pid: UInt16?, bus: Int?, address: Int?) {
    self.vid = vid
    self.pid = pid
    self.bus = bus
    self.address = address
  }
}

// Parse VID/PID values with hex-first semantics.
// This matches common USB notation where unprefixed values are typically hex.
@inline(__always)
public func parseUSBIdentifier(_ raw: String?) -> UInt16? {
  guard let raw else { return nil }
  let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !value.isEmpty else { return nil }
  if value.hasPrefix("0x") || value.hasPrefix("0X") {
    return UInt16(value.dropFirst(2), radix: 16)
  }
  if value.range(of: "[a-fA-F]", options: .regularExpression) != nil {
    return UInt16(value, radix: 16)
  }
  return UInt16(value, radix: 16) ?? UInt16(value, radix: 10)
}

@inline(__always)
private func parseInt(_ s: String) -> Int? { Int(s, radix: 10) }

public struct DeviceFilterParse {
  public static func parse(from args: inout [String]) -> DeviceFilter {
    var vid: UInt16?, pid: UInt16?, bus: Int?, address: Int?
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--vid":
        if i + 1 < args.count, let v = parseUSBIdentifier(args[i+1]) {
          vid = v
          args.removeSubrange(i...i+1)
          continue
        }
      case "--pid":
        if i + 1 < args.count, let v = parseUSBIdentifier(args[i+1]) {
          pid = v
          args.removeSubrange(i...i+1)
          continue
        }
      case "--bus":
        if i + 1 < args.count, let v = parseInt(args[i+1]) {
          bus = v
          args.removeSubrange(i...i+1)
          continue
        }
      case "--address":
        if i + 1 < args.count, let v = parseInt(args[i+1]) {
          address = v
          args.removeSubrange(i...i+1)
          continue
        }
      default:
        break
      }
      i += 1
    }
    return DeviceFilter(vid: vid, pid: pid, bus: bus, address: address)
  }
}

public enum SelectionOutcome<DeviceSummary: DeviceFilterCandidate> {
  case selected(DeviceSummary)
  case none
  case multiple([DeviceSummary])
}

// Call from command entrypoints after discovery
public func selectDevice<DeviceSummary: DeviceFilterCandidate>(
  _ devices: [DeviceSummary],
  filter: DeviceFilter,
  noninteractive: Bool
) -> SelectionOutcome<DeviceSummary> {
  let filtered = devices.filter { d in
    if let v = filter.vid, d.vendorID != v { return false }
    if let p = filter.pid, d.productID != p { return false }
    if let b = filter.bus {
      guard let db = d.bus, UInt8(exactly: b) == db else { return false }
    }
    if let a = filter.address {
      guard let da = d.address, UInt8(exactly: a) == da else { return false }
    }
    return true
  }
  if filtered.isEmpty { return .none }
  if filtered.count == 1 { return .selected(filtered[0]) }
  return .multiple(filtered)
}
