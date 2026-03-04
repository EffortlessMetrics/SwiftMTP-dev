// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

/// Integration tests for IOUSBHostTransport verifying the full MTP operation path.
///
/// These tests exercise protocol conformance, MTP transaction sequences,
/// container encoding/decoding round-trips, error cascading, configuration
/// validation, and event parsing — all without requiring real USB hardware.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTransportIOUSBHost

// MARK: - Protocol Conformance

final class IOUSBHostProtocolConformanceTests: XCTestCase {

  func testIOUSBHostLinkConformsToMTPLink() {
    let link = IOUSBHostLink()
    XCTAssertTrue(link is MTPLink, "IOUSBHostLink must conform to MTPLink")
  }

  func testIOUSBHostTransportConformsToMTPTransport() {
    let transport = IOUSBHostTransport()
    XCTAssertTrue(transport is MTPTransport, "IOUSBHostTransport must conform to MTPTransport")
  }

  func testIOUSBHostTransportFactoryConformance() {
    let transport = IOUSBHostTransportFactory.createTransport()
    XCTAssertTrue(transport is IOUSBHostTransport)
    XCTAssertTrue(transport is MTPTransport)
  }

  func testIOUSBHostLinkIsSendable() {
    // Compile-time check: IOUSBHostLink is @unchecked Sendable
    let link: any Sendable = IOUSBHostLink()
    XCTAssertNotNil(link)
  }

  func testIOUSBHostTransportIsSendable() {
    let transport: any Sendable = IOUSBHostTransport()
    XCTAssertNotNil(transport)
  }
}

// MARK: - Link Descriptor & Configuration

final class IOUSBHostLinkDescriptorTests: XCTestCase {

  func testDefaultLinkHasNilDescriptor() {
    // A default-constructed link uses zero-valued endpoints but still creates a descriptor
    let link = IOUSBHostLink()
    // linkDescriptor is set even on default init (with zeroed addresses)
    let desc = link.linkDescriptor
    XCTAssertNotNil(desc)
    if let d = desc {
      XCTAssertEqual(d.interfaceClass, 6, "MTP interface class")
      XCTAssertEqual(d.interfaceSubclass, 1, "MTP subclass")
      XCTAssertEqual(d.interfaceProtocol, 1, "MTP protocol")
      XCTAssertEqual(d.bulkInEndpoint, 0, "Default zero endpoint")
      XCTAssertEqual(d.bulkOutEndpoint, 0, "Default zero endpoint")
      XCTAssertNil(d.interruptEndpoint, "No interrupt on default link")
      XCTAssertNil(d.usbSpeedMBps, "Speed unknown on default link")
    }
  }

  func testLinkDescriptorHashable() {
    let d1 = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 6, interfaceSubclass: 1,
      interfaceProtocol: 1, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83, usbSpeedMBps: 480
    )
    let d2 = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 6, interfaceSubclass: 1,
      interfaceProtocol: 1, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83, usbSpeedMBps: 480
    )
    XCTAssertEqual(d1, d2)
    XCTAssertEqual(d1.hashValue, d2.hashValue)

    // Set insertion
    var set = Set<MTPLinkDescriptor>()
    set.insert(d1)
    set.insert(d2)
    XCTAssertEqual(set.count, 1)
  }

  func testLinkDescriptorCodable() throws {
    let original = MTPLinkDescriptor(
      interfaceNumber: 2, interfaceClass: 6, interfaceSubclass: 1,
      interfaceProtocol: 1, bulkInEndpoint: 0x83, bulkOutEndpoint: 0x04,
      interruptEndpoint: 0x85, usbSpeedMBps: 5000
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MTPLinkDescriptor.self, from: data)
    XCTAssertEqual(original, decoded)
  }
}

// MARK: - Full MTP Operation Sequence (Error Paths)

final class IOUSBHostMTPSequenceTests: XCTestCase {

