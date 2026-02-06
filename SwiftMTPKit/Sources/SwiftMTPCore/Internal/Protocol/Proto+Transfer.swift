// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum TransferMode { case whole, partial }

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

        _ = try await link.executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: dataHandler, dataOutHandler: nil)
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
        
        _ = try await link.executeStreamingCommand(sendObjectInfoCommand, dataPhaseLength: UInt64(dataset.count), dataInHandler: nil, dataOutHandler: { buf in
            let toCopy = min(buf.count, dataset.count)
            dataset.copyBytes(to: buf, from: 0..<toCopy)
            return toCopy
        })

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

        _ = try await link.executeStreamingCommand(sendObjectCommand, dataPhaseLength: size, dataInHandler: nil, dataOutHandler: dataHandler)
    }
}

private extension UInt64 {
    func clampedToIntMax() -> UInt64 { Swift.min(self, UInt64(Int.max)) }
}
