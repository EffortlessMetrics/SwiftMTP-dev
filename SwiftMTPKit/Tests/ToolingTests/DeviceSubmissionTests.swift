// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

// MARK: - Quirks JSON Helpers

private struct QuirksDatabase: Decodable, Sendable {
  let version: Int
  let entries: [QuirkEntry]

  enum CodingKeys: String, CodingKey {
    case version, entries
  }
}

private struct QuirkEntry: Decodable, Sendable {
  let id: String
  let match: QuirkMatch
  let status: String?
  let category: String?
  let confidence: String?
  let hooks: [QuirkHook]?
  let governance: QuirkGovernance?
  let evidenceRequired: [String]?
}

private struct QuirkMatch: Decodable, Sendable {
  let vid: String
  let pid: String
}

private struct QuirkHook: Decodable, Sendable {
  let phase: String?
}

private struct QuirkGovernance: Decodable, Sendable {
  let status: String?
  let addedBy: String?
  let addedDate: String?
}

// MARK: - DeviceSubmissionTests

final class DeviceSubmissionTests: XCTestCase {

  // Resolve project root from the test bundle location.
  private static let projectRoot: String = {
    // SwiftMTPKit is the package root; Specs/ is one level above it.
    let fileURL = URL(fileURLWithPath: #filePath)
    // #filePath -> .../SwiftMTPKit/Tests/ToolingTests/DeviceSubmissionTests.swift
    let swiftMTPKit = fileURL
      .deletingLastPathComponent()  // ToolingTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // SwiftMTPKit
    return swiftMTPKit.deletingLastPathComponent().path  // repo root
  }()

  private static let specsPath: String = {
    projectRoot + "/Specs/quirks.json"
  }()

  private static let resourcesPath: String = {
    projectRoot + "/SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json"
  }()

  // Lazily loaded quirks database (shared across tests in this class).
  private static let specsDB: QuirksDatabase? = {
    loadDB(at: specsPath)
  }()

  private static let resourcesDB: QuirksDatabase? = {
    loadDB(at: resourcesPath)
  }()

  private static func loadDB(at path: String) -> QuirksDatabase? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(QuirksDatabase.self, from: data)
  }

  // MARK: - Valid statuses, categories, and confidences

  private let validStatuses: Set<String> = [
    "stable", "experimental", "proposed", "blocked",
    "promoted", "verified", "community", "legacy",
  ]

  private let validCategories: Set<String> = [
    "3d-printer", "access-control", "action-camera", "audio-interface",
    "audio-recorder", "automotive", "body-camera", "camera", "cnc",
    "dap", "dashcam", "dev-board", "drone", "e-reader", "embedded",
    "fitness", "gaming-handheld", "gps-navigator", "industrial-camera",
    "lab-instrument", "media-player", "medical", "microscope", "phone",
    "point-of-sale", "printer", "projector", "scanner", "security-camera",
    "smart-home", "storage", "streaming-device", "synthesizer", "tablet",
    "telescope", "thermal-camera", "vr-headset", "wearable",
  ]

  private let validConfidences: Set<String> = [
    "high", "medium", "low", "community", "experimental",
  ]

  // MARK: 1 — Quirks JSON schema validation

  func testQuirksJSONHasRequiredTopLevelFields() throws {
    let db = try XCTUnwrap(Self.specsDB, "Failed to load Specs/quirks.json")
    XCTAssertGreaterThan(db.version, 0, "version must be positive")
    XCTAssertFalse(db.entries.isEmpty, "entries must not be empty")
  }

