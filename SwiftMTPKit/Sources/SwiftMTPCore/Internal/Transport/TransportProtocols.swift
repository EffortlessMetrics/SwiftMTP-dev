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
        dataInHandler: ((UnsafeRawBufferPointer) -> Int)?,
        dataOutHandler: ((UnsafeMutableRawBufferPointer) -> Int)?
    ) async throws -> Data?
}

public protocol TransportFactory {
    static func createTransport() -> MTPTransport
}
