// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import OSLog

final class LibUSBContext: @unchecked Sendable {
  static let shared = LibUSBContext()
  public let ctx: OpaquePointer
  private var eventThread: Thread?

  private init() {
    var c: OpaquePointer?
    let rc = libusb_init(&c)
    precondition(rc == 0, "libusb_init failed: \(rc)")
    self.ctx = c!
    // Skip libusb_set_option as it's variadic and unavailable in Swift
    Logger(subsystem: "SwiftMTP", category: "transport").info("LibUSB context initialized")
    startEventLoop()
  }

  deinit {
    libusb_exit(ctx)
  }

  private func startEventLoop() {
    eventThread = Thread { [weak self] in
      guard let self else { return }
      // 200ms poll interval balances responsiveness with CPU overhead:
      // - Short enough to detect hotplug and async transfer completion promptly
      // - Long enough to avoid busy-looping on the libusb file descriptors
      // - Matches the libusb recommended range for non-real-time applications
      let tv = timeval(tv_sec: 0, tv_usec: 200_000)
      while !Thread.current.isCancelled {
        var copy = tv
        _ = libusb_handle_events_timeout_completed(self.ctx, &copy, nil)
      }
    }
    eventThread?.qualityOfService = .userInitiated
    eventThread?.start()
  }

  var contextPointer: OpaquePointer {
    ctx
  }
}
