// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public struct JSONErrorEnvelope: Codable {
  public let type = "error"
  public let schemaVersion = "1.0"
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
  exit(70) // software error
}
