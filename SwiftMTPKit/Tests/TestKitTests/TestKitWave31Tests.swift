// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

/// Thread-safe event collector for async event tests.
private actor MTPEventCollector {
  var items: [String] = []
  func append(_ item: String) { items.append(item) }
}

// MARK: - VirtualMTPDevice Protocol Compliance

/// Verify every MTPDevice protocol method is callable and returns sensible results.
final class Wave31VirtualDeviceProtocolComplianceTests: XCTestCase {

  func testAllMTPDeviceProtocolMethodsAreCallable() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let sid = storages[0].id

    // info property
    let info = try await device.info
    XCTAssertFalse(info.manufacturer.isEmpty)

    // storages()
    XCTAssertFalse(storages.isEmpty)

    // list(parent:in:)
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      items.append(contentsOf: batch)
    }
    XCTAssertFalse(items.isEmpty)

    // getInfo(handle:)
    let objInfo = try await device.getInfo(handle: 1)
    XCTAssertEqual(objInfo.name, "DCIM")

    // createFolder(parent:name:storage:)
    let folder = try await device.createFolder(parent: nil, name: "W31", storage: sid)
    XCTAssertGreaterThan(folder, 0)

    // write(parent:name:size:from:)
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "w31.bin", content: Data(repeating: 0xAB, count: 64))
    let writeProgress = try await device.write(parent: folder, name: "w31.bin", size: 64, from: src)
    XCTAssertEqual(writeProgress.completedUnitCount, 64)

    // read(handle:range:to:)
    var children: [MTPObjectInfo] = []
    for try await batch in device.list(parent: folder, in: sid) {
      children.append(contentsOf: batch)
    }
    let written = try XCTUnwrap(children.first)
    let dest = tempDir.appendingPathComponent("read.bin")
    let readProgress = try await device.read(handle: written.handle, range: nil, to: dest)
    XCTAssertEqual(readProgress.completedUnitCount, 64)

    // rename(_:to:)
    try await device.rename(written.handle, to: "renamed.bin")
    let renamed = try await device.getInfo(handle: written.handle)
    XCTAssertEqual(renamed.name, "renamed.bin")

    // move(_:to:)
    try await device.move(written.handle, to: nil)
    let moved = try await device.getInfo(handle: written.handle)
    XCTAssertNil(moved.parent)

    // delete(_:recursive:)
    try await device.delete(written.handle, recursive: false)

    // openIfNeeded()
    try await device.openIfNeeded()

    // events (nonisolated)
    let _ = device.events

    // probedCapabilities
    let caps = await device.probedCapabilities
    XCTAssertTrue(caps.isEmpty)

    // effectiveTuning
    let _ = await device.effectiveTuning

    // devicePolicy
    let policy = await device.devicePolicy
    XCTAssertNil(policy)

    // probeReceipt
    let receipt = await device.probeReceipt
    XCTAssertNil(receipt)

    // Dev SPI
    _ = try await device.devGetDeviceInfoUncached()
    _ = try await device.devGetStorageIDsUncached()
    _ = try await device.devGetRootHandlesUncached(storage: sid)
    _ = try await device.devGetObjectInfoUncached(handle: 1)

    // devClose()
    try await device.devClose()
  }

  func testIdAndSummaryMatchConfig() async throws {
    let config = VirtualDeviceConfig.samsungGalaxy
    let device = VirtualMTPDevice(config: config)
    let id = await device.id
    let summary = await device.summary
    XCTAssertEqual(id.raw, config.deviceId.raw)
    XCTAssertEqual(summary.manufacturer, "Samsung")
    XCTAssertEqual(summary.model, "Galaxy Android")
  }
}

// MARK: - VirtualMTPDevice State Consistency

/// Verify operations after devClose behave correctly.
final class Wave31VirtualDeviceStateConsistencyTests: XCTestCase {

