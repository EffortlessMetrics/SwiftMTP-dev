import Foundation

/// Protocol for transport layer device discovery implementations
public protocol TransportDiscoveryProtocol {
    static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                      onDetach: @escaping (MTPDeviceID) -> Void)
}

/// Core transport discovery interface that transport layers extend to provide device discovery
public struct TransportDiscovery {
    /// Start device discovery with the specified attach/detach handlers
    /// This is extended by concrete transport implementations (USB, Bluetooth, etc.)
    public static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                             onDetach: @escaping (MTPDeviceID) -> Void) {
        // This will be implemented by the transport layer
        // For now, it's a no-op - will be wired up when transport is available
    }
}
