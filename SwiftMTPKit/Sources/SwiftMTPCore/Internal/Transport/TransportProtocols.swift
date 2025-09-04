// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public protocol MTPTransport: Sendable {
    func open(_ summary: MTPDeviceSummary) async throws -> MTPLink
}

public protocol MTPLink: Sendable {
    func close() async
    func executeCommand(_ command: PTPContainer) throws -> Data?

    // Streaming data transfer methods for file operations
    func executeStreamingCommand(
        _ command: PTPContainer,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> Data?
}

public protocol TransportFactory {
    static func createTransport() -> MTPTransport
}
