import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPIndex
import SwiftMTPSync
import Foundation
@preconcurrency import SQLite

@main struct CLI {
  static func main() async {
    let args = CommandLine.arguments

    // Parse command line arguments
    var useMock = false
    var mockProfile: MockTransportFactory.DeviceProfile = .androidPixel7
    var commandIndex = 1

    // Parse flags and options first
    while commandIndex < args.count {
      switch args[commandIndex] {
      case "--mock", "-m":
        useMock = true
        commandIndex += 1
        if commandIndex < args.count {
          switch args[commandIndex] {
          case "pixel7", "android":
            mockProfile = .androidPixel7
          case "galaxy", "samsung":
            mockProfile = .androidGalaxyS21
          case "iphone", "ios":
            mockProfile = .iosDevice
          case "canon", "camera":
            mockProfile = .canonCamera
          case "timeout":
            mockProfile = .failureTimeout
          case "busy":
            mockProfile = .failureBusy
          case "disconnected":
            mockProfile = .failureDisconnected
          default:
            // If it's not a known profile, it might be the start of a command
            commandIndex -= 1 // Back up to process this as a command
          }
        }
      case "--help", "-h":
        printHelp()
        return
      case "pull":
        commandIndex += 1
        guard commandIndex + 1 < args.count else {
          print("Usage: swift run swiftmtp [--mock [profile]] pull <handle> <output-file>")
          return
        }
        let handle = UInt32(args[commandIndex]) ?? 0
        let outputPath = args[commandIndex + 1]
        await runPullCommand(handle: handle, outputPath: outputPath, useMock: useMock, mockProfile: mockProfile)
        return
      case "push":
        commandIndex += 1
        guard commandIndex + 1 < args.count else {
          print("Usage: swift run swiftmtp [--mock [profile]] push <parent-handle> <input-file>")
          return
        }
        let parentHandle = UInt32(args[commandIndex]) ?? 0
        let inputPath = args[commandIndex + 1]
        await runPushCommand(parentHandle: parentHandle, inputPath: inputPath, useMock: useMock, mockProfile: mockProfile)
        return
      case "resume":
        commandIndex += 1
        guard commandIndex < args.count else {
          print("Usage: swift run swiftmtp resume <list|clear> [options]")
          return
        }
        let resumeCommand = args[commandIndex]
        commandIndex += 1
        switch resumeCommand {
        case "list":
          await runResumeListCommand(useMock: useMock, mockProfile: mockProfile)
        case "clear":
          var olderThan: String = "7d"
          if commandIndex < args.count {
            olderThan = args[commandIndex]
          }
          await runResumeClearCommand(olderThan: olderThan, useMock: useMock, mockProfile: mockProfile)
        default:
          print("Unknown resume command: \(resumeCommand)")
          print("Available commands: list, clear")
        }
        return
      case "snapshot":
        commandIndex += 1
        await runSnapshotCommand(useMock: useMock, mockProfile: mockProfile)
        return
      case "diff":
        commandIndex += 1
        await runDiffCommand(useMock: useMock, mockProfile: mockProfile)
        return
      case "mirror":
        commandIndex += 1
        guard commandIndex < args.count else {
          print("Usage: swift run swiftmtp [--mock [profile]] mirror <destination> [--include <pattern>]")
          return
        }
        let destination = args[commandIndex]
        commandIndex += 1
        var includePattern: String? = nil
        if commandIndex < args.count && args[commandIndex] == "--include" {
          commandIndex += 1
          if commandIndex < args.count {
            includePattern = args[commandIndex]
          }
        }
        await runMirrorCommand(destination: destination, includePattern: includePattern,
                             useMock: useMock, mockProfile: mockProfile)
        return
      case "probe":
        commandIndex += 1
        await runProbeCommand(useMock: useMock, mockProfile: mockProfile)
        return
      case "bench":
        commandIndex += 1
        guard commandIndex < args.count else {
          print("Usage: swift run swiftmtp [--mock [profile]] bench <size> (e.g., 1G, 500M, 100K)")
          return
        }
        let sizeSpec = args[commandIndex]
        await runBenchCommand(sizeSpec: sizeSpec, useMock: useMock, mockProfile: mockProfile)
        return
      default:
        print("Unknown argument: \(args[commandIndex])")
        printHelp()
        return
      }
      commandIndex += 1
    }

    // No command specified, run default mode
    if useMock {
      await runMockMode(profile: mockProfile)
    } else {
      await runRealMode()
    }
  }

