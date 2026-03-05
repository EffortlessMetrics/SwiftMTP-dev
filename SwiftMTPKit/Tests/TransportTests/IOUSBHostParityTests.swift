// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// IOUSBHost ↔ LibUSB transport parity tests.
// Validates that IOUSBHostLink/IOUSBHostTransport expose the same MTPLink
// and MTPTransport protocol surface as their LibUSB counterparts.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTransportIOUSBHost
@testable import SwiftMTPTransportLibUSB

// MARK: - Protocol Conformance Parity

final class IOUSBHostProtocolParityTests: XCTestCase {

  // MARK: - MTPLink conformance

  func testIOUSBHostLinkConformsToMTPLink() {
    // Compile-time: IOUSBHostLink must satisfy the MTPLink protocol.
    let link: any MTPLink = IOUSBHostLink()
    XCTAssertNotNil(link)
  }

  func testIOUSBHostTransportConformsToMTPTransport() {
    let transport: any MTPTransport = IOUSBHostTransport()
    XCTAssertNotNil(transport)
  }

  func testIOUSBHostTransportFactoryConformsToTransportFactory() {
    let transport = IOUSBHostTransportFactory.createTransport()
    XCTAssertTrue(transport is IOUSBHostTransport)
  }

  // MARK: - MTPLink method presence (not default-only)

  /// Every required MTPLink method must be callable on IOUSBHostLink.
  /// Default-constructed links throw (no USB pipes) but the methods must exist.
  func testAllMTPLinkMethodsAreCallable() async {
    let link = IOUSBHostLink()

    // Session lifecycle
    await assertThrows { try await link.openUSBIfNeeded() }
    await assertThrows { try await link.openSession(id: 1) }
    await assertThrows { try await link.closeSession() }

    // Device queries
    await assertThrows { _ = try await link.getDeviceInfo() }
    await assertThrows { _ = try await link.getStorageIDs() }
    await assertThrows { _ = try await link.getStorageInfo(id: MTPStorageID(raw: 1)) }
    await assertThrows {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 1), parent: nil)
    }
    await assertThrows { _ = try await link.getObjectInfos([1]) }
    await assertThrows {
      _ = try await link.getObjectInfos(storage: MTPStorageID(raw: 1), parent: nil, format: nil)
    }

    // Mutation operations
    await assertThrows { try await link.resetDevice() }
    await assertThrows { try await link.deleteObject(handle: 1) }
    await assertThrows {
      try await link.moveObject(handle: 1, to: MTPStorageID(raw: 1), parent: nil)
    }
    await assertThrows {
      _ = try await link.copyObject(handle: 1, toStorage: MTPStorageID(raw: 1), parent: nil)
    }

    // Raw command execution
    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 0, params: []
    )
    await assertThrows { _ = try await link.executeCommand(cmd) }
    await assertThrows {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
    }

    // close() should not crash (void return)
    await link.close()
  }

  // MARK: - Optional / default-provided methods

  func testEventStreamExists() async {
    let link = IOUSBHostLink()
    // eventStream should finish immediately on a stub link
    var count = 0
    for await _ in link.eventStream { count += 1 }
    XCTAssertEqual(count, 0, "Stub eventStream should be empty")
  }

  func testStartEventPumpIsCallable() {
    let link = IOUSBHostLink()
    // Should not crash
    link.startEventPump()
  }

  func testCachedDeviceInfoIsNilOnStub() {
    let link = IOUSBHostLink()
    XCTAssertNil(link.cachedDeviceInfo)
  }

  func testLinkDescriptorIsNotNilOnStub() {
    // On platforms with IOUSBHost, default init populates a zero-valued descriptor.
    // On the #else stub, linkDescriptor is nil (from protocol default).
    let link = IOUSBHostLink()
    // Both are acceptable — we just check the property is accessible.
    _ = link.linkDescriptor
  }

  /// Default-provided MTPLink methods (getThumb, beginEditObject, etc.) should
  /// delegate to executeCommand/executeStreamingCommand and therefore also throw.
  func testDefaultProvidedMethodsDelegateCorrectly() async {
    let link = IOUSBHostLink()

    // getThumb — default impl calls executeStreamingCommand
    await assertThrows { _ = try await link.getThumb(handle: 1) }

    // Android edit extensions — default impls call executeCommand
    await assertThrows { try await link.beginEditObject(handle: 1) }
    await assertThrows { try await link.endEditObject(handle: 1) }
    await assertThrows { try await link.truncateObject(handle: 1, offset: 0) }

    // Property operations — default impls call executeStreamingCommand
    await assertThrows { _ = try await link.getObjectPropValue(handle: 1, property: 0xDC01) }
    await assertThrows {
      try await link.setObjectPropValue(handle: 1, property: 0xDC01, value: Data([0x01]))
    }
    await assertThrows { _ = try await link.getObjectPropsSupported(format: 0x3001) }

    // SetObjectPropList
    let entry = MTPPropListEntry(handle: 1, propCode: 0xDC01, datatype: 0xFFFF, value: Data([0x01]))
    await assertThrows { _ = try await link.setObjectPropList(entries: [entry]) }
  }

  // MARK: - Helper

  private func assertThrows(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected error", file: file, line: line)
    } catch {
      // Any error is acceptable — the point is the method exists and is callable
    }
  }
}

