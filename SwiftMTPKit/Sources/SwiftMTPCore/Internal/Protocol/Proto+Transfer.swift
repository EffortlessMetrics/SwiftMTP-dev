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

        _ = try await link.executeStreamingCommand(command, dataInHandler: dataHandler, dataOutHandler: nil)
    }

    /// Whole-object write: SendObjectInfo → SendObject (single pass).
    static func writeWholeObject(parent: UInt32?, name: String, size: UInt64,
                                 dataHandler: @escaping MTPDataOut,
                                 on link: MTPLink,
                                 ioTimeoutMs: Int) async throws {
        let parentParam = parent ?? 0
        // SendObjectInfo: pack minimal fields (name, size, parent)
        let sendObjectInfoCommand = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObjectInfo.rawValue,
            txid: 3,
            params: [parentParam, 0, 0] // storage filled by parent; keep simple in v1
        )

        _ = try await link.executeStreamingCommand(sendObjectInfoCommand, dataInHandler: nil, dataOutHandler: { buf in
            // For SendObjectInfo, we need to encode the ObjectInfo dataset
            // This is a simplified implementation - in practice you'd encode the full ObjectInfo dataset
            return 0 // No data to send in this simplified version
        })

        // SendObject: stream out the bytes
        let sendObjectCommand = PTPContainer(
            length: 12,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObject.rawValue,
            txid: 4,
            params: []
        )

        _ = try await link.executeStreamingCommand(sendObjectCommand, dataInHandler: nil, dataOutHandler: dataHandler)
    }
}

private extension UInt64 {
    func clampedToIntMax() -> UInt64 { Swift.min(self, UInt64(Int.max)) }
}
