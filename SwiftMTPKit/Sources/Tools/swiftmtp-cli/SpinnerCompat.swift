// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public struct CLISpinner {
  public let enabled: Bool
  private var message: String

  // Preferred initializer
  public init(_ message: String = "", enabled: Bool = true) {
    // Disable spinner if stdout is not a TTY (e.g., when output is piped or redirected)
    #if canImport(Darwin)
    let isStdoutTTY = isatty(STDOUT_FILENO) == 1
    #else
    let isStdoutTTY = true
    #endif
    self.enabled = enabled && isStdoutTTY
    self.message = message
    if self.enabled, !message.isEmpty { Self.printStart(message) }
  }

  // Back-compat initializer some call-sites still use
  @available(*, deprecated, message: "Use Spinner(\"message\", enabled:)")
  public init(message: String, enabled: Bool) {
    self.init(message, enabled: enabled)
  }

  // Convenience used when call-site only toggles JSON mode
  public init(enabled: Bool) {
    self.init("", enabled: enabled)
  }

  public mutating func start(_ msg: String? = nil) {
    guard enabled else { return }
    if let m = msg { message = m; Self.printStart(m) }
  }
  public func succeed(_ msg: String? = nil) { guard enabled else { return }; Self.printDone(msg ?? message, ok: true) }
  public func fail(_ msg: String? = nil)    { guard enabled else { return }; Self.printDone(msg ?? message, ok: false) }
  public func stopAndClear()                 { /* no-op for simple TTY spinner; left for API compat */ }

  // --- tiny TTY helpers (stdout is fine for progress; JSON is suppressed via enabled=false) ---
  private static func printStart(_ s: String) { fputs("⏳ \(s)\n", stderr) }
  private static func printDone(_ s: String, ok: Bool) {
    fputs("\(ok ? "✅" : "❌") \(s)\n", stderr)
  }
}

// Make CLI use `Spinner` type name
public typealias Spinner = CLISpinner
