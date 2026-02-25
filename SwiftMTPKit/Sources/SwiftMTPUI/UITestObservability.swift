// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Configuration consumed by deterministic UI test flows.
public struct UITestConfiguration {
  public let enabled: Bool
  public let scenario: String
  public let mockProfile: String
  public let demoModeEnabled: Bool
  public let runIdentifier: String
  public let artifactDirectory: URL

  public static var current: UITestConfiguration {
    let env = ProcessInfo.processInfo.environment
    let enabled = Self.boolValue(env["SWIFTMTP_UI_TEST"]) ?? false
    let scenario = env["SWIFTMTP_UI_SCENARIO"] ?? "mock-default"
    let mockProfile = env["SWIFTMTP_MOCK_PROFILE"] ?? "pixel7"
    let demoModeEnabled = Self.boolValue(env["SWIFTMTP_DEMO_MODE"]) ?? true
    let runIdentifier = env["SWIFTMTP_UI_TEST_RUN_ID"] ?? Self.defaultRunID()
    let artifactDirectory: URL
    if let raw = env["SWIFTMTP_UI_TEST_ARTIFACT_DIR"], !raw.isEmpty {
      artifactDirectory = URL(fileURLWithPath: raw, isDirectory: true)
    } else {
      artifactDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftmtp-ui-test-artifacts", isDirectory: true)
        .appendingPathComponent(runIdentifier, isDirectory: true)
    }

    return UITestConfiguration(
      enabled: enabled,
      scenario: scenario,
      mockProfile: mockProfile,
      demoModeEnabled: demoModeEnabled,
      runIdentifier: runIdentifier,
      artifactDirectory: artifactDirectory
    )
  }

  private static func boolValue(_ raw: String?) -> Bool? {
    guard let raw else { return nil }
    switch raw.lowercased() {
    case "1", "true", "yes":
      return true
    case "0", "false", "no":
      return false
    default:
      return nil
    }
  }

  private static func defaultRunID() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: Date())
  }
}

public enum UITestEventLogger {
  private static let lock = NSLock()

  public static func emit(
    flow: UXFlowID,
    step: String,
    result: String,
    metadata: [String: String] = [:]
  ) {
    let config = UITestConfiguration.current
    guard config.enabled else { return }

    lock.lock()
    defer { lock.unlock() }

    do {
      try FileManager.default.createDirectory(
        at: config.artifactDirectory,
        withIntermediateDirectories: true
      )

      let payload: [String: Any] = [
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "flow": flow.rawValue,
        "step": step,
        "result": result,
        "metadata": metadata,
      ]

      let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
      let lineURL = config.artifactDirectory.appendingPathComponent("ux-events.jsonl")
      if !FileManager.default.fileExists(atPath: lineURL.path) {
        FileManager.default.createFile(atPath: lineURL.path, contents: data)
        if let handle = try? FileHandle(forWritingTo: lineURL) {
          try handle.seekToEnd()
          try handle.write(contentsOf: Data("\n".utf8))
          try handle.close()
        }
        return
      }

      let handle = try FileHandle(forWritingTo: lineURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.write(contentsOf: Data("\n".utf8))
      try handle.close()
    } catch {
      // Observability should never block UX/test execution.
    }
  }
}