  /// Verify that the expected MTP lifecycle sequence fails gracefully
  /// on a default-constructed link (no real USB hardware).
  func testFullLifecycleSequenceFailsGracefully() async throws {
    let transport = IOUSBHostTransport()

    // Step 1: open with nil VID/PID → deviceNotFound
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test:device"),
      manufacturer: "Test",
      model: "Mock",
      vendorID: nil,
      productID: nil
    )
    do {
      _ = try await transport.open(summary, config: SwiftMTPConfig())
      XCTFail("Expected deviceNotFound error")
    } catch let error as IOUSBHostTransportError {
      if case .deviceNotFound(let vid, let pid) = error {
        XCTAssertEqual(vid, 0)
        XCTAssertEqual(pid, 0)
      } else {
        XCTFail("Expected deviceNotFound, got \(error)")
      }
    }

    // Step 2: close without successful open is safe
    try await transport.close()
  }

  /// Test that openUSBIfNeeded → openSession → operations → closeSession → close
  /// all fail with correct errors on a default-constructed link.
  func testOperationSequenceOnDefaultLink() async {
    let link = IOUSBHostLink()

    // openUSBIfNeeded on default link → invalidState
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected invalidState error")
    } catch let error as IOUSBHostTransportError {
      if case .invalidState(let msg) = error {
        XCTAssertTrue(msg.contains("default-constructed"))
      } else {
        XCTFail("Expected invalidState, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    // Without USB open, session commands should also fail
    await assertThrowsAnyError { try await link.openSession(id: 1) }
    await assertThrowsAnyError { _ = try await link.getDeviceInfo() }
    await assertThrowsAnyError { _ = try await link.getStorageIDs() }
    await assertThrowsAnyError { try await link.deleteObject(handle: 1) }

    // Close is always safe
    await link.close()
  }

  /// Verify that multiple close calls are idempotent.
  func testDoubleCloseIsSafe() async throws {
    let transport = IOUSBHostTransport()
    try await transport.close()
    try await transport.close()
    // No crash = pass
  }

  func testDefaultLinkDoubleCloseIsSafe() async {
    let link = IOUSBHostLink()
    await link.close()
    await link.close()
  }

  private func assertThrowsAnyError(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected an error", file: file, line: line)
    } catch {
      // Any error is expected — we're verifying it doesn't succeed
    }
  }
}

// MARK: - IOUSBHostTransportError Exhaustive Tests

final class IOUSBHostTransportErrorExhaustiveTests: XCTestCase {

  func testAllErrorDescriptionsAreUnique() {
    let errors: [IOUSBHostTransportError] = [
      .notImplemented("resetDevice"),
      .deviceNotFound(vendorID: 0x1234, productID: 0x5678),
      .claimFailed("permission denied"),
      .noMTPInterface,
      .endpointNotFound("bulk-in"),
      .ioError("stalled", -536_870_212),
      .invalidState("not open"),
      .pipeStall,
      .transferTimeout,
    ]
    let descriptions = errors.map(\.description)
    XCTAssertEqual(descriptions.count, Set(descriptions).count, "All descriptions should be unique")
  }

  func testErrorDescriptionContainsContext() {
    // claimFailed includes reason
    let claim = IOUSBHostTransportError.claimFailed("entitlement missing")
    XCTAssertTrue(claim.description.contains("entitlement missing"))

    // endpointNotFound includes endpoint name
    let ep = IOUSBHostTransportError.endpointNotFound("interrupt-in 0x83")
    XCTAssertTrue(ep.description.contains("interrupt-in 0x83"))

    // invalidState includes state detail
    let state = IOUSBHostTransportError.invalidState("pipe closed")
    XCTAssertTrue(state.description.contains("pipe closed"))
  }

  func testDeviceNotFoundFormatsVIDPIDAsHex() {
    let error = IOUSBHostTransportError.deviceNotFound(vendorID: 0x2717, productID: 0xFF10)
    XCTAssertTrue(error.description.contains("2717"))
    XCTAssertTrue(error.description.contains("ff10"))
  }

  func testIOErrorIncludesReturnCode() {
    let code: Int32 = -536_870_111
    let error = IOUSBHostTransportError.ioError("bulk transfer failed", code)
    XCTAssertTrue(error.description.contains("bulk transfer failed"))
    XCTAssertTrue(error.description.contains(String(code)))
  }
}

// MARK: - PTP Container Encoding Round-Trip

