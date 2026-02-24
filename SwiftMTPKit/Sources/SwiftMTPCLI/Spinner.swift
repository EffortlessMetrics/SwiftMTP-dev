// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public final class Spinner: Sendable {
  private let enabled: Bool
  private let driver = SpinnerDriver()

  public init(enabled: Bool) {
    self.enabled = enabled
  }

  public func start(_ label: String = "") {
    guard enabled else { return }
    Task { await driver.start(label: label) }
  }

  public func stopAndClear(_ end: String? = nil) {
    guard enabled else { return }
    Task { await driver.stop(end: end) }
  }
}

private actor SpinnerDriver {
  private var task: Task<Void, Never>?
  private let frames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]

  func start(label: String) {
    stopInternal()
    task = Task { [frames] in
      var index = 0
      while !Task.isCancelled {
        fputs("\r\(frames[index % frames.count]) \(label)", stderr)
        fflush(stderr)
        index += 1
        do {
          try await Task.sleep(for: .milliseconds(80))
        } catch {
          break
        }
      }
      fputs("\r", stderr)
    }
  }

  func stop(end: String? = nil) {
    stopInternal()
    fputs("\r", stderr)
    if let end { fputs("\(end)\n", stderr) }
  }

  private func stopInternal() {
    task?.cancel()
    task = nil
  }
}
