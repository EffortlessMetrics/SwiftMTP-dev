import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore

@MainActor
final class DeviceLabToolingTests: XCTestCase {
  private func makeFlags(
    targetVID: String? = nil,
    targetPID: String? = nil,
    targetBus: Int? = nil,
    targetAddress: Int? = nil
  ) -> CLIFlags {
    CLIFlags(
      realOnly: true,
      useMock: false,
      mockProfile: "default",
      json: true,
      jsonlOutput: false,
      traceUSB: false,
      strict: false,
      safe: false,
      traceUSBDetails: false,
      targetVID: targetVID,
      targetPID: targetPID,
      targetBus: targetBus,
      targetAddress: targetAddress
    )
  }

  private func makeDevice(
    id: String,
    vid: UInt16,
    pid: UInt16,
    bus: UInt8,
    address: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id),
      manufacturer: "Test",
      model: "Device",
      vendorID: vid,
      productID: pid,
      bus: bus,
      address: address
    )
  }

  func testApplyConnectedFilterWithVidPidAndBusAddress() {
    let devices = [
      makeDevice(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeDevice(id: "b", vid: 0x2717, pid: 0xff40, bus: 2, address: 5),
      makeDevice(id: "c", vid: 0x18d1, pid: 0x4ee1, bus: 2, address: 3),
    ]

    let flags = makeFlags(targetVID: "0x04e8", targetPID: "6860", targetBus: 1, targetAddress: 4)
    let result = DeviceLabCommand.applyConnectedFilter(discovered: devices, flags: flags)

    XCTAssertTrue(result.hasExplicitFilter)
    XCTAssertEqual(result.devices.count, 1)
    XCTAssertEqual(result.devices.first?.id.raw, "a")
  }

  func testApplyConnectedFilterWithoutFilterReturnsAllDevices() {
    let devices = [
      makeDevice(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeDevice(id: "b", vid: 0x2717, pid: 0xff40, bus: 2, address: 5),
    ]

    let result = DeviceLabCommand.applyConnectedFilter(discovered: devices, flags: makeFlags())

    XCTAssertFalse(result.hasExplicitFilter)
    XCTAssertEqual(result.devices.map(\.id.raw), ["a", "b"])
  }

  func testApplyConnectedFilterWithNoMatchesReturnsEmpty() {
    let devices = [
      makeDevice(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeDevice(id: "b", vid: 0x2717, pid: 0xff40, bus: 2, address: 5),
    ]

    let flags = makeFlags(targetVID: "0x18d1", targetPID: "0x4ee1", targetBus: 9, targetAddress: 9)
    let result = DeviceLabCommand.applyConnectedFilter(discovered: devices, flags: flags)

    XCTAssertTrue(result.hasExplicitFilter)
    XCTAssertTrue(result.devices.isEmpty)
  }

  func testClassifyFailureClassForStateStorageGated() {
    let failureClass = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: true,
      deviceInfoSucceeded: true,
      storagesSucceeded: true,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: ""
    )
    XCTAssertEqual(failureClass, "storage_gated")
  }

  func testLooksLikeRetryableWriteFailure() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("protocolError(code=0x201D)"))
    XCTAssertTrue(
      DeviceLabCommand.looksLikeRetryableWriteFailure("protocolError(code=0x2008) InvalidStorageID")
    )
    XCTAssertTrue(
      DeviceLabCommand.looksLikeRetryableWriteFailure("ParameterNotSupported from SendObjectInfo"))
    XCTAssertTrue(
      DeviceLabCommand.looksLikeRetryableWriteFailure(
        "transport(SwiftMTPCore.TransportError.timeout)"))
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("device busy"))
    XCTAssertFalse(DeviceLabCommand.looksLikeRetryableWriteFailure("permission denied"))
  }

  func testUSBDumpReportJSONShape() throws {
    let report = USBDumper.DumpReport(
      schemaVersion: "1.0.0", generatedAt: Date(timeIntervalSince1970: 0), devices: [])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(report)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["schemaVersion"] as? String, "1.0.0")
    XCTAssertNotNil(json["generatedAt"] as? String)
    XCTAssertEqual((json["devices"] as? [Any])?.count, 0)
  }

  func testWithinTimeoutProbeTimesOut() async {
    let startedAt = Date()
    let result = await DeviceLabCommand.testWithinTimeoutProbe(timeoutMs: 20, sleepMs: 200)
    let elapsed = Date().timeIntervalSince(startedAt)

    XCTAssertTrue(result.contains("test-timeout-probe"))
    XCTAssertLessThan(elapsed, 1.0)
  }
}