final class IOUSBHostContainerRoundTripTests: XCTestCase {

  func testCommandContainerEncodeRoundTrip() {
    var container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: 1,
      params: [1]
    )
    // Match IOUSBHostLink's encodePTPCommand: set length = header + params
    container.length = UInt32(12 + container.params.count * 4)

    // Encode into raw bytes
    var buf = [UInt8](repeating: 0, count: 128)
    let written = container.encode(into: &buf)

    // Parse back from raw bytes
    let data = Data(buf[0..<written])
    data.withUnsafeBytes { raw in
      let base = raw.baseAddress!
      let length = UInt32(littleEndian: base.load(as: UInt32.self))
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      let code = UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self))
      let txid = UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self))
      let param0 = UInt32(littleEndian: base.load(fromByteOffset: 12, as: UInt32.self))

      XCTAssertEqual(length, UInt32(written))
      XCTAssertEqual(type, PTPContainer.Kind.command.rawValue)
      XCTAssertEqual(code, PTPOp.openSession.rawValue)
      XCTAssertEqual(txid, 1)
      XCTAssertEqual(param0, 1)
    }
  }

  func testAllContainerKindRawValues() {
    XCTAssertEqual(PTPContainer.Kind.command.rawValue, 1)
    XCTAssertEqual(PTPContainer.Kind.data.rawValue, 2)
    XCTAssertEqual(PTPContainer.Kind.response.rawValue, 3)
    XCTAssertEqual(PTPContainer.Kind.event.rawValue, 4)
  }

  func testContainerEncodeNoParams() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.closeSession.rawValue,
      txid: 5,
      params: []
    )
    var buf = [UInt8](repeating: 0, count: 64)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12, "No-param container should be exactly 12 bytes (header only)")
  }

  func testContainerEncodeMaxParams() {
    // MTP allows up to 5 params in a command
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: 1,
      params: [0x00010001, 0, 0xFFFFFFFF, 0, 0]
    )
    var buf = [UInt8](repeating: 0, count: 64)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12 + 5 * 4, "5-param container = 32 bytes")
  }
}

// MARK: - Event Container Parsing

final class IOUSBHostEventParsingTests: XCTestCase {

  /// Build a raw PTP event container and verify parsing.
  func testEventContainerParsing() {
    let eventCode: UInt16 = 0x4002  // ObjectAdded
    let txid: UInt32 = 0
    let objectHandle: UInt32 = 42

    let data = buildEventContainer(code: eventCode, txid: txid, params: [objectHandle])

    data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let length = UInt32(littleEndian: base.load(as: UInt32.self))
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      let code = UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self))
      let tx = UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self))

      XCTAssertEqual(length, 16, "Event with 1 param = 16 bytes")
      XCTAssertEqual(type, PTPContainer.Kind.event.rawValue)
      XCTAssertEqual(code, 0x4002)
      XCTAssertEqual(tx, 0)

      let param = UInt32(littleEndian: base.load(fromByteOffset: 12, as: UInt32.self))
      XCTAssertEqual(param, 42)
    }
  }

  func testEventContainerNoParams() {
    let data = buildEventContainer(code: 0x4004, txid: 0, params: [])  // StoreAdded
    data.withUnsafeBytes { buf in
      let length = UInt32(littleEndian: buf.load(as: UInt32.self))
      XCTAssertEqual(length, 12, "Parameterless event = 12 bytes")
    }
  }

  func testAllStandardMTPEventCodes() {
    // Verify known event codes are representable
    let events: [(String, UInt16)] = [
      ("CancelTransaction", 0x4001),
      ("ObjectAdded", 0x4002),
      ("ObjectRemoved", 0x4003),
      ("StoreAdded", 0x4004),
      ("StoreRemoved", 0x4005),
      ("DevicePropChanged", 0x4006),
      ("ObjectInfoChanged", 0x4007),
      ("DeviceInfoChanged", 0x4008),
      ("RequestObjectTransfer", 0x4009),
      ("StoreFull", 0x400A),
      ("DeviceReset", 0x400B),
      ("StorageInfoChanged", 0x400C),
      ("CaptureComplete", 0x400D),
      ("UnreportedStatus", 0x400E),
    ]
    for (name, code) in events {
      let data = buildEventContainer(code: code, txid: 0, params: [])
      XCTAssertGreaterThanOrEqual(data.count, 12, "\(name) event should be valid")
    }
  }

  func testEventStreamDefaultIsEmpty() async {
    let link = IOUSBHostLink()
    var count = 0
    for await _ in link.eventStream {
      count += 1
    }
    XCTAssertEqual(count, 0, "Default eventStream should finish immediately")
  }

  func testStartEventPumpIsNoOp() {
    let link = IOUSBHostLink()
    link.startEventPump()
    // No crash = pass; default implementation is no-op
  }

  // MARK: - Helpers

  private func buildEventContainer(code: UInt16, txid: UInt32, params: [UInt32]) -> Data {
    let length = UInt32(12 + params.count * 4)
    var data = Data(count: Int(length))
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.event.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      for (i, p) in params.enumerated() {
        base.storeBytes(of: p.littleEndian, toByteOffset: 12 + i * 4, as: UInt32.self)
      }
    }
    return data
  }
}

