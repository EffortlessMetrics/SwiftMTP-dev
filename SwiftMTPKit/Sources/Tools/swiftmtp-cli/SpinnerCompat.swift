// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Minimal spinner that never emits anything when disabled (e.g. --json)
public final class CLISpinner {
  private let enabled: Bool
  private var prefix: String

  public init(_ text: String = "", enabled: Bool = true) {
    self.enabled = enabled
    self.prefix = text
  }

  public func start() {
    guard enabled, !prefix.isEmpty else { return }
    fputs("\(prefix)…\n", stderr)
  }

  public func succeed(_ text: String) {
    guard enabled else { return }
    fputs("✅ \(text)\n", stderr)
  }

  public func fail(_ text: String) {
    guard enabled else { return }
    fputs("❌ \(text)\n", stderr)
  }

  public func stopAndClear(_ text: String?) {
    guard enabled else { return }
    if let t = text, !t.isEmpty {
      fputs("\(t)\n", stderr)
    }
  }
}

// Use the existing Spinner from CollectCommand instead
