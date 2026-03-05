// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// IOUSBHost native transport for App Store distribution.
// This module replaces LibUSBTransport with Apple's IOUSBHost framework,
// removing the libusb dependency for sandboxed / notarised builds.
//
// Requires macOS 15.0+ (IOUSBHost framework availability).
//
// Entitlement note: IOUSBHost requires the com.apple.vm.device-access entitlement
// for DeviceCapture mode, or root privileges. Standard (non-capture) init works
// for interfaces that are not already claimed by a kernel driver.

#if canImport(IOUSBHost)

import Foundation
import IOKit
import IOKit.usb
import IOUSBHost
import OSLog
import SwiftMTPCore

private let log = Logger(subsystem: "com.swiftmtp.transport.iousbhost", category: "IOUSBHost")

// MARK: - IOUSBHostTransportError

/// Errors specific to the IOUSBHost transport layer.
public enum IOUSBHostTransportError: Error, Sendable, CustomStringConvertible {
  case notImplemented(String)
  /// Device matching failed — no IOService found for the given VID:PID.
  case deviceNotFound(vendorID: UInt16, productID: UInt16)
  /// Failed to open/claim the IOUSBHostDevice or IOUSBHostInterface.
  case claimFailed(String)
  /// No MTP-compatible interface (class 6/subclass 1/protocol 1) found.
  case noMTPInterface
  /// Endpoint not found (bulk-in, bulk-out, or interrupt-in).
  case endpointNotFound(String)
  /// Bulk transfer I/O error with the underlying IOReturn code.
  case ioError(String, Int32)
  /// The link is not in the expected state for this operation.
  case invalidState(String)
  /// USB pipe stall/halt condition.
  case pipeStall
  /// Transfer timed out.
  case transferTimeout

  public var description: String {
    switch self {
    case .notImplemented(let msg): return "Not implemented: \(msg)"
    case .deviceNotFound(let vid, let pid):
      return String(format: "No IOUSBHost device found for %04x:%04x", vid, pid)
    case .claimFailed(let msg): return "Claim failed: \(msg)"
    case .noMTPInterface: return "No MTP interface (class 6/subclass 1/protocol 1) found"
    case .endpointNotFound(let ep): return "Endpoint not found: \(ep)"
    case .ioError(let msg, let code): return "IO error (\(code)): \(msg)"
    case .invalidState(let msg): return "Invalid state: \(msg)"
    case .pipeStall: return "USB pipe stall"
    case .transferTimeout: return "Transfer timed out"
    }
  }
}

// MARK: - MTP Interface Constants

/// USB class/subclass/protocol for MTP (Still Image / PTP class).
private enum MTPInterfaceMatch {
  static let interfaceClass: UInt8 = 6       // IMAGE
  static let interfaceSubclass: UInt8 = 1    // Still Image Capture
  static let interfaceProtocol: UInt8 = 1    // PTP
}

/// Heap-allocated mutable buffer for collecting data across @Sendable closures.
private final class DataCollector: @unchecked Sendable {
  var data = Data()
  func append(_ chunk: UnsafeRawBufferPointer) {
    data.append(contentsOf: chunk)
  }
}

/// PTP/MTP container header size (length + type + code + txid = 12 bytes).
private let ptpHeaderSize = 12

/// Default bulk transfer timeout in seconds.
private let defaultBulkTimeout: TimeInterval = 10.0

/// Maximum bulk read buffer size.
private let maxBulkReadSize = 1024 * 1024  // 1 MB

// MARK: - IOUSBHostLink

/// MTPLink implementation backed by Apple's IOUSBHost framework.
///
/// Lifecycle:
///   1. `IOUSBHostTransport.open()` discovers the device via IOKit matching and
///      constructs an `IOUSBHostLink` with the matched `io_service_t`.
///   2. `openUSBIfNeeded()` — claims the USB interface via `IOUSBHostInterface`,
///      finds bulk-in/out and interrupt-in endpoints, and creates `IOUSBHostPipe` objects.
///   3. `openSession(id:)` — sends MTP OpenSession (0x1002) via bulk pipes.
///   4. Use device operations (getDeviceInfo, getStorageIDs, etc.).
///   5. `closeSession()` / `close()` — sends CloseSession and releases USB resources.
public final class IOUSBHostLink: @unchecked Sendable, MTPLink {

  // USB state
  private var hostInterface: IOUSBHostInterface?
  private var bulkInPipe: IOUSBHostPipe?
  private var bulkOutPipe: IOUSBHostPipe?
  private var interruptInPipe: IOUSBHostPipe?

  // Endpoint addresses discovered during interface probe
  private let bulkInAddress: UInt8
  private let bulkOutAddress: UInt8
  private let interruptInAddress: UInt8?