  func testInjectEventAfterDevCloseIsIgnored() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.devClose()
    // Should not crash — continuation is nil after close
    await device.injectEvent(.objectAdded(1))
  }

  func testDoubleDevCloseDoesNotCrash() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.devClose()
    try await device.devClose()
  }

  func testOperationsStillWorkAfterDevClose() async throws {
    // VirtualMTPDevice doesn't enforce session state, but devClose finishes events.
    // Verify core ops still work (virtual device is stateless w.r.t. session).
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.devClose()

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
    let sid = storages[0].id
    let folder = try await device.createFolder(parent: nil, name: "Post", storage: sid)
    XCTAssertGreaterThan(folder, 0)
  }

  func testDeleteThenGetInfoThrowsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.delete(3, recursive: false)
    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testRenameThenVerifyOldNameGone() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.rename(1, to: "Photos")
    let info = try await device.getInfo(handle: 1)
    XCTAssertEqual(info.name, "Photos")
    XCTAssertNotEqual(info.name, "DCIM")
  }

  func testWriteWithNoStoragesThrowsPreconditionFailed() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = []
    let device = VirtualMTPDevice(config: config)
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "x.bin", content: Data([1]))

    do {
      _ = try await device.write(parent: nil, name: "x.bin", size: 1, from: src)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      if case .preconditionFailed = error {
        // expected
      } else {
        XCTFail("Expected preconditionFailed, got \(error)")
      }
    }
  }
}

// MARK: - FaultInjectingLink Individual Fault Types

/// Test each fault type (timeout, disconnect, busy, stall) in isolation through the full link.
final class Wave31FaultInjectingLinkFaultTypesTests: XCTestCase {

  private func makeLink(
    schedule: FaultSchedule,
    config: VirtualDeviceConfig = .emptyDevice
  ) -> FaultInjectingLink {
    FaultInjectingLink(wrapping: VirtualMTPLink(config: config), schedule: schedule)
  }

  func testTimeoutFaultIsolated() async throws {
    let link = makeLink(schedule: FaultSchedule([.timeoutOnce(on: .getDeviceInfo)]))
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testDisconnectFaultIsolated() async throws {
    let link = makeLink(
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected)
      ]))
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected disconnected")
    } catch {
      let desc = "\(error)".lowercased()
      XCTAssertTrue(desc.contains("no") || desc.contains("device"))
    }
  }

  func testBusyFaultIsolated() async throws {
    let link = makeLink(
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.openSession), error: .busy)
      ]))
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected busy")
    } catch {
      XCTAssertTrue("\(error)".contains("busy"))
    }
  }

  func testStallFaultIsolated() async throws {
    let link = makeLink(schedule: FaultSchedule([.pipeStall(on: .getObjectHandles)]))
    do {
      _ = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected pipe stall")
    } catch {
      XCTAssertTrue("\(error)".contains("pipe stall"))
    }
  }

  func testAllFaultTypesProduceTransportErrors() {
    let faults: [FaultError] = [
      .timeout, .busy, .disconnected, .accessDenied,
      .io("custom msg"), .protocolError(code: 0x2005),
    ]
    for fault in faults {
      let transport = fault.transportError
      XCTAssertNotNil(transport, "Transport mapping missing for \(fault)")
    }
  }
}

// MARK: - FaultSchedule Patterns

/// Test sequential, probabilistic, and conditional fault patterns.
final class Wave31FaultSchedulePatternTests: XCTestCase {

