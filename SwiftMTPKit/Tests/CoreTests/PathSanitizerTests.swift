// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

final class PathSanitizerTests: XCTestCase {

  func testNormalNamePassesThrough() {
    XCTAssertEqual(PathSanitizer.sanitize("photo.jpg"), "photo.jpg")
    XCTAssertEqual(PathSanitizer.sanitize("My Document.pdf"), "My Document.pdf")
    XCTAssertEqual(PathSanitizer.sanitize("DCIM"), "DCIM")
  }

  func testPathTraversalIsStripped() {
    // "../../../etc/passwd" — slashes stripped, remaining "....etcpasswd"
    // The result should not contain "/" or "\" and must not be pure dots.
    let result = PathSanitizer.sanitize("../../../etc/passwd")
    XCTAssertNotNil(result)
    XCTAssertFalse(result?.contains("/") ?? false)
    XCTAssertFalse(result?.contains("\\") ?? false)
    // The component ".." by itself must be rejected
    XCTAssertNil(PathSanitizer.sanitize(".."))
  }

  func testDotDotAloneIsRejected() {
    XCTAssertNil(PathSanitizer.sanitize(".."))
  }

  func testSingleDotIsRejected() {
    XCTAssertNil(PathSanitizer.sanitize("."))
  }

  func testOnlyDotsRejected() {
    XCTAssertNil(PathSanitizer.sanitize("..."))
    XCTAssertNil(PathSanitizer.sanitize("...."))
  }

  func testNullBytesAreStripped() {
    let withNull = "evil\0file"
    let result = PathSanitizer.sanitize(withNull)
    XCTAssertEqual(result, "evilfile")
  }

  func testForwardSlashIsStripped() {
    XCTAssertEqual(PathSanitizer.sanitize("foo/bar"), "foobar")
  }

  func testBackslashIsStripped() {
    XCTAssertEqual(PathSanitizer.sanitize("foo\\bar"), "foobar")
  }

  func testNameLongerThan255CharsIsTruncated() {
    let longName = String(repeating: "a", count: 300)
    let result = PathSanitizer.sanitize(longName)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.count, 255)
  }

  func testExactly255CharsPassesThrough() {
    let name = String(repeating: "x", count: 255)
    XCTAssertEqual(PathSanitizer.sanitize(name), name)
  }

  func testEmptyStringReturnsNil() {
    XCTAssertNil(PathSanitizer.sanitize(""))
  }

  func testWhitespaceOnlyReturnsNil() {
    XCTAssertNil(PathSanitizer.sanitize("   "))
  }

  func testLeadingAndTrailingWhitespaceIsTrimmed() {
    XCTAssertEqual(PathSanitizer.sanitize("  hello.txt  "), "hello.txt")
  }

  func testMaxNameLengthConstant() {
    XCTAssertEqual(PathSanitizer.maxNameLength, 255)
  }
}
