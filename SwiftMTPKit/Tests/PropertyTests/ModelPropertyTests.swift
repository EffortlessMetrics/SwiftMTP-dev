import XCTest
import SwiftCheck
@testable import SwiftMTPCore

class ModelPropertyTests: XCTestCase {
  func testStorageInfoProperties() {
    property("MTPStorageInfo retains values")
      <- forAll { (id: UInt32, desc: String, cap: UInt64, free: UInt64, readOnly: Bool) in
        let info = MTPStorageInfo(
          id: MTPStorageID(raw: id),
          description: desc,
          capacityBytes: cap,
          freeBytes: free,
          isReadOnly: readOnly
        )

        return info.id.raw == id && info.description == desc && info.capacityBytes == cap
          && info.freeBytes == free && info.isReadOnly == readOnly
      }
  }
}