  // Device metadata
  private let interfaceService: io_service_t
  private let vendorID: UInt16
  private let productID: UInt16
  private let manufacturer: String
  private let model: String
  private let interfaceNumber: UInt8

  // MTP transaction counter
  private var nextTx: UInt32 = 0

  // Queue for synchronous USB operations
  private let usbQueue = DispatchQueue(label: "com.swiftmtp.iousbhost.io", qos: .userInitiated)

  // Event polling state
  private var eventContinuation: AsyncStream<Data>.Continuation?
  private var eventPumpTask: Task<Void, Never>?
  public let eventStream: AsyncStream<Data>

  // Link descriptor
  public private(set) var linkDescriptor: MTPLinkDescriptor?
  public private(set) var cachedDeviceInfo: MTPDeviceInfo?

  /// Designated initializer — called by `IOUSBHostTransport.open()` after
  /// IOKit matching locates the MTP interface service.
  init(
    interfaceService: io_service_t,
    vendorID: UInt16,
    productID: UInt16,
    manufacturer: String,
    model: String,
    interfaceNumber: UInt8,
    bulkInAddress: UInt8,
    bulkOutAddress: UInt8,
    interruptInAddress: UInt8?
  ) {
    self.interfaceService = interfaceService
    self.vendorID = vendorID
    self.productID = productID
    self.manufacturer = manufacturer
    self.model = model
    self.interfaceNumber = interfaceNumber
    self.bulkInAddress = bulkInAddress
    self.bulkOutAddress = bulkOutAddress
    self.interruptInAddress = interruptInAddress

    var cont: AsyncStream<Data>.Continuation!
    self.eventStream = AsyncStream(Data.self, bufferingPolicy: .bufferingNewest(16)) { cont = $0 }
    self.eventContinuation = cont

    self.linkDescriptor = MTPLinkDescriptor(
      interfaceNumber: interfaceNumber,
      interfaceClass: MTPInterfaceMatch.interfaceClass,
      interfaceSubclass: MTPInterfaceMatch.interfaceSubclass,
      interfaceProtocol: MTPInterfaceMatch.interfaceProtocol,
      bulkInEndpoint: bulkInAddress,
      bulkOutEndpoint: bulkOutAddress,
      interruptEndpoint: interruptInAddress,
      usbSpeedMBps: nil
    )
  }

  // Keep the old public init for fallback/stub compatibility.
  public convenience init() {
    self.init(
      interfaceService: IO_OBJECT_NULL,
      vendorID: 0, productID: 0,
      manufacturer: "", model: "",
      interfaceNumber: 0,
      bulkInAddress: 0, bulkOutAddress: 0,
      interruptInAddress: nil
    )
  }

  // MARK: - USB Lifecycle

  /// Claim the USB interface and open bulk/interrupt pipes.
  public func openUSBIfNeeded() async throws {
    guard hostInterface == nil else { return }
    guard interfaceService != IO_OBJECT_NULL else {
      throw IOUSBHostTransportError.invalidState("No IOService — link was default-constructed")
    }

    log.info(
      "Opening IOUSBHost interface for \(self.manufacturer, privacy: .public) \(self.model, privacy: .public) [\(String(format: "%04x:%04x", self.vendorID, self.productID), privacy: .public)]"
    )

    do {
      let iface = try IOUSBHostInterface(
        __ioService: interfaceService,
        options: [],
        queue: usbQueue,
        interestHandler: nil
      )
      hostInterface = iface
    } catch {
      let msg = error.localizedDescription
      log.error("Failed to claim interface: \(msg, privacy: .public)")
      throw IOUSBHostTransportError.claimFailed(msg)
    }
    let iface = hostInterface!

    // Open bulk-out pipe
    do {
      bulkOutPipe = try iface.copyPipe(withAddress: Int(bulkOutAddress))
    } catch {
      throw IOUSBHostTransportError.endpointNotFound(
        "bulk-out 0x\(String(format: "%02x", bulkOutAddress)): \(error.localizedDescription)")
    }

    // Open bulk-in pipe
    do {
      bulkInPipe = try iface.copyPipe(withAddress: Int(bulkInAddress))
    } catch {
      throw IOUSBHostTransportError.endpointNotFound(
        "bulk-in 0x\(String(format: "%02x", bulkInAddress)): \(error.localizedDescription)")
    }

    // Open interrupt-in pipe (optional — some devices omit it)
    if let intAddr = interruptInAddress {
      interruptInPipe = try? iface.copyPipe(withAddress: Int(intAddr))
      if interruptInPipe == nil {
        log.warning(
          "Interrupt pipe 0x\(String(format: "%02x", intAddr), privacy: .public) not available (non-fatal)"
        )
      }
    }

    log.info(
      "IOUSBHost interface claimed: bulkIn=0x\(String(format: "%02x", self.bulkInAddress), privacy: .public) bulkOut=0x\(String(format: "%02x", self.bulkOutAddress), privacy: .public) interrupt=\(self.interruptInAddress.map { String(format: "0x%02x", $0) } ?? "none", privacy: .public)"
    )
  }

