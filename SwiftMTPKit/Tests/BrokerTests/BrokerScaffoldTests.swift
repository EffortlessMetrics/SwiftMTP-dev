// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPBroker

final class BrokerScaffoldTests: XCTestCase {
  func testBrokerInstantiates() async {
    let registry = DeviceServiceRegistry()
    let lookup = await registry.service(for: MTPDeviceID(raw: "nonexistent-device"))
    XCTAssertNil(lookup)
  }

  func testDomainMappingRoundTrip() async {
    let registry = DeviceServiceRegistry()
    let devA = MTPDeviceID(raw: "dev-a")
    await registry.registerDomainMapping(deviceId: devA, domainId: "domain-1")
    let domain = await registry.domainId(for: devA)
    let device = await registry.deviceId(for: "domain-1")
    XCTAssertEqual(domain, "domain-1")
    XCTAssertEqual(device, devA)
  }

  func testRemapEvictsStaleDomain() async {
    let registry = DeviceServiceRegistry()
    let devA = MTPDeviceID(raw: "dev-a")
    await registry.registerDomainMapping(deviceId: devA, domainId: "domain-1")
    await registry.registerDomainMapping(deviceId: devA, domainId: "domain-2")
    let oldReverse = await registry.deviceId(for: "domain-1")
    let newReverse = await registry.deviceId(for: "domain-2")
    XCTAssertNil(oldReverse)
    XCTAssertEqual(newReverse, devA)
  }

  func testPriorityOrdering() {
    XCTAssertLessThan(DeviceOperationPriority.low, DeviceOperationPriority.medium)
    XCTAssertLessThan(DeviceOperationPriority.medium, DeviceOperationPriority.high)
    XCTAssertLessThan(DeviceOperationPriority.high, DeviceOperationPriority.critical)
  }

  func testDefaultDeadline() {
    let deadline = OperationDeadline.default
    XCTAssertGreaterThan(deadline.timeout, 0)
    XCTAssertGreaterThanOrEqual(deadline.maxRetries, 0)
  }
}
