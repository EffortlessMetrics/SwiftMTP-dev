import XCTest
import CucumberSwift
import SwiftMTPCore
import SwiftMTPTransportLibUSB

final class BDDRunner: CucumberTest {}

/// Actor-isolated per-scenario state.
/// Global is a `let`, so it’s concurrency-safe.
/// All mutation happens behind actor isolation.
actor BDDWorld {
    var transport: MockTransport?
    var summary: MTPDeviceSummary?
    var device: MTPDevice?

    func reset() {
        transport = nil
        summary = nil
        device = nil
    }

    func setupConnectedDevice() {
        let mockData = MockDeviceData.androidPixel7
        let transport = MockTransport(deviceData: mockData)
        self.transport = transport

        self.summary = MTPDeviceSummary(
            id: mockData.deviceSummary.id,
            manufacturer: mockData.deviceSummary.manufacturer,
            model: mockData.deviceSummary.model,
            vendorID: mockData.deviceSummary.vendorID,
            productID: mockData.deviceSummary.productID
        )
    }

    func openDevice() async throws {
        guard let summary, let transport else {
            throw MTPError.preconditionFailed("Setup failed")
        }
        let device = try await MTPDeviceManager.shared.openDevice(with: summary, transport: transport)
        _ = try await device.info
        self.device = device
    }

    func assertSessionActive() async throws {
        guard let device else {
            throw MTPError.preconditionFailed("Device not open")
        }
        let info = try await device.info
        XCTAssertEqual(info.model, "Pixel 7")
    }
}

private let world = BDDWorld()

private func runAsync(
    _ step: Step,
    timeout: TimeInterval = 5.0,
    _ body: @escaping @Sendable () async throws -> Void
) {
    guard let testCase = step.testCase else { return }
    let exp = testCase.expectation(description: "BDD async step")

    Task {
        do { try await body() }
        catch { XCTFail("Error: \(error)") }
        exp.fulfill()
    }

    testCase.wait(for: [exp], timeout: timeout)
}

extension Cucumber: StepImplementation {
    public var bundle: Bundle { Bundle.module }

    public func setupSteps() {
        Given("a connected MTP device") { _, step in
            runAsync(step) {
                await world.reset()
                await world.setupConnectedDevice()
            }
        }

        When("I request to open the device") { _, step in
            runAsync(step) {
                try await world.openDevice()
            }
        }

        Then("the session should be active") { _, step in
            runAsync(step) {
                try await world.assertSessionActive()
            }
        }
    }
}