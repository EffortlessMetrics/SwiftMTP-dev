// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

@_exported import SwiftMTPCore

// SwiftMTPBroker hosts session ownership, the device-service registry,
// scheduling, and orchestrator wiring. The migration plan and rationale
// are captured in Docs/ROADMAP.broker-architecture.md.
//
// The module re-exports SwiftMTPCore so a single `import SwiftMTPBroker`
// is sufficient at call sites — broker types (DeviceService,
// DeviceServiceRegistry, etc.) and Core types (MTPDevice, MTPError, etc.)
// are all in scope without a second import.
