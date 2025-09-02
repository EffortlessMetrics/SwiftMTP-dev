import Foundation

public protocol TransportDiscoveryProtocol {
    static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                      onDetach: @escaping (MTPDeviceID) -> Void)
}

public enum TransportDiscovery {
    public static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                             onDetach: @escaping (MTPDeviceID) -> Void) {
        // This will be implemented by the transport layer
        // For now, it's a no-op - will be wired up when transport is available
    }
}
