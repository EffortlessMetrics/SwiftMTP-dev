import Foundation

protocol TransportDiscoveryProtocol {
    static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                      onDetach: @escaping (MTPDeviceID) -> Void)
}

struct TransportDiscovery {
    static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                             onDetach: @escaping (MTPDeviceID) -> Void) {
        // This will be implemented by the transport layer
        // For now, it's a no-op - will be wired up when transport is available
    }
}