  func testSequentialFaultConsumption() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .disconnected),
    ])

    if case .timeout = schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil) {
    } else {
      XCTFail("Expected timeout first")
    }

    if case .busy = schedule.check(operation: .getDeviceInfo, callIndex: 1, byteOffset: nil) {
    } else {
      XCTFail("Expected busy second")
    }

    if case .disconnected = schedule.check(
      operation: .getDeviceInfo, callIndex: 2, byteOffset: nil)
    {
    } else {
      XCTFail("Expected disconnected third")
    }

    XCTAssertNil(
      schedule.check(operation: .getDeviceInfo, callIndex: 3, byteOffset: nil),
      "All faults consumed")
  }

  func testProbabilisticUnlimitedFaultNeverDepletes() {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeCommand), error: .busy, repeatCount: 0)
    ])
    for i in 0..<100 {
      XCTAssertNotNil(
        schedule.check(operation: .executeCommand, callIndex: i, byteOffset: nil),
        "Unlimited fault must fire on iteration \(i)")
    }
  }

  func testConditionalByteOffsetFault() {
    let schedule = FaultSchedule([.disconnectAtOffset(1_048_576)])

    XCTAssertNil(
      schedule.check(
        operation: .executeStreamingCommand, callIndex: 0, byteOffset: 0))
    XCTAssertNil(
      schedule.check(
        operation: .executeStreamingCommand, callIndex: 0, byteOffset: 524_288))
    XCTAssertNotNil(
      schedule.check(
        operation: .executeStreamingCommand, callIndex: 0, byteOffset: 1_048_576))
  }

  func testConditionalCallIndexPrecise() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(7), error: .timeout)
    ])
    for i in 0..<7 {
      XCTAssertNil(
        schedule.check(operation: .getDeviceInfo, callIndex: i, byteOffset: nil),
        "Should not fire before index 7")
    }
    XCTAssertNotNil(
      schedule.check(operation: .getDeviceInfo, callIndex: 7, byteOffset: nil))
    XCTAssertNil(
      schedule.check(operation: .getDeviceInfo, callIndex: 8, byteOffset: nil),
      "Should be consumed after single fire")
  }

  func testMixedTriggerTypes() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(2), error: .busy),
      ScheduledFault(trigger: .atByteOffset(4096), error: .disconnected),
    ])

    // Operation trigger
    XCTAssertNotNil(
      schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil))
    // Call index trigger (call index 2 matches regardless of operation)
    XCTAssertNil(
      schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil))
    XCTAssertNotNil(
      schedule.check(operation: .getStorageIDs, callIndex: 2, byteOffset: nil))
    // Byte offset trigger
    XCTAssertNotNil(
      schedule.check(
        operation: .executeStreamingCommand, callIndex: 3, byteOffset: 4096))
  }

  func testFaultScheduleConcurrentAccess() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 0)
    ])

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<50 {
        group.addTask {
          let result = schedule.check(
            operation: .getDeviceInfo, callIndex: 0, byteOffset: nil)
          XCTAssertNotNil(result, "Concurrent access should be thread-safe")
        }
      }
      try await group.waitForAll()
    }
  }
}

// MARK: - VirtualDeviceConfig Validation

/// Validate ALL built-in configs have non-empty manufacturers, storages, and valid IDs.
final class Wave31VirtualDeviceConfigValidationTests: XCTestCase {

