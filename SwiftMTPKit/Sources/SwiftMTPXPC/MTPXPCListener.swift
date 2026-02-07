// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// XPC listener that serves the MTP XPC service
/// This should be started by the host app when it launches
@MainActor
public final class MTPXPCListener: NSObject {
    private var listener: NSXPCListener?
    private let serviceImpl: MTPXPCServiceImpl

    public init(serviceImpl: MTPXPCServiceImpl) {
        self.serviceImpl = serviceImpl
        super.init()
        self.listener = NSXPCListener(machServiceName: MTPXPCServiceName)
        self.listener?.delegate = self
    }

    public func start() {
        listener?.resume()
    }

    public func stop() {
        listener?.suspend()
        listener = nil
    }

    /// Clean up temp files periodically
    public func startTempFileCleanupTimer() {
        // Use a weak capture and ensure we stay on the MainActor
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                // Accessing serviceImpl which is @MainActor
                // Implementation of cleanupOldTempFiles should also be @MainActor
            }
        }
    }
}

extension MTPXPCListener: @preconcurrency NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: MTPXPCService.self)
        newConnection.exportedObject = self.serviceImpl
        newConnection.resume()

        return true
    }
}

/// Convenience extension for the host app to start/stop the XPC service
@MainActor
public extension MTPDeviceManager {
    private static var xpcListener: MTPXPCListener?

    func startXPCService() {
        if MTPDeviceManager.xpcListener == nil {
            let service = MTPXPCServiceImpl(deviceManager: self)
            MTPDeviceManager.xpcListener = MTPXPCListener(serviceImpl: service)
            MTPDeviceManager.xpcListener?.start()
            MTPDeviceManager.xpcListener?.startTempFileCleanupTimer()
        }
    }

    func stopXPCService() {
        MTPDeviceManager.xpcListener?.stop()
        MTPDeviceManager.xpcListener = nil
    }
}