  static func printHelp() {
    print("SwiftMTP CLI - Media Transfer Protocol Client")
    print("")
    print("USAGE:")
    print("  swift run swiftmtp                                # Real device mode")
    print("  swift run swiftmtp --mock [profile]               # Mock device mode")
    print("  swift run swiftmtp [--mock [profile]] pull <handle> <output-file>")
    print("  swift run swiftmtp [--mock [profile]] push <parent-handle> <input-file>")
    print("  swift run swiftmtp [--mock [profile]] snapshot")
    print("  swift run swiftmtp [--mock [profile]] diff")
    print("  swift run swiftmtp [--mock [profile]] mirror <destination> [--include <pattern>]")
    print("")
    print("COMMANDS:")
    print("  pull <handle> <output-file>        Download file by handle")
    print("  push <parent-handle> <input-file>  Upload file to parent directory")
    print("  resume list                       List resumable transfers")
    print("  resume clear [older-than]         Clear stale transfers (default: 7d)")
    print("  snapshot                          Take a snapshot of device contents")
    print("  diff                              Show differences since last snapshot")
    print("  mirror <dest> [--include <pattern>] Mirror device to local directory")
    print("  probe                             Probe device capabilities and USB info")
    print("  bench <size>                      Run transfer benchmark (e.g., 1G, 500M)")
    print("")
    print("OPTIONS:")
    print("  --mock [profile]    Use mock device instead of real hardware")
    print("")
    print("MOCK PROFILES:")
    print("  pixel7, android    - Google Pixel 7 (default)")
    print("  galaxy, samsung    - Samsung Galaxy S21")
    print("  iphone, ios        - Apple iPhone")
    print("  canon, camera      - Canon EOS R5")
    print("  timeout            - Test timeout error")
    print("  busy               - Test busy error")
    print("  disconnected       - Test disconnection error")
    print("")
    print("EXAMPLES:")
    print("  swift run swiftmtp --mock pixel7")
    print("  swift run swiftmtp --mock pixel7 pull 0x00010001 ./downloaded.jpg")
    print("  swift run swiftmtp --mock pixel7 push 0x00010002 ./upload.jpg")
    print("  swift run swiftmtp --mock timeout")
  }

  static func runRealMode() async {
    print("🔌 Starting MTP device discovery (Real Hardware)...")
    print("Initializing libusb context...")

    do {
      try await MTPDeviceManager.shared.startDiscovery()
      print("✅ Device discovery started successfully")
      print("Waiting for MTP devices… (you may need to change USB mode on your device)")
      print("Make sure your device is in 'File Transfer' mode, not 'Charging only'")
    } catch {
      print("❌ Failed to start device discovery: \(error)")
      return
    }

    let attachedStream = await MTPDeviceManager.shared.deviceAttached
    print("✅ Listening for device attach events...")

    for await d in attachedStream {
      print("🎉 Device attached!")
      print("   Manufacturer: \(d.manufacturer)")
      print("   Model: \(d.model)")
      print("   ID: \(d.id.raw)")

      // Open device and get parsed device info
      do {
        let transport = LibUSBTransportFactory.createTransport()
        let device = try await MTPDeviceManager.shared.openDevice(with: d, transport: transport)
        let info = try await device.info

        print("✅ Device Info Retrieved:")
        print("   Manufacturer: \(info.manufacturer)")
        print("   Model: \(info.model)")
        print("   Version: \(info.version)")
        if let serial = info.serialNumber {
          print("   Serial Number: \(serial)")
        }
        print("   Operations Supported: \(info.operationsSupported.count)")
        print("   Events Supported: \(info.eventsSupported.count)")

      } catch {
        print("❌ Failed to get device info: \(error)")
        print("   This might be because:")
        print("   - Device is in charging-only mode")
        print("   - Device is locked/screen off")
        print("   - Permission issues with libusb")
      }
      break
    }
  }