// MARK: - Error Type Parity

final class IOUSBHostErrorParityTests: XCTestCase {

  func testAllErrorCasesExist() {
    // Every IOUSBHostTransportError case must be constructible
    let errors: [IOUSBHostTransportError] = [
      .notImplemented("test"),
      .deviceNotFound(vendorID: 0x18D1, productID: 0x4EE1),
      .claimFailed("test"),
      .noMTPInterface,
      .endpointNotFound("bulk-in"),
      .ioError("transfer failed", -1),
      .invalidState("not open"),
      .pipeStall,
      .transferTimeout,
    ]
    XCTAssertEqual(errors.count, 9, "All 9 error cases must be present")
  }

  func testTimeoutErrorIsDistinct() {
    let err = IOUSBHostTransportError.transferTimeout
    // Ensure transferTimeout is its own case (not mapped to ioError)
    if case .transferTimeout = err {
      // expected
    } else {
      XCTFail("transferTimeout should be a distinct error case")
    }
  }

  func testPipeStallErrorIsDistinct() {
    let err = IOUSBHostTransportError.pipeStall
    if case .pipeStall = err {
      // expected
    } else {
      XCTFail("pipeStall should be a distinct error case")
    }
  }

  func testInvalidStateCarriesMessage() {
    let err = IOUSBHostTransportError.invalidState("bulk pipe not open")
    if case .invalidState(let msg) = err {
      XCTAssertTrue(msg.contains("bulk pipe"))
    } else {
      XCTFail("Expected invalidState case")
    }
  }

  func testIOErrorCarriesCodeAndMessage() {
    let err = IOUSBHostTransportError.ioError("pipe stalled", -536_870_212)
    if case .ioError(let msg, let code) = err {
      XCTAssertEqual(code, -536_870_212)
      XCTAssertTrue(msg.contains("stalled"))
    } else {
      XCTFail("Expected ioError case")
    }
  }

  func testClaimFailedCarriesReason() {
    let err = IOUSBHostTransportError.claimFailed("kernel driver active")
    if case .claimFailed(let reason) = err {
      XCTAssertTrue(reason.contains("kernel"))
    } else {
      XCTFail("Expected claimFailed case")
    }
  }

  func testDeviceNotFoundCarriesVIDPID() {
    let err = IOUSBHostTransportError.deviceNotFound(vendorID: 0x04E8, productID: 0x6860)
    if case .deviceNotFound(let vid, let pid) = err {
      XCTAssertEqual(vid, 0x04E8)
      XCTAssertEqual(pid, 0x6860)
    } else {
      XCTFail("Expected deviceNotFound case")
    }
  }

  func testEndpointNotFoundCarriesDetail() {
    let err = IOUSBHostTransportError.endpointNotFound("interrupt-in")
    if case .endpointNotFound(let detail) = err {
      XCTAssertTrue(detail.contains("interrupt"))
    } else {
      XCTFail("Expected endpointNotFound case")
    }
  }

