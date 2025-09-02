import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Foundation

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
    print("")
    print("COMMANDS:")
    print("  pull <handle> <output-file>        Download file by handle")
    print("  push <parent-handle> <input-file>  Upload file to parent directory")
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
}