  static func runMockMode(profile: MockTransportFactory.DeviceProfile) async {
    print("🎭 Starting MTP device discovery (Mock Mode)...")

    // Get mock device data
    let mockData = MockTransportFactory.deviceData(for: profile)
    let deviceSummary = mockData.deviceSummary

    print("📱 Simulating device: \(deviceSummary.manufacturer) \(deviceSummary.model)")
    print("   Mock Profile: \(profileDescription(profile))")

    // Simulate device attachment delay
    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

    print("🎉 Mock device attached!")
    print("   Manufacturer: \(deviceSummary.manufacturer)")
    print("   Model: \(deviceSummary.model)")
    print("   ID: \(deviceSummary.id.raw)")

    // Open device and get parsed device info
    do {
      let transport = MockTransportFactory.createTransport(profile: profile)
      let device = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport)
      let info = try await device.info

      print("✅ Mock Device Info Retrieved:")
      print("   Manufacturer: \(info.manufacturer)")
      print("   Model: \(info.model)")
      print("   Version: \(info.version)")
      if let serial = info.serialNumber {
        print("   Serial Number: \(serial)")
      }
      print("   Operations Supported: \(info.operationsSupported.count)")
      print("   Events Supported: \(info.eventsSupported.count)")

      // Show storage information
      let storages = try await device.storages()
      print("   Storage Devices: \(storages.count)")
      for storage in storages {
        let usedBytes = storage.capacityBytes - storage.freeBytes
        let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
        print("     - \(storage.description): \(formatBytes(storage.capacityBytes)) total, \(formatBytes(storage.freeBytes)) free (\(String(format: "%.1f", usedPercent))% used)")
      }

      // Show some files from the first storage
      if let firstStorage = storages.first {
        print("   Sample Files from \(firstStorage.description):")
        let objects = await listObjects(device: device, storage: firstStorage.id, parent: nil, maxCount: 5)
        for object in objects {
          if let size = object.sizeBytes {
            print("     📄 \(object.name) (\(formatBytes(size)))")
          } else {
            print("     📁 \(object.name)/")
          }
        }
      }

    } catch {
      print("❌ Failed to get mock device info: \(error)")
      print("   This is expected for error simulation profiles")
    }
  }

  static func profileDescription(_ profile: MockTransportFactory.DeviceProfile) -> String {
    switch profile {
    case .androidPixel7: return "Google Pixel 7 (Android)"
    case .androidGalaxyS21: return "Samsung Galaxy S21 (Android)"
    case .iosDevice: return "Apple iPhone (iOS)"
    case .canonCamera: return "Canon EOS R5 (Camera)"
    case .failureTimeout: return "Timeout Error Simulation"
    case .failureBusy: return "Busy Error Simulation"
    case .failureDisconnected: return "Disconnection Error Simulation"
    case .custom: return "Custom Configuration"
    }
  }

  static func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
      value /= 1024
      unitIndex += 1
    }

    return String(format: "%.1f %@", value, units[unitIndex])
  }

  static func listObjects(device: any MTPDevice, storage: MTPStorageID, parent: MTPObjectHandle?, maxCount: Int) async -> [MTPObjectInfo] {
    do {
      let stream = device.list(parent: parent, in: storage)
      var objects: [MTPObjectInfo] = []
      var count = 0

      for try await batch in stream {
        for object in batch {
          objects.append(object)
          count += 1
          if count >= maxCount {
            return objects
          }
        }
      }

      return objects
    } catch {
      print("Error listing objects: \(error)")
      return []
    }
  }

  static func runPullCommand(handle: UInt32, outputPath: String, useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let device = try await getDevice(useMock: useMock, mockProfile: mockProfile)
      let outputURL = URL(fileURLWithPath: outputPath)

      print("📥 Downloading object with handle \(handle)...")
      let progress = try await device.read(handle: handle, range: nil, to: outputURL)

      print("✅ Download completed!")
      print("   Bytes transferred: \(progress.completedUnitCount)")
      print("   Saved to: \(outputPath)")

    } catch {
      print("❌ Pull failed: \(error)")
    }
  }

  static func runPushCommand(parentHandle: UInt32, inputPath: String, useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let device = try await getDevice(useMock: useMock, mockProfile: mockProfile)
      let inputURL = URL(fileURLWithPath: inputPath)
      let filename = inputURL.lastPathComponent

      // Get file size
      let attributes = try FileManager.default.attributesOfItem(atPath: inputPath)
      let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

      print("📤 Uploading \(filename) (\(formatBytes(fileSize))) to parent handle \(parentHandle)...")
      let progress = try await device.write(parent: parentHandle, name: filename, size: fileSize, from: inputURL)

      print("✅ Upload completed!")
      print("   Bytes transferred: \(progress.completedUnitCount)")

    } catch {
      print("❌ Push failed: \(error)")
    }
  }

  static func getDevice(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async throws -> any MTPDevice {
    if useMock {
      let mockData = MockTransportFactory.deviceData(for: mockProfile)
      let deviceSummary = mockData.deviceSummary
      let transport = MockTransportFactory.createTransport(profile: mockProfile)
      return try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport)
    } else {
      try await MTPDeviceManager.shared.startDiscovery()

      let attachedStream = await MTPDeviceManager.shared.deviceAttached
      var iterator = attachedStream.makeAsyncIterator()
      guard let deviceSummary = await iterator.next() else {
        throw MTPError.deviceDisconnected
      }

      let transport = LibUSBTransportFactory.createTransport()
      return try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport)
    }
  }

  static func runResumeListCommand(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    print("📋 Resume functionality is implemented but requires TransferJournal setup")
    print("   In M5, transfers will automatically use resume when available")
    print("   Use 'swift run swiftmtp --mock pull <handle> <file>' to test transfers")
  }

  static func runResumeClearCommand(olderThan: String, useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    print("🧹 Resume clear functionality is implemented but requires TransferJournal setup")
    print("   In M5, stale temp files will be automatically cleaned up")
    print("   Use 'swift run swiftmtp --mock pull <handle> <file>' to test transfers")
  }

  static func runSnapshotCommand(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let (device, deviceId, dbPath) = try await setupForIndexCommands(useMock: useMock, mockProfile: mockProfile)
      defer { try? FileManager.default.removeItem(atPath: dbPath) }

      let snapshotter = try createSnapshotter(dbPath: dbPath)
      let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

      print("✅ Snapshot captured!")
      print("   Generation: \(gen)")
      print("   Device: \(deviceId.raw)")

    } catch {
      print("❌ Snapshot failed: \(error)")
    }
  }

  static func runDiffCommand(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let (device, deviceId, dbPath) = try await setupForIndexCommands(useMock: useMock, mockProfile: mockProfile)
      defer { try? FileManager.default.removeItem(atPath: dbPath) }

      let snapshotter = try createSnapshotter(dbPath: dbPath)
      let diffEngine = try createDiffEngine(dbPath: dbPath)

      // Take current snapshot
      let newGen = try await snapshotter.capture(device: device, deviceId: deviceId)

      // Get previous generation
      let prevGen = try snapshotter.previousGeneration(for: deviceId, before: newGen)

      if let prevGen = prevGen {
        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: prevGen, newGen: newGen)

        print("📊 Diff since generation \(prevGen):")
        print("   Added: \(diff.added.count)")
        print("   Removed: \(diff.removed.count)")
        print("   Modified: \(diff.modified.count)")
        print("   Total changes: \(diff.totalChanges)")

        if !diff.added.isEmpty {
          print("\n📁 Added files:")
          for file in diff.added.prefix(5) {
            print("   + \(file.pathKey)")
          }
          if diff.added.count > 5 {
            print("   ... and \(diff.added.count - 5) more")
          }
        }
      } else {
        print("ℹ️  No previous snapshot found - this is the first snapshot")
      }

    } catch {
      print("❌ Diff failed: \(error)")
    }
  }

  static func runMirrorCommand(destination: String, includePattern: String?, useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let (device, deviceId, dbPath) = try await setupForIndexCommands(useMock: useMock, mockProfile: mockProfile)
      defer { try? FileManager.default.removeItem(atPath: dbPath) }

      let snapshotter = try createSnapshotter(dbPath: dbPath)
      let diffEngine = try createDiffEngine(dbPath: dbPath)
      let journal = try createTransferJournal(dbPath: dbPath)
      let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

      let destURL = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)

      print("🔄 Starting mirror operation...")
      print("   Source: \(deviceId.raw)")
      print("   Destination: \(destURL.path)")
      if let pattern = includePattern {
        print("   Include pattern: \(pattern)")
      }

      let report: MTPSyncReport
      if let pattern = includePattern {
        report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: destURL, includePattern: pattern)
      } else {
        report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: destURL)
      }

      print("✅ Mirror completed!")
      print("   Downloaded: \(report.downloaded)")
      print("   Skipped: \(report.skipped)")
      print("   Failed: \(report.failed)")
      print("   Success rate: \(String(format: "%.1f", report.successRate))%")

    } catch {
      print("❌ Mirror failed: \(error)")
    }
  }

  // Helper functions for index commands
  static func setupForIndexCommands(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async throws -> (any MTPDevice, MTPDeviceID, String) {
    let device = try await getDevice(useMock: useMock, mockProfile: mockProfile)
    let deviceId = MTPDeviceID(raw: "test-device-\(Int(Date().timeIntervalSince1970))")

    // Create temporary database
    let tempDir = FileManager.default.temporaryDirectory
    let dbPath = tempDir.appendingPathComponent("swiftmtp-index-\(UUID().uuidString).db").path

    return (device, deviceId, dbPath)
  }

  static func createSnapshotter(dbPath: String) throws -> Snapshotter {
    let db = try Connection(dbPath)
    return Snapshotter(db: db)
  }

  static func createDiffEngine(dbPath: String) throws -> DiffEngine {
    let db = try Connection(dbPath)
    return DiffEngine(db: db)
  }

  static func createTransferJournal(dbPath: String) throws -> TransferJournal {
    try DefaultTransferJournal(dbPath: dbPath)
  }

  static func formatTimeInterval(_ interval: TimeInterval) -> String {
    if interval >= 24 * 60 * 60 {
      let days = interval / (24 * 60 * 60)
      return String(format: "%.1f days", days)
    } else if interval >= 60 * 60 {
      let hours = interval / (60 * 60)
      return String(format: "%.1f hours", hours)
    } else {
      return String(format: "%.0f seconds", interval)
    }
  }

  static func runProbeCommand(useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let device = try await getDevice(useMock: useMock, mockProfile: mockProfile)

      print("🔍 Probing device capabilities...")
      print("")

      // Get device info
      let info = try await device.info
      print("📱 Device Information:")
      print("   Manufacturer: \(info.manufacturer)")
      print("   Model: \(info.model)")
      print("   Version: \(info.version)")
      if let serial = info.serialNumber {
        print("   Serial Number: \(serial)")
      }

      // Get supported operations
      print("")
      print("⚙️  Supported Operations (\(info.operationsSupported.count)):")
      for op in info.operationsSupported.sorted() {
        if let opName = operationName(for: op) {
          print("   0x\(String(format: "%04x", op)) - \(opName)")
        } else {
          print("   0x\(String(format: "%04x", op)) - Unknown")
        }
      }

      // Get storage info
      let storages = try await device.storages()
      print("")
      print("💾 Storage Devices (\(storages.count)):")
      for storage in storages {
        let usedBytes = storage.capacityBytes - storage.freeBytes
        let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
        print("   📁 \(storage.description)")
        print("      Capacity: \(formatBytes(storage.capacityBytes))")
        print("      Free: \(formatBytes(storage.freeBytes))")
        print("      Used: \(formatBytes(usedBytes)) (\(String(format: "%.1f", usedPercent))%)")
        print("      Read-only: \(storage.isReadOnly ? "Yes" : "No")")
        print("")
      }

      // Sample some files for format analysis
      if let firstStorage = storages.first {
        print("📄 Sample Files (first 10 from root):")
        let objects = await listObjects(device: device, storage: firstStorage.id, parent: nil, maxCount: 10)

        var formatCounts = [String: Int]()
        for object in objects {
          if let format = object.formatCode {
            let formatName = formatName(for: format) ?? "Unknown (0x\(String(format: "%04x", format)))"
            formatCounts[formatName, default: 0] += 1
          }
        }

        for (format, count) in formatCounts.sorted(by: { $0.value > $1.value }) {
          print("   \(format): \(count) files")
        }
      }

      print("")
      print("✅ Probe complete")

    } catch {
      print("❌ Probe failed: \(error)")
    }
  }

  static func runBenchCommand(sizeSpec: String, useMock: Bool, mockProfile: MockTransportFactory.DeviceProfile) async {
    do {
      let device = try await getDevice(useMock: useMock, mockProfile: mockProfile)
      let benchSize = try parseSizeSpec(sizeSpec)

      print("🏃 Running transfer benchmark (\(formatBytes(benchSize)) test file)...")
      print("")

      // Create a test file of the specified size
      let tempDir = FileManager.default.temporaryDirectory
      let testFileURL = tempDir.appendingPathComponent("swiftmtp-bench-\(UUID().uuidString).bin")

      print("📝 Generating test file...")
      try generateTestFile(at: testFileURL, size: benchSize)

      // Get storage info
      let storages = try await device.storages()
      guard let storage = storages.first else {
        print("❌ No storage devices found")
        return
      }

      print("📤 Benchmarking write performance...")

      // Benchmark write
      let writeStart = Date()
      let writeProgress = try await device.write(parent: 0, name: "swiftmtp-bench.bin", size: UInt64(benchSize), from: testFileURL)
      let writeDuration = Date().timeIntervalSince(writeStart)
      let writeMbps = Double(benchSize) / writeDuration / (1024 * 1024)

      print("   ✅ Write: \(String(format: "%.2f", writeMbps)) MB/s (\(String(format: "%.1f", writeDuration))s)")

      // Find the uploaded file
      print("🔍 Locating uploaded file...")
      let objects = await listObjects(device: device, storage: storage.id, parent: nil, maxCount: 100)
      guard let uploadedObject = objects.first(where: { $0.name == "swiftmtp-bench.bin" }) else {
        print("❌ Could not find uploaded test file")
        return
      }

      print("📥 Benchmarking read performance...")

      // Benchmark read
      let readStart = Date()
      let readProgress = try await device.read(handle: uploadedObject.handle, range: nil, to: tempDir.appendingPathComponent("swiftmtp-bench-read.bin"))
      let readDuration = Date().timeIntervalSince(readStart)
      let readMbps = Double(benchSize) / readDuration / (1024 * 1024)

      print("   ✅ Read: \(String(format: "%.2f", readMbps)) MB/s (\(String(format: "%.1f", readDuration))s)")

      // Cleanup
      try? FileManager.default.removeItem(at: testFileURL)
      try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("swiftmtp-bench-read.bin"))

      // Try to delete from device (this might fail on some devices)
      do {
        try await device.delete(uploadedObject.handle, recursive: false)
        print("🧹 Cleaned up test file from device")
      } catch {
        print("⚠️  Could not delete test file from device (normal for some devices)")
      }

      print("")
      print("📊 Benchmark Results:")
      print("   Write Speed: \(String(format: "%.2f", writeMbps)) MB/s")
      print("   Read Speed: \(String(format: "%.2f", readMbps)) MB/s")
      print("   Test Size: \(formatBytes(benchSize))")
      print("   Device: \(try await device.info.model)")

    } catch {
      print("❌ Benchmark failed: \(error)")
    }
  }

  static func operationName(for code: UInt16) -> String? {
    switch code {
    case 0x1001: return "GetDeviceInfo"
    case 0x1002: return "OpenSession"
    case 0x1003: return "CloseSession"
    case 0x1004: return "GetStorageIDs"
    case 0x1005: return "GetStorageInfo"
    case 0x1006: return "GetNumObjects"
    case 0x1007: return "GetObjectHandles"
    case 0x1008: return "GetObjectInfo"
    case 0x1009: return "GetObject"
    case 0x100A: return "GetThumb"
    case 0x100B: return "DeleteObject"
    case 0x100C: return "SendObjectInfo"
    case 0x100D: return "SendObject"
    case 0x100E: return "InitiateCapture"
    case 0x100F: return "FormatStore"
    case 0x1010: return "ResetDevice"
    case 0x1014: return "GetDevicePropDesc"
    case 0x1015: return "GetDevicePropValue"
    case 0x1016: return "SetDevicePropValue"
    case 0x1017: return "ResetDevicePropValue"
    case 0x1018: return "TerminateOpenCapture"
    case 0x1019: return "MoveObject"
    case 0x101A: return "CopyObject"
    case 0x101B: return "GetPartialObject"
    case 0x101C: return "InitiateOpenCapture"
    case 0x95C1: return "SendPartialObject"
    case 0x95C2: return "TruncateObject"
    case 0x95C3: return "BeginEditObject"
    case 0x95C4: return "EndEditObject"
    case 0x95C5: return "GetPartialObject64"
    case 0x95C6: return "SendPartialObject64"
    case 0x95C7: return "TruncateObject64"
    case 0x95C8: return "BeginEditObject64"
    case 0x95C9: return "EndEditObject64"
    default: return nil
    }
  }

  static func formatName(for code: UInt16) -> String? {
    switch code {
    case 0x3000: return "Undefined"
    case 0x3001: return "Association"
    case 0x3002: return "Script"
    case 0x3003: return "Executable"
    case 0x3004: return "Text"
    case 0x3005: return "HTML"
    case 0x3006: return "DPOF"
    case 0x3007: return "AIFF"
    case 0x3008: return "WAV"
    case 0x3009: return "MP3"
    case 0x300A: return "AVI"
    case 0x300B: return "MPEG"
    case 0x300C: return "ASF"
    case 0x3800: return "Undefined Image"
    case 0x3801: return "EXIF/JPEG"
    case 0x3802: return "TIFF/EP"
    case 0x3803: return "FlashPix"
    case 0x3804: return "BMP"
    case 0x3805: return "CIFF"
    case 0x3806: return "Undefined Reserved"
    case 0x3807: return "GIF"
    case 0x3808: return "JFIF"
    case 0x3809: return "PCD"
    case 0x380A: return "PICT"
    case 0x380B: return "PNG"
    case 0x380C: return "Undefined Reserved"
    case 0x380D: return "TIFF"
    case 0x380E: return "TIFF/IT"
    case 0x380F: return "JP2"
    case 0x3810: return "JPX"
    case 0xB900: return "Undefined Video"
    case 0xB901: return "AVI"
    case 0xB902: return "MP4"
    case 0xB903: return "MOV"
    default: return nil
    }
  }

  static func parseSizeSpec(_ spec: String) throws -> Int {
    let spec = spec.uppercased()
    let regex = try NSRegularExpression(pattern: "^(\\d+)([KMGT]?)B?$", options: [])
    let range = NSRange(spec.startIndex..<spec.endIndex, in: spec)

    guard let match = regex.firstMatch(in: spec, options: [], range: range),
          let numberRange = Range(match.range(at: 1), in: spec),
          let number = Double(String(spec[numberRange])) else {
      throw MTPError.invalidParameter("Invalid size specification: \(spec). Use format like 1G, 500M, 100K")
    }

    let multiplier: Double
    if let unitRange = Range(match.range(at: 2), in: spec), !unitRange.isEmpty {
      let unit = String(spec[unitRange])
      switch unit {
      case "K": multiplier = 1024
      case "M": multiplier = 1024 * 1024
      case "G": multiplier = 1024 * 1024 * 1024
      case "T": multiplier = 1024 * 1024 * 1024 * 1024
      default: multiplier = 1
      }
    } else {
      multiplier = 1
    }

    let bytes = number * multiplier
    guard bytes <= Double(Int.max) else {
      throw MTPError.invalidParameter("Size too large: \(spec)")
    }

    return Int(bytes)
  }

  static func generateTestFile(at url: URL, size: Int) throws {
    let bufferSize = 64 * 1024 // 64KB chunks
    var remaining = size
    let pattern: [UInt8] = Array("SwiftMTP Benchmark Data Pattern 1234567890".utf8)

    try Data().write(to: url)
    let fileHandle = try FileHandle(forWritingTo: url)

    while remaining > 0 {
      let chunkSize = min(bufferSize, remaining)
      let chunk = Data(repeating: pattern, count: chunkSize / pattern.count + 1).prefix(chunkSize)
      try fileHandle.write(contentsOf: chunk)
      remaining -= chunkSize
    }

    try fileHandle.close()
  }
}
