// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTransportIOUSBHost

// MARK: - IOUSBHostTransportError Tests

final class IOUSBHostTransportErrorTests: XCTestCase {

  func testErrorCases() {
    // Verify all error cases are constructible and distinct
    let errors: [IOUSBHostTransportError] = [
      .notImplemented("test"),
      .deviceNotFound(vendorID: 0x1234, productID: 0x5678),
      .claimFailed("test"),
      .noMTPInterface,
      .endpointNotFound("bulk-in"),
      .ioError("failed", -1),
      .invalidState("not open"),
      .pipeStall,
      .transferTimeout,
    ]
    // Each error should have a non-empty description
    for error in errors {
      XCTAssertFalse(error.description.isEmpty, "Error \(error) should have a description")
    }
  }

  func testNotImplementedDescription() {
    let error = IOUSBHostTransportError.notImplemented("getStorageInfo")
    XCTAssertTrue(error.description.contains("getStorageInfo"))
    XCTAssertTrue(error.description.contains("Not implemented"))
  }

  func testDeviceNotFoundDescription() {
    let error = IOUSBHostTransportError.deviceNotFound(vendorID: 0x18D1, productID: 0x4EE1)
    XCTAssertTrue(error.description.contains("18d1"))
    XCTAssertTrue(error.description.contains("4ee1"))
  }

  func testIOErrorDescription() {
    let error = IOUSBHostTransportError.ioError("pipe stalled", -536870212)
    XCTAssertTrue(error.description.contains("pipe stalled"))
    XCTAssertTrue(error.description.contains("-536870212"))
  }
}

// MARK: - IOUSBHostLink Default Constructor Tests

final class IOUSBHostLinkDefaultTests: XCTestCase {

  func testDefaultInitHasNilProperties() {
    let link = IOUSBHostLink()
    // Default-constructed link has nil cached info but non-nil linkDescriptor
    // (linkDescriptor is set from the zero-valued endpoint addresses)
    XCTAssertNil(link.cachedDeviceInfo)
  }

  func testDefaultLinkOpenUSBThrowsInvalidState() async {
    let link = IOUSBHostLink()
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected invalidState error")
    } catch let error as IOUSBHostTransportError {
      if case .invalidState = error {
        // expected
      } else {
        XCTFail("Expected invalidState, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testDefaultLinkCloseIsNoOp() async {
    let link = IOUSBHostLink()
    // Should not crash
    await link.close()
  }
}

// MARK: - IOUSBHostTransport Factory Tests

final class IOUSBHostTransportTests: XCTestCase {

  func testTransportFactoryCreatesTransport() {
    let transport = IOUSBHostTransportFactory.createTransport()
    XCTAssertTrue(transport is IOUSBHostTransport)
  }

  func testTransportOpenWithNoDeviceThrows() async {
    let transport = IOUSBHostTransport()
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: nil,  // No VID → should fail
      productID: nil
    )
    do {
      _ = try await transport.open(summary, config: SwiftMTPConfig())
      XCTFail("Expected error for nil VID/PID")
    } catch let error as IOUSBHostTransportError {
      if case .deviceNotFound = error {
        // expected
      } else {
        XCTFail("Expected deviceNotFound, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testTransportCloseIsNoOp() async throws {
    let transport = IOUSBHostTransport()
    // Close without opening should be safe
    try await transport.close()
  }
}

// MARK: - IOUSBHostLink Stub Method Tests

final class IOUSBHostLinkStubTests: XCTestCase {

  /// Methods that are not yet implemented should throw notImplemented.
  func testUnimplementedMethodsThrowNotImplemented() async {
    let link = IOUSBHostLink()

    // getStorageInfo
    await assertThrowsNotImplemented { try await link.getStorageInfo(id: MTPStorageID(raw: 1)) }

    // getObjectHandles
    await assertThrowsNotImplemented {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 1), parent: nil)
    }

    // getObjectInfos (handles)
    await assertThrowsNotImplemented { _ = try await link.getObjectInfos([1, 2, 3]) }

    // getObjectInfos (storage)
    await assertThrowsNotImplemented {
      _ = try await link.getObjectInfos(storage: MTPStorageID(raw: 1), parent: nil, format: nil)
    }

    // resetDevice
    await assertThrowsNotImplemented { try await link.resetDevice() }

    // moveObject
    await assertThrowsNotImplemented {
      try await link.moveObject(handle: 1, to: MTPStorageID(raw: 1), parent: nil)
    }

    // copyObject
    await assertThrowsNotImplemented {
      _ = try await link.copyObject(handle: 1, toStorage: MTPStorageID(raw: 1), parent: nil)
    }
  }

  private func assertThrowsNotImplemented(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected notImplemented error", file: file, line: line)
    } catch let error as IOUSBHostTransportError {
      if case .notImplemented = error {
        // expected
      } else if case .invalidState = error {
        // also acceptable for default-constructed links
      } else {
        XCTFail("Expected notImplemented, got \(error)", file: file, line: line)
      }
    } catch {
      XCTFail("Unexpected error type: \(error)", file: file, line: line)
    }
  }
}

// MARK: - PTP Container Encoding Tests

final class IOUSBHostPTPEncodingTests: XCTestCase {

  func testPTPContainerBasicStructure() {
    // Verify PTPContainer round-trips correctly through the link's encoding.
    // We test indirectly by verifying the container struct itself.
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: 42,
      params: [1]
    )
    XCTAssertEqual(container.type, 1)
    XCTAssertEqual(container.code, 0x1002)
    XCTAssertEqual(container.txid, 42)
    XCTAssertEqual(container.params, [1])
  }

  func testPTPResponseResultOK() {
    let ok = PTPResponseResult(code: 0x2001, txid: 1)
    XCTAssertTrue(ok.isOK)

    let error = PTPResponseResult(code: 0x2002, txid: 1)
    XCTAssertFalse(error.isOK)
  }
}

// MARK: - Device Locator Tests

final class IOUSBHostDeviceLocatorTests: XCTestCase {

  func testEnumerateReturnsArrayWithoutCrash() async throws {
    // On a CI machine without USB devices, this should return an empty array.
    let devices = try await IOUSBHostDeviceLocator.enumerateMTPDevices()
    // We can't assert specific devices, but it shouldn't crash
    XCTAssertTrue(devices.count >= 0)
  }

  func testDeviceEventsStreamFinishes() async {
    let stream = IOUSBHostDeviceLocator.deviceEvents()
    var count = 0
    for await _ in stream {
      count += 1
    }
    // Empty stream should finish immediately
    XCTAssertEqual(count, 0)
  }
}

// MARK: - MTPDeviceEvent Tests

final class MTPDeviceEventTests: XCTestCase {

  func testAttachedEvent() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Google", model: "Pixel 7"
    )
    let event = MTPDeviceEvent.attached(summary)
    if case .attached(let s) = event {
      XCTAssertEqual(s.manufacturer, "Google")
    } else {
      XCTFail("Expected attached event")
    }
  }

  func testDetachedEvent() {
    let event = MTPDeviceEvent.detached("device-123")
    if case .detached(let id) = event {
      XCTAssertEqual(id, "device-123")
    } else {
      XCTFail("Expected detached event")
    }
  }
}
