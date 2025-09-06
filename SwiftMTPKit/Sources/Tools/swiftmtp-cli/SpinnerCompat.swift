// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public struct CLISpinner {
  private let enabled: Bool
  private var text: String

  public init(_ text: String = "", enabled: Bool = true) {
    self.enabled = enabled
    self.text = text
    if enabled && !text.isEmpty { fputs("\(text)…\n", stderr) }
  }
  public mutating func update(_ t: String) {
    guard enabled else { return }
    text = t
    fputs("\(t)…\n", stderr)
  }
  public func succeed(_ t: String? = nil) {
    guard enabled else { return }
    if let t = t, !t.isEmpty { fputs("✅ \(t)\n", stderr) }
  }
  public func fail(_ t: String? = nil) {
    guard enabled else { return }
    if let t = t, !t.isEmpty { fputs("❌ \(t)\n", stderr) }
  }
}

// Note: CollectCommand defines its own Spinner class
// CLI code should use CLISpinner directly or the existing Spinner class
