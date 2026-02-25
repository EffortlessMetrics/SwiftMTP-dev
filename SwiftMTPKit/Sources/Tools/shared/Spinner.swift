// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

final class Spinner {
  private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  private var idx = 0
  private var timer: DispatchSourceTimer?
  private let message: String
  private let isTTY: Bool
  private let enabled: Bool

  init(_ message: String, enabled: Bool = true) {
    self.message = message
    self.enabled = enabled
    #if canImport(Darwin)
      self.isTTY = isatty(STDOUT_FILENO) == 1
    #else
      self.isTTY = true
    #endif
  }

  // Back-compat initializer
  @available(*, deprecated, message: "Use init(_:enabled:) instead")
  init(_ message: String, jsonMode: Bool) {
    self.message = message
    self.enabled = !jsonMode
    #if canImport(Darwin)
      self.isTTY = isatty(STDOUT_FILENO) == 1
    #else
      self.isTTY = true
    #endif
  }

  func start() {
    guard isTTY, enabled else { return }
    fputs("  \(frames[idx]) \(message)\r", stderr)
    let t = DispatchSource.makeTimerSource(queue: .global())
    t.schedule(deadline: .now(), repeating: .milliseconds(80))
    t.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.idx = (self.idx + 1) % self.frames.count
      fputs("  \(self.frames[self.idx]) \(self.message)\r", stderr)
      fflush(stderr)
    }
    t.resume()
    timer = t
  }

  func succeed(_ final: String) {
    stop()
    if isTTY, enabled { fputs("  ✓ \(final)\n", stderr) }
  }

  func fail(_ final: String) {
    stop()
    if isTTY, enabled { fputs("  ✗ \(final)\n", stderr) }
  }

  private func stop() {
    timer?.cancel()
    timer = nil
    if isTTY, enabled { fputs("\r", stderr) }
  }
}
