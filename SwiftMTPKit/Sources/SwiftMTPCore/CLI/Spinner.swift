// Spinner.swift
import Foundation

public final class Spinner: @unchecked Sendable {
  private let enabled: Bool
  private var stop = false
  private var thread: Thread?

  public init(enabled: Bool) { self.enabled = enabled }

  public func start(_ label: String = "") {
    guard enabled else { return }
    stop = false
    thread = Thread {
      let frames: [String] = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
      var i = 0
      while !Thread.current.isCancelled {
        if self.stop { break }
        fputs("\r\(frames[i % frames.count]) \(label)", stderr)
        fflush(stderr)
        i += 1
        Thread.sleep(forTimeInterval: 0.08)
      }
      fputs("\r", stderr)
    }
    thread?.start()
  }

  public func stopAndClear(_ end: String? = nil) {
    guard enabled else { return }
    stop = true
    thread?.cancel()
    fputs("\r", stderr)
    if let end { fputs("\(end)\n", stderr) }
  }
}
