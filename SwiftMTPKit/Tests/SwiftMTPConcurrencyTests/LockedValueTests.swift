import XCTest
@testable import SwiftMTPConcurrency

final class LockedValueTests: XCTestCase {
  func testReadAndWriteRoundTrip() {
    let value = LockedValue(41)
    value.withValue { $0 += 1 }

    let result = value.read { $0 }
    XCTAssertEqual(result, 42)
  }

  func testConcurrentIncrementsRemainConsistent() {
    let value = LockedValue(0)
    let iterations = 1_000
    let group = DispatchGroup()

    for _ in 0..<iterations {
      group.enter()
      DispatchQueue.global().async {
        value.withValue { $0 += 1 }
        group.leave()
      }
    }

    XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
    XCTAssertEqual(value.read { $0 }, iterations)
  }
}
