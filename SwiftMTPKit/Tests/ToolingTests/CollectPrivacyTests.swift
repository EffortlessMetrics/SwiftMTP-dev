import XCTest
@testable import SwiftMTPTools

final class CollectPrivacyTests: XCTestCase {
    func testRedactionPatterns() throws {
        let raw = """
        Serial Number: ABCD-1234
        Hostname: stevens-mac-mini
        User Path: /Users/steven/Secret
        Windows Path: C:\\Users\\steven\\Secrets
        Email: user@example.com
        MAC: aa:bb:cc:dd:ee:ff
        IPv4: 10.0.0.23
        UUID: 550e8400-e29b-41d4-a716-446655440000
        """
        let redacted = Redaction.sanitize(text: raw)
        XCTAssertFalse(redacted.contains("ABCD-1234"))
        XCTAssertFalse(redacted.contains("steven"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertFalse(redacted.contains("aa:bb:cc:dd:ee:ff"))
        XCTAssertFalse(redacted.contains("10.0.0.23"))
        XCTAssertFalse(redacted.contains("550e8400-e29b-41d4-a716-446655440000"))
    }

    func testExitCodes() throws {
        // Use a tiny harness around CollectCommand to simulate argument sets
        let (codeNoDevice, _) = CollectHarness.run(args: ["collect", "--noninteractive", "--strict", "--no-bench"])
        XCTAssertEqual(codeNoDevice, 69) // unavailable

        let (codeUsage, _) = CollectHarness.run(args: ["collect", "--noninteractive", "--strict", "--vid","2717","--pid","ff10","--bus","99","--address","99"])
        XCTAssertEqual(codeUsage, 64) // usage error
    }
}