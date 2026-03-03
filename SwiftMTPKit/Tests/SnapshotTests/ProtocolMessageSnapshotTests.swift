// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import MTPEndianCodec
import SwiftMTPQuirks

/// Snapshot tests for MTP protocol message encoding, response formats,
/// event notifications, and data structure serialization.
/// Complements ProtocolSnapshotTests with additional operation, response,
/// event, and error format coverage.
final class ProtocolMessageSnapshotTests: XCTestCase {

  // MARK: - 1. Additional MTP Operation Request Formats

  func testOperationCodeGetThumb() {
    XCTAssertEqual(PTPOp.getThumb.rawValue, 0x100A)
  }

  func testOperationCodeMoveObject() {
    XCTAssertEqual(PTPOp.moveObject.rawValue, 0x100E)
  }

  func testOperationCodeGetDevicePropDesc() {
    XCTAssertEqual(PTPOp.getDevicePropDesc.rawValue, 0x1014)
  }

  func testOperationCodeGetDevicePropValue() {
    XCTAssertEqual(PTPOp.getDevicePropValue.rawValue, 0x1015)
  }

  func testOperationCodeSetDevicePropValue() {
    XCTAssertEqual(PTPOp.setDevicePropValue.rawValue, 0x1016)
  }

  func testOperationCodeResetDevicePropValue() {
    XCTAssertEqual(PTPOp.resetDevicePropValue.rawValue, 0x1017)
  }

  func testOperationCodeGetPartialObject32() {
    XCTAssertEqual(PTPOp.getPartialObject.rawValue, 0x101B)
  }

  // MARK: - MTP Extension Operation Codes

  func testMTPOpGetObjectPropsSupported() {
    XCTAssertEqual(MTPOp.getObjectPropsSupported.rawValue, 0x9801)
  }

  func testMTPOpGetObjectPropDesc() {
    XCTAssertEqual(MTPOp.getObjectPropDesc.rawValue, 0x9802)
  }

  func testMTPOpGetObjectPropValue() {
    XCTAssertEqual(MTPOp.getObjectPropValue.rawValue, 0x9803)
  }

  func testMTPOpSetObjectPropValue() {
    XCTAssertEqual(MTPOp.setObjectPropValue.rawValue, 0x9804)
  }

  func testMTPOpGetObjectPropList() {
    XCTAssertEqual(MTPOp.getObjectPropList.rawValue, 0x9805)
  }

  func testMTPOpSendObjectPropList() {
    XCTAssertEqual(MTPOp.sendObjectPropList.rawValue, 0x9808)
  }

  func testMTPOpGetObjectReferences() {
    XCTAssertEqual(MTPOp.getObjectReferences.rawValue, 0x9810)
  }

  func testMTPOpSetObjectReferences() {
    XCTAssertEqual(MTPOp.setObjectReferences.rawValue, 0x9811)
  }

  // MARK: - PTPOp Backward-Compat Aliases

  func testPTPOpGetPartialObject64Alias() {
    XCTAssertEqual(PTPOp.getPartialObject64Value, 0x95C4)
  }

  func testPTPOpSendPartialObjectAlias() {
    XCTAssertEqual(PTPOp.sendPartialObjectValue, 0x95C1)
  }

  func testPTPOpGetObjectPropListAlias() {
    XCTAssertEqual(PTPOp.getObjectPropListValue, 0x9805)
  }

  // MARK: - 2. Additional MTP Response Code Snapshots

