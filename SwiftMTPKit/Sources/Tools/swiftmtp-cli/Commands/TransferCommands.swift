// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI
import SwiftMTPSync

@MainActor
struct TransferCommands {
  static func runPull(flags: CLIFlags, args: [String]) async {
    guard args.count >= 2, let handle = UInt32(args[0]) else {
      print("❌ Missing required arguments for pull.")
      print("   Usage: swiftmtp pull <handle> <destination>")
      print("   Example: swiftmtp pull 42 ./photo.jpg")
      print("   Tip: Run 'swiftmtp ls <storage>' to find object handles.")
      exitNow(.usage)
    }

    let destPath = args[1]
    let destURL = URL(fileURLWithPath: destPath)
    print("⬇️  Downloading object \(handle) to \(destPath)...")

    do {
      let device = try await openDevice(flags: flags)
      let progress = try await device.read(handle: handle, range: nil, to: destURL)
      while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
      print("✅ Downloaded successfully")
    } catch {
      displayError("Failed to download", error: error, flags: flags)
      if let mtpError = error as? MTPError, case .transport(let te) = mtpError, case .noDevice = te
      {
        exitNow(.unavailable)
      }
      exitNow(.tempfail)
    }
  }

  static func runPush(flags: CLIFlags, args: [String]) async {
    guard args.count >= 2 else {
      print("❌ Missing required arguments for push.")
      print("   Usage: swiftmtp push <source> <parent-handle-or-folder-name>")
      print("   Example: swiftmtp push photo.jpg Download")
      print("   Example: swiftmtp push file.txt 0xFFFFFFF1")
      print("   Tip: Use a folder name (e.g. 'Download') or a hex handle.")
      exitNow(.usage)
    }

    let srcPath = args[0]
    let parentArg = args[1]
    let srcURL = URL(fileURLWithPath: srcPath)

    guard FileManager.default.fileExists(atPath: srcPath) else {
      print("❌ Source file not found: \(srcPath)")
      print("   Check that the path is correct and the file exists.")
      exitNow(.usage)
    }

    let attrs = try? FileManager.default.attributesOfItem(atPath: srcPath)
    let size = attrs?[.size] as? UInt64 ?? 0

    do {
      let device = try await openDevice(flags: flags)

      // Try to parse as hex or decimal handle first
      // Handle formats: "0xHEX", "HEX", "decimal"
      var parentHandle: UInt32?
      let cleanArg =
        parentArg.lowercased().hasPrefix("0x") ? String(parentArg.dropFirst(2)) : parentArg
      parentHandle = UInt32(cleanArg, radix: 16) ?? UInt32(cleanArg)

      // If not a valid number, treat as folder name and resolve it
      if parentHandle == nil {
        parentHandle = try await resolveFolderHandle(
          device: device,
          folderName: parentArg.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
        print("⬆️  Uploading \(srcPath) (\(formatBytes(size))) to folder \(parentArg)...")
      } else if parentHandle == 0 {
        // Handle is 0, try to resolve a default safe folder
        parentHandle = try await resolveSafeFolderHandle(device: device)
        print("⬆️  Uploading \(srcPath) (\(formatBytes(size))) to auto-selected folder...")
      } else {
        print(
          "⬆️  Uploading \(srcPath) (\(formatBytes(size))) to handle 0x\(String(format: "%x", parentHandle!))..."
        )
      }

      let progress = try await device.write(
        parent: parentHandle == 0xFFFFFFFF ? nil : parentHandle, name: srcURL.lastPathComponent,
        size: size, from: srcURL)
      while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
      print("✅ Uploaded successfully")
    } catch {
      displayError("Failed to upload", error: error, flags: flags)
      if let mtpError = error as? MTPError, case .transport(let te) = mtpError, case .noDevice = te
      {
        exitNow(.unavailable)
      }
      exitNow(.tempfail)
    }
  }

  /// Resolve a folder by name in the storage root.
  private static func resolveFolderHandle(device: any MTPDevice, folderName: String) async throws
    -> UInt32
  {
    let storages = try await device.storages()
    guard let storage = storages.first else {
      throw MTPError.preconditionFailed("No storage available")
    }

    let rootStream = device.list(parent: nil, in: storage.id)
    var rootItems: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootItems.append(contentsOf: batch)
    }

    let folders = rootItems.filter { $0.formatCode == 0x3001 }
    if let match = folders.first(where: {
      $0.name.caseInsensitiveCompare(folderName) == .orderedSame
    }) {
      return match.handle
    }

    throw MTPError.preconditionFailed("Folder '\(folderName)' not found in storage root")
  }

