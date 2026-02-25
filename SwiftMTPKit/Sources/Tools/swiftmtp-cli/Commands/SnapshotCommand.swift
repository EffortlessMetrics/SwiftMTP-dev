// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

@MainActor
struct SnapshotCommand {
  static func run(flags: CLIFlags, args: [String]) async {
    print("📸 Capturing device snapshot...")
    do {
      let device = try await openDevice(flags: flags)
      try await device.openIfNeeded()

      let info = try await device.info
      let storages = try await device.storages()

      var allObjects: [MTPObjectInfo] = []
      for storage in storages {
        print("   Scanning storage: \(storage.description)...")
        let stream = device.list(parent: nil as MTPObjectHandle?, in: storage.id)
        for try await batch in stream {
          allObjects.append(contentsOf: batch)
        }
      }

      let snapshot = MTPSnapshot(
        timestamp: Date(),
        deviceInfo: info,
        storages: storages,
        objects: allObjects
      )

      let jsonString = try snapshot.jsonString()
      let sanitizedManufacturer = info.manufacturer.replacingOccurrences(
        of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
      let sanitizedModel = info.model.replacingOccurrences(
        of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
      let filename = "snapshot-\(sanitizedManufacturer)-\(sanitizedModel).json"

      try jsonString.write(toFile: filename, atomically: true, encoding: .utf8)

      print("✅ Snapshot captured: \(filename)")
      print("   (\(storages.count) storages, \(allObjects.count) objects)")
    } catch {
      print("❌ Snapshot failed: \(error)")
      exitNow(.tempfail)
    }
  }
}