  /// Release all USB resources.
  public func close() async {
    log.info(
      "Closing IOUSBHost link: \(self.manufacturer, privacy: .public) \(self.model, privacy: .public)"
    )
    eventPumpTask?.cancel()
    eventPumpTask = nil
    eventContinuation?.finish()
    interruptInPipe = nil
    bulkInPipe = nil
    bulkOutPipe = nil
    hostInterface?.destroy()
    hostInterface = nil
    if interfaceService != IO_OBJECT_NULL {
      IOObjectRelease(interfaceService)
    }
  }

  // MARK: - Bulk Transfer Helpers

  /// Send raw bytes on the bulk-out pipe.
  private func bulkWrite(_ data: Data, timeout: TimeInterval = defaultBulkTimeout) throws {
    guard let pipe = bulkOutPipe else {
      throw IOUSBHostTransportError.invalidState("Bulk-out pipe not open")
    }
    let mutableData = NSMutableData(data: data)
    var transferred: Int = 0
    try pipe.__sendIORequest(
      with: mutableData, bytesTransferred: &transferred,
      completionTimeout: timeout
    )
  }

  /// Read up to `maxLength` bytes from the bulk-in pipe.
  private func bulkRead(
    maxLength: Int = maxBulkReadSize, timeout: TimeInterval = defaultBulkTimeout
  ) throws -> Data {
    guard let pipe = bulkInPipe else {
      throw IOUSBHostTransportError.invalidState("Bulk-in pipe not open")
    }
    let mutableData = NSMutableData(length: maxLength)!
    var transferred: Int = 0
    try pipe.__sendIORequest(
      with: mutableData, bytesTransferred: &transferred,
      completionTimeout: timeout
    )
    return Data(mutableData.subdata(with: NSRange(location: 0, length: transferred)))
  }

  /// Clear stall/halt on all endpoints.
  private func clearStall() {
    try? bulkOutPipe?.clearStall()
    try? bulkInPipe?.clearStall()
    try? interruptInPipe?.clearStall()
  }

  // MARK: - Interrupt Endpoint Event Polling

  /// Read up to `maxLength` bytes from the interrupt-in pipe.
  /// Returns `nil` on timeout or pipe error (non-fatal for event polling).
  private func interruptRead(
    maxLength: Int = 1024, timeout: TimeInterval = 1.0
  ) -> Data? {
    guard let pipe = interruptInPipe else { return nil }
    let mutableData = NSMutableData(length: maxLength)!
    var transferred: Int = 0
    do {
      try pipe.__sendIORequest(
        with: mutableData, bytesTransferred: &transferred,
        completionTimeout: timeout
      )
    } catch {
      return nil
    }
    guard transferred > 0 else { return nil }
    return Data(mutableData.subdata(with: NSRange(location: 0, length: transferred)))
  }

