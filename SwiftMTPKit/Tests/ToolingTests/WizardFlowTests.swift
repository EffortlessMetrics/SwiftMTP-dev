// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore
import SwiftMTPQuirks

// MARK: - Wizard Device Class Inference Tests

/// Tests for the wizard's device class inference logic and configuration output.
/// WizardCommand.inferDeviceClass is private, so we test via the same keyword logic.
final class WizardDeviceClassInferenceTests: XCTestCase {
  /// Mirrors WizardCommand.inferDeviceClass logic for testing
  private func inferDeviceClass(manufacturer: String, model: String) -> String {
    let combined = (manufacturer + " " + model).lowercased()
    let ptpKeywords = [
      "canon", "nikon", "sony", "fuji", "olympus", "panasonic", "pentax", "ricoh",
      "leica", "sigma", "hasselblad", "gopro", "dji", "camera", "dslr", "mirrorless",
    ]
    for kw in ptpKeywords where combined.contains(kw) {
      return "ptp"
    }
    return "android"
  }

  func testCanonDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Canon", model: "EOS R5"), "ptp")
  }

  func testNikonDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Nikon", model: "Z6 III"), "ptp")
  }

  func testSonyDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Sony", model: "Alpha 7R V"), "ptp")
  }

  func testFujiDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Fuji", model: "X-T5"), "ptp")
  }

  func testGoProDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "GoPro", model: "Hero 12"), "ptp")
  }

  func testDJIDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "DJI", model: "Osmo Action 4"), "ptp")
  }

  func testGenericCameraDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Unknown", model: "Digital Camera"), "ptp")
  }

  func testDSLRKeywordDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Generic", model: "DSLR Pro"), "ptp")
  }

  func testMirrorlessKeywordDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Brand", model: "Mirrorless X"), "ptp")
  }

  func testSamsungPhoneDetectedAsAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Samsung", model: "Galaxy S24"), "android")
  }

  func testGooglePixelDetectedAsAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Google", model: "Pixel 7"), "android")
  }

  func testXiaomiDetectedAsAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Xiaomi", model: "Mi Note 2"), "android")
  }

  func testOnePlusDetectedAsAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "OnePlus", model: "3T"), "android")
  }

  func testEmptyManufacturerAndModelDetectedAsAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "", model: ""), "android")
  }

  func testCaseInsensitiveDetection() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "CANON", model: "eos r5"), "ptp")
    XCTAssertEqual(inferDeviceClass(manufacturer: "nikon", model: "Z9"), "ptp")
  }

  func testOlympusDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Olympus", model: "OM-1"), "ptp")
  }

  func testPanasonicDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Panasonic", model: "Lumix S5"), "ptp")
  }

  func testPentaxDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Pentax", model: "K-3 III"), "ptp")
  }

  func testHasselbladDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Hasselblad", model: "X2D"), "ptp")
  }

  func testLeicaDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Leica", model: "Q3"), "ptp")
  }

  func testSigmaDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Sigma", model: "fp L"), "ptp")
  }

  func testRicohDetectedAsPTP() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Ricoh", model: "GR IIIx"), "ptp")
  }
}

// MARK: - Wizard Timeout Parsing Tests

final class WizardTimeoutParsingTests: XCTestCase {
  /// Mirrors the timeout parsing logic in WizardCommand.run
  private func parseTimeout(args: [String]) -> Int {
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
      let t = Int(args[idx + 1])
    {
      return t
    }
    return 60
  }

  func testDefaultTimeoutIs60() {
    XCTAssertEqual(parseTimeout(args: []), 60)
  }

  func testCustomTimeout() {
    XCTAssertEqual(parseTimeout(args: ["--timeout", "30"]), 30)
  }

  func testTimeoutWithOtherArgs() {
    XCTAssertEqual(parseTimeout(args: ["--safe", "--timeout", "120", "--help"]), 120)
  }

  func testTimeoutWithNonNumericValue() {
    XCTAssertEqual(parseTimeout(args: ["--timeout", "abc"]), 60)
  }

  func testTimeoutMissingValue() {
    XCTAssertEqual(parseTimeout(args: ["--timeout"]), 60)
  }

  func testTimeoutZero() {
    XCTAssertEqual(parseTimeout(args: ["--timeout", "0"]), 0)
  }

