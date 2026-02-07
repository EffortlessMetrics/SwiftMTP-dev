import XCTest
import SnapshotTesting
@testable import SwiftMTPCore

class ModelSnapshotTests: XCTestCase {
    func testDeviceInfoSnapshot() {
        let device = MTPDeviceInfo(
            manufacturer: "TestMfg",
            model: "TestModel",
            version: "1.0",
            serialNumber: "SN123456",
            operationsSupported: [0x1001, 0x1002],
            eventsSupported: [0x4001]
        )
        
        // Using dump strategy for pure Swift objects
        assertSnapshot(of: device, as: .dump)
    }
}
