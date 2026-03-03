// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

/// Release readiness checks — validates that repository artifacts, packaging,
/// and documentation are in a shippable state.
final class ReleaseReadinessTests: XCTestCase {

  // MARK: - Helpers

  /// Root of the SwiftMTPKit package (two levels up from the test source file).
  private var packageRoot: URL {
    // Tests/IntegrationTests/ReleaseReadinessTests.swift → SwiftMTPKit/
    let thisFile = URL(fileURLWithPath: #filePath)
    return
      thisFile
      .deletingLastPathComponent()  // IntegrationTests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // SwiftMTPKit/
  }

  /// Repository root (one level above SwiftMTPKit/).
  private var repoRoot: URL {
    packageRoot.deletingLastPathComponent()
  }

  // MARK: - Package.swift

  func testPackageSwiftIsParseable() throws {
    let packageSwift = packageRoot.appendingPathComponent("Package.swift")
    let content = try String(contentsOf: packageSwift, encoding: .utf8)
    XCTAssertTrue(
      content.contains("let package = Package("),
      "Package.swift must contain a Package declaration")
  }

  func testPackageSwiftHasRequiredProducts() throws {
    let packageSwift = packageRoot.appendingPathComponent("Package.swift")
    let content = try String(contentsOf: packageSwift, encoding: .utf8)

    let requiredProducts = [
      "SwiftMTPCore",
      "SwiftMTPTransportLibUSB",
      "SwiftMTPIndex",
      "SwiftMTPSync",
      "SwiftMTPQuirks",
      "SwiftMTPStore",
      "SwiftMTPObservability",
      "SwiftMTPXPC",
      "SwiftMTPFileProvider",
      "SwiftMTPTestKit",
      "SwiftMTPCLI",
      "swiftmtp",
    ]

    for product in requiredProducts {
      XCTAssertTrue(
        content.contains("\"\(product)\""),
        "Package.swift must define product '\(product)'")
    }
  }

  func testAllTestTargetsAreLinked() throws {
    let packageSwift = packageRoot.appendingPathComponent("Package.swift")
    let content = try String(contentsOf: packageSwift, encoding: .utf8)

    let expectedTestTargets = [
      "CoreTests", "IndexTests", "TransportTests", "BDDTests",
      "PropertyTests", "SnapshotTests", "TestKitTests",
      "FileProviderTests", "XPCTests", "IntegrationTests",
      "StoreTests", "SyncTests", "QuirksTests", "ObservabilityTests",
      "ErrorHandlingTests", "ScenarioTests", "ToolingTests",
      "MTPEndianCodecTests", "SwiftMTPCLITests",
    ]

    for target in expectedTestTargets {
      XCTAssertTrue(
        content.contains(".testTarget(") && content.contains("\"\(target)\""),
        "Package.swift must define test target '\(target)'")
    }
  }

  // MARK: - Repository Files

  func testREADMEExists() throws {
    let readme = repoRoot.appendingPathComponent("README.md")
    let content = try String(contentsOf: readme, encoding: .utf8)
    XCTAssertGreaterThan(
      content.count, 100,
      "README.md must exist and be non-trivial")
  }

  func testCHANGELOGExistsAndContainsVersionInfo() throws {
    let changelog = repoRoot.appendingPathComponent("CHANGELOG.md")
    let content = try String(contentsOf: changelog, encoding: .utf8)
    XCTAssertTrue(
      content.contains("## ["),
      "CHANGELOG.md must contain version headings")
    XCTAssertTrue(
      content.contains("Unreleased") || content.contains("unreleased"),
      "CHANGELOG.md should have an Unreleased section")
  }

  func testLICENSEExists() throws {
    let license = repoRoot.appendingPathComponent("LICENSE")
    let exists = FileManager.default.fileExists(atPath: license.path)
    XCTAssertTrue(exists, "LICENSE file must exist at repository root")
  }

  // MARK: - Quirks Database

  func testQuirksJSONIsValid() throws {
    let quirksPath =
      packageRoot
      .appendingPathComponent("Sources")
      .appendingPathComponent("SwiftMTPQuirks")
      .appendingPathComponent("Resources")
      .appendingPathComponent("quirks.json")

    let data = try Data(contentsOf: quirksPath)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(json, "quirks.json must be valid JSON object")

    let entries = json?["entries"] as? [[String: Any]]
    XCTAssertNotNil(entries, "quirks.json must have an 'entries' array")
    XCTAssertGreaterThan(
      entries?.count ?? 0, 1000,
      "quirks.json must have >1000 entries")
  }

  func testBothQuirksJSONCopiesAreInSync() throws {
    let specsQuirks =
      repoRoot
      .appendingPathComponent("Specs")
      .appendingPathComponent("quirks.json")
    let resourceQuirks =
      packageRoot
      .appendingPathComponent("Sources")
      .appendingPathComponent("SwiftMTPQuirks")
      .appendingPathComponent("Resources")
      .appendingPathComponent("quirks.json")

    let specsData = try Data(contentsOf: specsQuirks)
    let resourceData = try Data(contentsOf: resourceQuirks)

    XCTAssertEqual(
      specsData, resourceData,
      "Specs/quirks.json and SwiftMTPQuirks/Resources/quirks.json must be identical")
  }

  // MARK: - Code Quality

  func testNoTODOFixmeHackInPublicAPIs() throws {
    let publicDirs = [
      packageRoot.appendingPathComponent("Sources/SwiftMTPCore/Public"),
      packageRoot.appendingPathComponent("Sources/SwiftMTPQuirks/Public"),
    ]

    let markers = ["TODO:", "FIXME:", "HACK:"]

    for dir in publicDirs {
      guard FileManager.default.fileExists(atPath: dir.path) else { continue }
      let enumerator = FileManager.default.enumerator(
        at: dir, includingPropertiesForKeys: nil)
      while let fileURL = enumerator?.nextObject() as? URL {
        guard fileURL.pathExtension == "swift" else { continue }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        for marker in markers {
          XCTAssertFalse(
            content.contains(marker),
            "\(fileURL.lastPathComponent) contains '\(marker)' — resolve before release")
        }
      }
    }
  }

  func testPublicTypesHaveDocComments() throws {
    let publicDir = packageRoot.appendingPathComponent("Sources/SwiftMTPCore/Public")
    guard FileManager.default.fileExists(atPath: publicDir.path) else {
      XCTFail("Public API directory not found")
      return
    }

    let enumerator = FileManager.default.enumerator(
      at: publicDir, includingPropertiesForKeys: nil)
    var undocumented: [String] = []

    while let fileURL = enumerator?.nextObject() as? URL {
      guard fileURL.pathExtension == "swift" else { continue }
      let content = try String(contentsOf: fileURL, encoding: .utf8)
      let lines = content.components(separatedBy: .newlines)

      for (i, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isPublicDecl =
          trimmed.hasPrefix("public struct ") || trimmed.hasPrefix("public class ")
          || trimmed.hasPrefix("public enum ") || trimmed.hasPrefix("public protocol ")
          || trimmed.hasPrefix("public actor ")

        guard isPublicDecl else { continue }

        // Check preceding lines for doc comment (/// or /**)
        var hasDoc = false
        var checkLine = i - 1
        while checkLine >= 0 {
          let prev = lines[checkLine].trimmingCharacters(in: .whitespaces)
          if prev.hasPrefix("///") || prev.hasPrefix("/**") || prev.hasSuffix("*/") {
            hasDoc = true
            break
          } else if prev.isEmpty || prev.hasPrefix("@") || prev.hasPrefix("#") {
            // Skip attributes, compiler directives, blank lines
            checkLine -= 1
            continue
          } else {
            break
          }
        }

        if !hasDoc {
          undocumented.append("\(fileURL.lastPathComponent): \(trimmed)")
        }
      }
    }

    XCTAssertEqual(
      undocumented.count, 0,
      "Undocumented public types found:\n\(undocumented.joined(separator: "\n"))")
  }
}
