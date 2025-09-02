import Foundation

public protocol MTPTransport: Sendable {
    func open(_ summary: MTPDeviceSummary) async throws -> MTPLink
}

public protocol MTPLink: Sendable {
    func close() async
}

public protocol TransportFactory {
    static func createTransport() -> MTPTransport
}