  /// Begin polling the interrupt-in endpoint for MTP event containers.
  ///
  /// Reads are performed with a 1-second timeout so the loop can check for
  /// cancellation between reads. Parsed event data is yielded into `eventStream`.
  public func startEventPump() {
    guard interruptInPipe != nil else { return }
    guard eventPumpTask == nil else { return }
    let coalescer = MTPEventCoalescer()
    eventPumpTask = Task {
      while !Task.isCancelled {
        guard let data = self.interruptRead() else { continue }
        if coalescer.shouldForward() {
          if let event = MTPEvent.fromRaw(data) {
            log.debug(
              "IOUSBHost MTP event: \(event.eventDescription, privacy: .public)"
            )
          }
          self.eventContinuation?.yield(data)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
    }
  }

  // MARK: - PTP Container Encoding/Decoding

  /// Encode a PTP command container into raw bytes.
  private func encodePTPCommand(_ command: PTPContainer) -> Data {
    let paramBytes = command.params.count * 4
    let totalLength = UInt32(ptpHeaderSize + paramBytes)
    var data = Data(count: Int(totalLength))
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: totalLength.littleEndian, as: UInt32.self)
      base.storeBytes(of: command.type.littleEndian, toByteOffset: 4, as: UInt16.self)
      base.storeBytes(of: command.code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: command.txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      for (i, param) in command.params.enumerated() {
        base.storeBytes(of: param.littleEndian, toByteOffset: 12 + i * 4, as: UInt32.self)
      }
    }
    return data
  }

  /// Parse a PTP response container from raw bytes.
  private func parsePTPResponse(_ data: Data) -> PTPResponseResult? {
    guard data.count >= ptpHeaderSize else { return nil }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      // type 3 = response
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

  // MARK: - MTP Session Commands

  /// Send MTP OpenSession (0x1002) to the device.
  public func openSession(id: UInt32) async throws {
    try await executeSimpleCommand(code: PTPOp.openSession.rawValue, params: [id])
    nextTx = 1
  }

  /// Send MTP CloseSession (0x1003) to the device.
  public func closeSession() async throws {
    try await executeSimpleCommand(code: PTPOp.closeSession.rawValue, params: [])
    nextTx = 0
  }

  /// Read MTP DeviceInfo (0x1001) from the device.
  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    if let cached = cachedDeviceInfo { return cached }

    let dataPayload = try await executeDataInCommand(
      code: PTPOp.getDeviceInfo.rawValue, params: []
    )
    if let info = PTPDeviceInfo.parse(from: dataPayload) {
      let result = MTPDeviceInfo(
        manufacturer: info.manufacturer, model: info.model,
        version: info.deviceVersion, serialNumber: info.serialNumber,
        operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported)
      )
      cachedDeviceInfo = result
      return result
    }
    return MTPDeviceInfo(
      manufacturer: manufacturer, model: model, version: "1.0",
      serialNumber: "Unknown", operationsSupported: [], eventsSupported: []
    )
  }

