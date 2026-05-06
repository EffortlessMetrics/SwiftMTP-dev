// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore

// SwiftMTPBroker is the future home of session ownership, the device-service
// registry, scheduling, and orchestrator wiring. The migration plan is captured
// in Docs/ROADMAP.broker-architecture.md.
//
// Today the implementations still live in SwiftMTPCore. This module re-exports
// them under broker-flavored names so call sites can begin importing
// SwiftMTPBroker without waiting for the source move. When the implementations
// migrate here, these typealiases will flip direction without breaking callers.

public typealias Broker = DeviceServiceRegistry
public typealias BrokerDeviceService = DeviceService
public typealias BrokerOperationHandle = DeviceOperationHandle
public typealias BrokerOperationPriority = DeviceOperationPriority
public typealias BrokerOperationDeadline = OperationDeadline
