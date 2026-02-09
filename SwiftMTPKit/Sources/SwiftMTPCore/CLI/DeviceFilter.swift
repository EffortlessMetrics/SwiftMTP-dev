// DeviceFilter.swift
import Foundation

public struct DeviceFilter: Sendable {
  public let vid: UInt16?
  public let pid: UInt16?
  public let bus: Int?
  public let address: Int?

  public init(vid: UInt16?, pid: UInt16?, bus: Int?, address: Int?) {
    self.vid = vid; self.pid = pid; self.bus = bus; self.address = address
  }
}

// hex or decimal
@inline(__always)
private func parseU16(_ s: String) -> UInt16? {
  if s.hasPrefix("0x") || s.hasPrefix("0X") { return UInt16(s.dropFirst(2), radix: 16) }
  return UInt16(s, radix: 10)
}

@inline(__always)
private func parseInt(_ s: String) -> Int? { Int(s, radix: 10) }

public struct DeviceFilterParse {
  public static func parse(from args: inout [String]) -> DeviceFilter {
    var vid: UInt16?, pid: UInt16?, bus: Int?, address: Int?
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--vid":     if i+1 < args.count, let v = parseU16(args[i+1]) { vid = v; args.removeSubrange(i...i+1); continue }
      case "--pid":     if i+1 < args.count, let v = parseU16(args[i+1]) { pid = v; args.removeSubrange(i...i+1); continue }
      case "--bus":     if i+1 < args.count, let v = parseInt(args[i+1]) { bus = v; args.removeSubrange(i...i+1); continue }
      case "--address": if i+1 < args.count, let v = parseInt(args[i+1]) { address = v; args.removeSubrange(i...i+1); continue }
      default: break
      }
      i += 1
    }
    return DeviceFilter(vid: vid, pid: pid, bus: bus, address: address)
  }
}

public enum SelectionOutcome {
  case selected(MTPDeviceSummary) // your existing summary type
  case none
  case multiple([MTPDeviceSummary])
}

// Call from command entrypoints after discovery
public func selectDevice(
  _ devices: [MTPDeviceSummary],
  filter: DeviceFilter,
  noninteractive: Bool
) -> SelectionOutcome {
  let filtered = devices.filter { d in
    if let v = filter.vid, d.vendorID != v { return false }
    if let p = filter.pid, d.productID != p { return false }
    // If filter specifies bus, device must have the same bus value
    if let b = filter.bus {
      guard let db = d.bus, b == db else { return false }
    }
    // If filter specifies address, device must have the same address value
    if let a = filter.address {
      guard let da = d.address, a == da else { return false }
    }
    return true
  }
  if filtered.isEmpty { return .none }
  if filtered.count == 1 { return .selected(filtered[0]) }
  return noninteractive ? .multiple(filtered) : .multiple(filtered) // in interactive, you prompt
}
