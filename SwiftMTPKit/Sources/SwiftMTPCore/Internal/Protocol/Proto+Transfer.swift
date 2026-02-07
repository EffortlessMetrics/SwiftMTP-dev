// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum TransferMode { case whole, partial }

final class BoxedOffset: @unchecked Sendable {
    var value: Int = 0
    private let lock = NSLock()
    func getAndAdd(_ n: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        let old = value; value += n; return old
    }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

public enum ProtoTransfer {
    /// Whole-object read: GetObject, stream data-in into a sink.
    public static func readWholeObject(handle: UInt32, on link: MTPLink,
                                dataHandler: @escaping MTPDataIn,
                                ioTimeoutMs: Int) async throws {
        let command = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getObject.rawValue,
            txid: 1,
            params: [handle]
        )
        try await link.executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: dataHandler, dataOutHandler: nil).checkOK()
    }

    /// Whole-object write: SendObjectInfo → SendObject (single pass).
    public static func writeWholeObject(storageID: UInt32, parent: UInt32?, name: String, size: UInt64,
                                 dataHandler: @escaping MTPDataOut,
                                 on link: MTPLink,
                                 ioTimeoutMs: Int) async throws {
        // PTP Spec: SendObjectInfo command parameters are [StorageID, ParentHandle]
        // Try using 0xFFFFFFFF for storageID in both places for some devices,
        // but real ID is usually better. 
        let parentParam = parent ?? 0xFFFFFFFF
        let targetStorage = (storageID == 0 || storageID == 0xFFFFFFFF) ? 0xFFFFFFFF : storageID
        let formatCode = PTPObjectFormat.forFilename(name)
        
        let sendObjectInfoCommand = PTPContainer(
            length: 20, // 12 + 2 * 4
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObjectInfo.rawValue,
            txid: 0,
            params: [targetStorage, parentParam]
        )

        let dataset = PTPObjectInfoDataset.encode(storageID: targetStorage, parentHandle: parentParam, format: formatCode, size: size, name: name)
        
        if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
            print("   [USB] SendObjectInfo dataset length: \(dataset.count) bytes")
        }
        
        let infoOffset = BoxedOffset()
        let infoRes = try await link.executeStreamingCommand(sendObjectInfoCommand, dataPhaseLength: UInt64(dataset.count), dataInHandler: nil, dataOutHandler: { buf in
            let off = infoOffset.get()
            let remaining = dataset.count - off
            guard remaining > 0 else { return 0 }
            let toCopy = min(buf.count, remaining)
            dataset.copyBytes(to: buf, from: off..<off+toCopy)
            _ = infoOffset.getAndAdd(toCopy)
            return toCopy
        })
        try infoRes.checkOK()

        try await Task.sleep(nanoseconds: 100_000_000)

        let sendObjectCommand = PTPContainer(
            length: 12,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObject.rawValue,
            txid: 0,
            params: []
        )
        try await link.executeStreamingCommand(sendObjectCommand, dataPhaseLength: size, dataInHandler: nil, dataOutHandler: dataHandler).checkOK()
    }
}

extension PTPResponseResult {
    public func checkOK() throws {
        if !isOK {
            throw MTPError.protocolError(code: code, message: "PTP Response Error 0x\(String(format: "%04x", code))")
        }
    }
}

private extension UInt64 {
    func clampedToIntMax() -> UInt64 { Swift.min(self, UInt64(Int.max)) }
}