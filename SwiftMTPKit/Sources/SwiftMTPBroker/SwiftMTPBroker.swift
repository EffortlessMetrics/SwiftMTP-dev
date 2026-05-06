// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

@_exported import SwiftMTPCore

// SwiftMTPBroker is the future home of session ownership, the device-service
// registry, scheduling, and orchestrator wiring. The migration plan is captured
// in Docs/ROADMAP.broker-architecture.md.
//
// Today the implementations still live in SwiftMTPCore. This module re-exports
// SwiftMTPCore's surface (so `import SwiftMTPBroker` is sufficient at call
// sites — no second `import SwiftMTPCore` needed to use methods on aliased
// types) and provides broker-flavored names for the primitives that will
// physically migrate here next. When the source move lands, these typealiases
// are replaced by the real definitions and the @_exported re-export is
// dropped (callers continue using `Broker`, `BrokerDeviceService`, etc.).

public typealias Broker = DeviceServiceRegistry
public typealias BrokerDeviceService = DeviceService
public typealias BrokerOperationHandle = DeviceOperationHandle
public typealias BrokerOperationPriority = DeviceOperationPriority
public typealias BrokerOperationDeadline = OperationDeadline
