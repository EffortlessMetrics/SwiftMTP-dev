// JSONIO.swift
import Foundation

public struct CLIErrorEnvelope: Codable, Sendable {
  public let schemaVersion: String
  public let type: String
  public let error: String
  public let timestamp: String
  public let details: [String:String]?
  public let mode: String?
  public init(_ error: String, details: [String:String]? = nil, mode: String? = nil) {
    self.schemaVersion = "1.0"
    self.type = "error"
    self.error = error
    self.timestamp = ISO8601DateFormatter().string(from: Date())
    self.details = details
    self.mode = mode
  }
}

@inline(__always)
public func printJSON<T: Encodable>(_ value: T) {
  let enc = JSONEncoder()
  enc.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
  do {
    let data = try enc.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  } catch {
    let fallback = CLIErrorEnvelope("encoding_failed")
    if let d = try? enc.encode(fallback) {
      FileHandle.standardError.write(d)
      FileHandle.standardError.write(Data([0x0A]))
    }
  }
}

@inline(__always)
public func printJSONErrorAndExit(_ message: String, code: ExitCode = .software, details: [String:String]? = nil, mode: String? = nil) -> Never {
  printJSON(CLIErrorEnvelope(message, details: details, mode: mode))
  exitNow(code)
}