  func testEveryEntryHasRequiredFields() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      XCTAssertFalse(entry.id.isEmpty, "Entry must have non-empty id")
      XCTAssertFalse(entry.match.vid.isEmpty, "Entry \(entry.id): missing match.vid")
      XCTAssertFalse(entry.match.pid.isEmpty, "Entry \(entry.id): missing match.pid")
    }
  }

  // MARK: 2 — VID/PID format validation

  func testVIDPIDHexFormat() throws {
    let db = try XCTUnwrap(Self.specsDB)
    let hexPattern = #/^0x[0-9a-fA-F]{4}$/#
    for entry in db.entries {
      XCTAssertNotNil(
        try? hexPattern.wholeMatch(in: entry.match.vid),
        "Entry \(entry.id): vid '\(entry.match.vid)' must match 0x[0-9a-fA-F]{4}")
      XCTAssertNotNil(
        try? hexPattern.wholeMatch(in: entry.match.pid),
        "Entry \(entry.id): pid '\(entry.match.pid)' must match 0x[0-9a-fA-F]{4}")
    }
  }

  // MARK: 3 — Duplicate VID:PID detection

  func testNoDuplicateVIDPIDPairs() throws {
    let db = try XCTUnwrap(Self.specsDB)
    var seen = [String: String]()  // "vid:pid" -> first entry id
    for entry in db.entries {
      let pair = "\(entry.match.vid):\(entry.match.pid)"
      if let existing = seen[pair] {
        XCTFail("Duplicate VID:PID \(pair) in entries '\(existing)' and '\(entry.id)'")
      }
      seen[pair] = entry.id
    }
  }

  // MARK: 4 — ID uniqueness

  func testAllQuirkIDsAreUnique() throws {
    let db = try XCTUnwrap(Self.specsDB)
    var seen = Set<String>()
    for entry in db.entries {
      XCTAssertTrue(seen.insert(entry.id).inserted, "Duplicate quirk ID: \(entry.id)")
    }
  }

  func testQuirkIDFormat() throws {
    let db = try XCTUnwrap(Self.specsDB)
    let idPattern = #/^[a-z0-9][a-z0-9-]*[a-z0-9]$/#
    for entry in db.entries {
      XCTAssertNotNil(
        try? idPattern.wholeMatch(in: entry.id),
        "Entry ID '\(entry.id)' must be lowercase kebab-case (a-z0-9 with hyphens)")
    }
  }

  // MARK: 5 — Category validation

  func testAllCategoriesAreValid() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      if let category = entry.category {
        XCTAssertTrue(
          validCategories.contains(category),
          "Entry \(entry.id): unknown category '\(category)'")
      }
    }
  }

  // MARK: 6 — Hooks format

  func testHooksAreArraysNotDicts() throws {
    // Parse raw JSON to detect dict-typed hooks that the Decodable model would reject.
    let path = Self.specsPath
    let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
    for entry in entries {
      let id = entry["id"] as? String ?? "unknown"
      if let hooks = entry["hooks"] {
        XCTAssertTrue(hooks is [Any], "Entry \(id): hooks must be an array, got \(type(of: hooks))")
      }
    }
  }

  // MARK: 7 — Status field governance values

  func testStatusFieldValues() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      if let status = entry.status {
        XCTAssertTrue(
          validStatuses.contains(status),
          "Entry \(entry.id): unknown status '\(status)'")
      }
    }
  }

  func testGovernanceStatusValues() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      if let gs = entry.governance?.status {
        XCTAssertTrue(
          validStatuses.contains(gs),
          "Entry \(entry.id): unknown governance.status '\(gs)'")
      }
    }
  }

  // MARK: 8 — New entry template is valid JSON

  func testNewEntryTemplateIsValidJSON() throws {
    // Mirrors the JSON template generated by scripts/add-device.sh
    let template = """
      {
        "id": "test-device-0001",
        "deviceName": "Test Device",
        "category": "phone",
        "match": { "vid": "0x1234", "pid": "0x5678" },
        "tuning": { "chunkSize": 1048576, "timeoutMs": 8000, "maxRetries": 3 },
        "hooks": [],
        "ops": { "getPartialObject": true, "sendPartialObject": true },
        "flags": { "noZeroLengthPackets": false },
        "status": "community",
        "confidence": "community"
      }
      """
    let data = Data(template.utf8)
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(obj, "Template must be valid JSON")
    XCTAssertEqual(obj?["id"] as? String, "test-device-0001")
    XCTAssertEqual(obj?["category"] as? String, "phone")
    XCTAssertEqual(obj?["status"] as? String, "community")

    let match = obj?["match"] as? [String: String]
    XCTAssertEqual(match?["vid"], "0x1234")
    XCTAssertEqual(match?["pid"], "0x5678")

    let hooks = obj?["hooks"] as? [Any]
    XCTAssertNotNil(hooks, "hooks must be an array")
    XCTAssertTrue(hooks?.isEmpty ?? false, "Template hooks should start empty")
  }

  // MARK: 9 — Contributor / governance metadata

  func testGovernanceMetadataFieldsIfPresent() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      guard let gov = entry.governance else { continue }
      // If addedDate is present, it should look like an ISO date (YYYY-MM-DD).
      if let date = gov.addedDate, !date.isEmpty {
        let datePattern = #/^\d{4}-\d{2}-\d{2}$/#
        XCTAssertNotNil(
          try? datePattern.wholeMatch(in: date),
          "Entry \(entry.id): governance.addedDate '\(date)' must be YYYY-MM-DD")
      }
      // addedBy, if present, should be non-empty.
      if let addedBy = gov.addedBy {
        XCTAssertFalse(addedBy.isEmpty, "Entry \(entry.id): governance.addedBy must not be empty")
      }
    }
  }

  func testConfidenceFieldValues() throws {
    let db = try XCTUnwrap(Self.specsDB)
    for entry in db.entries {
      if let conf = entry.confidence {
        XCTAssertTrue(
          validConfidences.contains(conf),
          "Entry \(entry.id): unknown confidence '\(conf)'")
      }
    }
  }

  // MARK: 10 — Cross-reference integrity

  func testSpecsMatchesResourcesQuirks() throws {
    let specsData = try XCTUnwrap(
      FileManager.default.contents(atPath: Self.specsPath),
      "Cannot read Specs/quirks.json")
    let resourcesData = try XCTUnwrap(
      FileManager.default.contents(atPath: Self.resourcesPath),
      "Cannot read Resources/quirks.json")
    XCTAssertEqual(
      specsData, resourcesData,
      "Specs/quirks.json and SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json must be identical")
  }
}