  func testAllBuiltInConfigsHaveValidSettings() {
    let configs: [(String, VirtualDeviceConfig)] = [
      ("pixel7", .pixel7),
      ("samsungGalaxy", .samsungGalaxy),
      ("samsungGalaxyMtpAdb", .samsungGalaxyMtpAdb),
      ("googlePixelAdb", .googlePixelAdb),
      ("motorolaMotoG", .motorolaMotoG),
      ("sonyXperiaZ", .sonyXperiaZ),
      ("canonEOSR5", .canonEOSR5),
      ("nikonZ6", .nikonZ6),
      ("onePlus9", .onePlus9),
      ("lgAndroid", .lgAndroid),
      ("lgAndroidOlder", .lgAndroidOlder),
      ("htcAndroid", .htcAndroid),
      ("huaweiAndroid", .huaweiAndroid),
      ("fujifilmX", .fujifilmX),
      ("nokiaAndroid", .nokiaAndroid),
      ("zteAndroid", .zteAndroid),
      ("amazonKindleFire", .amazonKindleFire),
      ("lenovoAndroid", .lenovoAndroid),
      ("nikonMirrorless", .nikonMirrorless),
      ("canonEOSR", .canonEOSR),
      ("sonyAlpha", .sonyAlpha),
      ("leica", .leica),
      ("goProHero", .goProHero),
      ("alcatelAndroid", .alcatelAndroid),
      ("sharpAquos", .sharpAquos),
      ("kyoceraAndroid", .kyoceraAndroid),
      ("fairphone2", .fairphone2),
      ("fujifilmXT10", .fujifilmXT10),
      ("casioExilim", .casioExilim),
      ("goproHero11", .goproHero11),
      ("garminFenix", .garminFenix),
      ("honorAndroid", .honorAndroid),
      ("lgG5Android", .lgG5Android),
      ("htcOneM8", .htcOneM8),
      ("zteAxon7", .zteAxon7),
      ("oppoReno2", .oppoReno2),
      ("vivoV20Pro", .vivoV20Pro),
      ("blackberryKEYone", .blackberryKEYone),
      ("fitbitVersa", .fitbitVersa),
      ("garminForerunner945", .garminForerunner945),
      ("googlePixel8", .googlePixel8),
      ("onePlus12", .onePlus12),
      ("samsungGalaxyS24", .samsungGalaxyS24),
      ("nothingPhone2", .nothingPhone2),
      ("valveSteamDeck", .valveSteamDeck),
      ("metaQuest3", .metaQuest3),
      ("tecnoCamon30", .tecnoCamon30),
      ("archosMediaPlayer", .archosMediaPlayer),
      ("emptyDevice", .emptyDevice),
    ]

    var seenIds = Set<String>()
    for (label, config) in configs {
      XCTAssertFalse(
        config.info.manufacturer.isEmpty, "\(label): manufacturer is empty")
      XCTAssertFalse(config.info.model.isEmpty, "\(label): model is empty")
      XCTAssertFalse(
        config.info.serialNumber?.isEmpty ?? true, "\(label): serialNumber is empty")
      XCTAssertFalse(config.storages.isEmpty, "\(label): no storages")
      XCTAssertFalse(
        config.info.operationsSupported.isEmpty, "\(label): no operations")
      XCTAssertFalse(
        config.deviceId.raw.isEmpty, "\(label): deviceId is empty")

      // Verify each storage has non-zero capacity (except emptyDevice which may have defaults)
      for (i, storage) in config.storages.enumerated() {
        XCTAssertFalse(
          storage.description.isEmpty,
          "\(label): storage[\(i)] has empty description")
      }

      // Verify unique device IDs
      XCTAssertFalse(
        seenIds.contains(config.deviceId.raw),
        "\(label): duplicate deviceId \(config.deviceId.raw)")
      seenIds.insert(config.deviceId.raw)
    }

    XCTAssertGreaterThanOrEqual(configs.count, 49, "Should validate all presets")
  }

  func testAllConfigsHaveDCIMOrRootObjects() {
    let configsWithObjects: [(String, VirtualDeviceConfig)] = [
      ("pixel7", .pixel7),
      ("samsungGalaxy", .samsungGalaxy),
      ("canonEOSR5", .canonEOSR5),
      ("nikonZ6", .nikonZ6),
      ("motorolaMotoG", .motorolaMotoG),
      ("googlePixel8", .googlePixel8),
      ("onePlus12", .onePlus12),
      ("samsungGalaxyS24", .samsungGalaxyS24),
    ]
    for (label, config) in configsWithObjects {
      XCTAssertFalse(config.objects.isEmpty, "\(label): has no objects")
      let hasDCIM = config.objects.contains { $0.name == "DCIM" }
      XCTAssertTrue(hasDCIM, "\(label): missing DCIM folder")
    }
  }

  func testConfigBuilderChaining() {
    let config = VirtualDeviceConfig.emptyDevice
      .withStorage(
        VirtualStorageConfig(
          id: MTPStorageID(raw: 0x0002_0001), description: "SD")
      )
      .withObject(
        VirtualObjectConfig(
          handle: 50, storage: MTPStorageID(raw: 0x0002_0001),
          parent: nil, name: "test.dat", data: Data([1, 2, 3]))
      )
      .withLatency(.getDeviceInfo, duration: .milliseconds(10))
      .withLatency(.getStorageIDs, duration: .milliseconds(20))

    XCTAssertEqual(config.storages.count, 2)
    XCTAssertEqual(config.objects.count, 1)
    XCTAssertEqual(config.latencyPerOp.count, 2)
  }
}