  /// Read storage IDs from the device (0x1004).
  public func getStorageIDs() async throws -> [MTPStorageID] {
    let data = try await executeDataInCommand(
      code: PTPOp.getStorageIDs.rawValue, params: []
    )
    guard data.count >= 4 else { return [] }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let count = Int(UInt32(littleEndian: base.load(as: UInt32.self)))
      let available = (data.count - 4) / 4
      let total = min(count, available)
      var ids: [MTPStorageID] = []
      ids.reserveCapacity(total)
      for i in 0..<total {
        let id = UInt32(littleEndian: base.load(fromByteOffset: 4 + i * 4, as: UInt32.self))
        ids.append(MTPStorageID(raw: id))
      }
      return ids
    }
  }

  /// Read storage info for a given storage ID (0x1005).
  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let data = try await executeDataInCommand(
      code: PTPOp.getStorageInfo.rawValue, params: [id.raw]
    )
    var r = PTPReader(data: data)
    _ = r.u16()  // StorageType
    _ = r.u16()  // FilesystemType
    let accessCapability = r.u16()
    let maxCapacity = r.u64()
    let freeSpace = r.u64()
    _ = r.u32()  // FreeSpaceInObjects
    let description = r.string() ?? ""
    return MTPStorageInfo(
      id: id, description: description,
      capacityBytes: maxCapacity ?? 0, freeBytes: freeSpace ?? 0,
      isReadOnly: accessCapability == 0x0001
    )
  }

  /// Enumerate object handles in the given storage/parent (0x1007).
  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    let data = try await executeDataInCommand(
      code: PTPOp.getObjectHandles.rawValue,
      params: [storage.raw, 0, parent ?? 0x00000000]
    )
    guard data.count >= 4 else { return [] }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let count = Int(UInt32(littleEndian: base.load(as: UInt32.self)))
      let available = (data.count - 4) / 4
      let total = min(count, available)
      var handles: [MTPObjectHandle] = []
      handles.reserveCapacity(total)
      for i in 0..<total {
        let h = UInt32(littleEndian: base.load(fromByteOffset: 4 + i * 4, as: UInt32.self))
        handles.append(h)
      }
      return handles
    }
  }

  /// Batch-fetch object info for the given handles.
  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var out: [MTPObjectInfo] = []
    for handle in handles {
      let collector = DataCollector()
      let result = try await executeStreamingCommand(
        PTPContainer(
          type: PTPContainer.Kind.command.rawValue,
          code: PTPOp.getObjectInfo.rawValue,
          txid: nextTx, params: [handle]
        ),
        dataPhaseLength: nil,
        dataInHandler: { chunk in
          collector.append(chunk)
          return chunk.count
        },
        dataOutHandler: nil
      )
      if !result.isOK { continue }
      var r = PTPReader(data: collector.data)
      guard let sid = r.u32(), let fmt = r.u16() else { continue }
      _ = r.u16()  // ProtectionStatus
      let size = r.u32()
      _ = r.u16()  // ThumbFormat
      _ = r.u32()  // ThumbCompressedSize
      _ = r.u32()  // ThumbPixWidth
      _ = r.u32()  // ThumbPixHeight
      _ = r.u32()  // ImagePixWidth
      _ = r.u32()  // ImagePixHeight
      _ = r.u32()  // ImageBitDepth
      let par = r.u32()
      _ = r.u16()  // AssociationType
      _ = r.u32()  // AssociationDesc
      _ = r.u32()  // SequenceNumber
      let name = r.string() ?? "Unknown"
      out.append(
        MTPObjectInfo(
          handle: handle, storage: MTPStorageID(raw: sid),
          parent: par == 0 ? nil : par, name: name,
          sizeBytes: (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!),
          modified: nil as Date?, formatCode: fmt, properties: [:]
        )
      )
    }
    return out
  }

  /// Fetch object infos filtered by storage/parent/format.
  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    let handles = try await getObjectHandles(storage: storage, parent: parent)
    return try await getObjectInfos(handles)
  }

  /// Send MTP ResetDevice via USB class-specific request.
  public func resetDevice() async throws {
    throw IOUSBHostTransportError.notImplemented("resetDevice")
  }

  /// Delete an object on the device (0x100B).
  public func deleteObject(handle: MTPObjectHandle) async throws {
    try await executeSimpleCommand(code: PTPOp.deleteObject.rawValue, params: [handle])
  }

  /// Move an object on the device (0x100E).
  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    try await executeSimpleCommand(
      code: PTPOp.moveObject.rawValue,
      params: [handle, storage.raw, parent ?? 0xFFFFFFFF]
    )
  }

  /// Copy an object on the device (0x101A).
  public func copyObject(
    handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws -> MTPObjectHandle {
    let result = try await executeStreamingCommand(
      PTPContainer(
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.copyObject.rawValue,
        txid: nextTx,
        params: [handle, storage.raw, parent ?? 0xFFFFFFFF]
      ),
      dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
    guard result.isOK else {
      throw MTPError.protocolError(
        code: result.code,
        message: "CopyObject failed: response 0x\(String(format: "%04x", result.code))"
      )
    }
    return result.params.first ?? 0
  }

  // MARK: - Command Execution

  /// Execute a simple command (no data phase) and check OK response.
  private func executeSimpleCommand(code: UInt16, params: [UInt32]) async throws {
    let result = try await executeStreamingCommand(
      PTPContainer(type: PTPContainer.Kind.command.rawValue, code: code, txid: nextTx, params: params),
      dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
    guard result.isOK else {
      throw MTPError.protocolError(code: result.code, message: "Command 0x\(String(format: "%04x", code)) failed: response 0x\(String(format: "%04x", result.code))")
    }
  }

  /// Execute a command with a data-in phase, collecting the payload.
  private func executeDataInCommand(code: UInt16, params: [UInt32]) async throws -> Data {
    let collector = DataCollector()
    let result = try await executeStreamingCommand(
      PTPContainer(type: PTPContainer.Kind.command.rawValue, code: code, txid: nextTx, params: params),
      dataPhaseLength: nil,
      dataInHandler: { chunk in
        collector.append(chunk)
        return chunk.count
      },
      dataOutHandler: nil
    )
    guard result.isOK else {
      throw MTPError.protocolError(code: result.code, message: "Command 0x\(String(format: "%04x", code)) failed: response 0x\(String(format: "%04x", result.code))")
    }
    return collector.data
  }

  /// Execute a raw PTP/MTP command container (no data phase).
  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    return try await executeStreamingCommand(
      command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
  }

  /// Execute a streaming command with optional data-in/data-out phases.
  ///
  /// PTP/MTP transaction flow:
  ///   1. Send command container on bulk-out
  ///   2. (Optional) Send data container on bulk-out (data-out) OR
  ///      read data container from bulk-in (data-in)
  ///   3. Read response container from bulk-in
  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    var cmd = command
    cmd.txid = nextTx
    let paramBytes = cmd.params.count * 4
    cmd.length = UInt32(ptpHeaderSize + paramBytes)
    nextTx += 1

    // Phase 1: Send command container
    let cmdData = encodePTPCommand(cmd)
    try bulkWrite(cmdData)

    // Phase 2: Data phase (if any)
    if let dataOut = dataOutHandler, let dataLen = dataPhaseLength {
      // Data-out: build PTP data container header, then stream payload in chunks.
      // For large files (>4GB), PTP uses 0xFFFFFFFF as a sentinel length.
      let containerLen: UInt32
      if dataLen > UInt64(UInt32.max) - UInt64(ptpHeaderSize) {
        containerLen = 0xFFFFFFFF
      } else {
        containerLen = UInt32(ptpHeaderSize) + UInt32(dataLen)
      }
      var header = Data(count: ptpHeaderSize)
      header.withUnsafeMutableBytes { buf in
        let base = buf.baseAddress!
        base.storeBytes(of: containerLen.littleEndian, as: UInt32.self)
        base.storeBytes(of: PTPContainer.Kind.data.rawValue.littleEndian, toByteOffset: 4, as: UInt16.self)
        base.storeBytes(of: cmd.code.littleEndian, toByteOffset: 6, as: UInt16.self)
        base.storeBytes(of: cmd.txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      }
      try bulkWrite(header)

      // Stream payload in chunks from the callback
      let chunkSize = 65536
      let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: chunkSize)
      defer { buf.deallocate() }
      var remaining = Int(dataLen)
      while remaining > 0 {
        let wrote = dataOut(UnsafeMutableRawBufferPointer(buf))
        if wrote == 0 { break }
        let toSend = min(wrote, remaining)
        try bulkWrite(Data(bytes: buf.baseAddress!, count: toSend))
        remaining -= toSend
      }
    }

    if let handler = dataInHandler {
      // Data-in: read PTP data container header, then stream payload in chunks.
      var firstRead = try bulkRead()
      guard firstRead.count >= ptpHeaderSize else {
        return PTPResponseResult(code: 0x2002, txid: cmd.txid)
      }

      let (containerType, containerLen) = firstRead.withUnsafeBytes { buf -> (UInt16, UInt32) in
        let base = buf.baseAddress!
        let len = UInt32(littleEndian: base.load(as: UInt32.self))
        let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
        return (type, len)
      }

      if containerType == PTPContainer.Kind.response.rawValue {
        // Device sent response directly (no data phase)
        if let resp = parsePTPResponse(firstRead) { return resp }
        return PTPResponseResult(code: 0x2002, txid: cmd.txid)
      }

      guard containerType == PTPContainer.Kind.data.rawValue else {
        return PTPResponseResult(code: 0x2002, txid: cmd.txid)
      }

      // Total payload = containerLen - header, or indeterminate if 0xFFFFFFFF
      let knownLength = containerLen != 0xFFFFFFFF
      let totalPayload = knownLength ? Int(containerLen) - ptpHeaderSize : Int.max

      // Deliver payload from the first read (after PTP header)
      var delivered = 0
      if firstRead.count > ptpHeaderSize {
        let payload = firstRead.subdata(in: ptpHeaderSize..<firstRead.count)
        payload.withUnsafeBytes { buf in
          _ = handler(UnsafeRawBufferPointer(buf))
        }
        delivered += payload.count
      }

      // Continue reading chunks until we have all data
      while delivered < totalPayload {
        let chunk: Data
        do {
          chunk = try bulkRead()
        } catch {
          break  // Transfer ended (stall, ZLP, or timeout)
        }
        if chunk.isEmpty { break }

        // Check if this chunk contains a PTP response (end of data phase)
        if chunk.count >= ptpHeaderSize {
          let chunkType = chunk.withUnsafeBytes { buf in
            UInt16(littleEndian: buf.load(fromByteOffset: 4, as: UInt16.self))
          }
          if chunkType == PTPContainer.Kind.response.rawValue {
            if let resp = parsePTPResponse(chunk) { return resp }
            break
          }
        }

        chunk.withUnsafeBytes { buf in
          _ = handler(UnsafeRawBufferPointer(buf))
        }
        delivered += chunk.count
      }
    }

    // Phase 3: Read response container
    let responseData = try bulkRead(maxLength: 512)
    if let resp = parsePTPResponse(responseData) {
      return resp
    }
    // If we can't parse a response, return a generic error
    return PTPResponseResult(code: 0x2002, txid: cmd.txid)  // 0x2002 = GeneralError
  }
}

// MARK: - IOUSBHostTransport (MTPTransport)

/// MTPTransport factory that discovers USB devices via IOKit matching
/// and creates IOUSBHostLink instances for MTP communication.
public final class IOUSBHostTransport: @unchecked Sendable, MTPTransport {

  private var activeLink: IOUSBHostLink?

  public init() {}

  /// Open a link to the specified MTP device via IOUSBHost.
  ///
  /// Steps:
  ///   1. Build an IOKit matching dictionary for IOUSBHostInterface with the
  ///      MTP class/subclass/protocol (or fall back to VID:PID matching).
  ///   2. Find the matching IOService.
  ///   3. Inspect the interface descriptor to locate bulk-in, bulk-out, and
  ///      interrupt-in endpoint addresses.
  ///   4. Construct an IOUSBHostLink with the service and endpoint metadata.
  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    guard let vid = summary.vendorID, let pid = summary.productID else {
      throw IOUSBHostTransportError.deviceNotFound(vendorID: 0, productID: 0)
    }

    log.info(
      "IOUSBHostTransport.open: looking for \(summary.manufacturer, privacy: .public) \(summary.model, privacy: .public) [\(String(format: "%04x:%04x", vid, pid), privacy: .public)]"
    )

    // Try MTP-class interface matching first (class 6 / subclass 1 / protocol 1)
    let result = try findMTPInterface(vendorID: vid, productID: pid)

    let link = IOUSBHostLink(
      interfaceService: result.service,
      vendorID: vid,
      productID: pid,
      manufacturer: summary.manufacturer,
      model: summary.model,
      interfaceNumber: result.interfaceNumber,
      bulkInAddress: result.bulkIn,
      bulkOutAddress: result.bulkOut,
      interruptInAddress: result.interruptIn
    )
    activeLink = link
    return link
  }

  /// Close and release all transport resources.
  public func close() async throws {
    if let link = activeLink {
      await link.close()
      activeLink = nil
    }
  }

  // MARK: - IOKit Device Discovery

  private struct InterfaceProbeResult {
    let service: io_service_t
    let interfaceNumber: UInt8
    let bulkIn: UInt8
    let bulkOut: UInt8
    let interruptIn: UInt8?
  }

  /// Find an MTP-compatible USB interface using IOKit matching.
  private func findMTPInterface(vendorID: UInt16, productID: UInt16) throws -> InterfaceProbeResult {
    // Build matching dictionary for IOUSBHostInterface with MTP class
    let matchDict = IOUSBHostInterface.__createMatchingDictionary(
      withVendorID: NSNumber(value: vendorID),
      productID: NSNumber(value: productID),
      bcdDevice: nil,
      interfaceNumber: nil,
      configurationValue: nil,
      interfaceClass: NSNumber(value: MTPInterfaceMatch.interfaceClass),
      interfaceSubclass: NSNumber(value: MTPInterfaceMatch.interfaceSubclass),
      interfaceProtocol: NSNumber(value: MTPInterfaceMatch.interfaceProtocol),
      speed: nil,
      productIDArray: nil
    )

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict.takeRetainedValue(), &iterator)
    guard kr == KERN_SUCCESS else {
      return try findVendorSpecificInterface(vendorID: vendorID, productID: productID)
    }
    defer { IOObjectRelease(iterator) }

    let service = IOIteratorNext(iterator)
    guard service != IO_OBJECT_NULL else {
      return try findVendorSpecificInterface(vendorID: vendorID, productID: productID)
    }

    // Probe endpoint addresses from the interface descriptor
    let endpoints = probeEndpoints(service: service)
    guard let bulkIn = endpoints.bulkIn, let bulkOut = endpoints.bulkOut else {
      IOObjectRelease(service)
      throw IOUSBHostTransportError.endpointNotFound(
        "Missing bulk endpoints on MTP interface")
    }

    let ifNum = readInterfaceNumber(service: service)
    return InterfaceProbeResult(
      service: service, interfaceNumber: ifNum,
      bulkIn: bulkIn, bulkOut: bulkOut, interruptIn: endpoints.interruptIn
    )
  }

  /// Fallback: match by VID:PID only (for vendor-specific MTP devices like Android).
  private func findVendorSpecificInterface(
    vendorID: UInt16, productID: UInt16
  ) throws -> InterfaceProbeResult {
    let matchDict = IOUSBHostInterface.__createMatchingDictionary(
      withVendorID: NSNumber(value: vendorID),
      productID: NSNumber(value: productID),
      bcdDevice: nil,
      interfaceNumber: nil,
      configurationValue: nil,
      interfaceClass: nil,
      interfaceSubclass: nil,
      interfaceProtocol: nil,
      speed: nil,
      productIDArray: nil
    )

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict.takeRetainedValue(), &iterator)
    guard kr == KERN_SUCCESS else {
      throw IOUSBHostTransportError.deviceNotFound(vendorID: vendorID, productID: productID)
    }
    defer { IOObjectRelease(iterator) }

    // Iterate interfaces looking for one with bulk-in + bulk-out
    var candidateService = IOIteratorNext(iterator)
    while candidateService != IO_OBJECT_NULL {
      let endpoints = probeEndpoints(service: candidateService)
      if let bulkIn = endpoints.bulkIn, let bulkOut = endpoints.bulkOut {
        let ifNum = readInterfaceNumber(service: candidateService)
        return InterfaceProbeResult(
          service: candidateService, interfaceNumber: ifNum,
          bulkIn: bulkIn, bulkOut: bulkOut, interruptIn: endpoints.interruptIn
        )
      }
      IOObjectRelease(candidateService)
      candidateService = IOIteratorNext(iterator)
    }
    throw IOUSBHostTransportError.noMTPInterface
  }

  private struct EndpointInfo {
    var bulkIn: UInt8?
    var bulkOut: UInt8?
    var interruptIn: UInt8?
  }

  /// Read endpoint addresses from the IOService registry properties.
  /// IOUSBHost publishes endpoint descriptors as registry properties.
  private func probeEndpoints(service: io_service_t) -> EndpointInfo {
    var info = EndpointInfo()

    // IOUSBHostInterface stores endpoint descriptors in registry.
    // We read bNumEndpoints and walk the endpoint descriptors.
    // The "bEndpointAddress" property is published for each endpoint child.
    var childIterator: io_iterator_t = 0
    let kr = IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator)
    guard kr == KERN_SUCCESS else {
      // If we can't enumerate children, try common MTP defaults
      return defaultMTPEndpoints()
    }
    defer { IOObjectRelease(childIterator) }

    var child = IOIteratorNext(childIterator)
    while child != IO_OBJECT_NULL {
      if let props = readProperties(child) {
        if let address = props["bEndpointAddress"] as? UInt8 {
          let transferType = props["bmAttributes"] as? UInt8 ?? 0
          let direction = address & 0x80  // bit 7: 0=OUT, 1=IN
          let epType = transferType & 0x03  // bits 0-1: 0=control, 2=bulk, 3=interrupt

          if epType == 2 {  // Bulk
            if direction != 0 { info.bulkIn = address }
            else { info.bulkOut = address }
          } else if epType == 3 && direction != 0 {  // Interrupt IN
            info.interruptIn = address
          }
        }
      }
      IOObjectRelease(child)
      child = IOIteratorNext(childIterator)
    }

    // If child probing didn't find endpoints, use defaults
    if info.bulkIn == nil || info.bulkOut == nil {
      return defaultMTPEndpoints()
    }
    return info
  }

  /// Default MTP endpoint addresses per PTP/MTP spec convention.
  private func defaultMTPEndpoints() -> EndpointInfo {
    // Most MTP devices use: bulk-in=0x81, bulk-out=0x02, interrupt-in=0x83
    EndpointInfo(bulkIn: 0x81, bulkOut: 0x02, interruptIn: 0x83)
  }

  /// Read the interface number from the IOService registry.
  private func readInterfaceNumber(service: io_service_t) -> UInt8 {
    if let props = readProperties(service),
      let ifNum = props["bInterfaceNumber"] as? UInt8
    {
      return ifNum
    }
    return 0
  }

  /// Read all registry properties of an IOService.
  private func readProperties(_ service: io_service_t) -> [String: Any]? {
    var propsRef: Unmanaged<CFMutableDictionary>?
    let kr = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
      return nil
    }
    return props
  }
}

