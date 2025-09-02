import SwiftMTPCore

// Extend the core TransportDiscovery to provide the libusb implementation
extension SwiftMTPCore.TransportDiscovery {
    public static func start(onAttach: @escaping (MTPDeviceSummary)->Void,
                             onDetach: @escaping (MTPDeviceID)->Void) {
        USBDeviceWatcher.start(onAttach: onAttach, onDetach: onDetach)
    }
}
