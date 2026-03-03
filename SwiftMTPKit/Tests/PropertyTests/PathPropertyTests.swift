// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Generators

/// Generator for storage IDs.
private enum StorageIDGenerator {
  static var arbitrary: Gen<UInt32> {
    Gen<UInt32>
      .fromElements(of: [
        0x0001_0001, 0x0001_0002, 0x0002_0001,
        0x0001_0003, 0xFFFF_FFFF, 1,
      ])
  }
}

/// Generator for path component arrays.
private enum PathComponentsGen {
  static var arbitrary: Gen<[String]> {
    let allNames = [
      "DCIM", "Music", "Documents", "Photos", "Videos",
      "Download", "Pictures", "Camera", "2024", "vacation",
      "IMG_001.jpg", "track.mp3", "notes.txt", "photo.png",
      "naïve", "café", "文件", "ファイル", "emoji📷",
    ]
    return Gen<Int>.choose((0, 10))
      .flatMap { depth in
        if depth == 0 { return Gen.pure([String]()) }
        return Gen<[String]>
          .compose { composer in
            (0..<depth)
              .map { _ in
                composer.generate(using: Gen<String>.fromElements(of: allNames))
              }
          }
      }
  }
}

/// Generator for special-character path components.
private enum SpecialCharComponentGen {
  static var arbitrary: Gen<String> {
    Gen<String>
      .one(of: [
        Gen<String>
          .fromElements(of: [
            "file with spaces", "file-with-dashes", "file_with_underscores",
            "file.multiple.dots.txt", "UPPERCASE", "MiXeD CaSe",
            "naïve café", "日本語ファイル", "한국어파일", "中文文件",
            "emoji📷photo", "résumé.pdf", "Ångström.dat",
            "(parentheses)", "[brackets]", "{braces}",
            "file+plus", "file=equals", "file@at",
            "file#hash", "file$dollar", "file%percent",
            "file&ampersand", "file!exclaim",
          ])
      ])
  }
}

// MARK: - Path Property Tests

final class PathPropertyTests: XCTestCase {

  // MARK: - Path Normalization Idempotency

  /// Normalizing a path twice produces the same result as normalizing once.
  func testNormalizationIsIdempotent() {
    property("PathKey.normalize is idempotent")
      <- forAll(StorageIDGenerator.arbitrary, PathComponentsGen.arbitrary) {
        (storage: UInt32, components: [String]) in
        let once = PathKey.normalize(storage: storage, components: components)
        let (parsedStorage, parsedComponents) = PathKey.parse(once)
        let twice = PathKey.normalize(storage: parsedStorage, components: parsedComponents)
        return once == twice
      }
  }

  /// NormalizeComponent is idempotent.
  func testComponentNormalizationIsIdempotent() {
    property("PathKey.normalizeComponent is idempotent")
      <- forAll(SpecialCharComponentGen.arbitrary) { (component: String) in
        let once = PathKey.normalizeComponent(component)
        let twice = PathKey.normalizeComponent(once)
        return once == twice
      }
  }

  /// Normalizing arbitrary strings is idempotent.
  func testArbitraryComponentNormalizationIdempotent() {
    property("PathKey.normalizeComponent idempotent for arbitrary strings")
      <- forAll { (s: String) in
        let once = PathKey.normalizeComponent(s)
        let twice = PathKey.normalizeComponent(once)
        return once == twice
      }
  }

  // MARK: - Path Joining Associativity