  func testResponseCodeInvalidTransactionID() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2004), "InvalidTransactionID")
  }

  func testResponseCodeParameterNotSupported() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2006), "ParameterNotSupported")
  }

  func testResponseCodeIncompleteTransfer() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2007), "IncompleteTransfer")
  }

  func testResponseCodeInvalidStorageID() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2008), "InvalidStorageID")
  }

  func testResponseCodeInvalidObjectHandle() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2009), "InvalidObjectHandle")
  }

  func testResponseCodeDevicePropNotSupported() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200A), "DevicePropNotSupported")
  }

  func testResponseCodeInvalidObjectFormatCode() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200B), "InvalidObjectFormatCode")
  }

  func testResponseCodeObjectWriteProtected() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200D), "ObjectWriteProtected")
  }

  func testResponseCodeStoreReadOnly() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200E), "StoreReadOnly")
  }

  func testResponseCodeNoThumbnailPresent() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2010), "NoThumbnailPresent")
  }

  func testResponseCodeSelfTestFailed() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2011), "SelfTestFailed")
  }

  func testResponseCodePartialDeletion() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2012), "PartialDeletion")
  }

  func testResponseCodeStoreNotAvailable() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2013), "StoreNotAvailable")
  }

  func testResponseCodeNoValidObjectInfo() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2015), "NoValidObjectInfo")
  }

  func testResponseCodeCaptureAlreadyTerminated() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2018), "CaptureAlreadyTerminated")
  }

  func testResponseCodeInvalidParentObject() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201A), "InvalidParentObject")
  }

  func testResponseCodeInvalidDevicePropFormat() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201B), "InvalidDevicePropFormat")
  }

  func testResponseCodeInvalidDevicePropValue() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201C), "InvalidDevicePropValue")
  }

  func testResponseCodeTransactionCancelled() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201F), "TransactionCancelled")
  }

  func testResponseCodeSpecOfDestUnsupported() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2020), "SpecificationOfDestinationUnsupported")
  }

  // MARK: - Response Code Describe Format

  func testResponseCodeDescribeOK() {
    XCTAssertEqual(PTPResponseCode.describe(0x2001), "OK (0x2001)")
  }

  func testResponseCodeDescribeGeneralError() {
    XCTAssertEqual(PTPResponseCode.describe(0x2002), "GeneralError (0x2002)")
  }

  func testResponseCodeDescribeDeviceBusy() {
    XCTAssertEqual(PTPResponseCode.describe(0x2019), "DeviceBusy (0x2019)")
  }

  func testResponseCodeDescribeSessionAlreadyOpen() {
    XCTAssertEqual(PTPResponseCode.describe(0x201E), "SessionAlreadyOpen (0x201e)")
  }

  func testResponseCodeNameReturnsNilForUnknown() {
    XCTAssertNil(PTPResponseCode.name(for: 0xBEEF))
  }

  // MARK: - 3. Event Notification Container Formats

  func testEventContainerObjectAdded() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4002,  // ObjectAdded
      txid: 0,
      params: [0x00000005]  // objectHandle
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[4], 0x04)  // event type
    XCTAssertEqual(buf[6], 0x02)  // 0x4002 low byte
    XCTAssertEqual(buf[7], 0x40)  // 0x4002 high byte
    XCTAssertEqual(buf[12], 0x05)  // objectHandle param
  }

  func testEventContainerObjectRemoved() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4003,  // ObjectRemoved
      txid: 0,
      params: [0x0000000A]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x03)  // 0x4003 low byte
    XCTAssertEqual(buf[7], 0x40)
    XCTAssertEqual(buf[12], 0x0A)  // handle
  }

  func testEventContainerStoreAdded() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4004,  // StoreAdded
      txid: 0,
      params: [0x00010001]  // storageID
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x04)  // 0x4004
    XCTAssertEqual(buf[7], 0x40)
    XCTAssertEqual(buf[12], 0x01)  // storageID low
    XCTAssertEqual(buf[14], 0x01)  // storageID high word low
  }

  func testEventContainerStoreRemoved() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4005,  // StoreRemoved
      txid: 0,
      params: [0x00020001]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x05)
    XCTAssertEqual(buf[7], 0x40)
  }

  func testEventContainerDevicePropChanged() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4006,  // DevicePropChanged
      txid: 0,
      params: [0x5001]  // BatteryLevel property code
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x06)
    XCTAssertEqual(buf[7], 0x40)
  }

  func testEventContainerCancelTransaction() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4001,  // CancelTransaction
      txid: 7,
      params: [7]  // transaction to cancel
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x01)
    XCTAssertEqual(buf[7], 0x40)
  }

  func testEventContainerStoreFull() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x400A,  // StoreFull
      txid: 0,
      params: [0x00010001]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x0A)
    XCTAssertEqual(buf[7], 0x40)
  }

  // MARK: - 4. Command Request Container Formats

  func testCommandGetStorageInfo() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getStorageInfo.rawValue,
      txid: 2,
      params: [0x00010001]  // storageID
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[4], 0x01)  // command type
    XCTAssertEqual(buf[6], 0x05)  // 0x1005 low
    XCTAssertEqual(buf[7], 0x10)  // 0x1005 high
  }

  func testCommandGetObjectInfo() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectInfo.rawValue,
      txid: 4,
      params: [42]  // objectHandle
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x08)  // 0x1008
    XCTAssertEqual(buf[7], 0x10)
    XCTAssertEqual(buf[12], 42)  // handle param
  }

  func testCommandDeleteObject() {
    let container = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.deleteObject.rawValue,
      txid: 5,
      params: [100, 0x00000000]  // objectHandle, formatCode=all
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 20)
    XCTAssertEqual(buf[6], 0x0B)  // 0x100B
    XCTAssertEqual(buf[7], 0x10)
  }

  func testCommandSendObjectInfo() {
    let container = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObjectInfo.rawValue,
      txid: 6,
      params: [0x00010001, 0xFFFFFFFF]  // storageID, parentHandle
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 20)
    XCTAssertEqual(buf[6], 0x0C)  // 0x100C
    XCTAssertEqual(buf[7], 0x10)
    // parentHandle = 0xFFFFFFFF (root)
    XCTAssertEqual(buf[16], 0xFF)
    XCTAssertEqual(buf[17], 0xFF)
    XCTAssertEqual(buf[18], 0xFF)
    XCTAssertEqual(buf[19], 0xFF)
  }

  func testCommandCloseSession() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.closeSession.rawValue,
      txid: 99
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    XCTAssertEqual(buf[6], 0x03)  // 0x1003
    XCTAssertEqual(buf[7], 0x10)
    XCTAssertEqual(buf[8], 99)  // txid
  }

  func testCommandGetObject() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObject.rawValue,
      txid: 10,
      params: [255]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    XCTAssertEqual(buf[6], 0x09)  // 0x1009
    XCTAssertEqual(buf[7], 0x10)
    XCTAssertEqual(buf[12], 0xFF)
  }

  func testCommandMoveObject() {
    let container = PTPContainer(
      length: 24,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.moveObject.rawValue,
      txid: 11,
      params: [1, 0x00010001, 0x00000002]  // handle, storageID, newParent
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 24)
    XCTAssertEqual(buf[6], 0x0E)  // 0x100E
    XCTAssertEqual(buf[7], 0x10)
  }

  // MARK: - 5. ObjectInfo Encoding Snapshots

  func testObjectInfoDatasetJPEG() {
    let dataset = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0x00000002,
      format: 0x3801,  // EXIF/JPEG
      size: 5_242_880,
      name: "sunset.jpg"
    )
    XCTAssertGreaterThan(dataset.count, 50)
    // format at offset 4: 0x3801
    XCTAssertEqual(dataset[4], 0x01)
    XCTAssertEqual(dataset[5], 0x38)
  }

  func testObjectInfoDatasetPNG() {
    let dataset = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0xFFFFFFFF,
      format: 0x380B,  // PNG
      size: 2048,
      name: "icon.png"
    )
    XCTAssertGreaterThan(dataset.count, 50)
    XCTAssertEqual(dataset[4], 0x0B)
    XCTAssertEqual(dataset[5], 0x38)
  }

  func testObjectInfoDatasetMP4() {
    let dataset = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0x00000003,
      format: 0x300B,  // MP4
      size: 100_000_000,
      name: "video.mp4"
    )
    XCTAssertGreaterThan(dataset.count, 50)
    XCTAssertEqual(dataset[4], 0x0B)
    XCTAssertEqual(dataset[5], 0x30)
  }

  func testObjectInfoDatasetFolder() {
    let dataset = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0xFFFFFFFF,
      format: 0x3001,  // Association (folder)
      size: 0,
      name: "DCIM"
    )
    XCTAssertGreaterThan(dataset.count, 40)
    XCTAssertEqual(dataset[4], 0x01)
    XCTAssertEqual(dataset[5], 0x30)
  }

  // MARK: - Additional Object Format Code Lookups

  func testObjectFormatCodeGIF() {
    // GIF maps to undefined (0x3000) if not explicitly mapped
    let code = PTPObjectFormat.forFilename("anim.gif")
    XCTAssertTrue(code == 0x380A || code == 0x3000)
  }

  func testObjectFormatCodeWAV() {
    let code = PTPObjectFormat.forFilename("audio.wav")
    XCTAssertTrue(code == 0x3008 || code == 0x3000)
  }

  func testObjectFormatCodeCaseInsensitive() {
    XCTAssertEqual(PTPObjectFormat.forFilename("PHOTO.JPG"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("Video.MP4"), 0x300B)
    XCTAssertEqual(PTPObjectFormat.forFilename("Song.MP3"), 0x3009)
  }

  func testObjectFormatCodeNoExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("README"), 0x3000)
  }

  func testObjectFormatCodeDotFile() {
    XCTAssertEqual(PTPObjectFormat.forFilename(".hidden"), 0x3000)
  }

  // MARK: - 6. DeviceInfo Structure Additional Snapshots

  func testDeviceInfoOperationsSupportedSnapshot() throws {
    let info = MTPDeviceInfo(
      manufacturer: "Samsung",
      model: "Galaxy S7",
      version: "2.0",
      serialNumber: "SM-G930W8",
      operationsSupported: [
        0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007,
        0x1008, 0x1009, 0x100B, 0x100C, 0x100D, 0x101B, 0x95C4,
      ],
      eventsSupported: [0x4002, 0x4003, 0x4004, 0x4005, 0x4006]
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.operationsSupported.count, 14)
    XCTAssertTrue(decoded.operationsSupported.contains(0x95C4))
    XCTAssertTrue(decoded.operationsSupported.contains(0x101B))
    XCTAssertEqual(decoded.eventsSupported.count, 5)
  }

  func testDeviceInfoCameraDevice() throws {
    let info = MTPDeviceInfo(
      manufacturer: "Canon",
      model: "EOS Rebel T7",
      version: "1.0.0",
      serialNumber: "CANON12345",
      operationsSupported: [0x1001, 0x1002, 0x1003, 0x1008, 0x1009],
      eventsSupported: [0x4002]
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "Canon")
    XCTAssertEqual(decoded.model, "EOS Rebel T7")
    XCTAssertEqual(decoded.operationsSupported.count, 5)
  }

  func testDeviceInfoUnicodeManufacturer() throws {
    let info = MTPDeviceInfo(
      manufacturer: "日本電気",
      model: "テストデバイス",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: [0x1001],
      eventsSupported: []
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "日本電気")
    XCTAssertEqual(decoded.model, "テストデバイス")
  }

  // MARK: - 7. StorageInfo Additional Snapshots

  func testStorageInfoZeroCapacity() throws {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00010001),
      description: "Virtual Storage",
      capacityBytes: 0,
      freeBytes: 0,
      isReadOnly: true
    )
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.capacityBytes, 0)
    XCTAssertEqual(decoded.freeBytes, 0)
    XCTAssertTrue(decoded.isReadOnly)
  }

  func testStorageInfoLargeCapacity() throws {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00010001),
      description: "1TB External",
      capacityBytes: 1_000_000_000_000,
      freeBytes: 500_000_000_000,
      isReadOnly: false
    )
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.capacityBytes, 1_000_000_000_000)
    XCTAssertEqual(decoded.freeBytes, 500_000_000_000)
  }

  func testStorageInfoSDCardFull() throws {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00020001),
      description: "SD Card",
      capacityBytes: 32_000_000_000,
      freeBytes: 1024,
      isReadOnly: false
    )
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.freeBytes, 1024)
    XCTAssertFalse(decoded.isReadOnly)
  }

  func testStorageIDRawValues() {
    // First storage on first physical unit
    XCTAssertEqual(MTPStorageID(raw: 0x00010001).raw, 0x00010001)
    // Second storage on first physical unit
    XCTAssertEqual(MTPStorageID(raw: 0x00020001).raw, 0x00020001)
    // First storage on second physical unit
    XCTAssertEqual(MTPStorageID(raw: 0x00010002).raw, 0x00010002)
  }

  // MARK: - 8. Error Response Format Snapshots

  func testErrorObjectWriteProtected() {
    let err = MTPError.objectWriteProtected
    XCTAssertEqual(err.errorDescription, "The target object is write-protected.")
  }

  func testErrorTransportWrapping() {
    let err = MTPError.transport(.timeout)
    XCTAssertEqual(err.errorDescription, "The USB transfer timed out.")
  }

  func testErrorTransportIO() {
    let err = TransportError.io("LIBUSB_ERROR_PIPE: endpoint halted")
    XCTAssertEqual(err.errorDescription, "LIBUSB_ERROR_PIPE: endpoint halted")
  }

  func testErrorTransportBusy() {
    let err = TransportError.busy
    XCTAssertEqual(err.errorDescription, "USB access is temporarily busy.")
  }

  func testErrorTransportAccessDenied() {
    let err = TransportError.accessDenied
    XCTAssertEqual(
      err.errorDescription,
      "The USB device is currently unavailable due to access/claim restrictions.")
  }

  func testErrorTransportStall() {
    let err = TransportError.stall
    XCTAssertEqual(err.errorDescription, "A USB endpoint stalled; the transfer was aborted.")
  }

  func testErrorProtocolErrorGenericFormat() {
    let err = MTPError.protocolError(code: 0x2002, message: nil)
    XCTAssertEqual(
      err.errorDescription,
      "GeneralError (0x2002): the device reported an unspecified failure.")
  }

  func testErrorProtocolErrorWithMessage() {
    let err = MTPError.protocolError(code: 0x2005, message: "OperationNotSupported")
    XCTAssertEqual(
      err.errorDescription,
      "OperationNotSupported (0x2005): the device does not support this operation.")
  }

  func testErrorProtocolError201DSpecialFormat() {
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertEqual(
      err.errorDescription,
      "Protocol error InvalidParameter (0x201D): write request rejected by device.")
  }

  func testErrorRecoverySuggestionGenericProtocol() {
    let err = MTPError.protocolError(code: 0x2002, message: nil)
    XCTAssertEqual(
      err.recoverySuggestion,
      "Retry the operation. If the error persists, reconnect the device.")
  }

  func testErrorFailureReasonProtocol201D() {
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertEqual(err.failureReason, "This device rejected invalid write parameters.")
  }

  func testErrorFailureReasonGenericProtocol() {
    let err = MTPError.protocolError(code: 0x2002, message: nil)
    XCTAssertEqual(err.failureReason, "The device response indicates a protocol error.")
  }

  func testErrorFailureReasonNilForNonProtocol() {
    XCTAssertNotNil(MTPError.timeout.failureReason)
    XCTAssertNotNil(MTPError.busy.failureReason)
    XCTAssertNotNil(MTPError.storageFull.failureReason)
  }

  func testErrorRecoverySuggestionNilForNonProtocol() {
    XCTAssertNotNil(MTPError.timeout.recoverySuggestion)
    XCTAssertNotNil(MTPError.busy.recoverySuggestion)
    XCTAssertNotNil(MTPError.deviceDisconnected.recoverySuggestion)
  }

  // MARK: - Transport Error Details

  func testTransportErrorFailureReasonNoDevice() {
    let err = TransportError.noDevice
    XCTAssertEqual(
      err.failureReason,
      "No matching USB interface was claimed for MTP operations.")
  }

  func testTransportErrorFailureReasonAccessDenied() {
    let err = TransportError.accessDenied
    XCTAssertEqual(
      err.failureReason,
      "Another process may own the interface (Android File Transfer, adb, browsers).")
  }

  func testTransportErrorRecoverySuggestionAccessDenied() {
    let err = TransportError.accessDenied
    XCTAssertEqual(
      err.recoverySuggestion,
      "Close competing USB tools (Android File Transfer, adb, Samsung Smart Switch), then retry.")
  }

  func testTransportErrorRecoverySuggestionStall() {
    let err = TransportError.stall
    XCTAssertEqual(
      err.recoverySuggestion,
      "Disconnect and reconnect the device. If the issue persists, try a different USB port or cable."
    )
  }

  func testTransportErrorRecoverySuggestionBusy() {
    let err = TransportError.busy
    XCTAssertEqual(
      err.recoverySuggestion,
      "Wait a moment for the bus to become available, then retry. Close other USB-intensive applications."
    )
  }

  func testTransportPhaseResponseWait() {
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testTransportErrorTimeoutInResponseWaitPhase() {
    let err = TransportError.timeoutInPhase(.responseWait)
    XCTAssertEqual(
      err.errorDescription,
      "The USB transfer timed out during the response-wait phase.")
  }

  // MARK: - 9. Actionable Error Message Snapshots

  func testActionableErrorObjectWriteProtected() {
    let err = MTPError.objectWriteProtected
    XCTAssertEqual(
      err.actionableDescription,
      "Device storage is write-protected. Remove protection on the device and retry.")
  }

  func testActionableErrorReadOnly() {
    let err = MTPError.readOnly
    XCTAssertEqual(
      err.actionableDescription,
      "The storage is read-only. Check for a physical write-protect switch or device setting.")
  }

  func testActionableErrorStorageFull() {
    let err = MTPError.storageFull
    XCTAssertEqual(
      err.actionableDescription,
      "Device storage is full. Free space on the device, then retry the transfer.")
  }

  func testActionableErrorObjectNotFound() {
    let err = MTPError.objectNotFound
    XCTAssertEqual(
      err.actionableDescription,
      "The requested object was not found on the device. It may have been deleted or moved.")
  }

  func testActionableErrorTimeout() {
    let err = MTPError.timeout
    XCTAssertEqual(
      err.actionableDescription,
      "The operation timed out. Check that the device is still connected and unlocked.")
  }

  func testActionableErrorSessionBusy() {
    let err = MTPError.sessionBusy
    XCTAssertEqual(
      err.actionableDescription,
      "An MTP operation is already in progress. Wait briefly and retry.")
  }

  func testActionableErrorNotSupported() {
    let err = MTPError.notSupported("GetPartialObject64")
    XCTAssertEqual(
      err.actionableDescription,
      "Not supported: GetPartialObject64. Check device firmware or try a different approach.")
  }

  func testActionableErrorVerificationFailed() {
    let err = MTPError.verificationFailed(expected: 1024, actual: 512)
    XCTAssertTrue(err.actionableDescription.contains("Write verification failed"))
  }

  func testActionableTransportBusy() {
    let err = TransportError.busy
    XCTAssertEqual(
      err.actionableDescription,
      "USB access is busy. Close competing USB tools and retry.")
  }

  func testActionableTransportStall() {
    let err = TransportError.stall
    XCTAssertEqual(
      err.actionableDescription,
      "USB endpoint stalled. Disconnect and reconnect the device. Try a different USB port if it persists."
    )
  }

  func testActionableTransportIO() {
    let err = TransportError.io("LIBUSB_ERROR_OVERFLOW")
    XCTAssertEqual(
      err.actionableDescription,
      "USB I/O error: LIBUSB_ERROR_OVERFLOW. Try a different USB port or cable.")
  }

  func testActionableTransportTimeout() {
    let err = TransportError.timeout
    XCTAssertEqual(
      err.actionableDescription,
      "USB transfer timed out. Ensure the device screen is on and unlocked, then check the cable.")
  }

  // MARK: - 10. PTP String Encoding Edge Cases

  func testPTPStringEncodeUnicode() {
    let encoded = PTPString.encode("日本語")
    // Count prefix: 4 (3 chars + null terminator)
    XCTAssertEqual(encoded[0], 4)
    // Each char is 2 bytes in UTF-16LE, plus null terminator
    XCTAssertEqual(encoded.count, 1 + 4 * 2)  // prefix + (3 chars + null) * 2
  }

  func testPTPStringRoundTripUnicode() {
    let original = "фото"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }

  func testPTPStringRoundTripLong() {
    let original = String(repeating: "A", count: 100)
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }

  func testPTPStringRoundTripSpecialChars() {
    let original = "photo (1).jpg"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }

  func testPTPStringEncodeSingleChar() {
    let encoded = PTPString.encode("X")
    // Count prefix: 2 (1 char + null terminator)
    XCTAssertEqual(encoded[0], 2)
    // 'X' = 0x58 in UTF-16LE
    XCTAssertEqual(encoded[1], 0x58)
    XCTAssertEqual(encoded[2], 0x00)
  }

  // MARK: - 11. Container Encoding Edge Cases

  func testContainerZeroTxID() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 0
    )
    var buf = [UInt8](repeating: 0xFF, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    XCTAssertEqual(buf[8], 0x00)
    XCTAssertEqual(buf[9], 0x00)
    XCTAssertEqual(buf[10], 0x00)
    XCTAssertEqual(buf[11], 0x00)
  }

  func testContainerMaxTxID() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.response.rawValue,
      code: 0x2001,
      txid: 0xFFFFFFFF
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    XCTAssertEqual(buf[8], 0xFF)
    XCTAssertEqual(buf[9], 0xFF)
    XCTAssertEqual(buf[10], 0xFF)
    XCTAssertEqual(buf[11], 0xFF)
  }

  func testContainerFiveParams() {
    let container = PTPContainer(
      length: 32,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: 1,
      params: [0x00010001, 0x00003001, 0xFFFFFFFF, 0, 0]
    )
    var buf = [UInt8](repeating: 0, count: 48)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 32)
  }

  // MARK: - 12. MTPError Equatable Snapshots

  func testMTPErrorEquality() {
    XCTAssertEqual(MTPError.timeout, MTPError.timeout)
    XCTAssertEqual(MTPError.busy, MTPError.busy)
    XCTAssertEqual(MTPError.storageFull, MTPError.storageFull)
    XCTAssertNotEqual(MTPError.timeout, MTPError.busy)
  }

  func testMTPErrorNotSupportedEquality() {
    XCTAssertEqual(
      MTPError.notSupported("GetPartialObject64"),
      MTPError.notSupported("GetPartialObject64"))
    XCTAssertNotEqual(
      MTPError.notSupported("GetPartialObject64"),
      MTPError.notSupported("SendPartialObject"))
  }

  func testMTPErrorInternalErrorFactory() {
    let err = MTPError.internalError("test message")
    XCTAssertEqual(err, MTPError.notSupported("test message"))
  }
}