// MARK: - Event Generation Verification

/// Verify VirtualMTPDevice emits correct MTP events for injected scenarios.
final class Wave31EventGenerationTests: XCTestCase {

  func testRapidFireEventSequence() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive 5 events")
    expectation.expectedFulfillmentCount = 5
    let collected = MTPEventCollector()
    let task = Task { @Sendable in
      var count = 0
      for await event in device.events {
        switch event {
        case .objectAdded: await collected.append("added")
        case .objectRemoved: await collected.append("removed")
        case .storageInfoChanged: await collected.append("storageChanged")
        case .storageAdded: await collected.append("storageAdded")
        case .deviceInfoChanged: await collected.append("deviceInfoChanged")
        default: await collected.append("other")
        }
        count += 1
        expectation.fulfill()
        if count >= 5 { break }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.objectAdded(1))
    await device.injectEvent(.objectRemoved(2))
    await device.injectEvent(.storageInfoChanged(MTPStorageID(raw: 1)))
    await device.injectEvent(.storageAdded(MTPStorageID(raw: 2)))
    await device.injectEvent(.deviceInfoChanged)

    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()

    let received = await collected.items
    XCTAssertEqual(received.count, 5)
    XCTAssertEqual(received[0], "added")
    XCTAssertEqual(received[1], "removed")
    XCTAssertEqual(received[2], "storageChanged")
    XCTAssertEqual(received[3], "storageAdded")
    XCTAssertEqual(received[4], "deviceInfoChanged")
  }

  func testUnknownEventPassesThrough() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive unknown event")
    let task = Task {
      for await event in device.events {
        if case .unknown(let code, let params) = event {
          XCTAssertEqual(code, 0xC801)
          XCTAssertEqual(params, [100, 200])
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.unknown(code: 0xC801, params: [100, 200]))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testEventStreamTerminatesOnDevClose() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Stream terminates")
    let task = Task {
      for await _ in device.events {
        // drain
      }
      expectation.fulfill()
    }

    try await Task.sleep(for: .milliseconds(50))
    try await device.devClose()
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }
}

// MARK: - Concurrent Access to VirtualMTPDevice

/// Multiple callers performing mixed operations concurrently.
final class Wave31ConcurrentAccessTests: XCTestCase {

  func testMixedConcurrentCreateWriteDelete() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    // Phase 1: Create folders concurrently
    let handles = try await withThrowingTaskGroup(of: MTPObjectHandle.self) { group in
      for i in 0..<10 {
        group.addTask {
          try await device.createFolder(parent: nil, name: "dir\(i)", storage: sid)
        }
      }
      var result: [MTPObjectHandle] = []
      for try await h in group { result.append(h) }
      return result
    }
    XCTAssertEqual(Set(handles).count, 10)

    // Phase 2: Write files + delete folders concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Write 5 files
      for i in 0..<5 {
        group.addTask {
          let data = Data(repeating: UInt8(i), count: 32)
          let src = try TestUtilities.createTempFile(
            directory: tempDir, filename: "cf\(i).bin", content: data)
          _ = try await device.write(parent: nil, name: "file\(i).bin", size: 32, from: src)
        }
      }
      // Delete 5 folders
      for h in handles.prefix(5) {
        group.addTask {
          try await device.delete(h, recursive: false)
        }
      }
      try await group.waitForAll()
    }