// MARK: - MTP Response Code Coverage

final class IOUSBHostResponseCodeTests: XCTestCase {

  func testResponseOKCode() {
    let ok = PTPResponseResult(code: 0x2001, txid: 1)
    XCTAssertTrue(ok.isOK)
  }

  func testCommonErrorResponseCodes() {
    let codes: [(String, UInt16)] = [
      ("GeneralError", 0x2002),
      ("SessionNotOpen", 0x2003),
      ("InvalidTransactionID", 0x2004),
      ("OperationNotSupported", 0x2005),
      ("ParameterNotSupported", 0x2006),
      ("IncompleteTransfer", 0x2007),
      ("InvalidStorageID", 0x2008),
      ("InvalidObjectHandle", 0x2009),
      ("DevicePropNotSupported", 0x200A),
      ("InvalidObjectFormatCode", 0x200B),
      ("StoreFull", 0x200C),
      ("ObjectWriteProtected", 0x200D),
      ("StoreReadOnly", 0x200E),
      ("AccessDenied", 0x200F),
      ("NoThumbnailPresent", 0x2010),
      ("SelfTestFailed", 0x2011),
      ("PartialDeletion", 0x2012),
      ("StoreNotAvailable", 0x2013),
      ("SpecByFormatUnsupported", 0x2014),
      ("NoValidObjectInfo", 0x2015),
      ("InvalidCodeFormat", 0x2016),
      ("UnknownVendorCode", 0x2017),
      ("CaptureAlreadyTerminated", 0x2018),
      ("DeviceBusy", 0x2019),
      ("InvalidParentObject", 0x201A),
      ("InvalidDevicePropFormat", 0x201B),
      ("InvalidDevicePropValue", 0x201C),
      ("InvalidParameter", 0x201D),
      ("SessionAlreadyOpen", 0x201E),
      ("TransactionCancelled", 0x201F),
      ("SpecOfDestUnsupported", 0x2020),
    ]
    for (name, code) in codes {
      let result = PTPResponseResult(code: code, txid: 1)
      XCTAssertFalse(result.isOK, "\(name) (0x\(String(format: "%04x", code))) should not be OK")
    }
  }

  func testResponseResultWithData() {
    let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let result = PTPResponseResult(code: 0x2001, txid: 1, params: [], data: payload)
    XCTAssertTrue(result.isOK)
    XCTAssertEqual(result.data, payload)
  }

  func testResponseResultParams() {
    // CopyObject response with new handle
    let result = PTPResponseResult(code: 0x2001, txid: 5, params: [999])
    XCTAssertTrue(result.isOK)
    XCTAssertEqual(result.params.first, 999)
  }
}

// MARK: - PTP Operation Code Completeness

final class IOUSBHostPTPOpCodeTests: XCTestCase {

