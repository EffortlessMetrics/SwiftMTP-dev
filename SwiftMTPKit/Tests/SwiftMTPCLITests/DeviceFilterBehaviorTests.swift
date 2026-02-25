// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

@Suite("CLI Parsing Behavior")
struct CLIParsingBehavior {
  @Test("parseUSBIdentifier treats unprefixed values as hex (USB convention)")
  func parseUSBIdentifierFormats() {
    #expect(SwiftMTPCLI.parseUSBIdentifier("0x2717") == 0x2717)  // explicit 0x prefix → hex
    #expect(SwiftMTPCLI.parseUSBIdentifier("0XABCD") == 0xABCD)  // explicit 0X prefix → hex
    #expect(SwiftMTPCLI.parseUSBIdentifier("4660") == 0x4660)  // unprefixed → hex (USB convention)
    #expect(SwiftMTPCLI.parseUSBIdentifier("ff40") == 0xFF40)  // hex letters → hex
    #expect(SwiftMTPCLI.parseUSBIdentifier(" 1234 ") == 0x1234)  // whitespace-stripped, unprefixed → hex
    #expect(SwiftMTPCLI.parseUSBIdentifier("not-a-number") == nil)
  }

  @Test("DeviceFilter parser is canonical under randomized idempotence runs")
  func parseIdempotenceProperty() {
    let seed: UInt64 = 0xD15EA5E5_00F0_0001
    var rng = SeededGenerator(seed: seed)

    for i in 0..<256 {
      let vid = rng.flip(1, 3) ? UInt16(rng.nextInt(0...0xFFFF)) : nil
      let pid = rng.flip(1, 3) ? UInt16(rng.nextInt(0...0xFFFF)) : nil
      let bus = rng.flip(1, 4) ? rng.nextInt(1...128) : nil
      let address = rng.flip(1, 4) ? rng.nextInt(1...255) : nil
      let filter = DeviceFilter(vid: vid, pid: pid, bus: bus, address: address)

      var args = canonicalFilterArgs(
        vid: vid,
        pid: pid,
        bus: bus,
        address: address
      )

      for _ in 0..<rng.nextInt(0...3) {
        args.append("--noise-\(rng.nextInt(1...99))")
        args.append("noise-\(rng.nextInt(1...999))")
      }
      let unknownCount =
        (args.count - canonicalFilterArgs(vid: vid, pid: pid, bus: bus, address: address).count) / 2

      var parsedArgs = args
      let parsed = DeviceFilterParse.parse(from: &parsedArgs)
      let remainingArgs = parsedArgs.filter { !$0.isEmpty }

      let roundTripArgs = canonicalFilterArgs(
        vid: parsed.vid,
        pid: parsed.pid,
        bus: parsed.bus,
        address: parsed.address
      )
      var reparsedArgs = roundTripArgs
      let reparsed = DeviceFilterParse.parse(from: &reparsedArgs)

      #expect(parsed.vid == filter.vid, "Seed: \(seed), iteration: \(i)")
      #expect(parsed.pid == filter.pid, "Seed: \(seed), iteration: \(i)")
      #expect(parsed.bus == filter.bus, "Seed: \(seed), iteration: \(i)")
      #expect(parsed.address == filter.address, "Seed: \(seed), iteration: \(i)")
      #expect(reparsed.vid == parsed.vid, "Seed: \(seed), iteration: \(i)")
      #expect(reparsed.pid == parsed.pid, "Seed: \(seed), iteration: \(i)")
      #expect(reparsed.bus == parsed.bus, "Seed: \(seed), iteration: \(i)")
      #expect(reparsed.address == parsed.address, "Seed: \(seed), iteration: \(i)")
      #expect(
        reparsedArgs.isEmpty,
        "Expected canonical args to fully parse. Seed: \(seed), iteration: \(i)"
      )
      if unknownCount > 0 {
        #expect(!remainingArgs.isEmpty, "Seed: \(seed), iteration: \(i)")
      }
    }
  }
}

