// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// Import ExitCode and exitNow from SwiftMTPCore
import enum SwiftMTPCore.ExitCode
import func SwiftMTPCore.exitNow

public struct JSONErrorEnvelope: Codable {
  public var type = "error"
  public var schemaVersion = "1.0"
  public let message: String
  public let timestamp: String
}

public func printJSONErrorAndExit(_ message: String) -> Never {
  let env = JSONErrorEnvelope(message: message, timestamp: ISO8601DateFormatter().string(from: Date()))
  let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
  if let data = try? enc.encode(env) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
  } else {
    fputs("{\"type\":\"error\",\"schemaVersion\":\"1.0\",\"message\":\"encoding failed\"}\n", stderr)
  }
  exitNow(.software)
}

public func printJSONErrorAndExit(_ message: String, code: ExitCode, details: [String: String]? = nil) -> Never {
  var errorDict: [String: Any] = [
    "type": "error",
    "schemaVersion": "1.0",
    "message": message,
    "timestamp": ISO8601DateFormatter().string(from: Date()),
    "exitCode": code.rawValue
  ]

  if let details = details {
    errorDict["details"] = details
  }

  if let data = try? JSONSerialization.data(withJSONObject: errorDict, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
  } else {
    fputs("{\"type\":\"error\",\"schemaVersion\":\"1.0\",\"message\":\"encoding failed\"}\n", stderr)
  }
  exitNow(code)
}
