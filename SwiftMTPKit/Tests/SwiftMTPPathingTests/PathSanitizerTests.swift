import XCTest
@testable import SwiftMTPPathing

final class PathSanitizerTests: XCTestCase {
  func testRejectsTraversalDotComponents() {
    XCTAssertNil(PathSanitizer.sanitize(".."))
    XCTAssertNil(PathSanitizer.sanitize("."))
    XCTAssertNil(PathSanitizer.sanitize("..."))
  }

  func testStripsSeparatorsAndNullBytes() {
    let result = PathSanitizer.sanitize("..\\/my\0file.txt")
    XCTAssertEqual(result, "..myfile.txt")
  }

  func testTrimsAndTruncatesToMaxLength() {
    let longName = String(repeating: "a", count: PathSanitizer.maxNameLength + 20)
    let result = PathSanitizer.sanitize("  \(longName)  ")
    XCTAssertEqual(result?.count, PathSanitizer.maxNameLength)
  }
}
