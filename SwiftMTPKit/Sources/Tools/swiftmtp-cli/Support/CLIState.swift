// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

public struct CLIFlags: Sendable {
    public let realOnly: Bool
    public let useMock: Bool
    public let mockProfile: String
    public let json: Bool
    public let jsonlOutput: Bool
    public let traceUSB: Bool
    public let strict: Bool
    public let safe: Bool
    public let traceUSBDetails: Bool
    public let targetVID: String?
    public let targetPID: String?
    public let targetBus: Int?
    public let targetAddress: Int?

    public init(realOnly: Bool, useMock: Bool, mockProfile: String, json: Bool, jsonlOutput: Bool, traceUSB: Bool, strict: Bool, safe: Bool, traceUSBDetails: Bool, targetVID: String?, targetPID: String?, targetBus: Int?, targetAddress: Int?) {
        self.realOnly = realOnly
        self.useMock = useMock
        self.mockProfile = mockProfile
        self.json = json
        self.jsonlOutput = jsonlOutput
        self.traceUSB = traceUSB
        self.strict = strict
        self.safe = safe
        self.traceUSBDetails = traceUSBDetails
        self.targetVID = targetVID
        self.targetPID = targetPID
        self.targetBus = targetBus
        self.targetAddress = targetAddress
    }

    // Back-compat property
    @available(*, deprecated, message: "Use json instead")
    public var jsonOutput: Bool { json }
}

public struct JSONEnvelope<T: Encodable>: Encodable {
    public let schemaVersion: String
    public let type: String
    public let timestamp: String
    public let data: T
    
    public init(schemaVersion: String, type: String, timestamp: String, data: T) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}

public struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    public init(_ value: Encodable) {
        encode = { try value.encode(to: $0) }
    }
    public func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

public func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes), unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 { value /= 1024; unitIndex += 1 }
    return String(format: "%.1f %@", value, units[unitIndex])
}

public func parseSize(_ str: String) -> UInt64 {
    let multipliers: [Character: UInt64] = ["K": 1024, "M": 1024*1024, "G": 1024*1024*1024]
    let numStr = str.filter { $0.isNumber }
    let suffix = str.last(where: { multipliers.keys.contains($0.uppercased().first!) })
    guard let num = UInt64(numStr) else { return 0 }
    if let mult = suffix?.uppercased().first, let multiplier = multipliers[mult] { return num * multiplier }
    return num
}

public func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

@MainActor
public func printJSON(_ value: Any, type: String) {
    var envelope: [String: Any] = [
        "schemaVersion": "1.0.0",
        "type": type,
        "timestamp": ISO8601DateFormatter().string(from: Date())
    ]
    
    do {
        if let dict = value as? [String: Any] {
            for (k, v) in dict { envelope[k] = v }
        } else if let encodable = value as? Encodable {
            let jsonData = try JSONEncoder().encode(AnyEncodable(encodable))
            if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                for (k, v) in dict { envelope[k] = v }
            } else {
                envelope["data"] = try JSONSerialization.jsonObject(with: jsonData)
            }
        } else {
            envelope["data"] = value
        }
        
        let outputData = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        print(String(data: outputData, encoding: .utf8) ?? "{}")
    } catch {
        print("{\"error\": \"json_encoding_failed\", \"type\": \"\(type)\"}")
    }
}

@MainActor
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

