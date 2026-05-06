// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPBroker

final class BrokerScaffoldTests: XCTestCase {
  func testBrokerInstantiates() async {
    let broker = Broker()
    let lookup = await broker.service(for: "nonexistent-device")
    XCTAssertNil(lookup)
  }

  func testDomainMappingRoundTrip() async {
    let broker = Broker()
    await broker.registerDomainMapping(deviceId: "dev-a", domainId: "domain-1")
    let domain = await broker.domainId(for: "dev-a")
    let device = await broker.deviceId(for: "domain-1")
    XCTAssertEqual(domain, "domain-1")
    XCTAssertEqual(device, "dev-a")
  }

  func testRemapEvictsStaleDomain() async {
    let broker = Broker()
    await broker.registerDomainMapping(deviceId: "dev-a", domainId: "domain-1")
    await broker.registerDomainMapping(deviceId: "dev-a", domainId: "domain-2")
    let oldReverse = await broker.deviceId(for: "domain-1")
    let newReverse = await broker.deviceId(for: "domain-2")
    XCTAssertNil(oldReverse)
    XCTAssertEqual(newReverse, "dev-a")
  }

  func testPriorityOrdering() {
    XCTAssertLessThan(BrokerOperationPriority.low, BrokerOperationPriority.medium)
    XCTAssertLessThan(BrokerOperationPriority.medium, BrokerOperationPriority.high)
    XCTAssertLessThan(BrokerOperationPriority.high, BrokerOperationPriority.critical)
  }

  func testDefaultDeadline() {
    let deadline = BrokerOperationDeadline.default
    XCTAssertGreaterThan(deadline.timeout, 0)
    XCTAssertGreaterThanOrEqual(deadline.maxRetries, 0)
  }
}
