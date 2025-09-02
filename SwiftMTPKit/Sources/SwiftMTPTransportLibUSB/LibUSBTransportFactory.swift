import Foundation
import SwiftMTPCore

public struct LibUSBTransportFactory: TransportFactory {
    public static func createTransport() -> MTPTransport {
        return LibUSBTransport()
    }
}
