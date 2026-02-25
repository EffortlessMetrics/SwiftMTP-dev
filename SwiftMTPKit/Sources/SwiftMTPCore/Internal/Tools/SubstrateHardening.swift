// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - Feature Flagging

public enum MTPFeature: String, CaseIterable, Sendable {
  case propListFastPath = "PROPLIST_FASTPATH"
  case chunkedTransfer = "CHUNKED_TRANSFER"
  case extendedObjectInfo = "EXTENDED_OBJECTINFO"
  case backgroundEventPump = "BACKGROUND_EVENTPUMP"
  case learnPromote = "LEARN_PROMOTE"
}

public final class MTPFeatureFlags: @unchecked Sendable {
  private var flags: [MTPFeature: Bool] = [:]
  private let lock = NSLock()
  public static let shared = MTPFeatureFlags()

  private init() {
    for feature in MTPFeature.allCases {
      let envVal = ProcessInfo.processInfo.environment["SWIFTMTP_FEATURE_\(feature.rawValue)"]
      flags[feature] = (envVal == "1" || envVal == "true")
    }
  }

  public func isEnabled(_ feature: MTPFeature) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return flags[feature] ?? false
  }

  public func setEnabled(_ feature: MTPFeature, _ enabled: Bool) {
    lock.lock()
    defer { lock.unlock() }
    flags[feature] = enabled
  }

  public func resetAllFeatures() {
    lock.lock()
    defer { lock.unlock() }
    for feature in MTPFeature.allCases {
      let envVal = ProcessInfo.processInfo.environment["SWIFTMTP_FEATURE_\(feature.rawValue)"]
      flags[feature] = (envVal == "1" || envVal == "true")
    }
  }
}

// MARK: - BDD Foundation

public protocol BDDScenario: Sendable {
  var name: String { get }
  func execute(context: BDDContext) async throws
}

public final class BDDContext: @unchecked Sendable {
  public let link: MTPLink
  private var logs: [String] = []
  private let lock = NSLock()

  public init(link: MTPLink) { self.link = link }

  public func step(_ description: String) {
    lock.lock()
    defer { lock.unlock() }
    logs.append(description)
    print("   [BDD] \(description)")
  }

  public func verify(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(domain: "BDDFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
}

// MARK: - Snapshot Testing

public struct MTPSnapshot: Codable, Sendable {
  public let timestamp: Date
  public let deviceInfo: MTPDeviceInfo
  public let storages: [MTPStorageInfo]
  public let objects: [MTPObjectInfo]

  public init(
    timestamp: Date, deviceInfo: MTPDeviceInfo, storages: [MTPStorageInfo], objects: [MTPObjectInfo]
  ) {
    self.timestamp = timestamp
    self.deviceInfo = deviceInfo
    self.storages = storages
    self.objects = objects
  }

  public func jsonString() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(self)
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}

// MARK: - Fuzz & Mutate Helpers

public enum MTPFuzzer {
  public static func randomData(length: Int) -> Data {
    var data = Data(count: length)
    _ = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
    }
    return data
  }

  public static func mutate(_ data: Data) -> Data {
    if data.isEmpty { return randomData(length: 1) }
    var mutated = data
    let index = Int.random(in: 0..<data.count)
    mutated[index] = UInt8.random(in: 0...255)
    return mutated
  }
}
