import XCTest
import CucumberSwift
import SwiftMTPCore
import SwiftMTPTransportLibUSB

final class BDDRunner: CucumberTest {}

// Global state container
final class BDDState: @unchecked Sendable {
    var transport: MockTransport?
    var summary: MTPDeviceSummary?
    var device: MTPDevice?
}
nonisolated(unsafe) var state = BDDState()

extension Cucumber: StepImplementation {
    public var bundle: Bundle { return Bundle.module }

    public func setupSteps() {
        Given("a connected MTP device") { match, step in
            state = BDDState() // Reset state
            
            let mockData = MockDeviceData.androidPixel7
            let transport = MockTransport(deviceData: mockData)
            state.transport = transport
            
            state.summary = MTPDeviceSummary(
                id: MTPDeviceID(raw: "mock"),
                manufacturer: mockData.deviceSummary.manufacturer,
                model: mockData.deviceSummary.model,
                vendorID: mockData.deviceSummary.vendorID,
                productID: mockData.deviceSummary.productID
            )
        }
        
        When("I request to open the device") { match, step in
            guard let testCase = step.testCase else { return }
            let exp = testCase.expectation(description: "Open device")
            
            Task {
                do {
                    guard let summary = state.summary,
                          let transport = state.transport else {
                        XCTFail("Setup failed")
                        exp.fulfill()
                        return
                    }
                    
                    let device = try await MTPDeviceManager.shared.openDevice(with: summary, transport: transport)
                    let _ = try await device.info
                    state.device = device
                } catch {
                    XCTFail("Error: \(error)")
                }
                exp.fulfill()
            }
            
            testCase.wait(for: [exp], timeout: 5.0)
        }
        
        Then("the session should be active") { match, step in
            guard let testCase = step.testCase else { return }
            let exp = testCase.expectation(description: "Verify session")
            
            Task {
                do {
                    guard let device = state.device else {
                        XCTFail("Device not open")
                        exp.fulfill()
                        return
                    }
                    let info = try await device.info
                    XCTAssertEqual(info.model, "Pixel 7")
                } catch {
                     XCTFail("Error: \(error)")
                }
                exp.fulfill()
            }
            
            testCase.wait(for: [exp], timeout: 5.0)
        }
    }
}
