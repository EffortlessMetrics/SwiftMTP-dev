// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Minimal capability surface used by the tuning pipeline.
public struct ProbedCapabilities: Sendable, Codable, Equatable {
  public var partialRead: Bool
  public var partialWrite: Bool
  public var supportsEvents: Bool

  public init(
    partialRead: Bool = false,
    partialWrite: Bool = false,
    supportsEvents: Bool = false
  ) {
    self.partialRead = partialRead
    self.partialWrite = partialWrite
    self.supportsEvents = supportsEvents
  }
}

/// Parsed runtime overrides (env or CLI) applied last in the merge.
public struct UserOverride: Sendable, Equatable {
  public var maxChunkBytes: Int?
  public var ioTimeoutMs: Int?
  public var handshakeTimeoutMs: Int?
  public var inactivityTimeoutMs: Int?
  public var overallDeadlineMs: Int?
  public var stabilizeMs: Int?
  public var postClaimStabilizeMs: Int?
  public var disablePartialRead: Bool?
  public var disablePartialWrite: Bool?

  public init(
    maxChunkBytes: Int? = nil,
    ioTimeoutMs: Int? = nil,
    handshakeTimeoutMs: Int? = nil,
    inactivityTimeoutMs: Int? = nil,
    overallDeadlineMs: Int? = nil,
    stabilizeMs: Int? = nil,
    postClaimStabilizeMs: Int? = nil,
    disablePartialRead: Bool? = nil,
    disablePartialWrite: Bool? = nil
  ) {
    self.maxChunkBytes = maxChunkBytes
    self.ioTimeoutMs = ioTimeoutMs
    self.handshakeTimeoutMs = handshakeTimeoutMs
    self.inactivityTimeoutMs = inactivityTimeoutMs
    self.overallDeadlineMs = overallDeadlineMs
    self.stabilizeMs = stabilizeMs
    self.postClaimStabilizeMs = postClaimStabilizeMs
    self.disablePartialRead = disablePartialRead
    self.disablePartialWrite = disablePartialWrite
  }
}

public enum UserOverrideSource {
  case environment
  case none
}

public extension UserOverride {
  /// SWIFTMTP_OVERRIDES env format:
  ///   key=value,key=value (e.g. "maxChunkBytes=2097152,ioTimeoutMs=15000,stabilizeMs=400")
  static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> (
    UserOverride, UserOverrideSource
  ) {
    guard let raw = env["SWIFTMTP_OVERRIDES"], !raw.isEmpty else { return (UserOverride(), .none) }
    var ov = UserOverride()
    for pair in raw.split(separator: ",") {
      let kv = pair.split(separator: "=", maxSplits: 1).map { String($0) }
      guard kv.count == 2 else { continue }
      let k = kv[0].trimmingCharacters(in: .whitespaces)
      let v = kv[1].trimmingCharacters(in: .whitespaces)
      switch k {
      case "maxChunkBytes": ov.maxChunkBytes = Int(v)
      case "ioTimeoutMs": ov.ioTimeoutMs = Int(v)
      case "handshakeTimeoutMs": ov.handshakeTimeoutMs = Int(v)
      case "inactivityTimeoutMs": ov.inactivityTimeoutMs = Int(v)
      case "overallDeadlineMs": ov.overallDeadlineMs = Int(v)
      case "stabilizeMs": ov.stabilizeMs = Int(v)
      case "postClaimStabilizeMs": ov.postClaimStabilizeMs = Int(v)
      case "disablePartialRead": ov.disablePartialRead = (v == "1" || v.lowercased() == "true")
      case "disablePartialWrite": ov.disablePartialWrite = (v == "1" || v.lowercased() == "true")
      default: break
      }
    }
    return (ov, .environment)
  }
}
