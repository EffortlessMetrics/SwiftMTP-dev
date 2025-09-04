// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// XPC listener that serves the MTP XPC service
/// This should be started by the host app when it launches
public final class MTPXPCListener {
    private var listener: NSXPCListener?
    private let serviceImpl: MTPXPCServiceImpl

    public init(serviceImpl: MTPXPCServiceImpl = MTPXPCServiceImpl()) {
        self.serviceImpl = serviceImpl
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
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.serviceImpl.cleanupOldTempFiles()
        }
    }
}

extension MTPXPCListener: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: MTPXPCService.self)
        newConnection.exportedObject = serviceImpl

        // Set up connection handlers
        newConnection.invalidationHandler = {
            print("XPC connection invalidated")
        }

        newConnection.interruptionHandler = {
            print("XPC connection interrupted")
        }

        // Start the connection
        newConnection.resume()

        return true
    }
}

/// Convenience extension for the host app to start/stop the XPC service
public extension MTPDeviceManager {
    private static var xpcListener: MTPXPCListener?

    func startXPCService() {
        if MTPDeviceManager.xpcListener == nil {
            MTPDeviceManager.xpcListener = MTPXPCListener()
            MTPDeviceManager.xpcListener?.start()
            MTPDeviceManager.xpcListener?.startTempFileCleanupTimer()
        }
    }

    func stopXPCService() {
        MTPDeviceManager.xpcListener?.stop()
        MTPDeviceManager.xpcListener = nil
    }
}
