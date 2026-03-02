// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Data quality tests that validate structural invariants of quirks.json
/// beyond what validate-quirks.sh checks. These tests ensure the database
/// maintains internal consistency, reasonable bounds, and correct conventions.
final class QuirksDataQualityTests: XCTestCase {

  private var db: QuirkDatabase!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
  }

  // MARK: - VID:PID Uniqueness

  func testNoDuplicateVIDPIDPairs() {
    var seen = [String: String]()  // "vid:pid" → first quirk ID
    var duplicates = [(String, String, String)]()  // (key, first, second)
    for entry in db.entries {
      let key = String(format: "%04x:%04x", entry.vid, entry.pid)
      if let first = seen[key] {
        duplicates.append((key, first, entry.id))
      } else {
        seen[key] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate VID:PID pairs: \(duplicates.prefix(5).map { "\($0.0) [\($0.1), \($0.2)]" })")
  }

  // MARK: - ID Naming Convention

  func testAllIDsFollowKebabCase() {
    let valid = CharacterSet.lowercaseLetters
      .union(.decimalDigits)
      .union(CharacterSet(charactersIn: "-"))
    var violations = [String]()
    for entry in db.entries {
      if !entry.id.unicodeScalars.allSatisfy({ valid.contains($0) }) {
        violations.append(entry.id)
      }
    }
    XCTAssertTrue(
      violations.isEmpty,
      "IDs with invalid characters (expected lowercase, digits, hyphens): \(violations.prefix(10))")
  }

  func testIDsContainNoUnderscores() {
    let offenders = db.entries.filter { $0.id.contains("_") }
    XCTAssertTrue(
      offenders.isEmpty,
      "IDs with underscores (should use hyphens): \(offenders.prefix(10).map(\.id))")
  }

  func testIDsContainNoUppercase() {
    let offenders = db.entries.filter { $0.id != $0.id.lowercased() }
    XCTAssertTrue(
      offenders.isEmpty,
      "IDs with uppercase chars: \(offenders.prefix(10).map(\.id))")
  }

  func testIDsHaveMinimumLength() {
    let short = db.entries.filter { $0.id.count < 6 }
    XCTAssertTrue(
      short.isEmpty,
      "IDs shorter than 6 chars: \(short.prefix(10).map(\.id))")
  }

  func testIDsDoNotStartOrEndWithHyphen() {
    let offenders = db.entries.filter {
      $0.id.hasPrefix("-") || $0.id.hasSuffix("-")
    }
    XCTAssertTrue(
      offenders.isEmpty,
      "IDs starting/ending with hyphen: \(offenders.prefix(10).map(\.id))")
  }

  func testIDsDoNotContainSpaces() {
    let offenders = db.entries.filter { $0.id.contains(" ") }
    XCTAssertTrue(
      offenders.isEmpty,
      "IDs containing spaces: \(offenders.prefix(10).map(\.id))")
  }

  // MARK: - Category Validation

  func testAllCategoriesFromKnownSet() {
    let validCategories: Set<String> = [
      "3d-printer", "access-control", "action-camera", "audio-interface", "audio-player",
      "audio-recorder", "automotive", "body-camera", "camera", "cnc", "dashcam", "dev-board",
      "drone", "e-reader", "embedded", "fitness", "gaming-handheld", "gps-navigator",
      "industrial-camera", "lab-instrument", "media-player", "medical", "microscope", "phone",
      "point-of-sale", "printer", "projector", "scanner", "security-camera", "smart-home",
      "storage", "streaming-device", "synthesizer", "tablet", "telescope", "thermal-camera",
      "vr-headset", "wearable",
    ]
    var unknown = [(String, String)]()  // (id, category)
    for entry in db.entries {
      guard let cat = entry.category else { continue }
      if !validCategories.contains(cat) {
        unknown.append((entry.id, cat))
      }
    }
    XCTAssertTrue(
      unknown.isEmpty,
      "Unknown categories: \(unknown.prefix(10).map { "\($0.0)=\($0.1)" })")
  }

  func testCategoriesAreKebabCase() {
    let kebab = try! NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
    let categories = Set(db.entries.compactMap(\.category))
    for cat in categories {
      let range = NSRange(cat.startIndex..., in: cat)
      XCTAssertNotNil(
        kebab.firstMatch(in: cat, range: range),
        "Category '\(cat)' is not valid kebab-case")
    }
  }

  func testNoCategoryIsEmpty() {
    let empty = db.entries.filter { ($0.category ?? "x").isEmpty }
    XCTAssertTrue(
      empty.isEmpty,
      "Entries with empty category string: \(empty.prefix(10).map(\.id))")
  }

  // MARK: - Tuning Parameter Bounds

  func testChunkSizeWithinReasonableBounds() {
    let minChunk = 512
    let maxChunk = 16 * 1024 * 1024  // 16 MB
    for entry in db.entries {
      guard let chunk = entry.maxChunkBytes else { continue }
      XCTAssertGreaterThanOrEqual(
        chunk, minChunk,
        "Entry '\(entry.id)' maxChunkBytes \(chunk) < \(minChunk)")
      XCTAssertLessThanOrEqual(
        chunk, maxChunk,
        "Entry '\(entry.id)' maxChunkBytes \(chunk) > \(maxChunk)")
    }
  }

  func testChunkSizeIsPowerOfTwo() {
    for entry in db.entries {
      guard let chunk = entry.maxChunkBytes else { continue }
      XCTAssertEqual(
        chunk & (chunk - 1), 0,
        "Entry '\(entry.id)' maxChunkBytes \(chunk) is not a power of 2")
    }
  }

  func testIOTimeoutWithinBounds() {
    let minTimeout = 100  // 100ms
    let maxTimeout = 120_000  // 120s
    for entry in db.entries {
      guard let timeout = entry.ioTimeoutMs else { continue }
      XCTAssertGreaterThanOrEqual(
        timeout, minTimeout,
        "Entry '\(entry.id)' ioTimeoutMs \(timeout) < \(minTimeout)")
      XCTAssertLessThanOrEqual(
        timeout, maxTimeout,
        "Entry '\(entry.id)' ioTimeoutMs \(timeout) > \(maxTimeout)")
    }
  }

  func testHandshakeTimeoutWithinBounds() {
    let minTimeout = 100
    let maxTimeout = 120_000
    for entry in db.entries {
      guard let timeout = entry.handshakeTimeoutMs else { continue }
      XCTAssertGreaterThanOrEqual(
        timeout, minTimeout,
        "Entry '\(entry.id)' handshakeTimeoutMs \(timeout) < \(minTimeout)")
      XCTAssertLessThanOrEqual(
        timeout, maxTimeout,
        "Entry '\(entry.id)' handshakeTimeoutMs \(timeout) > \(maxTimeout)")
    }
  }

  func testInactivityTimeoutWithinBounds() {
    let minTimeout = 100
    let maxTimeout = 120_000
    for entry in db.entries {
      guard let timeout = entry.inactivityTimeoutMs else { continue }
      XCTAssertGreaterThanOrEqual(
        timeout, minTimeout,
        "Entry '\(entry.id)' inactivityTimeoutMs \(timeout) < \(minTimeout)")
      XCTAssertLessThanOrEqual(
        timeout, maxTimeout,
        "Entry '\(entry.id)' inactivityTimeoutMs \(timeout) > \(maxTimeout)")
    }
  }

  func testOverallDeadlineWithinBounds() {
    let minDeadline = 1_000  // 1s
    let maxDeadline = 600_000  // 10 minutes
    for entry in db.entries {
      guard let deadline = entry.overallDeadlineMs else { continue }
      XCTAssertGreaterThanOrEqual(
        deadline, minDeadline,
        "Entry '\(entry.id)' overallDeadlineMs \(deadline) < \(minDeadline)")
      XCTAssertLessThanOrEqual(
        deadline, maxDeadline,
        "Entry '\(entry.id)' overallDeadlineMs \(deadline) > \(maxDeadline)")
    }
  }

  func testStabilizeMsWithinBounds() {
    let maxStabilize = 10_000  // 10s
    for entry in db.entries {
      guard let ms = entry.stabilizeMs else { continue }
      XCTAssertGreaterThanOrEqual(
        ms, 0,
        "Entry '\(entry.id)' stabilizeMs \(ms) is negative")
      XCTAssertLessThanOrEqual(
        ms, maxStabilize,
        "Entry '\(entry.id)' stabilizeMs \(ms) > \(maxStabilize)")
    }
  }

  // MARK: - Contradictory Flags

  func testNoWriteToSubfolderWithoutPreferredFolder() {
    // If typed flags explicitly set writeToSubfolderOnly, preferredWriteFolder should be specified
    for entry in db.entries {
      guard let flags = entry.flags, flags.writeToSubfolderOnly else { continue }
      if let folder = flags.preferredWriteFolder {
        XCTAssertFalse(
          folder.isEmpty,
          "Entry '\(entry.id)' has writeToSubfolderOnly=true but empty preferredWriteFolder")
      }
    }
  }

  func testNoStallOnLargeReadsWithoutChunkSizeCap() {
    // Entries flagging stallOnLargeReads should have a maxChunkBytes set
    for entry in db.entries {
      let flags = entry.resolvedFlags()
      if flags.stallOnLargeReads {
        XCTAssertNotNil(
          entry.maxChunkBytes,
          "Entry '\(entry.id)' has stallOnLargeReads=true but no maxChunkBytes cap")
      }
    }
  }

  func testIOTimeoutNotExceedOverallDeadline() {
    for entry in db.entries {
      guard let io = entry.ioTimeoutMs, let overall = entry.overallDeadlineMs else { continue }
      XCTAssertLessThanOrEqual(
        io, overall,
        "Entry '\(entry.id)' ioTimeoutMs \(io) > overallDeadlineMs \(overall)")
    }
  }

  func testHandshakeTimeoutNotExceedOverallDeadline() {
    for entry in db.entries {
      guard let hs = entry.handshakeTimeoutMs, let overall = entry.overallDeadlineMs else {
        continue
      }
      XCTAssertLessThanOrEqual(
        hs, overall,
        "Entry '\(entry.id)' handshakeTimeoutMs \(hs) > overallDeadlineMs \(overall)")
    }
  }

  // MARK: - Status Transitions

  func testPromotedEntriesHaveEvidence() {
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Promoted entry '\(entry.id)' must declare evidenceRequired")
      if let evidence = entry.evidenceRequired {
        XCTAssertFalse(
          evidence.isEmpty,
          "Promoted entry '\(entry.id)' must list at least one evidence type")
      }
    }
  }

  func testVerifiedEntriesHaveEvidence() {
    let verified = db.entries.filter { $0.status == .verified }
    for entry in verified {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Verified entry '\(entry.id)' should declare evidenceRequired")
    }
  }

  func testPromotedEntriesHaveLastVerifiedDate() {
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.lastVerifiedDate,
        "Promoted entry '\(entry.id)' should have lastVerifiedDate")
      if let date = entry.lastVerifiedDate {
        XCTAssertFalse(
          date.isEmpty,
          "Promoted entry '\(entry.id)' has empty lastVerifiedDate")
      }
    }
  }

  // MARK: - Confidence Field

  func testConfidenceValuesFromExpectedSet() {
    let validConfidence: Set<String> = ["low", "medium", "high", "community", "experimental"]
    for entry in db.entries {
      guard let conf = entry.confidence else { continue }
      XCTAssertTrue(
        validConfidence.contains(conf),
        "Entry '\(entry.id)' has unknown confidence '\(conf)'")
    }
  }

  // MARK: - Hook Validation

  func testHookDelaysArePositive() {
    for entry in db.entries {
      guard let hooks = entry.hooks else { continue }
      for hook in hooks {
        if let delay = hook.delayMs {
          XCTAssertGreaterThan(
            delay, 0,
            "Entry '\(entry.id)' hook \(hook.phase) has non-positive delay \(delay)")
        }
      }
    }
  }

  func testBusyBackoffRetriesArePositive() {
    for entry in db.entries {
      guard let hooks = entry.hooks else { continue }
      for hook in hooks {
        if let backoff = hook.busyBackoff {
          XCTAssertGreaterThan(
            backoff.retries, 0,
            "Entry '\(entry.id)' hook \(hook.phase) has non-positive retries")
          XCTAssertGreaterThan(
            backoff.baseMs, 0,
            "Entry '\(entry.id)' hook \(hook.phase) has non-positive baseMs")
          XCTAssertGreaterThanOrEqual(
            backoff.jitterPct, 0.0,
            "Entry '\(entry.id)' hook \(hook.phase) has negative jitterPct")
          XCTAssertLessThanOrEqual(
            backoff.jitterPct, 1.0,
            "Entry '\(entry.id)' hook \(hook.phase) has jitterPct > 1.0")
        }
      }
    }
  }

  // MARK: - VID/PID Structural Checks

  func testAllVIDsAreNonZero() {
    let zeros = db.entries.filter { $0.vid == 0 }
    XCTAssertTrue(
      zeros.isEmpty,
      "Entries with VID=0x0000: \(zeros.prefix(10).map(\.id))")
  }

  func testAllPIDsAreNonZero() {
    let zeros = db.entries.filter { $0.pid == 0 }
    XCTAssertTrue(
      zeros.isEmpty,
      "Entries with PID=0x0000: \(zeros.prefix(10).map(\.id))")
  }

  // MARK: - Cross-Field Consistency

  func testCameraClassEntriesHaveValidIfaceClass() {
    // Entries with cameraClass=true should have PTP (0x06) or vendor-specific (0xff) class
    let validClasses: Set<UInt8> = [0x06, 0xff]
    for entry in db.entries {
      guard let flags = entry.flags, flags.cameraClass else { continue }
      if let iface = entry.ifaceClass {
        XCTAssertTrue(
          validClasses.contains(iface),
          "Entry '\(entry.id)' has cameraClass=true but ifaceClass=0x\(String(iface, radix: 16))")
      }
    }
  }

  func testDeviceNamesAreNonEmptyWhenPresent() {
    let emptyNames = db.entries.filter {
      guard let name = $0.deviceName else { return false }
      return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    XCTAssertTrue(
      emptyNames.isEmpty,
      "Entries with blank deviceName: \(emptyNames.prefix(10).map(\.id))")
  }

  func testNoNilStatusOnPromotedConfidence() {
    // Entries with confidence "high" should not have nil status
    for entry in db.entries {
      if entry.confidence == "high" {
        XCTAssertNotNil(
          entry.status,
          "Entry '\(entry.id)' has confidence=high but nil status")
      }
    }
  }

  func testLastVerifiedDateFormatWhenPresent() {
    // ISO-8601 date: YYYY-MM-DD
    let datePattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
    for entry in db.entries {
      guard let date = entry.lastVerifiedDate, !date.isEmpty else { continue }
      let range = NSRange(date.startIndex..., in: date)
      XCTAssertNotNil(
        datePattern.firstMatch(in: date, range: range),
        "Entry '\(entry.id)' lastVerifiedDate '\(date)' not in YYYY-MM-DD format")
    }
  }
}
