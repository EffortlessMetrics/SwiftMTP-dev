// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Bridges MTP device events to the crawl scheduler and live index.
///
/// Consumes the device's `events` async stream and routes events to the appropriate
/// handler on the `CrawlScheduler`. Falls back to periodic refresh if the device
/// does not support events.
public actor EventBridge {
    private let scheduler: CrawlScheduler
    private let deviceId: String
    private var eventTask: Task<Void, Never>?
    private var stopped = false

    public init(scheduler: CrawlScheduler, deviceId: String) {
        self.scheduler = scheduler
        self.deviceId = deviceId
    }

    /// Start listening to device events.
    public func start(device: any MTPDevice) async {
        stopped = false

        // Check if device supports events
        let info = try? await device.info
        let supportsEvents = !(info?.eventsSupported.isEmpty ?? true)

        if supportsEvents {
            eventTask = Task { [weak self, deviceId] in
                for await event in device.events {
                    guard let self, await !self.isStopped() else { break }
                    switch event {
                    case .objectAdded(let handle):
                        await self.scheduler.handleObjectAdded(deviceId: deviceId, handle: handle, device: device)
                    case .objectRemoved(let handle):
                        await self.scheduler.handleObjectRemoved(deviceId: deviceId, handle: handle)
                    case .storageInfoChanged:
                        // Re-seed the crawl to pick up storage changes
                        await self.scheduler.seedOnConnect(deviceId: deviceId, device: device)
                    }
                }
            }
        } else {
            // No event support — use periodic refresh
            await scheduler.startPeriodicRefresh(deviceId: deviceId, device: device)
        }
    }

    /// Stop listening to events.
    public func stop() {
        stopped = true
        eventTask?.cancel()
        eventTask = nil
    }

    private func isStopped() -> Bool {
        stopped
    }
}