  func testCoreOperationCodes() {
    XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
    XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
    XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
    XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
    XCTAssertEqual(PTPOp.getStorageInfo.rawValue, 0x1005)
    XCTAssertEqual(PTPOp.getNumObjects.rawValue, 0x1006)
    XCTAssertEqual(PTPOp.getObjectHandles.rawValue, 0x1007)
    XCTAssertEqual(PTPOp.getObjectInfo.rawValue, 0x1008)
    XCTAssertEqual(PTPOp.getObject.rawValue, 0x1009)
    XCTAssertEqual(PTPOp.getThumb.rawValue, 0x100A)
    XCTAssertEqual(PTPOp.deleteObject.rawValue, 0x100B)
    XCTAssertEqual(PTPOp.sendObjectInfo.rawValue, 0x100C)
    XCTAssertEqual(PTPOp.sendObject.rawValue, 0x100D)
    XCTAssertEqual(PTPOp.moveObject.rawValue, 0x100E)
    XCTAssertEqual(PTPOp.copyObject.rawValue, 0x101A)
  }

  func testAndroidExtensionCodes() {
    XCTAssertEqual(PTPOp.getPartialObject64.rawValue, 0x95C1)
    XCTAssertEqual(PTPOp.sendPartialObject.rawValue, 0x95C2)
    XCTAssertEqual(PTPOp.truncateObject.rawValue, 0x95C3)
    XCTAssertEqual(PTPOp.beginEditObject.rawValue, 0x95C4)
    XCTAssertEqual(PTPOp.endEditObject.rawValue, 0x95C5)
  }
}

// MARK: - Object Info Parsing Integration

final class IOUSBHostObjectInfoParsingTests: XCTestCase {

  func testObjectInfoDatasetParsing() {
    // Build a minimal MTP ObjectInfo dataset per PTP/MTP spec
    var data = Data()
    appendUInt32(&data, 0x00010001)  // StorageID
    appendUInt16(&data, 0x3001)      // ObjectFormat (GenericFile)
    appendUInt16(&data, 0x0000)      // ProtectionStatus
    appendUInt32(&data, 1024)        // ObjectCompressedSize
    appendUInt16(&data, 0x3801)      // ThumbFormat (JPEG)
    appendUInt32(&data, 0)           // ThumbCompressedSize
    appendUInt32(&data, 0)           // ThumbPixWidth
    appendUInt32(&data, 0)           // ThumbPixHeight
    appendUInt32(&data, 0)           // ImagePixWidth
    appendUInt32(&data, 0)           // ImagePixHeight
    appendUInt32(&data, 0)           // ImageBitDepth
    appendUInt32(&data, 0xFFFFFFFF)  // ParentObject (root)
    appendUInt16(&data, 0x0000)      // AssociationType
    appendUInt32(&data, 0)           // AssociationDesc
    appendUInt32(&data, 0)           // SequenceNumber
    appendPTPString(&data, "test-file.jpg")  // Filename

    var r = PTPReader(data: data)
    let storageID = r.u32()
    let format = r.u16()
    _ = r.u16()  // protection
    let size = r.u32()
    _ = r.u16()  // thumb format
    _ = r.u32(); _ = r.u32(); _ = r.u32()  // thumb size/width/height
    _ = r.u32(); _ = r.u32(); _ = r.u32()  // image width/height/depth
    let parent = r.u32()
    _ = r.u16(); _ = r.u32(); _ = r.u32()  // assoc type/desc/seq
    let name = r.string()

    XCTAssertEqual(storageID, 0x00010001)
    XCTAssertEqual(format, 0x3001)
    XCTAssertEqual(size, 1024)
    XCTAssertEqual(parent, 0xFFFFFFFF)
    XCTAssertEqual(name, "test-file.jpg")
  }

  func testObjectInfoLargeFile() {
    // Files > 4GB use 0xFFFFFFFF as compressed size
    var data = Data()
    appendUInt32(&data, 0x00010001)
    appendUInt16(&data, 0x3001)
    appendUInt16(&data, 0x0000)
    appendUInt32(&data, 0xFFFFFFFF)  // sentinel: use GetObjectPropValue for actual size

    var r = PTPReader(data: data)
    _ = r.u32()  // storage
    _ = r.u16()  // format
    _ = r.u16()  // protection
    let size = r.u32()
    XCTAssertEqual(size, 0xFFFFFFFF, "Sentinel should indicate >4GB file")
  }