  /// Joining path components is associative: join(a, join(b, c)) == join(a ++ b, c).
  func testPathJoiningIsAssociative() {
    property("Path component joining is associative")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary,
        PathComponentsGen.arbitrary
      ) { (storage: UInt32, left: [String], right: [String]) in
        let combined = PathKey.normalize(storage: storage, components: left + right)
        // Normalize left then append right components
        let leftPath = PathKey.normalize(storage: storage, components: left)
        let (_, leftParsed) = PathKey.parse(leftPath)
        let sequential = PathKey.normalize(
          storage: storage, components: leftParsed + right)
        return combined == sequential
      }
  }

  /// Concatenating empty components on either side is identity.
  func testEmptyComponentsConcatIsIdentity() {
    property("Appending empty component array is identity")
      <- forAll(StorageIDGenerator.arbitrary, PathComponentsGen.arbitrary) {
        (storage: UInt32, components: [String]) in
        let original = PathKey.normalize(storage: storage, components: components)
        let withEmpty = PathKey.normalize(storage: storage, components: components + [])
        return original == withEmpty
      }
  }

  // MARK: - Parent/Child Relationship

  /// Parent path of a child path returns a prefix of the original.
  func testParentOfChildReturnsPrefix() {
    property("Parent of a child path is a prefix of the child")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary.suchThat { $0.count >= 2 }
      ) { (storage: UInt32, components: [String]) in
        let childPath = PathKey.normalize(storage: storage, components: components)
        guard let parentPath = PathKey.parent(of: childPath) else {
          return false
        }
        // Parent should be a prefix of the child (either string prefix or isPrefix)
        return PathKey.isPrefix(parentPath, of: childPath)
      }
  }

  /// Parent of a single-component path returns nil (at root level of storage).
  func testParentOfSingleComponentIsNil() {
    property("Parent of single-component path is nil")
      <- forAll(
        StorageIDGenerator.arbitrary,
        Gen<String>.fromElements(of: ["DCIM", "Music", "file.txt"])
      ) { (storage: UInt32, name: String) in
        let path = PathKey.normalize(storage: storage, components: [name])
        return PathKey.parent(of: path) == nil
      }
  }

  /// Parent of a bare storage ID (no components) returns nil.
  func testParentOfBareStorageIsNil() {
    property("Parent of bare storage path is nil")
      <- forAll(StorageIDGenerator.arbitrary) { (storage: UInt32) in
        let path = PathKey.normalize(storage: storage, components: [])
        return PathKey.parent(of: path) == nil
      }
  }

  // MARK: - Basename

  /// Basename of a normalized path returns the last component.
  func testBasenameReturnsLastComponent() {
    property("Basename returns the last normalized component")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary.suchThat { !$0.isEmpty }
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        let basename = PathKey.basename(of: path)
        let expectedLast = PathKey.normalizeComponent(components.last!)
        return basename == expectedLast
      }
  }

  /// Basename of a bare storage path is empty.
  func testBasenameOfBareStorageIsEmpty() {
    property("Basename of bare storage path is empty string")
      <- forAll(StorageIDGenerator.arbitrary) { (storage: UInt32) in
        let path = PathKey.normalize(storage: storage, components: [])
        return PathKey.basename(of: path) == ""
      }
  }

  // MARK: - Case Sensitivity

  /// Case-insensitive comparison of identical strings is reflexive.
  func testCaseInsensitiveComparisonIsReflexive() {
    property("Case-insensitive comparison is reflexive")
      <- forAll(SpecialCharComponentGen.arbitrary) { (name: String) in
        return name.caseInsensitiveCompare(name) == .orderedSame
      }
  }

  /// Case-insensitive comparison is symmetric.
  func testCaseInsensitiveComparisonIsSymmetric() {
    property("Case-insensitive comparison is symmetric")
      <- forAll(
        SpecialCharComponentGen.arbitrary,
        SpecialCharComponentGen.arbitrary
      ) { (a: String, b: String) in
        let ab = a.caseInsensitiveCompare(b)
        let ba = b.caseInsensitiveCompare(a)
        switch ab {
        case .orderedSame: return ba == .orderedSame
        case .orderedAscending: return ba == .orderedDescending
        case .orderedDescending: return ba == .orderedAscending
        }
      }
  }

  /// Case-insensitive comparison is transitive.
  func testCaseInsensitiveComparisonIsTransitive() {
    property("Case-insensitive comparison is transitive for equal values")
      <- forAll(SpecialCharComponentGen.arbitrary) { (name: String) in
        let upper = name.uppercased()
        let lower = name.lowercased()
        let eq1 = name.caseInsensitiveCompare(upper) == .orderedSame
        let eq2 = upper.caseInsensitiveCompare(lower) == .orderedSame
        let eq3 = name.caseInsensitiveCompare(lower) == .orderedSame
        // If a == b and b == c then a == c
        if eq1 && eq2 { return eq3 }
        return true
      }
  }

  // MARK: - Special Characters

  /// Special characters in path components survive normalize round-trip.
  func testSpecialCharactersSurviveRoundTrip() {
    property("Special characters survive PathKey normalize/parse round-trip")
      <- forAll(
        StorageIDGenerator.arbitrary,
        SpecialCharComponentGen.arbitrary
      ) { (storage: UInt32, component: String) in
        let normalized = PathKey.normalize(storage: storage, components: [component])
        let (parsedStorage, parsedComponents) = PathKey.parse(normalized)
        let reNormalized = PathKey.normalize(
          storage: parsedStorage, components: parsedComponents)
        return normalized == reNormalized
      }
  }

  /// Unicode normalization (NFC) is preserved through round-trip.
  func testUnicodeNFCPreservedThroughRoundTrip() {
    // Test with composed vs decomposed forms
    let testCases = [
      ("é", "\u{00E9}"),  // precomposed
      ("é", "e\u{0301}"),  // decomposed
      ("ñ", "\u{00F1}"),
      ("ü", "\u{00FC}"),
    ]
    for (_, form) in testCases {
      let normalized = PathKey.normalizeComponent(form)
      let reNormalized = PathKey.normalizeComponent(normalized)
      XCTAssertEqual(normalized, reNormalized, "NFC should be stable: \(form)")
    }
  }

  // MARK: - Empty Path Components

  /// Empty component is replaced with underscore.
  func testEmptyComponentBecomesUnderscore() {
    let result = PathKey.normalizeComponent("")
    XCTAssertEqual(result, "_")
  }

  /// All-control-character component becomes underscore.
  func testControlCharOnlyComponentBecomesUnderscore() {
    let controlStr = String(UnicodeScalar(0x01)!) + String(UnicodeScalar(0x02)!)
    let result = PathKey.normalizeComponent(controlStr)
    XCTAssertEqual(result, "_")
  }

  /// Slashes in components are stripped.
  func testSlashesInComponentsAreStripped() {
    property("Forward/backslashes are removed from components")
      <- forAll(
        Gen<String>
          .fromElements(of: [
            "path/traversal", "back\\slash", "a/b/c",
            "/leading", "trailing/", "mixed/back\\slash",
          ])
      ) { (input: String) in
        let normalized = PathKey.normalizeComponent(input)
        return !normalized.contains("/") && !normalized.contains("\\")
      }
  }

  // MARK: - isPrefix

  /// isPrefix is not reflexive (a path is not a prefix of itself).
  func testIsPrefixNotReflexive() {
    property("A path is not a prefix of itself")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        return !PathKey.isPrefix(path, of: path)
      }
  }

  /// isPrefix holds for proper parent-child relationships.
  func testIsPrefixForParentChild() {
    property("isPrefix holds for parent-child paths")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary.suchThat { $0.count >= 1 },
        Gen<String>.fromElements(of: ["child.txt", "subdir", "photo.jpg"])
      ) { (storage: UInt32, parentComponents: [String], childName: String) in
        let parentPath = PathKey.normalize(storage: storage, components: parentComponents)
        let childPath = PathKey.normalize(
          storage: storage, components: parentComponents + [childName])
        return PathKey.isPrefix(parentPath, of: childPath)
      }
  }

  /// isPrefix is false for paths with different storage IDs.
  func testIsPrefixFalseForDifferentStorage() {
    property("isPrefix is false when storage IDs differ")
      <- forAll(
        PathComponentsGen.arbitrary.suchThat { $0.count >= 1 },
        Gen<String>.fromElements(of: ["child.txt"])
      ) { (components: [String], childName: String) in
        let parent = PathKey.normalize(storage: 0x0001_0001, components: components)
        let child = PathKey.normalize(
          storage: 0x0002_0001, components: components + [childName])
        return !PathKey.isPrefix(parent, of: child)
      }
  }

  // MARK: - Parse Round-Trip

  /// Parse is the inverse of normalize.
  func testParseIsInverseOfNormalize() {
    property("parse(normalize(s, c)) recovers storage and components")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary.suchThat { !$0.isEmpty }
      ) { (storage: UInt32, components: [String]) in
        let normalized = PathKey.normalize(storage: storage, components: components)
        let (parsedStorage, parsedComponents) = PathKey.parse(normalized)
        return parsedStorage == storage
          && parsedComponents
            == components.map { PathKey.normalizeComponent($0) }
      }
  }

  // MARK: - fromLocalURL

  /// fromLocalURL returns nil when URL is not under root.
  func testFromLocalURLReturnsNilForUnrelatedPath() {
    let root = URL(fileURLWithPath: "/tmp/root")
    let url = URL(fileURLWithPath: "/other/path/file.txt")
    XCTAssertNil(PathKey.fromLocalURL(url, relativeTo: root, storage: 0x0001_0001))
  }

  /// fromLocalURL returns a valid path key for a file under root.
  func testFromLocalURLReturnsValidPathKey() {
    let root = URL(fileURLWithPath: "/tmp/root")
    let url = URL(fileURLWithPath: "/tmp/root/DCIM/photo.jpg")
    let result = PathKey.fromLocalURL(url, relativeTo: root, storage: 0x0001_0001)
    XCTAssertNotNil(result)
    if let pathKey = result {
      let (storageId, components) = PathKey.parse(pathKey)
      XCTAssertEqual(storageId, 0x0001_0001)
      XCTAssertEqual(components, ["DCIM", "photo.jpg"])
    }
  }

  // MARK: - Normalize Storage Prefix Format

  /// Storage ID is always formatted as 8-digit lowercase hex.
  func testStorageIDFormattedAsEightDigitHex() {
    property("Storage prefix is always 8 lowercase hex digits")
      <- forAll(StorageIDGenerator.arbitrary) { (storage: UInt32) in
        let path = PathKey.normalize(storage: storage, components: [])
        return path.count == 8
          && path.allSatisfy { "0123456789abcdef".contains($0) }
      }
  }

  /// Normalized path always starts with the storage prefix.
  func testNormalizedPathStartsWithStoragePrefix() {
    property("Normalized path starts with storage hex prefix")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        let prefix = String(format: "%08x", storage)
        return path.hasPrefix(prefix)
      }
  }

  // MARK: - Depth Preservation

  /// Path depth is preserved through normalize/parse.
  func testPathDepthPreserved() {
    property("Component count is preserved through round-trip")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        let (_, parsed) = PathKey.parse(path)
        return parsed.count == components.count
      }
  }

  /// Normalized components never contain slashes.
  func testNormalizedComponentsNeverContainSlashes() {
    property("No normalized component contains a slash")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        let (_, parsed) = PathKey.parse(path)
        return parsed.allSatisfy { !$0.contains("/") && !$0.contains("\\") }
      }
  }

  /// Normalized components are never empty.
  func testNormalizedComponentsNeverEmpty() {
    property("No normalized component is empty")
      <- forAll(
        StorageIDGenerator.arbitrary,
        PathComponentsGen.arbitrary.suchThat { !$0.isEmpty }
      ) { (storage: UInt32, components: [String]) in
        let path = PathKey.normalize(storage: storage, components: components)
        let (_, parsed) = PathKey.parse(path)
        return parsed.allSatisfy { !$0.isEmpty }
      }
  }
}