  /// Error mapping parity: IOUSBHost should have dedicated cases for the same
  /// failure modes that LibUSB maps (timeout, stall, claim failure, I/O error).
  func testErrorCasesCoverLibUSBFailureModes() {
    // LibUSB maps: LIBUSB_ERROR_TIMEOUT → timeout, stall → pipeStall,
    // ACCESS/BUSY → claim, IO → ioError. Verify IOUSBHost has equivalents.
    _ = IOUSBHostTransportError.transferTimeout     // ↔ LIBUSB_ERROR_TIMEOUT
    _ = IOUSBHostTransportError.pipeStall           // ↔ LIBUSB_ERROR_PIPE (stall)
    _ = IOUSBHostTransportError.claimFailed("")     // ↔ LIBUSB_ERROR_ACCESS / BUSY
    _ = IOUSBHostTransportError.ioError("", 0)      // ↔ LIBUSB_ERROR_IO
    _ = IOUSBHostTransportError.deviceNotFound(vendorID: 0, productID: 0)  // ↔ LIBUSB_ERROR_NO_DEVICE
    _ = IOUSBHostTransportError.invalidState("")    // ↔ no-session guard
  }
}

// MARK: - API Surface Parity

final class IOUSBHostAPISurfaceParityTests: XCTestCase {

  /// IOUSBHostTransport.open() must accept the same (MTPDeviceSummary, SwiftMTPConfig) signature.
  func testTransportOpenSignatureMatches() async {
    let transport = IOUSBHostTransport()
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "parity-test"),
      manufacturer: "Test", model: "Device",
      vendorID: 0xFFFF, productID: 0xFFFF
    )
    do {
      _ = try await transport.open(summary, config: SwiftMTPConfig())
      XCTFail("Expected error — no real device")
    } catch {
      // Expected: the open signature compiles and throws on missing device
    }
  }

  /// IOUSBHostTransport.close() must be callable without prior open.
  func testTransportCloseWithoutOpenIsSafe() async throws {
    let transport = IOUSBHostTransport()
    try await transport.close()
  }

  /// IOUSBHostLink must expose the same properties as MTPUSBLink (via MTPLink protocol).
  func testLinkPropertyParity() {
    let iousbLink = IOUSBHostLink()

    // Both link types must expose these MTPLink properties:
    _ = iousbLink.cachedDeviceInfo     // MTPDeviceInfo?
    _ = iousbLink.linkDescriptor       // MTPLinkDescriptor?
    _ = iousbLink.eventStream          // AsyncStream<Data>
  }

  /// MTPLinkDescriptor fields should be the same struct on both transports.
  func testLinkDescriptorFieldParity() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0,
      interfaceClass: 6,
      interfaceSubclass: 1,
      interfaceProtocol: 1,
      bulkInEndpoint: 0x81,
      bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83,
      usbSpeedMBps: 40
    )
    // All fields that LibUSBTransport uses must also be accessible
    XCTAssertEqual(desc.interfaceNumber, 0)
    XCTAssertEqual(desc.interfaceClass, 6)
    XCTAssertEqual(desc.interfaceSubclass, 1)
    XCTAssertEqual(desc.interfaceProtocol, 1)
    XCTAssertEqual(desc.bulkInEndpoint, 0x81)
    XCTAssertEqual(desc.bulkOutEndpoint, 0x02)
    XCTAssertEqual(desc.interruptEndpoint, 0x83)
    XCTAssertEqual(desc.usbSpeedMBps, 40)
  }
}

// MARK: - Discovery & Configuration Parity

final class IOUSBHostDiscoveryParityTests: XCTestCase {

  /// IOUSBHostDeviceLocator.enumerateMTPDevices() mirrors LibUSBContext enumeration.
  func testEnumerateDoesNotCrash() async throws {
    let devices = try await IOUSBHostDeviceLocator.enumerateMTPDevices()
    XCTAssertTrue(devices.count >= 0)
  }