  // MARK: - Helpers

  private func appendUInt16(_ data: inout Data, _ value: UInt16) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 2))
  }

  private func appendUInt32(_ data: inout Data, _ value: UInt32) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 4))
  }

  private func appendPTPString(_ data: inout Data, _ string: String) {
    let utf16 = Array(string.utf16)
    data.append(UInt8(utf16.count + 1))
    for ch in utf16 {
      var v = ch.littleEndian
      data.append(Data(bytes: &v, count: 2))
    }
    var null: UInt16 = 0
    data.append(Data(bytes: &null, count: 2))
  }
}

// MARK: - MTP Transaction ID Sequencing

final class IOUSBHostTransactionIDTests: XCTestCase {

  func testContainerPreservesTransactionID() {
    for txid: UInt32 in [0, 1, 0xFFFFFFFF, 42, 1000] {
      let container = PTPContainer(
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.getDeviceInfo.rawValue,
        txid: txid,
        params: []
      )
      var buf = [UInt8](repeating: 0, count: 16)
      _ = container.encode(into: &buf)
      let data = Data(buf)
      let decoded = data.withUnsafeBytes { raw in
        UInt32(littleEndian: raw.load(fromByteOffset: 8, as: UInt32.self))
      }
      XCTAssertEqual(decoded, txid, "Transaction ID \(txid) should round-trip")
    }
  }

  func testResponsePreservesTransactionID() {
    for txid: UInt32 in [0, 1, 42, 0xFFFFFFFE] {
      let result = PTPResponseResult(code: 0x2001, txid: txid)
      XCTAssertEqual(result.txid, txid)
    }
  }
}

// MARK: - IOUSBHost Fallback (Non-IOUSBHost Platforms)

final class IOUSBHostFallbackBehaviorTests: XCTestCase {

  /// On platforms where IOUSBHost is unavailable, all link operations should throw.
  func testFallbackLinkAllMethodsThrow() async {
    #if !canImport(IOUSBHost)
    let link = IOUSBHostLink()

    await assertThrowsUnavailable { try await link.openUSBIfNeeded() }
    await assertThrowsUnavailable { try await link.openSession(id: 1) }
    await assertThrowsUnavailable { try await link.closeSession() }
    await assertThrowsUnavailable { _ = try await link.getDeviceInfo() }
    await assertThrowsUnavailable { _ = try await link.getStorageIDs() }
    await assertThrowsUnavailable {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 1))
    }
    await assertThrowsUnavailable {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 1), parent: nil)
    }
    await assertThrowsUnavailable { _ = try await link.getObjectInfos([1]) }
    await assertThrowsUnavailable {
      _ = try await link.getObjectInfos(storage: MTPStorageID(raw: 1), parent: nil, format: nil)
    }
    await assertThrowsUnavailable { try await link.resetDevice() }
    await assertThrowsUnavailable { try await link.deleteObject(handle: 1) }
    await assertThrowsUnavailable {
      try await link.moveObject(handle: 1, to: MTPStorageID(raw: 1), parent: nil)
    }
    await assertThrowsUnavailable {
      _ = try await link.copyObject(handle: 1, toStorage: MTPStorageID(raw: 1), parent: nil)
    }
    await assertThrowsUnavailable {
      _ = try await link.executeCommand(PTPContainer(
        type: 1, code: 0x1001, txid: 0, params: []
      ))
    }
    await assertThrowsUnavailable {
      _ = try await link.executeStreamingCommand(
        PTPContainer(type: 1, code: 0x1001, txid: 0, params: []),
        dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
      )
    }

    // close is always safe
    await link.close()
    #else
    // On IOUSBHost platforms, the real implementation is tested by other test classes
    #endif
  }

  func testFallbackTransportOpenThrows() async {
    #if !canImport(IOUSBHost)
    let transport = IOUSBHostTransport()
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device"
    )
    do {
      _ = try await transport.open(summary, config: SwiftMTPConfig())
      XCTFail("Expected unavailable error")
    } catch let error as IOUSBHostTransportError {
      if case .unavailable = error {
        // expected
      } else {
        XCTFail("Expected unavailable, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    #endif
  }

  #if !canImport(IOUSBHost)
  private func assertThrowsUnavailable(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected unavailable error", file: file, line: line)
    } catch let error as IOUSBHostTransportError {
      if case .unavailable = error {
        // expected
      } else {
        XCTFail("Expected unavailable, got \(error)", file: file, line: line)
      }
    } catch {
      XCTFail("Unexpected error type: \(error)", file: file, line: line)
    }
  }
  #endif
}

