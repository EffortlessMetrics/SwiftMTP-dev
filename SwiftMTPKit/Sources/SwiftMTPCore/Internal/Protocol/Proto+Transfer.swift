// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum TransferMode { case whole, partial }

final class BoxedOffset: @unchecked Sendable {
    var value: Int = 0
    private let lock = NSLock()
    func getAndAdd(_ n: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value += n
        return old
    }
    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum ProtoTransfer {
    /// Whole-object read: GetObject, stream data-in into a sink.
    static func readWholeObject(handle: UInt32, on link: MTPLink,
                                dataHandler: @escaping MTPDataIn,
                                ioTimeoutMs: Int) async throws {
        let command = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getObject.rawValue,
            txid: 1,
            params: [handle]
        )

        _ = try await link.executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: dataHandler, dataOutHandler: nil as MTPDataOut?)
    }

    /// Whole-object write: SendObjectInfo → SendObject (single pass).
    static func writeWholeObject(storageID: UInt32, parent: UInt32?, name: String, size: UInt64,
                                 dataHandler: @escaping MTPDataOut,
                                 on link: MTPLink,
                                 ioTimeoutMs: Int) async throws {
        let parentParam = parent ?? 0x00000000
        let targetStorage = (parentParam == 0x00000000) ? 0xFFFFFFFF : storageID
        
        // SendObjectInfo (0x100C): params = [storageID, parentHandle]
        let sendObjectInfoCommand = PTPContainer(
            length: 20,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObjectInfo.rawValue,
            txid: 0,
            params: [targetStorage, parentParam]
        )

        let dataset = PTPObjectInfoDataset.encode(storageID: targetStorage, parentHandle: parentParam, format: 0x3000, size: size, name: name)
        
        let infoOffset = BoxedOffset()
        let responseData = try await link.executeStreamingCommand(sendObjectInfoCommand, dataPhaseLength: UInt64(dataset.count), dataInHandler: nil as MTPDataIn?, dataOutHandler: { buf in
            let off = infoOffset.get()
            let remaining = dataset.count - off
            guard remaining > 0 else { return 0 }
            let toCopy = min(buf.count, remaining)
            dataset.copyBytes(to: buf, from: off..<off+toCopy)
            _ = infoOffset.getAndAdd(toCopy)
            return toCopy
        })

        // SendObjectInfo returns the handle in the response parameters
        guard let handleData = responseData, handleData.count >= 4 else {
            throw MTPError.protocolError(code: 0, message: "SendObjectInfo did not return a handle")
        }
        
        let _ = handleData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        // Stabilization delay between Info and Data
        try await Task.sleep(nanoseconds: 100_000_000)

        // SendObject (0x100D): stream out the bytes
        // Note: txid will be handled by executeStreamingCommand
        let sendObjectCommand = PTPContainer(
            length: 12,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObject.rawValue,
            txid: 0,
            params: []
        )

        _ = try await link.executeStreamingCommand(sendObjectCommand, dataPhaseLength: size, dataInHandler: nil as MTPDataIn?, dataOutHandler: dataHandler)
    }
}

private extension UInt64 {
    func clampedToIntMax() -> UInt64 { Swift.min(self, UInt64(Int.max)) }
}