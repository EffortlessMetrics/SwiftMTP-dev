import Foundation
import XCTest
@testable import swiftmtp_cli

final class CollectPrivacyTests: XCTestCase {
  func testRedactionUsesStableHMACForSameSalt() throws {
    let salt = Data("fixture-salt-for-tests".utf8)
    let first = Redaction.redactSerial("ABCD-1234", salt: salt)
    let second = Redaction.redactSerial("ABCD-1234", salt: salt)
    let different = Redaction.redactSerial("EFGH-5678", salt: salt)

    XCTAssertEqual(first, second)
    XCTAssertNotEqual(first, different)
    XCTAssertTrue(first.hasPrefix("hmacsha256:"))
  }

  func testGenerateSaltLength() throws {
    let salt = Redaction.generateSalt(count: 48)
    XCTAssertEqual(salt.count, 48)
  }

  func testRedactionWithBinarySaltDoesNotCrash() throws {
    let salt = Redaction.generateSalt(count: 32)
    let value = Redaction.redactSerial("ABCD-1234", salt: salt)

    XCTAssertTrue(value.hasPrefix("hmacsha256:"))
    XCTAssertEqual(value.count, "hmacsha256:".count + 64)
  }

  func testRedactorTokenizeFilenamePreservesExtension() throws {
    let redactor = Redactor(bundleKey: "unit-test-key")
    let token = redactor.tokenizeFilename("private-report.txt")

    XCTAssertTrue(token.hasPrefix("file_"))
    XCTAssertTrue(token.hasSuffix(".txt"))
    XCTAssertNotEqual(token, "private-report.txt")
  }
}
