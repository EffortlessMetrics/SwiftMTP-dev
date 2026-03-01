// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import MTPEndianCodec
import SwiftMTPQuirks

/// Inline snapshot tests for MTP protocol types: operation codes, response codes,
/// container headers, device/object/storage info serialization, error descriptions,
/// and quirk policy resolution.  Every test uses `XCTAssertEqual` against a known
/// expected value — no file-based snapshot infrastructure required.
final class ProtocolSnapshotTests: XCTestCase {

  // MARK: - 1. MTP Operation Code Snapshots

  func testOperationCodeOpenSession() {
    XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
  }

  func testOperationCodeCloseSession() {
    XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
  }

  func testOperationCodeGetDeviceInfo() {
    XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
  }

  func testOperationCodeGetStorageIDs() {
    XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
  }

  func testOperationCodeGetStorageInfo() {
    XCTAssertEqual(PTPOp.getStorageInfo.rawValue, 0x1005)
  }

  func testOperationCodeGetNumObjects() {
    XCTAssertEqual(PTPOp.getNumObjects.rawValue, 0x1006)
  }

  func testOperationCodeGetObjectHandles() {
    XCTAssertEqual(PTPOp.getObjectHandles.rawValue, 0x1007)
  }

  func testOperationCodeGetObjectInfo() {
    XCTAssertEqual(PTPOp.getObjectInfo.rawValue, 0x1008)
  }

  func testOperationCodeGetObject() {
    XCTAssertEqual(PTPOp.getObject.rawValue, 0x1009)
  }

  func testOperationCodeDeleteObject() {
    XCTAssertEqual(PTPOp.deleteObject.rawValue, 0x100B)
  }

  func testOperationCodeSendObjectInfo() {
    XCTAssertEqual(PTPOp.sendObjectInfo.rawValue, 0x100C)
  }

  func testOperationCodeSendObject() {
    XCTAssertEqual(PTPOp.sendObject.rawValue, 0x100D)
  }

  func testOperationCodeGetPartialObject64() {
    XCTAssertEqual(PTPOp.getPartialObject64.rawValue, 0x95C4)
  }

  func testOperationCodeSendPartialObject() {
    XCTAssertEqual(PTPOp.sendPartialObject.rawValue, 0x95C1)
  }

  // MARK: - 2. MTP Response Code Snapshots