  func testTimeoutNegative() {
    XCTAssertEqual(parseTimeout(args: ["--timeout", "-5"]), -5)
  }
}

// MARK: - Wizard Help Detection Tests

final class WizardHelpDetectionTests: XCTestCase {
  /// Mirrors the help detection logic in WizardCommand.run
  private func isHelpRequested(args: [String]) -> Bool {
    args.contains("--help") || args.contains("-h")
  }

  func testHelpLongFlag() {
    XCTAssertTrue(isHelpRequested(args: ["--help"]))
  }

  func testHelpShortFlag() {
    XCTAssertTrue(isHelpRequested(args: ["-h"]))
  }

  func testNoHelpFlag() {
    XCTAssertFalse(isHelpRequested(args: ["--safe", "--timeout", "30"]))
  }

  func testHelpWithOtherArgs() {
    XCTAssertTrue(isHelpRequested(args: ["--safe", "--help"]))
  }

  func testEmptyArgs() {
    XCTAssertFalse(isHelpRequested(args: []))
  }
}

// MARK: - Wizard Configuration Output Tests

@MainActor
final class WizardConfigurationOutputTests: XCTestCase {
  func testCollectFlagsSafeMode() {
    let flags = CollectCommand.CollectFlags(
      strict: true,
      safe: true,
      runBench: [],
      json: false,
      noninteractive: true,
      bundlePath: nil,
      vid: 0x18D1, pid: 0x4EE1, bus: nil, address: nil)
    XCTAssertTrue(flags.safe)
    XCTAssertTrue(flags.strict)
    XCTAssertTrue(flags.noninteractive)
    XCTAssertTrue(flags.runBench.isEmpty)
    XCTAssertEqual(flags.vid, 0x18D1)
    XCTAssertEqual(flags.pid, 0x4EE1)
  }

  func testCollectFlagsWithBusAddress() {
    let flags = CollectCommand.CollectFlags(
      strict: true,
      safe: true,
      runBench: [],
      json: false,
      noninteractive: true,
      bundlePath: nil,
      vid: 0x2717, pid: 0xFF40, bus: 2, address: 5)
    XCTAssertEqual(flags.bus, 2)
    XCTAssertEqual(flags.address, 5)
  }

  func testCollectFlagsWithBundlePath() {
    let flags = CollectCommand.CollectFlags(
      strict: true,
      safe: true,
      runBench: [],
      json: false,
      noninteractive: true,
      bundlePath: "/tmp/wizard-bundle",
      vid: nil, pid: nil, bus: nil, address: nil)
    XCTAssertEqual(flags.bundlePath, "/tmp/wizard-bundle")
    XCTAssertNil(flags.vid)
  }

  func testCollectFlagsNoninteractiveForWizard() {
    // Wizard always sets noninteractive to true for automated collection
    let flags = CollectCommand.CollectFlags(
      strict: true,
      safe: true,
      runBench: [],
      json: false,
      noninteractive: true,
      bundlePath: nil,
      vid: nil, pid: nil, bus: nil, address: nil)
    XCTAssertTrue(flags.noninteractive)
  }
}

// MARK: - Wizard Input Validation Tests

final class WizardInputValidationTests: XCTestCase {
  /// Mirrors the device selection validation in WizardCommand
  private func isValidSelection(_ input: String?, deviceCount: Int) -> Bool {
    guard let line = input, let choice = Int(line) else { return false }
    return choice >= 1 && choice <= deviceCount
  }

  func testValidSelectionFirst() {
    XCTAssertTrue(isValidSelection("1", deviceCount: 3))
  }

  func testValidSelectionLast() {
    XCTAssertTrue(isValidSelection("3", deviceCount: 3))
  }

  func testInvalidSelectionZero() {
    XCTAssertFalse(isValidSelection("0", deviceCount: 3))
  }

  func testInvalidSelectionOverflow() {
    XCTAssertFalse(isValidSelection("4", deviceCount: 3))
  }

  func testInvalidSelectionNonNumeric() {
    XCTAssertFalse(isValidSelection("abc", deviceCount: 3))
  }

  func testInvalidSelectionEmpty() {
    XCTAssertFalse(isValidSelection("", deviceCount: 3))
  }

  func testInvalidSelectionNil() {
    XCTAssertFalse(isValidSelection(nil, deviceCount: 3))
  }