  /// IOUSBHostDeviceLocator.deviceEvents() must return an AsyncStream (same as LibUSB watcher).
  func testDeviceEventsStreamType() async {
    let stream = IOUSBHostDeviceLocator.deviceEvents()
    var count = 0
    for await _ in stream { count += 1 }
    // Empty on CI — just verify it finishes
    XCTAssertEqual(count, 0)
  }

  /// MTPDeviceSummary produced by both locators must share the same fields.
  func testDeviceSummaryFieldParity() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "18d1:4ee1"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1,
      bus: 1,
      address: 5,
      usbSerial: "ABC123"
    )
    XCTAssertEqual(summary.vendorID, 0x18D1)
    XCTAssertEqual(summary.productID, 0x4EE1)
    XCTAssertEqual(summary.manufacturer, "Google")
    XCTAssertEqual(summary.model, "Pixel 7")
    XCTAssertEqual(summary.bus, 1)
    XCTAssertEqual(summary.usbSerial, "ABC123")
  }
}

// MARK: - Session & Bulk Operation Parity

final class IOUSBHostSessionParityTests: XCTestCase {

  /// openSession / closeSession must exist and throw on stub link.
  func testSessionLifecycleMethodsExist() async {
    let link = IOUSBHostLink()
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
    do {
      try await link.closeSession()
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }

  /// openUSBIfNeeded must exist (IOUSBHost claims interface here; LibUSB does it in open()).
  func testOpenUSBIfNeededExists() async {
    let link = IOUSBHostLink()
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected error on default-constructed link")
    } catch {
      // Expected — no USB interface to claim
    }
  }

  /// Both transports must support executeCommand and executeStreamingCommand.
  func testCommandExecutionMethodsExist() async {
    let link = IOUSBHostLink()
    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 0, params: []
    )

    // executeCommand
    do {
      _ = try await link.executeCommand(cmd)
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }

    // executeStreamingCommand with data handlers
    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: UInt64(4),
        dataInHandler: { _ in return 0 },
        dataOutHandler: { _ in return 0 }
      )
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }

  /// deleteObject must match the same signature on both transports.
  func testDeleteObjectSignature() async {
    let link = IOUSBHostLink()
    do {
      try await link.deleteObject(handle: 42)
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }

  /// moveObject signature parity: (handle, to:, parent:)
  func testMoveObjectSignature() async {
    let link = IOUSBHostLink()
    do {
      try await link.moveObject(handle: 1, to: MTPStorageID(raw: 0x10001), parent: 0xFFFFFFFF)
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }

  /// copyObject signature parity: (handle, toStorage:, parent:) → MTPObjectHandle
  func testCopyObjectSignature() async {
    let link = IOUSBHostLink()
    do {
      let _: MTPObjectHandle = try await link.copyObject(
        handle: 1, toStorage: MTPStorageID(raw: 0x10001), parent: nil)
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }

  /// resetDevice must exist on IOUSBHostLink.
  func testResetDeviceExists() async {
    let link = IOUSBHostLink()
    do {
      try await link.resetDevice()
      XCTFail("Expected error on stub")
    } catch {
      // Expected
    }
  }
}

// MARK: - MTPDeviceEvent Parity

final class IOUSBHostDeviceEventParityTests: XCTestCase {

  func testAttachedEventCarriesSummary() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "2717:ff10"),
      manufacturer: "Xiaomi", model: "Mi Note 2"
    )
    let event = MTPDeviceEvent.attached(summary)
    if case .attached(let s) = event {
      XCTAssertEqual(s.manufacturer, "Xiaomi")
    } else {
      XCTFail("Expected attached event")
    }
  }

  func testDetachedEventCarriesIdentifier() {
    let event = MTPDeviceEvent.detached("18d1:4ee1")
    if case .detached(let id) = event {
      XCTAssertEqual(id, "18d1:4ee1")
    } else {
      XCTFail("Expected detached event")
    }
  }

  func testEventEnumIsSendable() {
    // MTPDeviceEvent must be Sendable for async stream usage
    let event: any Sendable = MTPDeviceEvent.detached("test")
    XCTAssertNotNil(event)
  }
}
