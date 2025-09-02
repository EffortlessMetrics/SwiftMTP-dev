import Foundation
import CLibusb
import SwiftMTPObservability

final class LibUSBContext: @unchecked Sendable {
    static let shared = LibUSBContext()
    private var ctx: OpaquePointer?
    private var eventThread: Thread?

    private init() {
        var c: OpaquePointer?
        let rc = libusb_init(&c)
        precondition(rc == 0, "libusb_init failed: \(rc)")
        ctx = c
        // Enable debug logging to see device events
        // Skip libusb_set_option for now as it's variadic and unavailable in Swift
        MTPLog.transport.info("LibUSB context initialized")
        startEventLoop()
    }

    deinit {
        if let ctx {
            libusb_exit(ctx)
        }
    }

    private func startEventLoop() {
        eventThread = Thread { [weak self] in
            guard let self, let ctx = self.ctx else { return }
            let tv = timeval(tv_sec: 0, tv_usec: 200_000) // 200ms
            while !Thread.current.isCancelled {
                var copy = tv
                _ = libusb_handle_events_timeout_completed(ctx, &copy, nil)
            }
        }
        eventThread?.qualityOfService = .userInitiated
        eventThread?.start()
    }

    var contextPointer: OpaquePointer? {
        ctx
    }
}