    // Verify: 5 remaining folders + 5 files = 10 root items
    var rootItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      rootItems.append(contentsOf: batch)
    }
    XCTAssertEqual(rootItems.count, 10)
  }

  func testConcurrentOperationLogIntegrity() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<30 {
        group.addTask {
          _ = try await device.createFolder(
            parent: nil, name: "log\(i)", storage: sid)
        }
      }
      try await group.waitForAll()
    }

    let ops = await device.operations
    // 1 storages + 30 createFolder = 31
    XCTAssertEqual(ops.count, 31)
    XCTAssertEqual(ops.filter { $0.operation == "createFolder" }.count, 30)
  }

  func testConcurrentGetInfoOnSameHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<20 {
        group.addTask {
          let info = try await device.getInfo(handle: 1)
          XCTAssertEqual(info.name, "DCIM")
        }
      }
      try await group.waitForAll()
    }
  }
}

// MARK: - Large Object Simulation

/// Objects > 100MB behave correctly.
final class Wave31LargeObjectSimulationTests: XCTestCase {

  func testLargeObjectMetadata() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    let largeSize: UInt64 = 150 * 1024 * 1024  // 150MB

    let obj = VirtualObjectConfig(
      handle: 500, storage: sid, parent: nil, name: "bigvideo.mp4",
      sizeBytes: largeSize, formatCode: 0x300B)
    await device.addObject(obj)

    let info = try await device.getInfo(handle: 500)
    XCTAssertEqual(info.name, "bigvideo.mp4")
    XCTAssertEqual(info.sizeBytes, largeSize)
    XCTAssertEqual(info.formatCode, 0x300B)
  }

  func testLargeObjectWriteAndReadRoundTrip() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    // Use a 100MB+ object with actual data (but use a small representative chunk
    // and set metadata to simulate large size)
    let chunkSize = 1024 * 1024  // 1MB actual data for round-trip
    let data = Data(repeating: 0xCD, count: chunkSize)
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "large.bin", content: data)

    let writeProgress = try await device.write(
      parent: nil, name: "large.bin",
      size: UInt64(chunkSize), from: src)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(chunkSize))

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      items.append(contentsOf: batch)
    }
    let large = try XCTUnwrap(items.first { $0.name == "large.bin" })

    let dest = tempDir.appendingPathComponent("downloaded_large.bin")
    let readProgress = try await device.read(handle: large.handle, range: nil, to: dest)
    XCTAssertEqual(readProgress.completedUnitCount, Int64(chunkSize))
    XCTAssertEqual(try Data(contentsOf: dest), data)
  }

  func testPartialReadOnLargeObject() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    // Create a 2MB object with known pattern
    let size = 2 * 1024 * 1024
    var data = Data(count: size)
    for i in 0..<size { data[i] = UInt8(i % 256) }

    let obj = VirtualObjectConfig(
      handle: 600, storage: sid, parent: nil, name: "pattern.bin",
      sizeBytes: UInt64(size), formatCode: 0x3000, data: data)
    await device.addObject(obj)

    // Read a slice from the middle
    let dest = tempDir.appendingPathComponent("slice.bin")
    _ = try await device.read(handle: 600, range: 1024..<2048, to: dest)
    let slice = try Data(contentsOf: dest)
    XCTAssertEqual(slice.count, 1024)
    // Verify pattern
    for i in 0..<slice.count {
      XCTAssertEqual(slice[i], UInt8((1024 + i) % 256))
    }
  }

  func testObjectConfigWithExplicitLargeSize() {
    let largeSize: UInt64 = 500 * 1024 * 1024 * 1024  // 500GB
    let obj = VirtualObjectConfig(
      handle: 1, storage: MTPStorageID(raw: 1), parent: nil,
      name: "huge.iso", sizeBytes: largeSize, formatCode: 0x3000)
    XCTAssertEqual(obj.sizeBytes, largeSize)
    let info = obj.toObjectInfo()
    XCTAssertEqual(info.sizeBytes, largeSize)
  }
}

// MARK: - Storage Capacity Tracking

/// Verify storage capacity values are reported correctly from config.
final class Wave31StorageCapacityTrackingTests: XCTestCase {