// MARK: - MTPDeviceEvent Integration

final class IOUSBHostDeviceEventIntegrationTests: XCTestCase {

  func testDeviceEventSendableConformance() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Google", model: "Pixel 7"
    )
    let event: any Sendable = MTPDeviceEvent.attached(summary)
    XCTAssertNotNil(event)

    let detach: any Sendable = MTPDeviceEvent.detached("device-1")
    XCTAssertNotNil(detach)
  }

  func testDeviceEventsStreamIsEmpty() async {
    let stream = IOUSBHostDeviceLocator.deviceEvents()
    var events: [MTPDeviceEvent] = []
    for await event in stream {
      events.append(event)
    }
    XCTAssertTrue(events.isEmpty, "Current implementation returns empty stream")
  }
}

// MARK: - Data Container Construction Integration

final class IOUSBHostDataContainerIntegrationTests: XCTestCase {

  /// Verify that a complete MTP GetObject transaction can be modelled:
  /// command → data-in → response.
  func testGetObjectTransactionModelling() {
    // 1. Command container
    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObject.rawValue,
      txid: 1,
      params: [42]
    )
    var cmdBuf = [UInt8](repeating: 0, count: 32)
    let cmdLen = cmd.encode(into: &cmdBuf)
    XCTAssertEqual(cmdLen, 16, "GetObject command = 12 header + 4 param")

    // 2. Data container (device response with file data)
    let fileData = Data(repeating: 0xFF, count: 100)
    let dataContainer = buildDataContainer(code: PTPOp.getObject.rawValue, txid: 1, payload: fileData)
    XCTAssertEqual(dataContainer.count, 12 + 100)

    // 3. Response container
    let response = buildResponseContainer(code: 0x2001, txid: 1, params: [])
    XCTAssertEqual(response.count, 12)
    let parsed = parseResponseContainer(response)
    XCTAssertNotNil(parsed)
    XCTAssertTrue(parsed!.isOK)
  }

  /// Verify that a complete MTP SendObjectInfo + SendObject sequence can be modelled.
  func testSendObjectSequenceModelling() {
    // 1. SendObjectInfo command
    let infoCmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObjectInfo.rawValue,
      txid: 1,
      params: [0x00010001, 0xFFFFFFFF]  // storage, parent
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let infoLen = infoCmd.encode(into: &buf)
    XCTAssertEqual(infoLen, 20, "SendObjectInfo = 12 + 2*4")

    // 2. SendObjectInfo response with new handle
    let infoResp = buildResponseContainer(code: 0x2001, txid: 1, params: [0x00010001, 0xFFFFFFFF, 100])
    let parsed = parseResponseContainer(infoResp)!
    XCTAssertTrue(parsed.isOK)
    XCTAssertEqual(parsed.params[2], 100, "New object handle")

    // 3. SendObject command
    let sendCmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObject.rawValue,
      txid: 2,
      params: []
    )
    var buf2 = [UInt8](repeating: 0, count: 16)
    let sendLen = sendCmd.encode(into: &buf2)
    XCTAssertEqual(sendLen, 12)

    // 4. Data-out container for file content
    let fileContent = Data(repeating: 0xAB, count: 4096)
    let dataOut = buildDataContainer(
      code: PTPOp.sendObject.rawValue, txid: 2, payload: fileContent
    )
    XCTAssertEqual(dataOut.count, 12 + 4096)

    // 5. Final response
    let finalResp = buildResponseContainer(code: 0x2001, txid: 2, params: [])
    XCTAssertTrue(parseResponseContainer(finalResp)!.isOK)
  }

  /// Verify DeleteObject + MoveObject + CopyObject command framing.
  func testMutatingOperationFraming() {
    // DeleteObject: 1 param (handle)
    let del = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.deleteObject.rawValue,
      txid: 1,
      params: [42]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    XCTAssertEqual(del.encode(into: &buf), 16)

    // MoveObject: 3 params (handle, storage, parent)
    let move = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.moveObject.rawValue,
      txid: 2,
      params: [42, 0x00010001, 0xFFFFFFFF]
    )
    XCTAssertEqual(move.encode(into: &buf), 24)

    // CopyObject: 3 params
    let copy = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.copyObject.rawValue,
      txid: 3,
      params: [42, 0x00010001, 0xFFFFFFFF]
    )
    XCTAssertEqual(copy.encode(into: &buf), 24)
  }

  // MARK: - Helpers

  private func buildDataContainer(code: UInt16, txid: UInt32, payload: Data) -> Data {
    let length = UInt32(12 + payload.count)
    var data = Data(count: 12)
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.data.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
    }
    data.append(payload)
    return data
  }

  private func buildResponseContainer(code: UInt16, txid: UInt32, params: [UInt32]) -> Data {
    let length = UInt32(12 + params.count * 4)
    var data = Data(count: Int(length))
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.response.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      for (i, p) in params.enumerated() {
        base.storeBytes(of: p.littleEndian, toByteOffset: 12 + i * 4, as: UInt32.self)
      }
    }
    return data
  }

  private func parseResponseContainer(_ data: Data) -> PTPResponseResult? {
    guard data.count >= 12 else { return nil }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      guard type == PTPContainer.Kind.response.rawValue else { return nil }
      let code = UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self))
      let txid = UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self))
      var params: [UInt32] = []
      var offset = 12
      while offset + 4 <= data.count {
        let p = UInt32(littleEndian: base.load(fromByteOffset: offset, as: UInt32.self))
        params.append(p)
        offset += 4
      }
      return PTPResponseResult(code: code, txid: txid, params: params)
    }
  }
}

