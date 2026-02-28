// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPIndex

// MARK: - PathKey Tests

@Suite("PathKey Tests")
struct PathKeyTests {

  // MARK: - Basic Normalization Tests

  @Test("Normalize simple component")
  func testNormalizeSimpleComponent() {
    #expect(PathKey.normalizeComponent("file.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("MyFile.jpg") == "MyFile.jpg")
  }

  @Test("Normalize component with control characters")
  func testNormalizeComponentWithControlChars() {
    #expect(PathKey.normalizeComponent("file\u{00}.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("file\n.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("file\t.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("file\r.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("file\u{1b}.txt") == "file.txt")  // ESC
  }

  @Test("Normalize component with slashes")
  func testNormalizeComponentWithSlashes() {
    #expect(PathKey.normalizeComponent("file/with/slashes.txt") == "filewithslashes.txt")
    #expect(PathKey.normalizeComponent("file\\with\\backslashes.txt") == "filewithbackslashes.txt")
    #expect(
      PathKey.normalizeComponent("file/with/mixed\\slashes.txt") == "filewithmixedslashes.txt")
  }

  @Test("Normalize component NFC")
  func testNormalizeComponentNFC() {
    // Test with a character that has composed/decomposed forms
    let nfd = "cafe\u{0301}"  // Decomposed (café with combining accent)
    let nfc = "café"  // Composed
    #expect(PathKey.normalizeComponent(nfd) == nfc)

    // Test with German umlaut
    let nfdUmlaut = "Mu\u{0308}ller"  // Decomposed
    let nfcUmlaut = "Müller"  // Composed
    #expect(PathKey.normalizeComponent(nfdUmlaut) == nfcUmlaut)
  }

  @Test("Normalize component empty result")
  func testNormalizeComponentEmpty() {
    #expect(PathKey.normalizeComponent("") == "_")
    #expect(PathKey.normalizeComponent("\u{00}\u{01}\u{02}") == "_")
    #expect(PathKey.normalizeComponent("///") == "_")
  }

  // MARK: - Unicode Path Tests

  @Test("Normalize emoji in path")
  func testNormalizeEmoji() {
    #expect(PathKey.normalizeComponent("📷 photo.jpg") == "📷 photo.jpg")
    #expect(PathKey.normalizeComponent("file🎉.txt") == "file🎉.txt")
    #expect(PathKey.normalizeComponent("🎉") == "🎉")
  }

  @Test("Normalize accented characters")
  func testNormalizeAccentedCharacters() {
    // French accents
    #expect(PathKey.normalizeComponent("café") == "café")
    #expect(PathKey.normalizeComponent("naïve") == "naïve")

    // Spanish accents
    #expect(PathKey.normalizeComponent("niño") == "niño")
    #expect(PathKey.normalizeComponent("Señor") == "Señor")

    // Nordic characters
    #expect(PathKey.normalizeComponent("Ångström") == "Ångström")
    #expect(PathKey.normalizeComponent("øresund") == "øresund")
  }

  @Test("Normalize CJK characters")
  func testNormalizeCJK() {
    // Chinese characters (should pass through unchanged)
    #expect(PathKey.normalizeComponent("文件.txt") == "文件.txt")
    #expect(PathKey.normalizeComponent("中文") == "中文")

    // Japanese
    #expect(PathKey.normalizeComponent("日本語.txt") == "日本語.txt")

    // Korean
    #expect(PathKey.normalizeComponent("파일.txt") == "파일.txt")
  }

  @Test("Normalize mixed Unicode")
  func testNormalizeMixedUnicode() {
    let mixed = "café-🎉-файл-文件.txt"
    let result = PathKey.normalizeComponent(mixed)
    #expect(result.contains("café"))
    #expect(result.contains("файл"))
    #expect(result.contains("文件"))
    #expect(result.hasSuffix(".txt"))
  }

  // MARK: - Long Path Tests

  @Test("Very long paths (>255 characters)")
  func testVeryLongPaths() {
    // Create a path longer than typical filesystem limits
    let longName = String(repeating: "a", count: 300)
    let result = PathKey.normalizeComponent(longName)
    #expect(result.count == 300)
    #expect(result == longName)
  }

  @Test("Long path with components")
  func testLongPathWithComponents() {
    let components = (0..<50).map { "folder\($0)" }
    let result = PathKey.normalize(storage: 0x10001, components: components)
    #expect(result.hasPrefix("00010001/"))

    let parsed = PathKey.parse(result)
    #expect(parsed.storageId == 0x10001)
    #expect(parsed.components.count == 50)
  }

  @Test("Maximum depth path")
  func testMaximumDepthPath() {
    let deepComponents = (0..<100).map { "level\($0)" }
    let result = PathKey.normalize(storage: 0x20002, components: deepComponents)

    let parsed = PathKey.parse(result)
    #expect(parsed.components.count == 100)
    #expect(parsed.storageId == 0x20002)
  }

  // MARK: - Path Normalization Edge Cases

  @Test("Normalize whitespace variations")
  func testNormalizeWhitespace() {
    #expect(PathKey.normalizeComponent("file  with  spaces") == "file  with  spaces")
    #expect(PathKey.normalizeComponent("file\twith\ttabs") == "filewithtabs")
    #expect(PathKey.normalizeComponent("file\nwith\nnewlines") == "filewithnewlines")
  }

  @Test("Normalize Unicode normalization forms")
  func testUnicodeNormalizationForms() {
    // NFD (decomposed)
    let nfd = "\u{0041}\u{0300}"  // À (A + combining grave)
    // NFC (composed)
    let nfc = "\u{00C0}"  // À (precomposed)

    #expect(PathKey.normalizeComponent(nfd) == nfc)
  }

  @Test("Normalize special Unicode characters")
  func testNormalizeSpecialUnicode() {
    // Zero-width characters should be stripped
    #expect(PathKey.normalizeComponent("file\u{200B}.txt") == "file.txt")
    #expect(PathKey.normalizeComponent("file\u{200C}.txt") == "file.txt")

    // Byte order mark should be stripped
    #expect(PathKey.normalizeComponent("\u{FEFF}hidden") == "hidden")
  }

  // MARK: - Path Key Operations Tests

  @Test("Normalize path with components")
  func testNormalizePath() {
    let components = ["folder", "subfolder", "file.txt"]
    let result = PathKey.normalize(storage: 0x10001, components: components)
    #expect(result == "00010001/folder/subfolder/file.txt")
  }

  @Test("Normalize path with special characters")
  func testNormalizePathSpecialChars() {
    let components = ["folder with spaces", "file-with-dashes.jpg"]
    let result = PathKey.normalize(storage: 0x20002, components: components)
    #expect(result == "00020002/folder with spaces/file-with-dashes.jpg")
  }

  @Test("Parse path key")
  func testParsePathKey() {
    let pathKey = "00010001/folder/subfolder/file.txt"
    let (storageId, components) = PathKey.parse(pathKey)
    #expect(storageId == 0x10001)
    #expect(components == ["folder", "subfolder", "file.txt"])
  }

  @Test("Parse path key with no components")
  func testParsePathKeyNoComponents() {
    let pathKey = "00010001/"
    let (storageId, components) = PathKey.parse(pathKey)
    #expect(storageId == 0x10001)
    #expect(components.isEmpty)
  }

  @Test("Parse invalid path key")
  func testParseInvalidPathKey() {
    let pathKey = "invalid"
    let (storageId, components) = PathKey.parse(pathKey)
    #expect(storageId == 0)
    #expect(components.isEmpty)
  }

  @Test("Parse path key with hex storage ID")
  func testParseHexStorageId() {
    let pathKey = "deadbeef/path/to/file.txt"
    let (storageId, components) = PathKey.parse(pathKey)
    #expect(storageId == 0xDEADBEEF)
    #expect(components == ["path", "to", "file.txt"])
  }

  @Test("Parse path key with lowercase hex")
  func testParseLowercaseHex() {
    let pathKey = "a1b2c3d4/test.txt"
    let (storageId, _) = PathKey.parse(pathKey)
    #expect(storageId == 0xA1B2C3D4)
  }

  // MARK: - Path Hierarchy Tests

  @Test("Get parent path")
  func testGetParent() {
    let pathKey = "00010001/folder/subfolder/file.txt"
    let parent = PathKey.parent(of: pathKey)
    #expect(parent == "00010001/folder/subfolder")
  }

  @Test("Get parent of root path")
  func testGetParentOfRoot() {
    let pathKey = "00010001/file.txt"
    let parent = PathKey.parent(of: pathKey)
    #expect(parent == nil)
  }

  @Test("Get parent of storage root")
  func testGetParentOfStorageRoot() {
    let pathKey = "00010001/"
    let parent = PathKey.parent(of: pathKey)
    #expect(parent == nil)
  }

  @Test("Get multiple levels of parent")
  func testGetMultipleParents() {
    let pathKey = "00010001/a/b/c/d/e/file.txt"

    let parent1 = PathKey.parent(of: pathKey)
    #expect(parent1 == "00010001/a/b/c/d/e")

    let parent2 = PathKey.parent(of: parent1!)
    #expect(parent2 == "00010001/a/b/c/d")

    let parent3 = PathKey.parent(of: parent2!)
    #expect(parent3 == "00010001/a/b/c")

    let parent4 = PathKey.parent(of: parent3!)
    #expect(parent4 == "00010001/a/b")

    let parent5 = PathKey.parent(of: parent4!)
    #expect(parent5 == "00010001/a")

    let parent6 = PathKey.parent(of: parent5!)
    #expect(parent6 == nil)
  }

  // MARK: - Basename Tests

  @Test("Get basename")
  func testGetBasename() {
    let pathKey = "00010001/folder/subfolder/file.txt"
    let basename = PathKey.basename(of: pathKey)
    #expect(basename == "file.txt")
  }

  @Test("Get basename of root file")
  func testGetBasenameOfRootFile() {
    let pathKey = "00010001/file.txt"
    let basename = PathKey.basename(of: pathKey)
    #expect(basename == "file.txt")
  }

  @Test("Get basename of directory")
  func testGetBasenameOfDirectory() {
    let pathKey = "00010001/DCIM"
    let basename = PathKey.basename(of: pathKey)
    #expect(basename == "DCIM")
  }

  // MARK: - Path Prefix Tests

  @Test("Check path prefix")
  func testIsPrefix() {
    let prefix = "00010001/folder"
    let path = "00010001/folder/subfolder/file.txt"
    #expect(PathKey.isPrefix(prefix, of: path))
  }

  @Test("Check path prefix with different storage")
  func testIsPrefixDifferentStorage() {
    let prefix = "00010001/folder"
    let path = "00020002/folder/subfolder/file.txt"
    #expect(!PathKey.isPrefix(prefix, of: path))
  }

  @Test("Check path prefix too long")
  func testIsPrefixTooLong() {
    let prefix = "00010001/folder/subfolder/file.txt/extra"
    let path = "00010001/folder/subfolder/file.txt"
    #expect(!PathKey.isPrefix(prefix, of: path))
  }

  @Test("Check exact path match is not prefix")
  func testExactPathNotPrefix() {
    let prefix = "00010001/folder/subfolder/file.txt"
    let path = "00010001/folder/subfolder/file.txt"
    #expect(!PathKey.isPrefix(prefix, of: path))
  }

  @Test("Check empty prefix")
  func testEmptyPrefix() {
    let path = "00010001/folder/file.txt"
    #expect(PathKey.isPrefix("00010001", of: path))
  }

  // MARK: - Path Collision Tests

  @Test("Detect path collision same storage")
  func testPathCollisionSameStorage() {
    let key1 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "photo.jpg"])
    let key2 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "photo.jpg"])
    #expect(key1 == key2)
  }

  @Test("Detect no collision different storage")
  func testNoCollisionDifferentStorage() {
    let key1 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "photo.jpg"])
    let key2 = PathKey.normalize(storage: 0x10002, components: ["DCIM", "photo.jpg"])
    #expect(key1 != key2)
  }

  @Test("Detect no collision different name")
  func testNoCollisionDifferentName() {
    let key1 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "photo1.jpg"])
    let key2 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "photo2.jpg"])
    #expect(key1 != key2)
  }

  @Test("Detect no collision different path")
  func testNoCollisionDifferentPath() {
    let key1 = PathKey.normalize(storage: 0x10001, components: ["DCIM", "folder", "photo.jpg"])
    let key2 = PathKey.normalize(storage: 0x10001, components: ["Pictures", "photo.jpg"])
    #expect(key1 != key2)
  }

  // MARK: - Local URL Conversion Tests

  @Test("Convert local URL to path key")
  func testFromLocalURL() throws {
    let rootURL = URL(fileURLWithPath: "/root")
    let fileURL = URL(fileURLWithPath: "/root/folder/subfolder/file.txt")
    let pathKey = PathKey.fromLocalURL(fileURL, relativeTo: rootURL, storage: 0x10001)
    #expect(pathKey == "00010001/folder/subfolder/file.txt")
  }

  @Test("Convert local URL outside root")
  func testFromLocalURLOutsideRoot() throws {
    let rootURL = URL(fileURLWithPath: "/root")
    let fileURL = URL(fileURLWithPath: "/other/file.txt")
    let pathKey = PathKey.fromLocalURL(fileURL, relativeTo: rootURL, storage: 0x10001)
    #expect(pathKey == nil)
  }

  @Test("Convert root URL")
  func testFromLocalURLRoot() throws {
    let rootURL = URL(fileURLWithPath: "/root")
    let fileURL = URL(fileURLWithPath: "/root")
    let pathKey = PathKey.fromLocalURL(fileURL, relativeTo: rootURL, storage: 0x10001)
    #expect(pathKey == "00010001")
  }

  @Test("Convert URL with trailing slash")
  func testFromLocalURLWithTrailingSlash() throws {
    let rootURL = URL(fileURLWithPath: "/root/")
    let fileURL = URL(fileURLWithPath: "/root/folder/file.txt")
    let pathKey = PathKey.fromLocalURL(fileURL, relativeTo: rootURL, storage: 0x10001)
    #expect(pathKey == "00010001/folder/file.txt")
  }

  // MARK: - Hierarchical Path Building Tests

  @Test("Build path hierarchy from components")
  func testBuildHierarchyFromComponents() {
    let root = PathKey.normalize(storage: 0x10001, components: ["DCIM"])
    let subfolder = PathKey.normalize(storage: 0x10001, components: ["DCIM", "2024"])
    let file = PathKey.normalize(storage: 0x10001, components: ["DCIM", "2024", "photo.jpg"])

    // Verify hierarchical relationship
    #expect(PathKey.isPrefix(root, of: subfolder))
    #expect(PathKey.isPrefix(root, of: file))
    #expect(PathKey.isPrefix(subfolder, of: file))

    // Verify parent chain
    #expect(PathKey.parent(of: file) == subfolder)
    #expect(PathKey.parent(of: subfolder) == root)
    #expect(PathKey.parent(of: root) == nil)
  }

  @Test("Build deep hierarchy")
  func testBuildDeepHierarchy() {
    let components = ["storage", "photos", "2024", "january", "events", "vacation", "images"]
    let deepPath = PathKey.normalize(storage: 0xDEADBEEF, components: components)

    let parsed = PathKey.parse(deepPath)
    #expect(parsed.storageId == 0xDEADBEEF)
    #expect(parsed.components == components)

    // Verify each level's parent
    for i in 0..<components.count {
      let path = PathKey.normalize(storage: 0xDEADBEEF, components: Array(components[0...i]))
      let parent = PathKey.parent(of: path)

      if i == 0 {
        #expect(parent == nil)
      } else {
        let expectedParent = PathKey.normalize(
          storage: 0xDEADBEEF, components: Array(components[0..<i]))
        #expect(parent == expectedParent)
      }
    }
  }

  @Test("Path round-trip")
  func testPathRoundTrip() {
    let originalComponents = ["DCIM", "photos", "vacation", "IMG_20241208_123456.jpg"]
    let storageId: UInt32 = 0xABCDEF01

    let normalized = PathKey.normalize(storage: storageId, components: originalComponents)
    let (parsedStorageId, parsedComponents) = PathKey.parse(normalized)

    #expect(parsedStorageId == storageId)
    #expect(parsedComponents == originalComponents)
  }

  // MARK: - Edge Cases

  @Test("Handle component with only dots")
  func testComponentWithOnlyDots() {
    #expect(PathKey.normalizeComponent("...") == "...")
    #expect(PathKey.normalizeComponent(".") == ".")
    #expect(PathKey.normalizeComponent("..") == "..")
  }

  @Test("Handle component with Unicode dots")
  func testComponentWithUnicodeDots() {
    // Full-width dot (U+3002) should pass through
    #expect(PathKey.normalizeComponent("file。txt") == "file。txt")
    // Middle dot (U+00B7) should pass through
    #expect(PathKey.normalizeComponent("file·txt") == "file·txt")
  }

  @Test("Handle very short storage ID")
  func testVeryShortStorageId() {
    let result = PathKey.normalize(storage: 0x01, components: ["test"])
    #expect(result == "00000001/test")
  }

  @Test("Handle zero storage ID")
  func testZeroStorageId() {
    let result = PathKey.normalize(storage: 0x00, components: ["test"])
    #expect(result == "00000000/test")
  }

  @Test("Handle component with null byte")
  func testComponentWithNullByte() {
    #expect(PathKey.normalizeComponent("file\u{0000}.txt") == "file.txt")
  }
}

// MARK: - PathKey Performance Tests

@Suite("PathKey Performance Tests")
struct PathKeyPerformanceTests {

  @Test("Batch path normalization performance")
  func testBatchNormalizationPerformance() {
    let components = ["folder", "subfolder", "file.txt"]

    let startTime = Date()
    for _ in 0..<10000 {
      _ = PathKey.normalize(storage: 0x10001, components: components)
    }
    let elapsed = Date().timeIntervalSince(startTime)

    // 10,000 normalizations should be very fast
    #expect(elapsed < 1.0)
  }

  @Test("Batch path parsing performance")
  func testBatchParsingPerformance() {
    let pathKey = "00010001/folder/subfolder/file.txt"

    let startTime = Date()
    for _ in 0..<10000 {
      _ = PathKey.parse(pathKey)
    }
    let elapsed = Date().timeIntervalSince(startTime)

    // 10,000 parses should be very fast
    #expect(elapsed < 1.0)
  }
}