  func testValidSelectionSingleDevice() {
    XCTAssertTrue(isValidSelection("1", deviceCount: 1))
  }

  func testNegativeSelection() {
    XCTAssertFalse(isValidSelection("-1", deviceCount: 3))
  }
}

// MARK: - Wizard VID/PID Formatting Tests

final class WizardVIDPIDFormattingTests: XCTestCase {
  func testFormatVIDPIDHexOutput() {
    let vid: UInt16 = 0x18D1
    let pid: UInt16 = 0x4EE1
    let vidStr = String(format: "0x%04x", vid)
    let pidStr = String(format: "0x%04x", pid)
    XCTAssertEqual(vidStr, "0x18d1")
    XCTAssertEqual(pidStr, "0x4ee1")
  }

  func testFormatBusAddressOutput() {
    let bus: UInt8 = 2
    let address: UInt8 = 5
    let formatted = String(format: "%d:%d", bus, address)
    XCTAssertEqual(formatted, "2:5")
  }

  func testFormatZeroPaddedVID() {
    let vid: UInt16 = 0x001A
    let vidStr = String(format: "0x%04x", vid)
    XCTAssertEqual(vidStr, "0x001a")
  }

  func testAddDeviceCommandString() {
    let vid: UInt16 = 0x04A9
    let pid: UInt16 = 0x3139
    let vidStr = String(format: "0x%04x", vid)
    let pidStr = String(format: "0x%04x", pid)
    let cmd =
      "swiftmtp add-device --vid \(vidStr) --pid \(pidStr) --class ptp --name \"Canon EOS R5\""
    XCTAssertTrue(cmd.contains("--vid 0x04a9"))
    XCTAssertTrue(cmd.contains("--pid 0x3139"))
    XCTAssertTrue(cmd.contains("--class ptp"))
  }
}

// MARK: - Wizard Privacy Confirmation Tests

final class WizardPrivacyConfirmationTests: XCTestCase {
  /// Mirrors the privacy confirmation logic in WizardCommand
  private func isAborted(_ answer: String?) -> Bool {
    guard let a = answer?.lowercased() else { return false }
    return a == "n" || a == "no"
  }

  func testConfirmationYes() {
    XCTAssertFalse(isAborted("y"))
  }

  func testConfirmationYesUppercase() {
    XCTAssertFalse(isAborted("Y"))
  }

  func testConfirmationEmpty() {
    XCTAssertFalse(isAborted(""))
  }

  func testConfirmationNil() {
    XCTAssertFalse(isAborted(nil))
  }

  func testCancellationN() {
    XCTAssertTrue(isAborted("n"))
  }

  func testCancellationNo() {
    XCTAssertTrue(isAborted("no"))
  }

  func testCancellationNoUppercase() {
    XCTAssertTrue(isAborted("NO"))
  }

  func testCancellationNMixed() {
    XCTAssertTrue(isAborted("No"))
  }

  func testOtherInputNotAborted() {
    XCTAssertFalse(isAborted("maybe"))
  }
}

// MARK: - Wizard Action Choice Tests

final class WizardActionChoiceTests: XCTestCase {
  /// Mirrors the action choice logic in WizardCommand
  private func actionForChoice(_ input: String?) -> String {
    let choice = input?.trimmingCharacters(in: .whitespaces) ?? "3"
    switch choice {
    case "1": return "submit"
    case "2": return "finder"
    default: return "print"
    }
  }

  func testChoice1IsSubmit() {
    XCTAssertEqual(actionForChoice("1"), "submit")
  }

  func testChoice2IsFinder() {
    XCTAssertEqual(actionForChoice("2"), "finder")
  }

  func testChoice3IsPrint() {
    XCTAssertEqual(actionForChoice("3"), "print")
  }

  func testInvalidChoiceDefaultsToPrint() {
    XCTAssertEqual(actionForChoice("99"), "print")
  }

  func testEmptyChoiceDefaultsToPrint() {
    XCTAssertEqual(actionForChoice(""), "print")
  }

  func testNilChoiceDefaultsToPrint() {
    XCTAssertEqual(actionForChoice(nil), "print")
  }

  func testWhitespaceChoice() {
    XCTAssertEqual(actionForChoice("  1  "), "submit")
  }
}