@Suite("CLI Selection Integration")
struct CLISelectionIntegration {
  @Test("selectDevice filters summaries using CLI-compatible parse and selection flow")
  func selectDeviceIntegration() {
    var args = ["--vid", "2717", "--bus", "11", "--address", "6", "--other", "token"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == 0x2717)
    #expect(filter.pid == nil)
    #expect(filter.bus == 11)
    #expect(filter.address == 6)

    let matched = MTPDeviceSummary(
      id: MTPDeviceID(raw: "int-match"),
      manufacturer: "Vendor",
      model: "Matched",
      vendorID: 0x2717,
      productID: 0xAABB,
      bus: 11,
      address: 6
    )
    let nonmatch = MTPDeviceSummary(
      id: MTPDeviceID(raw: "int-mismatch"),
      manufacturer: "Vendor",
      model: "Miss",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 11,
      address: 7
    )

    let outcome = SwiftMTPCLI.selectDevice(
      [matched, nonmatch], filter: filter, noninteractive: true)

    #expect(args == ["--other", "token"])
    switch outcome {
    case .selected(let selected):
      #expect(selected.id == matched.id)
      #expect(selected.vendorID == 0x2717)
      #expect(selected.bus == 11)
    default:
      Issue.record("Expected selected outcome from integration flow")
    }
  }
}

@Suite("CLI JSON Snapshot")
struct CLIJSONSnapshot {
  @Test("CLIErrorEnvelope JSON encoding is deterministic with fixed timestamp")
  func envelopeSnapshot() throws {
    let envelope = CLIErrorEnvelope(
      "snapshot-error",
      details: ["code": "E42"],
      mode: "unit",
      timestamp: "2026-01-01T00:00:00Z"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? ""

    let snapshot =
      #"{"details":{"code":"E42"},"error":"snapshot-error","mode":"unit","schemaVersion":"1.0","timestamp":"2026-01-01T00:00:00Z","type":"error"}"#
    #expect(text == snapshot)
  }
}

@Suite("CLI Parser Fuzz Harness")
struct CLIParserFuzz {
  @Test("Parser withstands seeded fuzz corpus without crash")
  func fuzzHarness() {
    let seed: UInt64 = 0xA17F_00FF_C0FF_EE00
    var rng = SeededGenerator(seed: seed)

    for i in 0..<2000 {
      var args: [String] = []
      let argCount = rng.nextInt(0...32)
      var expectedUnknown: [String] = []

      for _ in 0..<argCount {
        let token = rng.nextNoiseToken()
        if token == "--vid" || token == "--bus" || token == "--address" {
          let value = String(rng.nextInt(0...65_535))
          args.append(token)
          args.append(value)
        } else {
          args.append(token)
          let value = "noise-\(rng.nextInt(0...9999))"
          args.append(value)
          expectedUnknown.append(token)
          expectedUnknown.append(value)
        }
      }

      for _ in 0..<rng.nextInt(0...3) {
        let noiseIndex = rng.nextInt(1...999)
        let noise = "--noise-\(noiseIndex)"
        let value = "noise-\(rng.nextInt(0...9999))"
        args.append(contentsOf: [noise, value])
        expectedUnknown.append(contentsOf: [noise, value])
      }
      var parseArgs = args
      _ = DeviceFilterParse.parse(from: &parseArgs)
      #expect(
        expectedUnknown == parseArgs,
        "Seed: \(seed), iteration: \(i)"
      )
    }
  }
}

// MARK: - Deterministic random helpers

private struct SeededGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt32 {
    state &*= 6_364_136_223_846_793_005
    state &+= 1
    state ^= state >> 12
    state ^= state << 25
    state ^= state >> 27
    return UInt32(truncatingIfNeeded: state >> 32)
  }

  mutating func nextInt(_ bounds: ClosedRange<Int>) -> Int {
    let width = UInt64(bounds.upperBound - bounds.lowerBound + 1)
    return bounds.lowerBound + Int(UInt64(next()) % width)
  }

  mutating func flip(_ numerator: UInt32, _ denominator: UInt32) -> Bool {
    return (UInt64(next()) % UInt64(denominator)) < UInt64(numerator)
  }

  mutating func nextNoiseToken() -> String {
    let tokenKind = nextInt(0...4)
    switch tokenKind {
    case 0: return "--vid"
    case 1: return "--bus"
    case 2: return "--address"
    case 3: return "--noise-\(nextInt(0...99))"
    default: return "noise-\(nextInt(0...999))"
    }
  }
}

private func canonicalFilterArgs(
  vid: UInt16?,
  pid: UInt16?,
  bus: Int?,
  address: Int?
) -> [String] {
  var args: [String] = []
  if let vid { args.append(contentsOf: ["--vid", String(format: "%04x", vid)]) }
  if let pid { args.append(contentsOf: ["--pid", String(format: "%04x", pid)]) }
  if let bus { args.append(contentsOf: ["--bus", "\(bus)"]) }
  if let address { args.append(contentsOf: ["--address", "\(address)"]) }
  return args
}
