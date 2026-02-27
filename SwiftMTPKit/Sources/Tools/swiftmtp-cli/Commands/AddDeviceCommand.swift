// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Generates a well-formed quirk entry template for a new device.
@MainActor
struct AddDeviceCommand {

  enum DeviceClass: String {
    case android
    case ptp
    case unknown
  }

  static func printHelp() {
    print("Usage: swiftmtp add-device --vid 0x1234 --pid 0x5678 --name \"Device Name\" [options]")
    print("")
    print("Generate a quirk entry template for a new device.")
    print("")
    print("Required:")
    print("  --vid <hex>       USB Vendor ID (e.g. 0x18d1)")
    print("  --pid <hex>       USB Product ID (e.g. 0x4ee1)")
    print("  --name <string>   Human-readable device name")
    print("")
    print("Optional:")
    print("  --class <type>    Device class: android (default), ptp, unknown")
    print("  --brand <string>  Brand/manufacturer name (used in quirk ID)")
    print("  --model <string>  Model name (used in quirk ID)")
    print("  --help, -h        Show this help")
  }

  static func run(flags: CLIFlags, args: [String]) {
    if args.contains("--help") || args.contains("-h") {
      printHelp()
      return
    }

    // Parse arguments
    // NOTE: --vid/--pid may be pre-consumed by the top-level CLI parser into flags
    var vid: String? = flags.targetVID
    var pid: String? = flags.targetPID
    var name: String?
    var deviceClass: DeviceClass = .android
    var brand: String?
    var model: String?

    var i = 0
    while i < args.count {
      switch args[i] {
      case "--vid":
        if i + 1 < args.count { vid = args[i + 1]; i += 1 }
      case "--pid":
        if i + 1 < args.count { pid = args[i + 1]; i += 1 }
      case "--name":
        if i + 1 < args.count { name = args[i + 1]; i += 1 }
      case "--class":
        if i + 1 < args.count {
          deviceClass = DeviceClass(rawValue: args[i + 1]) ?? .android
          i += 1
        }
      case "--brand":
        if i + 1 < args.count { brand = args[i + 1]; i += 1 }
      case "--model":
        if i + 1 < args.count { model = args[i + 1]; i += 1 }
      default:
        // handle --key=value forms
        let arg = args[i]
        if arg.hasPrefix("--vid=") { vid = String(arg.dropFirst(6)) }
        else if arg.hasPrefix("--pid=") { pid = String(arg.dropFirst(6)) }
        else if arg.hasPrefix("--name=") { name = String(arg.dropFirst(7)) }
        else if arg.hasPrefix("--class=") {
          deviceClass = DeviceClass(rawValue: String(arg.dropFirst(8))) ?? .android
        } else if arg.hasPrefix("--brand=") { brand = String(arg.dropFirst(8)) }
        else if arg.hasPrefix("--model=") { model = String(arg.dropFirst(8)) }
      }
      i += 1
    }

    guard let vid = vid, let pid = pid, let name = name else {
      print("❌ --vid, --pid, and --name are required.")
      print("")
      printHelp()
      return
    }

    // Normalise VID/PID to lowercase hex with 0x prefix
    let normVID = normalizeHex(vid)
    let normPID = normalizeHex(pid)

    // Build quirk ID
    let brandSlug = slugify(brand ?? inferBrand(name: name))
    let modelSlug = slugify(model ?? inferModel(name: name))
    let pidShort = normPID.replacingOccurrences(of: "0x", with: "")
    let quirkyID = [brandSlug, modelSlug, pidShort]
      .filter { !$0.isEmpty }
      .joined(separator: "-")

    // Interface class settings
    let ifaceClass: String
    let ifaceSubclass: String
    let ifaceProtocol: String
    let supportsGetObjectPropList: Bool
    let requiresKernelDetach: Bool

    switch deviceClass {
    case .ptp:
      ifaceClass = "0x06"
      ifaceSubclass = "0x01"
      ifaceProtocol = "0x01"
      supportsGetObjectPropList = true
      requiresKernelDetach = false
    case .android, .unknown:
      ifaceClass = "0xff"
      ifaceSubclass = "0xff"
      ifaceProtocol = "0x00"
      supportsGetObjectPropList = false
      requiresKernelDetach = true
    }

    let json = """
      {
        "id": "\(quirkyID)",
        "match": {
          "vid": "\(normVID)",
          "pid": "\(normPID)",
          "iface": {
            "class": "\(ifaceClass)",
            "subclass": "\(ifaceSubclass)",
            "protocol": "\(ifaceProtocol)"
          }
        },
        "ops": {
          "supportsGetObjectPropList": \(supportsGetObjectPropList),
          "requiresKernelDetach": \(requiresKernelDetach),
          "ioTimeoutMs": 10000
        },
        "governance": {
          "status": "proposed",
          "evidenceRequired": [],
          "submittedBy": "community"
        },
        "provenance": {
          "source": "user-submission",
          "sourceRef": "swiftmtp-add-device",
          "notes": "\(name) — submitted via swiftmtp add-device"
        }
      }
      """

    print(json)
    print("")
    print("--- How to submit ---")
    print("1. Test this profile with your device")
    print("2. Add it to Specs/quirks.json")
    print("3. Copy to SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json")
    print("4. Run: ./scripts/validate-quirks.sh")
    print("5. Submit a PR — see Docs/DeviceSubmission.md")
  }

  // MARK: - Helpers

  private static func normalizeHex(_ value: String) -> String {
    let stripped = value.lowercased()
      .replacingOccurrences(of: "0x", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let intVal = UInt64(stripped, radix: 16) else { return value.lowercased() }
    return String(format: "0x%04x", intVal)
  }

  private static func slugify(_ input: String) -> String {
    input
      .lowercased()
      .components(separatedBy: .alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "-")
  }

  /// Attempt to extract a brand from a device name (first word).
  private static func inferBrand(name: String) -> String {
    name.components(separatedBy: .whitespaces).first ?? name
  }

  /// Attempt to extract a model from a device name (remaining words).
  private static func inferModel(name: String) -> String {
    let parts = name.components(separatedBy: .whitespaces)
    guard parts.count > 1 else { return "" }
    return parts.dropFirst().joined(separator: " ")
  }
}