// MARK: - IOUSBHostTransportFactory

/// TransportFactory for IOUSBHost-backed transport.
public struct IOUSBHostTransportFactory: TransportFactory {
  public static func createTransport() -> MTPTransport {
    IOUSBHostTransport()
  }
}

#else

// Fallback for platforms where IOUSBHost is unavailable (e.g. Linux, older macOS).
// Provides the same public types so downstream code can reference them without
// conditional compilation at every call site.

import Foundation
import SwiftMTPCore

public enum IOUSBHostTransportError: Error, Sendable {
  case notImplemented(String)
  case unavailable
  case deviceNotFound(vendorID: UInt16, productID: UInt16)
  case claimFailed(String)
  case noMTPInterface
  case endpointNotFound(String)
  case ioError(String, Int32)
  case invalidState(String)
  case pipeStall
  case transferTimeout
}

public final class IOUSBHostLink: @unchecked Sendable, MTPLink {
  public init() {}
  public func openUSBIfNeeded() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func openSession(id: UInt32) async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func closeSession() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func close() async {}
  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    throw IOUSBHostTransportError.unavailable
  }
  public func getStorageIDs() async throws -> [MTPStorageID] {
    throw IOUSBHostTransportError.unavailable
  }
  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func resetDevice() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func deleteObject(handle: MTPObjectHandle) async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func copyObject(
    handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws -> MTPObjectHandle {
    throw IOUSBHostTransportError.unavailable
  }
  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.unavailable
  }
  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.unavailable
  }
}

public final class IOUSBHostTransport: @unchecked Sendable, MTPTransport {
  public init() {}
  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    throw IOUSBHostTransportError.unavailable
  }
  public func close() async throws {}
}

public struct IOUSBHostTransportFactory: TransportFactory {
  public static func createTransport() -> MTPTransport {
    IOUSBHostTransport()
  }
}

#endif