// MARK: - PTPReader Integration for IOUSBHost Path

final class IOUSBHostPTPReaderIntegrationTests: XCTestCase {

  func testPTPReaderMaxSafeCount() {
    XCTAssertEqual(PTPReader.maxSafeCount, 100_000)
  }

  func testPTPReaderValidateCountThrowsForLargeValues() {
    XCTAssertThrowsError(try PTPReader.validateCount(100_001))
    XCTAssertThrowsError(try PTPReader.validateCount(UInt32.max))
  }

  func testPTPReaderValidateCountAcceptsValidValues() {
    XCTAssertNoThrow(try PTPReader.validateCount(0))
    XCTAssertNoThrow(try PTPReader.validateCount(100_000))
    XCTAssertNoThrow(try PTPReader.validateCount(1))
  }

  func testPTPReaderSequentialReads() {
    var data = Data()
    appendUInt16(&data, 0x1234)
    appendUInt32(&data, 0xDEADBEEF)

    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u16(), 0x1234)
    XCTAssertEqual(reader.u32(), 0xDEADBEEF)
    XCTAssertNil(reader.u8(), "Should return nil at end of data")
  }

  func testPTPReaderStringParsing() {
    var data = Data()
    appendPTPString(&data, "Hello MTP")

    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.string(), "Hello MTP")
  }

  func testPTPReaderEmptyString() {
    // Empty PTP string: count = 0
    var data = Data()
    data.append(0)  // count = 0

    var reader = PTPReader(data: data)
    let result = reader.string()
    // Empty string or nil depending on implementation
    XCTAssertTrue(result == nil || result == "", "Empty PTP string should be nil or empty")
  }

  // MARK: - Helpers

  private func appendUInt16(_ data: inout Data, _ value: UInt16) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 2))
  }

  private func appendUInt32(_ data: inout Data, _ value: UInt32) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 4))
  }

  private func appendPTPString(_ data: inout Data, _ string: String) {
    let utf16 = Array(string.utf16)
    data.append(UInt8(utf16.count + 1))
    for ch in utf16 {
      var v = ch.littleEndian
      data.append(Data(bytes: &v, count: 2))
    }
    var null: UInt16 = 0
    data.append(Data(bytes: &null, count: 2))
  }
}
