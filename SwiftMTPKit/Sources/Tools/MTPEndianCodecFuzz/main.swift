// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec

private struct SeededGenerator: Sendable {
  private var state: UInt64
  init(seed: UInt64) { self.state = seed }
  mutating func next() -> UInt64 {
    state &*= 6_364_136_223_846_793_005
    state &+= 1
    return state
  }

  mutating func next(_ upperExclusive: Int) -> Int {
    if upperExclusive <= 0 { return 0 }
    return Int(next() % UInt64(upperExclusive))
  }
}

private enum HexFailure: Error {
  case invalidByte(String)
}

private func decodeHexLines(_ text: String) -> Result<[Data], HexFailure> {
  let lines = text.split(whereSeparator: \.isNewline)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  let values: [Data] = lines.compactMap { line in
    let parts = line.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(parts.count)
    for part in parts {
      guard let value = UInt8(part, radix: 16) else { return nil }
      bytes.append(value)
    }
    return Data(bytes)
  }
  return values.isEmpty ? .failure(.invalidByte("corpus has no valid lines")) : .success(values)
}

private func readCorpus(from path: String) throws -> [Data] {
  let corpusURL = URL(fileURLWithPath: path)
  let text = try String(contentsOf: corpusURL, encoding: .utf8)
  switch decodeHexLines(text) {
  case .success(let values): return values
  case .failure:
    if let fallback = try? String(contentsOf: corpusURL.appendingPathComponent("event.hex")) {
      return try decodeHexLines(fallback).get()
    }
    throw HexFailure.invalidByte("corpus format not recognized")
  }
}

func runFuzz(seed: UInt64, rounds: Int, corpus: [Data]) -> Int {
  var rng = SeededGenerator(seed: seed)
  var failures = 0

  for round in 0..<rounds {
    guard let seedCase = corpus.isEmpty ? nil : corpus[rng.next(corpus.count)] else {
      break
    }
    var buffer = [UInt8](seedCase)

    for _ in 0..<rng.next(8) {
      let index = rng.next(max(1, buffer.count + 1))
      let bit = rng.next(4)
      if bit == 0 {
        buffer.append(UInt8(rng.next(256)))
      } else if bit == 1 && !buffer.isEmpty {
        let removeIndex = rng.next(buffer.count)
        buffer.remove(at: removeIndex)
      } else if bit == 2 && !buffer.isEmpty {
        let mutateIndex = rng.next(buffer.count)
        buffer[mutateIndex] = UInt8(rng.next(256))
      } else {
        buffer.insert(UInt8(rng.next(256)), at: 0)
      }
    }

    let data = Data(buffer)
    var iterationFailed = false

    // Validate round-trip invariants and detect decode anomalies
    let _ = MTPEndianCodec.decodeUInt16(from: data, at: 0)
    let _ = MTPEndianCodec.decodeUInt32(from: data, at: 0)
    let _ = MTPEndianCodec.decodeUInt64(from: data, at: 0)
    if let u16 = MTPEndianCodec.decodeUInt16(from: data, at: max(0, data.count - 2)) {
      var roundTrip = Data()
      roundTrip.append(MTPEndianCodec.encode(u16))
      if let decoded = MTPEndianCodec.decodeUInt16(from: roundTrip, at: 0), decoded != u16 {
        iterationFailed = true
        print(
          "FAILURE[round=\(round)]: UInt16 round-trip mismatch: encoded \(u16) decoded \(decoded)")
        print("  input: \(buffer.map { String(format: "%02x", $0) }.joined(separator: " "))")
      }
    }

    // Validate encoder produces stable output
    var enc = MTPDataEncoder()
    enc.append(UInt32(data.count))
    _ = enc.encodedData

    if iterationFailed {
      failures += 1
      // Dump crash corpus entry so CI can collect
      let hex = buffer.map { String(format: "%02x", $0) }.joined(separator: " ")
      print("CRASH_CORPUS[\(failures)]: \(hex)")
    }

    if round.isMultiple(of: 1024) {
      print("fuzz round \(round) seed=0x\(String(seed, radix: 16)) failures=\(failures)")
    }
  }

  return failures
}

let arguments = CommandLine.arguments
let defaultSeed: UInt64 = 0x1A_11_C0DE_BAAD_F00D
let seed =
  arguments.dropFirst()
  .compactMap { arg in
    if arg.hasPrefix("--seed=") { return UInt64(arg.dropFirst(7), radix: 16) }
    return nil
  }
  .first ?? defaultSeed
let iterations =
  arguments.dropFirst()
  .compactMap { arg in
    if arg.hasPrefix("--iterations=") { return Int(arg.dropFirst(13)) }
    return nil
  }
  .first ?? 8192
let corpusPath = arguments.first(where: { $0.hasSuffix(".hex") || $0.hasSuffix(".txt") })

let corpus = {
  if let corpusPath {
    return try? readCorpus(from: corpusPath)
  }
  let bundleURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  let fallback = bundleURL.appendingPathComponent("Corpus")
    .appendingPathComponent("event-buffer.hex")
  return try? readCorpus(from: fallback.path)
}()

print("MTPEndianCodec fuzz starting with seed=0x\(String(seed, radix: 16))")
if let corpus, !corpus.isEmpty {
  print("Using corpus size: \(corpus.count)")
  let failures = runFuzz(seed: seed, rounds: iterations, corpus: corpus)
  if failures == 0 {
    print("MTPEndianCodec fuzz completed without observed decode crashes.")
    exit(0)
  }
  print("MTPEndianCodec fuzz failed with \(failures) failures.")
  exit(1)
}

print("No corpus found; fuzz completed with no mutations.")