  func testResponseCodeOK() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
  }

  func testResponseCodeGeneralError() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2002), "GeneralError")
  }

  func testResponseCodeSessionNotOpen() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2003), "SessionNotOpen")
  }

  func testResponseCodeOperationNotSupported() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2005), "OperationNotSupported")
  }

  func testResponseCodeStoreFull() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200C), "StoreFull")
  }

  func testResponseCodeAccessDenied() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x200F), "AccessDenied")
  }

  func testResponseCodeDeviceBusy() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2019), "DeviceBusy")
  }

  func testResponseCodeInvalidParameter() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201D), "InvalidParameter")
  }

  func testResponseCodeSessionAlreadyOpen() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201E), "SessionAlreadyOpen")
  }

  func testResponseCodeDescribeFormat() {
    XCTAssertEqual(
      PTPResponseCode.describe(0x201D),
      "InvalidParameter (0x201d)")
  }

  func testResponseCodeDescribeUnknown() {
    XCTAssertEqual(
      PTPResponseCode.describe(0xFFFF),
      "Unknown (0xffff)")
  }

  // MARK: - 3. Container Header Snapshots

  func testCommandContainerEncoding() {
    let container = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: 1,
      params: [1]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 16)
    // length (LE): 16 = 0x10,0x00,0x00,0x00
    XCTAssertEqual(buf[0], 0x10)
    XCTAssertEqual(buf[1], 0x00)
    XCTAssertEqual(buf[2], 0x00)
    XCTAssertEqual(buf[3], 0x00)
    // type (LE): command = 1 = 0x01,0x00
    XCTAssertEqual(buf[4], 0x01)
    XCTAssertEqual(buf[5], 0x00)
    // code (LE): OpenSession = 0x1002 = 0x02,0x10
    XCTAssertEqual(buf[6], 0x02)
    XCTAssertEqual(buf[7], 0x10)
    // txid (LE): 1 = 0x01,0x00,0x00,0x00
    XCTAssertEqual(buf[8], 0x01)
    XCTAssertEqual(buf[9], 0x00)
    XCTAssertEqual(buf[10], 0x00)
    XCTAssertEqual(buf[11], 0x00)
    // param[0] (LE): 1 = 0x01,0x00,0x00,0x00
    XCTAssertEqual(buf[12], 0x01)
    XCTAssertEqual(buf[13], 0x00)
    XCTAssertEqual(buf[14], 0x00)
    XCTAssertEqual(buf[15], 0x00)
  }

  func testResponseContainerEncoding() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.response.rawValue,
      code: 0x2001,  // OK
      txid: 42
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    // type (LE): response = 3 = 0x03,0x00
    XCTAssertEqual(buf[4], 0x03)
    XCTAssertEqual(buf[5], 0x00)
    // code (LE): OK = 0x2001 = 0x01,0x20
    XCTAssertEqual(buf[6], 0x01)
    XCTAssertEqual(buf[7], 0x20)
    // txid (LE): 42 = 0x2A,0x00,0x00,0x00
    XCTAssertEqual(buf[8], 0x2A)
    XCTAssertEqual(buf[9], 0x00)
  }

  func testEventContainerEncoding() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.event.rawValue,
      code: 0x4002,  // ObjectAdded
      txid: 0
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    // type (LE): event = 4
    XCTAssertEqual(buf[4], 0x04)
    XCTAssertEqual(buf[5], 0x00)
    // code (LE): 0x4002
    XCTAssertEqual(buf[6], 0x02)
    XCTAssertEqual(buf[7], 0x40)
  }

  func testDataContainerEncoding() {
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.data.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 5
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12)
    // type (LE): data = 2
    XCTAssertEqual(buf[4], 0x02)
    XCTAssertEqual(buf[5], 0x00)
  }

  func testContainerKindRawValues() {
    XCTAssertEqual(PTPContainer.Kind.command.rawValue, 1)
    XCTAssertEqual(PTPContainer.Kind.data.rawValue, 2)
    XCTAssertEqual(PTPContainer.Kind.response.rawValue, 3)
    XCTAssertEqual(PTPContainer.Kind.event.rawValue, 4)
  }

  func testContainerMultipleParams() {
    let container = PTPContainer(
      length: 24,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: 3,
      params: [0x00010001, 0x00000000, 0xFFFFFFFF]
    )
    var buf = [UInt8](repeating: 0, count: 32)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 24)
    // param[0] storageID = 0x00010001
    XCTAssertEqual(buf[12], 0x01)
    XCTAssertEqual(buf[13], 0x00)
    XCTAssertEqual(buf[14], 0x01)
    XCTAssertEqual(buf[15], 0x00)
    // param[2] parentHandle = 0xFFFFFFFF
    XCTAssertEqual(buf[20], 0xFF)
    XCTAssertEqual(buf[21], 0xFF)
    XCTAssertEqual(buf[22], 0xFF)
    XCTAssertEqual(buf[23], 0xFF)
  }

  // MARK: - 4. Device Info Structure Snapshots

  func testDeviceInfoJSONRoundTrip() throws {
    let info = MTPDeviceInfo(
      manufacturer: "Google",
      model: "Pixel 7",
      version: "1.0",
      serialNumber: "ABC123",
      operationsSupported: [0x1001, 0x1002, 0x1003, 0x1007, 0x95C4],
      eventsSupported: [0x4002, 0x4003]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "Google")
    XCTAssertEqual(decoded.model, "Pixel 7")
    XCTAssertEqual(decoded.version, "1.0")
    XCTAssertEqual(decoded.serialNumber, "ABC123")
    XCTAssertEqual(decoded.operationsSupported, [0x1001, 0x1002, 0x1003, 0x1007, 0x95C4])
    XCTAssertEqual(decoded.eventsSupported, [0x4002, 0x4003])
  }

  func testDeviceInfoMinimalFields() throws {
    let info = MTPDeviceInfo(
      manufacturer: "",
      model: "",
      version: "",
      serialNumber: nil,
      operationsSupported: [],
      eventsSupported: []
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "")
    XCTAssertNil(decoded.serialNumber)
    XCTAssertTrue(decoded.operationsSupported.isEmpty)
  }

  func testPTPDeviceInfoParsing() {
    // Build a minimal PTP DeviceInfo dataset manually
    var w = MTPDataEncoder()
    w.append(UInt16(100))              // standardVersion
    w.append(UInt32(0x00000006))       // vendorExtensionID (MTP)
    w.append(UInt16(100))              // vendorExtensionVersion
    w.append(PTPString.encode("microsoft.com: 1.0"))  // vendorExtensionDesc
    w.append(UInt16(0))                // functionalMode
    // operationsSupported: [0x1001, 0x1002]
    w.append(UInt32(2))
    w.append(UInt16(0x1001))
    w.append(UInt16(0x1002))
    // eventsSupported: []
    w.append(UInt32(0))
    // devicePropertiesSupported: []
    w.append(UInt32(0))
    // captureFormats: []
    w.append(UInt32(0))
    // playbackFormats: [0x3001]
    w.append(UInt32(1))
    w.append(UInt16(0x3001))
    w.append(PTPString.encode("TestMfg"))    // manufacturer
    w.append(PTPString.encode("TestModel"))  // model
    w.append(PTPString.encode("1.0.0"))      // deviceVersion
    w.append(PTPString.encode("SN12345"))    // serialNumber

    let parsed = PTPDeviceInfo.parse(from: w.encodedData)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.manufacturer, "TestMfg")
    XCTAssertEqual(parsed?.model, "TestModel")
    XCTAssertEqual(parsed?.serialNumber, "SN12345")
    XCTAssertEqual(parsed?.operationsSupported, [0x1001, 0x1002])
    XCTAssertEqual(parsed?.playbackFormats, [0x3001])
    XCTAssertEqual(parsed?.standardVersion, 100)
    XCTAssertEqual(parsed?.vendorExtensionID, 6)
  }

  // MARK: - 5. Object Info Structure Snapshots

  func testObjectInfoJSONRoundTrip() throws {
    let obj = MTPObjectInfo(
      handle: 0x00000001,
      storage: MTPStorageID(raw: 0x00010001),
      parent: 0xFFFFFFFF,
      name: "photo.jpg",
      sizeBytes: 4_200_000,
      modified: nil,
      formatCode: 0x3801,
      properties: [0xDC01: "photo.jpg", 0xDC04: "4200000"]
    )
    let data = try JSONEncoder().encode(obj)
    let decoded = try JSONDecoder().decode(MTPObjectInfo.self, from: data)
    XCTAssertEqual(decoded.handle, 1)
    XCTAssertEqual(decoded.storage.raw, 0x00010001)
    XCTAssertEqual(decoded.parent, 0xFFFFFFFF)
    XCTAssertEqual(decoded.name, "photo.jpg")
    XCTAssertEqual(decoded.sizeBytes, 4_200_000)
    XCTAssertEqual(decoded.formatCode, 0x3801)
  }

  func testObjectInfoDirectory() throws {
    let dir = MTPObjectInfo(
      handle: 0x00000002,
      storage: MTPStorageID(raw: 0x00010001),
      parent: nil,
      name: "DCIM",
      sizeBytes: nil,
      modified: nil,
      formatCode: 0x3001,
      properties: [:]
    )
    let data = try JSONEncoder().encode(dir)
    let decoded = try JSONDecoder().decode(MTPObjectInfo.self, from: data)
    XCTAssertEqual(decoded.name, "DCIM")
    XCTAssertNil(decoded.parent)
    XCTAssertNil(decoded.sizeBytes)
    XCTAssertEqual(decoded.formatCode, 0x3001)
  }

  func testObjectInfoDatasetEncoding() {
    let dataset = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0xFFFFFFFF,
      format: 0x3004,  // Text
      size: 1024,
      name: "test.txt"
    )
    // Verify dataset is non-empty and starts with storageID bytes
    XCTAssertGreaterThan(dataset.count, 50)
    // storageID at offset 0: 0x00010001 LE
    XCTAssertEqual(dataset[0], 0x01)
    XCTAssertEqual(dataset[1], 0x00)
    XCTAssertEqual(dataset[2], 0x01)
    XCTAssertEqual(dataset[3], 0x00)
    // format at offset 4: 0x3004 LE
    XCTAssertEqual(dataset[4], 0x04)
    XCTAssertEqual(dataset[5], 0x30)
  }

  func testObjectFormatCodeLookup() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.jpeg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("doc.txt"), 0x3004)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380B)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300B)
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.aac"), 0xB903)
    XCTAssertEqual(PTPObjectFormat.forFilename("unknown.xyz"), 0x3000)
  }

  // MARK: - 6. Storage Info Structure Snapshots

  func testStorageInfoJSONRoundTrip() throws {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00010001),
      description: "Internal Storage",
      capacityBytes: 128_000_000_000,
      freeBytes: 64_000_000_000,
      isReadOnly: false
    )
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.id.raw, 0x00010001)
    XCTAssertEqual(decoded.description, "Internal Storage")
    XCTAssertEqual(decoded.capacityBytes, 128_000_000_000)
    XCTAssertEqual(decoded.freeBytes, 64_000_000_000)
    XCTAssertEqual(decoded.isReadOnly, false)
  }

  func testStorageInfoReadOnly() throws {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00020001),
      description: "SD Card",
      capacityBytes: 32_000_000_000,
      freeBytes: 0,
      isReadOnly: true
    )
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.description, "SD Card")
    XCTAssertEqual(decoded.isReadOnly, true)
    XCTAssertEqual(decoded.freeBytes, 0)
  }

  func testStorageInfoMultipleStorages() throws {
    let storages = [
      MTPStorageInfo(
        id: MTPStorageID(raw: 0x00010001),
        description: "Internal",
        capacityBytes: 128_000_000_000,
        freeBytes: 64_000_000_000,
        isReadOnly: false
      ),
      MTPStorageInfo(
        id: MTPStorageID(raw: 0x00020001),
        description: "SD Card",
        capacityBytes: 64_000_000_000,
        freeBytes: 32_000_000_000,
        isReadOnly: false
      ),
    ]
    let data = try JSONEncoder().encode(storages)
    let decoded = try JSONDecoder().decode([MTPStorageInfo].self, from: data)
    XCTAssertEqual(decoded.count, 2)
    XCTAssertEqual(decoded[0].id.raw, 0x00010001)
    XCTAssertEqual(decoded[1].id.raw, 0x00020001)
  }

  // MARK: - 7. Error Code Snapshots

  func testErrorDeviceDisconnected() {
    let err = MTPError.deviceDisconnected
    XCTAssertEqual(err.errorDescription, "The device disconnected during the operation.")
  }

  func testErrorPermissionDenied() {
    let err = MTPError.permissionDenied
    XCTAssertEqual(err.errorDescription, "Access to the USB device was denied.")
  }

  func testErrorNotSupported() {
    let err = MTPError.notSupported("GetPartialObject64")
    XCTAssertEqual(err.errorDescription, "Not supported: GetPartialObject64")
  }

  func testErrorObjectNotFound() {
    let err = MTPError.objectNotFound
    XCTAssertEqual(err.errorDescription, "The requested object was not found.")
  }

  func testErrorStorageFull() {
    let err = MTPError.storageFull
    XCTAssertEqual(err.errorDescription, "The destination storage is full.")
  }

  func testErrorReadOnly() {
    let err = MTPError.readOnly
    XCTAssertEqual(err.errorDescription, "The storage is read-only.")
  }

  func testErrorTimeout() {
    let err = MTPError.timeout
    XCTAssertEqual(err.errorDescription, "The operation timed out while waiting for the device.")
  }

  func testErrorBusy() {
    let err = MTPError.busy
    XCTAssertEqual(err.errorDescription, "The device is busy. Retry shortly.")
  }

  func testErrorSessionBusy() {
    let err = MTPError.sessionBusy
    XCTAssertEqual(
      err.errorDescription,
      "A protocol transaction is already in progress on this device.")
  }

  func testErrorProtocolInvalidParameter() {
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertTrue(err.isSessionAlreadyOpen == false)
    XCTAssertNotNil(err.errorDescription)
    XCTAssertNotNil(err.recoverySuggestion)
  }

  func testErrorSessionAlreadyOpenDetection() {
    let err = MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
    XCTAssertTrue(err.isSessionAlreadyOpen)
  }

  func testErrorVerificationFailed() {
    let err = MTPError.verificationFailed(expected: 1024, actual: 512)
    XCTAssertEqual(
      err.errorDescription,
      "Write verification failed: remote size 512 does not match expected 1024.")
  }

  func testErrorPreconditionFailed() {
    let err = MTPError.preconditionFailed("session not open")
    XCTAssertEqual(err.errorDescription, "Precondition failed: session not open")
  }

  func testTransportErrorNoDevice() {
    let err = TransportError.noDevice
    XCTAssertTrue(err.errorDescription?.contains("No MTP-capable USB device found") == true)
  }

  func testTransportErrorTimeout() {
    let err = TransportError.timeout
    XCTAssertEqual(err.errorDescription, "The USB transfer timed out.")
  }

  func testTransportErrorTimeoutInPhase() {
    let err = TransportError.timeoutInPhase(.bulkOut)
    XCTAssertEqual(
      err.errorDescription,
      "The USB transfer timed out during the bulk-out phase.")
  }

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  // MARK: - 8. Quirk Policy Snapshots

  func testQuirkFlagsDefaults() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.resetOnOpen, false)
    XCTAssertEqual(flags.requiresKernelDetach, true)
    XCTAssertEqual(flags.supportsPartialRead64, true)
    XCTAssertEqual(flags.supportsPartialRead32, true)
    XCTAssertEqual(flags.supportsPartialWrite, true)
    XCTAssertEqual(flags.prefersPropListEnumeration, true)
    XCTAssertEqual(flags.disableEventPump, false)
    XCTAssertEqual(flags.requireStabilization, false)
    XCTAssertEqual(flags.skipPTPReset, false)
    XCTAssertEqual(flags.writeToSubfolderOnly, false)
    XCTAssertEqual(flags.supportsGetObjectPropList, false)
    XCTAssertEqual(flags.cameraClass, false)
  }

  func testQuirkFlagsPTPCameraDefaults() {
    let flags = QuirkFlags.ptpCameraDefaults()
    XCTAssertEqual(flags.requiresKernelDetach, false)
    XCTAssertEqual(flags.supportsGetObjectPropList, true)
    XCTAssertEqual(flags.prefersPropListEnumeration, true)
    XCTAssertEqual(flags.supportsPartialRead32, true)
  }

  func testQuirkFlagsJSONRoundTrip() throws {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.requireStabilization = true
    flags.writeToSubfolderOnly = true
    flags.preferredWriteFolder = "Download"
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertEqual(decoded.resetOnOpen, true)
    XCTAssertEqual(decoded.requireStabilization, true)
    XCTAssertEqual(decoded.writeToSubfolderOnly, true)
    XCTAssertEqual(decoded.preferredWriteFolder, "Download")
  }

  func testQuirkPolicyResolutionXiaomi() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertTrue(policy.tuning.stabilizeMs > 0, "Xiaomi should have stabilization delay")
  }

  func testQuirkPolicyResolutionUnknownDevice() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "ffff", pid: "ffff", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    // Unknown PTP class device should get camera defaults
    XCTAssertEqual(policy.flags.requiresKernelDetach, false)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, true)
  }

  func testQuirkDatabaseLoadAndMatchXiaomi() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff10")
  }

  func testQuirkDatabaseNoMatchForUnknown() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0xFFFF, pid: 0xFFFF,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNil(match)
  }

  func testPolicySources() {
    let sources = PolicySources()
    XCTAssertEqual(sources.chunkSizeSource, .defaults)
    XCTAssertEqual(sources.ioTimeoutSource, .defaults)
    XCTAssertEqual(sources.flagsSource, .defaults)
    XCTAssertEqual(sources.fallbackSource, .defaults)
  }

  func testPolicySourcesRawValues() {
    XCTAssertEqual(PolicySources.Source.defaults.rawValue, "defaults")
    XCTAssertEqual(PolicySources.Source.learned.rawValue, "learned")
    XCTAssertEqual(PolicySources.Source.quirk.rawValue, "quirk")
    XCTAssertEqual(PolicySources.Source.probe.rawValue, "probe")
    XCTAssertEqual(PolicySources.Source.userOverride.rawValue, "userOverride")
  }

  // MARK: - PTP String Encoding Snapshots

  func testPTPStringEncodeEmpty() {
    let encoded = PTPString.encode("")
    XCTAssertEqual(encoded.count, 1)
    XCTAssertEqual(encoded[0], 0)  // zero-length prefix
  }

  func testPTPStringEncodeASCII() {
    let encoded = PTPString.encode("Hi")
    // Count prefix: 3 (2 chars + null terminator)
    XCTAssertEqual(encoded[0], 3)
    // 'H' = 0x48 in UTF-16LE = 0x48, 0x00
    XCTAssertEqual(encoded[1], 0x48)
    XCTAssertEqual(encoded[2], 0x00)
    // 'i' = 0x69 in UTF-16LE = 0x69, 0x00
    XCTAssertEqual(encoded[3], 0x69)
    XCTAssertEqual(encoded[4], 0x00)
    // null terminator
    XCTAssertEqual(encoded[5], 0x00)
    XCTAssertEqual(encoded[6], 0x00)
  }

  func testPTPStringRoundTrip() {
    let original = "test.txt"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }
}