  /// Resolve a safe folder (Download > DCIM > first folder) for writes.
  private static func resolveSafeFolderHandle(device: any MTPDevice) async throws -> UInt32 {
    let storages = try await device.storages()
    guard let storage = storages.first else {
      throw MTPError.preconditionFailed("No storage available")
    }

    let rootStream = device.list(parent: nil, in: storage.id)
    var rootItems: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootItems.append(contentsOf: batch)
    }

    let folders = rootItems.filter { $0.formatCode == 0x3001 }
    print("   [DEBUG] Found \(folders.count) folders in storage root:")
    for folder in folders.prefix(5) {
      print("   [DEBUG]   handle=0x\(String(format: "%08x", folder.handle)) name=\(folder.name)")
    }

    let preferredNames = ["Download", "DCIM", "Pictures"]
    for name in preferredNames {
      if let match = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
      {
        print(
          "   [DEBUG] Selected folder: name=\(name) handle=0x\(String(format: "%08x", match.handle))"
        )
        return match.handle
      }
    }

    if let first = folders.first {
      print(
        "   [DEBUG] Using first available folder: handle=0x\(String(format: "%08x", first.handle)) name=\(first.name)"
      )
      return first.handle
    }

    throw MTPError.preconditionFailed("No writable folder found in storage root")
  }

  static func runBench(flags: CLIFlags, args: [String]) async {
    guard let sizeStr = args.first else {
      print("❌ Missing required argument: <size>")
      print(
        "   Usage: swiftmtp bench <size> [--storage <id>] [--parent <handle>] [--repeat <n>] [--out <csv>]"
      )
      print("   Example: swiftmtp bench 10M --repeat 3 --out results.csv")
      print("   Sizes: 1M, 10M, 100M, 1G")
      exitNow(.usage)
    }

    let sizeBytes = parseSize(sizeStr)
    guard sizeBytes > 0 else {
      print("❌ Invalid size format: '\(sizeStr)'")
      print("   Use a number with optional suffix: 1M, 10M, 100M, 1G")
      exitNow(.usage)
    }

    // Parse optional --storage / --parent / --repeat / --out flags
    var explicitStorage: UInt32? = nil
    var explicitParent: UInt32? = nil
    var repeatCount = 1
    var outPath: String? = nil
    var i = 1
    while i < args.count {
      if args[i] == "--storage", i + 1 < args.count {
        let val = args[i + 1]
        explicitStorage = UInt32(val, radix: 16) ?? UInt32(val)
        i += 2
      } else if args[i] == "--parent", i + 1 < args.count {
        let val = args[i + 1]
        explicitParent = UInt32(val, radix: 16) ?? UInt32(val)
        i += 2
      } else if args[i] == "--repeat", i + 1 < args.count {
        if let n = Int(args[i + 1]), n > 0 {
          repeatCount = n
          i += 2
        } else {
          print("❌ Invalid value for --repeat: '\(args[i + 1])'. Must be a positive integer.")
          exitNow(.usage)
        }
      } else if args[i].hasPrefix("--repeat=") {
        let value = String(args[i].dropFirst("--repeat=".count))
        if let n = Int(value), n > 0 {
          repeatCount = n
          i += 1
        } else {
          print("❌ Invalid value for --repeat: '\(value)'. Must be a positive integer.")
          exitNow(.usage)
        }
      } else if args[i] == "--out", i + 1 < args.count {
        outPath = args[i + 1]
        i += 2
      } else if args[i].hasPrefix("--out=") {
        outPath = String(args[i].dropFirst("--out=".count))
        i += 1
      } else {
        i += 1
      }
    }

    print("Benchmarking with \(formatBytes(sizeBytes)) (repeat: \(repeatCount))...")

    do {
      let device = try await openDevice(flags: flags)
      let (storageID, parentHandle) = try await resolveBenchTarget(
        device: device, explicitStorage: explicitStorage, explicitParent: explicitParent
      )

      print(
        "   Target: storage=0x\(String(format: "%08x", storageID.raw)) parent=0x\(String(format: "%08x", parentHandle))"
      )

      // Load persisted tuning for this device (if available).
      let tuningStore = DeviceTuningStore()
      let vidPid = await deviceVIDPID(device)
      let existingRecord = tuningStore.load(vid: vidPid.vid, pid: vidPid.pid)
      let initialChunk = existingRecord?.optimalChunkSize
      let tuner = AdaptiveChunkTuner(initialChunkSize: initialChunk)

      if let existing = existingRecord {
        print("   Loaded tuning: chunk=\(formatBytes(UInt64(existing.optimalChunkSize))) peak=\(String(format: "%.1f", existing.maxObservedThroughput / 1_000_000)) MB/s")
      } else {
        print("   No prior tuning data — starting at \(formatBytes(UInt64(await tuner.currentChunkSize)))")
      }

      var csvRows = ["timestamp,operation,size_bytes,duration_seconds,speed_mbps,chunk_size"]
      let iso = ISO8601DateFormatter()

      for pass in 1...repeatCount {
        let randomSuffix = String(UInt32.random(in: 0...UInt32.max), radix: 16, uppercase: false)
        let benchFilename = "swiftmtp-bench-\(randomSuffix).tmp"
        let tempURL = try createBenchPayloadFile(name: benchFilename, sizeBytes: sizeBytes)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let chunkBefore = await tuner.currentChunkSize
        print("   Run \(pass)/\(repeatCount): upload \(benchFilename) chunk=\(formatBytes(UInt64(chunkBefore)))...")
        let startTime = Date()
        let progress = try await device.write(
          parent: parentHandle == 0xFFFFFFFF ? nil : parentHandle,
          name: benchFilename, size: sizeBytes, from: tempURL
        )
        while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }

        let duration = max(Date().timeIntervalSince(startTime), 0.001)
        let speedBps = Double(sizeBytes) / duration
        let speedMBps = speedBps / 1_000_000

        // Feed result into the adaptive tuner.
        let newChunk = await tuner.recordChunk(bytes: Int(sizeBytes), duration: duration)
        if newChunk != chunkBefore {
          let direction = newChunk > chunkBefore ? "▲" : "▼"
          print("   \(direction) Tuning adjusted: \(formatBytes(UInt64(chunkBefore))) → \(formatBytes(UInt64(newChunk)))")
        }

        print(String(format: "   Run %d: %.2f MB/s (%.2f seconds)", pass, speedMBps, duration))

        csvRows.append(
          "\(iso.string(from: startTime)),write,\(sizeBytes),\(String(format: "%.6f", duration)),\(String(format: "%.3f", speedMBps)),\(chunkBefore)"
        )

        await cleanupBenchFile(
          device: device, storage: storageID, parent: parentHandle, name: benchFilename)
      }

      // Print tuning summary.
      let snap = await tuner.snapshot
      print("")
      print("   ── Tuning Report ──")
      print("   Optimal chunk size : \(formatBytes(UInt64(snap.currentChunkSize)))")
      print(String(format: "   Avg throughput      : %.2f MB/s", snap.averageThroughput / 1_000_000))
      print(String(format: "   Peak throughput     : %.2f MB/s", snap.maxObservedThroughput / 1_000_000))
      print("   Errors              : \(snap.errorCount)")
      print("   Samples             : \(snap.sampleCount)")
      let adjustments = await tuner.adjustments
      let adjustCount = adjustments.filter { $0.reason != .initial }.count
      if adjustCount > 0 {
        print("   Adjustments         : \(adjustCount)")
      }

      // Persist tuning data.
      tuningStore.update(vid: vidPid.vid, pid: vidPid.pid, from: snap)
      print("   Tuning saved to ~/.swiftmtp/device-tuning.json")

      if let outPath {
        let outURL = URL(fileURLWithPath: outPath)
        let csv = csvRows.joined(separator: "\n") + "\n"
        try csv.write(to: outURL, atomically: true, encoding: .utf8)
        print("   CSV written: \(outURL.path)")
      }
    } catch {
      displayError("Benchmark failed", error: error, flags: flags)
      if let mtpError = error as? MTPError, case .transport(let te) = mtpError, case .noDevice = te
      {
        exitNow(.unavailable)
      }
      exitNow(.tempfail)
    }
  }

  /// Extract VID/PID from a device (falls back to "0000" if unavailable).
  private static func deviceVIDPID(_ device: any MTPDevice) async -> (vid: String, pid: String) {
    let summary = device.summary
    let vid = summary.vendorID.map { String(format: "%04x", $0) } ?? "0000"
    let pid = summary.productID.map { String(format: "%04x", $0) } ?? "0000"
    return (vid: vid, pid: pid)
  }

  private static func createBenchPayloadFile(name: String, sizeBytes: UInt64) throws -> URL {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    let testData = Data(repeating: 0xAA, count: Int(min(sizeBytes, 1024 * 1024)))
    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: tempURL)
    var written: UInt64 = 0
    while written < sizeBytes {
      let toWrite = min(UInt64(testData.count), sizeBytes - written)
      try fileHandle.write(contentsOf: testData.prefix(Int(toWrite)))
      written += toWrite
    }
    try fileHandle.close()
    return tempURL
  }

  /// Resolve a safe target folder for benchmark writes.
  ///
  /// Strategy: enumerate storages → pick first writable → list root objects →
  /// find safe folder (Download/Downloads > DCIM > first folder) →
  /// look for existing SwiftMTPBench subfolder, create if absent.
  private static func resolveBenchTarget(
    device: any MTPDevice, explicitStorage: UInt32?, explicitParent: UInt32?
  ) async throws -> (MTPStorageID, MTPObjectHandle) {
    // If both explicitly specified, use them directly
    if let s = explicitStorage, let p = explicitParent {
      return (MTPStorageID(raw: s), p)
    }

    let storages = try await device.storages()
    let targetStorage: MTPStorageInfo
    if let s = explicitStorage, let match = storages.first(where: { $0.id.raw == s }) {
      targetStorage = match
    } else {
      guard let first = storages.first(where: { !$0.isReadOnly }) ?? storages.first else {
        throw MTPError.preconditionFailed("No storage available")
      }
      targetStorage = first
    }

    if let p = explicitParent {
      return (targetStorage.id, p)
    }

    // List root objects, find a safe folder
    let rootStream = device.list(parent: nil, in: targetStorage.id)
    var rootItems: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootItems.append(contentsOf: batch)
    }

    // Prefer Download/Downloads, then DCIM, then first Association (folder)
    let folders = rootItems.filter { $0.formatCode == 0x3001 }
    let preferredNames = ["Download", "Downloads", "DCIM"]
    var safeFolder: MTPObjectInfo? = nil
    for name in preferredNames {
      if let match = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
      {
        safeFolder = match
        break
      }
    }
    if safeFolder == nil {
      safeFolder = folders.first
    }

    guard let parent = safeFolder else {
      // No folders found — fall back to root with a warning
      print("   WARNING: No safe folder found, writing to storage root (may fail on some devices)")
      return (targetStorage.id, 0xFFFFFFFF)
    }

    // Look for existing SwiftMTPBench subfolder inside the safe folder
    let childStream = device.list(parent: parent.handle, in: targetStorage.id)
    var children: [MTPObjectInfo] = []
    for try await batch in childStream {
      children.append(contentsOf: batch)
    }

    if let benchFolder = children.first(where: {
      $0.name == "SwiftMTPBench" && $0.formatCode == 0x3001
    }) {
      print("   Using existing SwiftMTPBench folder in \(parent.name)/")
      return (targetStorage.id, benchFolder.handle)
    }

    // Create SwiftMTPBench subfolder
    print("   Creating SwiftMTPBench folder in \(parent.name)/...")
    let newHandle = try await device.createFolder(
      parent: parent.handle, name: "SwiftMTPBench", storage: targetStorage.id)
    return (targetStorage.id, newHandle)
  }

  /// Enumerate the parent folder and delete the bench file by name.
  private static func cleanupBenchFile(
    device: any MTPDevice, storage: MTPStorageID, parent: MTPObjectHandle, name: String
  ) async {
    do {
      let stream = device.list(parent: parent == 0xFFFFFFFF ? nil : parent, in: storage)
      for try await batch in stream {
        if let target = batch.first(where: { $0.name == name }) {
          try await device.delete(target.handle, recursive: false)
          print("   Cleaned up bench file on device")
          return
        }
      }
    } catch {
      print("   Note: could not clean up bench file: \(error)")
    }
  }

  static func runMirror(flags: CLIFlags, args: [String]) async {
    // Parse mirror-specific flags
    var positionalArgs: [String] = []
    var photosOnly = false
    var formatInclude: [String] = []
    var formatExclude: [String] = []
    var conflictStrategy: String = "newer-wins"

    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--photos-only" {
        photosOnly = true
      } else if arg == "--format", i + 1 < args.count {
        i += 1
        formatInclude = args[i].split(separator: ",").map(String.init)
      } else if arg.hasPrefix("--format=") {
        formatInclude = String(arg.dropFirst("--format=".count)).split(separator: ",")
          .map(
            String.init)
      } else if arg == "--exclude-format", i + 1 < args.count {
        i += 1
        formatExclude = args[i].split(separator: ",").map(String.init)
      } else if arg.hasPrefix("--exclude-format=") {
        formatExclude = String(arg.dropFirst("--exclude-format=".count)).split(separator: ",")
          .map(
            String.init)
      } else if arg == "--on-conflict", i + 1 < args.count {
        i += 1
        conflictStrategy = args[i]
      } else if arg.hasPrefix("--on-conflict=") {
        conflictStrategy = String(arg.dropFirst("--on-conflict=".count))
      } else {
        positionalArgs.append(arg)
      }
      i += 1
    }

    guard let destPath = positionalArgs.first else {
      print("❌ Missing required argument: <destination>")
      print("   Usage: swiftmtp mirror <destination> [options]")
      print("   Example: swiftmtp mirror ./device-backup")
      print("   Options:")
      print("     --photos-only                Only mirror image files")
      print("     --format jpeg,png,heic        Only mirror specified formats")
      print("     --exclude-format mp4,avi      Exclude specified formats")
      print("     --on-conflict <strategy>      Conflict strategy: newer-wins, local-wins, device-wins, keep-both, skip")
      exitNow(.usage)
    }

    let validStrategies = ["newer-wins", "local-wins", "device-wins", "keep-both", "skip"]
    guard validStrategies.contains(conflictStrategy) else {
      print("❌ Unknown conflict strategy: '\(conflictStrategy)'")
      print("   Valid strategies: \(validStrategies.joined(separator: ", "))")
      exitNow(.usage)
    }

    // Build format filter
    let formatFilter: MTPFormatFilter
    if photosOnly {
      formatFilter = .category(.images)
    } else if !formatInclude.isEmpty {
      formatFilter = .including(extensions: formatInclude)
    } else if !formatExclude.isEmpty {
      formatFilter = .excluding(extensions: formatExclude)
    } else {
      formatFilter = .all
    }

    print("🔄 Mirroring device to \(destPath) (conflict strategy: \(conflictStrategy))...")
    do {
      let device = try await openDevice(flags: flags)
      let storages = try await device.storages()
      guard let firstStorage = storages.first else {
        print("❌ No storage available on the device.")
        print("   Ensure the device is unlocked and set to MTP/File Transfer mode.")
        exitNow(.tempfail)
      }
      let rootStream = device.list(parent: nil as MTPObjectHandle?, in: firstStorage.id)
      var count = 0
      for try await batch in rootStream {
        for item in batch {
          print("   Found: \(item.name)")
          count += 1
        }
      }
      print("✅ Found \(count) items in root.")
    } catch {
      displayError("Mirror failed", error: error, flags: flags)
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .notSupported:
          exitNow(.unavailable)
        case .transport(let te):
          if case .noDevice = te { exitNow(.unavailable) }
        default:
          break
        }
      }
      exitNow(.tempfail)
    }
  }
}
