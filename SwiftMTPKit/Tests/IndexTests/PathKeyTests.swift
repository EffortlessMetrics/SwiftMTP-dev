// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPIndex

@Suite("PathKey Tests")
struct PathKeyTests {

    @Test("Normalize simple component")
    func testNormalizeSimpleComponent() {
        #expect(PathKey.normalizeComponent("file.txt") == "file.txt")
        #expect(PathKey.normalizeComponent("MyFile.jpg") == "MyFile.jpg")
    }

    @Test("Normalize component with control characters")
    func testNormalizeComponentWithControlChars() {
        #expect(PathKey.normalizeComponent("file\u{00}.txt") == "file.txt")
        #expect(PathKey.normalizeComponent("file\n.txt") == "file.txt")
    }

    @Test("Normalize component with slashes")
    func testNormalizeComponentWithSlashes() {
        #expect(PathKey.normalizeComponent("file/with/slashes.txt") == "filewithslashes.txt")
        #expect(PathKey.normalizeComponent("file\\with\\backslashes.txt") == "filewithbackslashes.txt")
    }

    @Test("Normalize component NFC")
    func testNormalizeComponentNFC() {
        // Test with a character that has composed/decomposed forms
        let nfd = "cafe\u{0301}" // Decomposed
        let nfc = "café" // Composed
        #expect(PathKey.normalizeComponent(nfd) == nfc)
    }

    @Test("Normalize component empty result")
    func testNormalizeComponentEmpty() {
        #expect(PathKey.normalizeComponent("") == "_")
        #expect(PathKey.normalizeComponent("\u{00}\u{01}\u{02}") == "_")
    }

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
        #expect(storageId == 0)
        #expect(components.isEmpty)
    }

    @Test("Parse invalid path key")
    func testParseInvalidPathKey() {
        let pathKey = "invalid"
        let (storageId, components) = PathKey.parse(pathKey)
        #expect(storageId == 0)
        #expect(components.isEmpty)
    }

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
}
