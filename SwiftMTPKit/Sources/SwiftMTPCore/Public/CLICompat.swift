// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCLI

// MARK: - Exit helpers
@available(*, deprecated, message: "Use SwiftMTPCLI.ExitCode instead. This shim is a compatibility layer.")
public typealias ExitCode = SwiftMTPCLI.ExitCode

@available(*, deprecated, message: "Use SwiftMTPCLI.exitNow(_:) instead. This shim is a compatibility layer.")
public func exitNow(_ code: ExitCode) -> Never {
  SwiftMTPCLI.exitNow(code)
}

// MARK: - JSON I/O
@available(*, deprecated, message: "Use SwiftMTPCLI.CLIErrorEnvelope instead. This shim is a compatibility layer.")
public typealias CLIErrorEnvelope = SwiftMTPCLI.CLIErrorEnvelope

@available(*, deprecated, message: "Use SwiftMTPCLI.printJSON(_:) instead. This shim is a compatibility layer.")
public func printJSON<T: Encodable>(_ value: T) {
  SwiftMTPCLI.printJSON(value)
}

@available(*, deprecated, message: "Use SwiftMTPCLI.printJSONErrorAndExit(_:code:details:mode:) instead. This shim is a compatibility layer.")
public func printJSONErrorAndExit(
  _ message: String,
  code: ExitCode = .software,
  details: [String:String]? = nil,
  mode: String? = nil
) -> Never {
  SwiftMTPCLI.printJSONErrorAndExit(message, code: code, details: details, mode: mode)
}

// MARK: - Filter helpers
@available(*, deprecated, message: "Use SwiftMTPCLI.DeviceFilter instead. This shim is a compatibility layer.")
public typealias DeviceFilter = SwiftMTPCLI.DeviceFilter

@available(*, deprecated, message: "Use SwiftMTPCLI.parseUSBIdentifier(_:) instead. This shim is a compatibility layer.")
public func parseUSBIdentifier(_ raw: String?) -> UInt16? {
  SwiftMTPCLI.parseUSBIdentifier(raw)
}

@available(*, deprecated, message: "Use SwiftMTPCLI.DeviceFilterParse instead. This shim is a compatibility layer.")
public typealias DeviceFilterParse = SwiftMTPCLI.DeviceFilterParse

@available(*, deprecated, message: "Use SwiftMTPCLI.SelectionOutcome instead. This shim is a compatibility layer.")
public typealias SelectionOutcome = SwiftMTPCLI.SelectionOutcome<MTPDeviceSummary>

@available(*, deprecated, message: "Use SwiftMTPCLI.selectDevice(_:filter:noninteractive:) instead. This shim is a compatibility layer.")
public func selectDevice(
  _ devices: [MTPDeviceSummary],
  filter: DeviceFilter,
  noninteractive: Bool
) -> SelectionOutcome {
  SwiftMTPCLI.selectDevice(devices, filter: filter, noninteractive: noninteractive)
}

// MARK: - Spinner
@available(*, deprecated, message: "Use SwiftMTPCLI.Spinner instead. This shim is a compatibility layer.")
public typealias Spinner = SwiftMTPCLI.Spinner

extension MTPDeviceSummary: SwiftMTPCLI.DeviceFilterCandidate {}