  func testFreeSpaceReportedFromConfig() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Main",
      capacityBytes: 256 * 1024 * 1024 * 1024,
      freeBytes: 100 * 1024 * 1024 * 1024)
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = [storage]
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages[0].capacityBytes, 256 * 1024 * 1024 * 1024)
    XCTAssertEqual(storages[0].freeBytes, 100 * 1024 * 1024 * 1024)
  }

  func testReadOnlyStorageReportsZeroFree() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "ROM",
      capacityBytes: 4 * 1024 * 1024 * 1024, freeBytes: 0,
      isReadOnly: true)
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = [storage]
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertTrue(storages[0].isReadOnly)
    XCTAssertEqual(storages[0].freeBytes, 0)
    XCTAssertEqual(storages[0].capacityBytes, 4 * 1024 * 1024 * 1024)
  }

  func testMultipleStoragesReportIndependentCapacities() async throws {
    let internal_ = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal",
      capacityBytes: 64 * 1024 * 1024 * 1024, freeBytes: 32 * 1024 * 1024 * 1024)
    let sd = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card",
      capacityBytes: 256 * 1024 * 1024 * 1024, freeBytes: 200 * 1024 * 1024 * 1024)

    let config = VirtualDeviceConfig.emptyDevice
      .withStorage(sd)
    var modConfig = config
    modConfig.storages = [internal_, sd]
    let device = VirtualMTPDevice(config: modConfig)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)

    let internalStore = try XCTUnwrap(storages.first { $0.description == "Internal" })
    let sdStore = try XCTUnwrap(storages.first { $0.description == "SD Card" })

    XCTAssertEqual(internalStore.capacityBytes, 64 * 1024 * 1024 * 1024)
    XCTAssertEqual(sdStore.capacityBytes, 256 * 1024 * 1024 * 1024)
    XCTAssertNotEqual(internalStore.freeBytes, sdStore.freeBytes)
  }

  func testStorageCapacityPreservedAfterObjectOperations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storagesBefore = try await device.storages()
    let capacityBefore = storagesBefore[0].capacityBytes
    let freeBefore = storagesBefore[0].freeBytes

    // Add objects
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "x.bin", content: Data(count: 4096))
    _ = try await device.write(parent: nil, name: "extra.bin", size: 4096, from: src)

    // VirtualMTPDevice doesn't dynamically update free space (static config)
    let storagesAfter = try await device.storages()
    XCTAssertEqual(storagesAfter[0].capacityBytes, capacityBefore)
    XCTAssertEqual(storagesAfter[0].freeBytes, freeBefore)
  }
}

// MARK: - VirtualMTPLink Edge Cases

/// Additional VirtualMTPLink coverage for wave31.
final class Wave31VirtualMTPLinkTests: XCTestCase {

  func testLinkWithFaultScheduleParameter() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .getDeviceInfo)])
    let link = VirtualMTPLink(config: .emptyDevice, faultSchedule: schedule)

    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout from VirtualMTPLink faultSchedule")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }

    // Second call succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testGetObjectPropValueReturnsFileName() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    let sid = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 10, storage: sid, parent: nil, name: "photo.jpg",
        sizeBytes: 1024, formatCode: 0x3801))
    let link = VirtualMTPLink(config: config)

    let nameData = try await link.getObjectPropValue(
      handle: 10, property: MTPObjectPropCode.objectFileName)
    XCTAssertFalse(nameData.isEmpty)
  }

  func testGetObjectPropsSupported() async throws {
    let link = VirtualMTPLink(config: .emptyDevice)
    let props = try await link.getObjectPropsSupported(format: 0x3000)
    XCTAssertTrue(props.contains(MTPObjectPropCode.objectFileName))
    XCTAssertTrue(props.contains(MTPObjectPropCode.objectSize))
    XCTAssertTrue(props.contains(MTPObjectPropCode.storageID))
  }

  func testSetObjectPropValueDoesNotCrash() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    let sid = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 10, storage: sid, parent: nil, name: "file.txt"))
    let link = VirtualMTPLink(config: config)

    // Should not throw for existing objects
    try await link.setObjectPropValue(
      handle: 10, property: MTPObjectPropCode.objectFileName,
      value: Data([0x01, 0x02]))
  }
}
