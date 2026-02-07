// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Collections

// MARK: - Priority + Deadline

/// Priority levels for device operations.
public enum DeviceOperationPriority: Int, Comparable, Sendable {
    case low = 0       // background crawl
    case medium = 1    // thumbnails, prefetch
    case high = 2      // user-initiated enumeration
    case critical = 3  // session open/close

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Deadline and retry policy for an operation.
public struct OperationDeadline: Sendable {
    public let timeout: TimeInterval
    public let maxRetries: Int

    public init(timeout: TimeInterval = 30, maxRetries: Int = 0) {
        self.timeout = timeout; self.maxRetries = maxRetries
    }

    public static let `default` = OperationDeadline()
    public static let crawl = OperationDeadline(timeout: 60, maxRetries: 1)
    public static let userAction = OperationDeadline(timeout: 15, maxRetries: 0)
}

// MARK: - Operation Handle

/// A cancellable, awaitable handle to a submitted operation.
public final class DeviceOperationHandle<T: Sendable>: Sendable {
    private let continuation: UnsafeContinuation<T, Error>?
    private let task: Task<T, Error>

    /// True if the operation was cancelled.
    public var isCancelled: Bool { task.isCancelled }

    init(task: Task<T, Error>, continuation: UnsafeContinuation<T, Error>? = nil) {
        self.task = task
        self.continuation = continuation
    }

    /// Await the result of the operation.
    public var value: T {
        get async throws { try await task.value }
    }

    /// Cancel the operation.
    public func cancel() { task.cancel() }
}

// MARK: - Queued Operation

private struct QueuedOperation: Comparable, Sendable {
    let id: UInt64
    let priority: DeviceOperationPriority
    let execute: @Sendable () async -> Void

    static func < (lhs: QueuedOperation, rhs: QueuedOperation) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id < rhs.id // FIFO within same priority
    }

    static func == (lhs: QueuedOperation, rhs: QueuedOperation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DeviceService

/// Wraps an `MTPDeviceActor` with a priority queue for ordered operation submission.
///
/// Layering: `DeviceService` → `MTPDeviceActor` → `MTPLink`.
/// This actor adds priority ordering and cancellation above the serialized wire gateway.
public actor DeviceService {
    private let device: any MTPDevice
    private var queue = Heap<QueuedOperation>()
    private var nextId: UInt64 = 0
    private var isProcessing = false
    private var disconnected = false

    public init(device: any MTPDevice) {
        self.device = device
    }

    /// The underlying device.
    public var underlyingDevice: any MTPDevice { device }

    /// Submit an operation to the priority queue.
    public func submit<T: Sendable>(
        priority: DeviceOperationPriority,
        deadline: OperationDeadline = .default,
        operation: @Sendable @escaping (any MTPDevice) async throws -> T
    ) throws -> DeviceOperationHandle<T> {
        guard !disconnected else { throw MTPError.deviceDisconnected }

        let id = nextId
        nextId += 1

        let task = Task<T, Error> {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                let op = QueuedOperation(id: id, priority: priority) { [weak self] in
                    guard let self else {
                        cont.resume(throwing: MTPError.deviceDisconnected)
                        return
                    }
                    do {
                        let result = try await withThrowingTaskGroup(of: T.self) { group in
                            group.addTask {
                                try await operation(self.device)
                            }
                            group.addTask {
                                try await Task.sleep(for: .seconds(deadline.timeout))
                                throw MTPError.timeout
                            }
                            let result = try await group.next()!
                            group.cancelAll()
                            return result
                        }
                        cont.resume(returning: result)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                Task { await self.enqueue(op) }
            }
        }

        return DeviceOperationHandle(task: task)
    }

    /// Mark the device as disconnected, cancelling all pending operations.
    public func markDisconnected() {
        disconnected = true
        // Drain queue — each pending op will fail when executed
        while let op = queue.popMin() {
            Task { await op.execute() }
        }
    }

    /// Mark the device as reconnected.
    public func markReconnected() {
        disconnected = false
    }

    // MARK: - Convenience Methods

    /// Ensure the device session is open.
    public func ensureSession() async throws {
        let handle = try submit(priority: .critical, deadline: .default) { device in
            try await device.openIfNeeded()
        }
        try await handle.value
    }

    /// List objects in a directory.
    public func listObjects(
        parent: MTPObjectHandle?,
        storage: MTPStorageID,
        priority: DeviceOperationPriority = .high
    ) async throws -> [MTPObjectInfo] {
        let handle = try submit(priority: priority, deadline: .default) { device in
            var result: [MTPObjectInfo] = []
            let stream = device.list(parent: parent, in: storage)
            for try await batch in stream { result.append(contentsOf: batch) }
            return result
        }
        return try await handle.value
    }

    /// Read an object to a local file.
    public func readObject(
        handle: MTPObjectHandle,
        to url: URL,
        priority: DeviceOperationPriority = .medium
    ) async throws -> Progress {
        let opHandle = try submit(priority: priority, deadline: OperationDeadline(timeout: 300)) { device in
            try await device.read(handle: handle, range: nil, to: url)
        }
        return try await opHandle.value
    }

    // MARK: - Internal Queue

    private func enqueue(_ op: QueuedOperation) {
        queue.insert(op)
        processNextIfNeeded()
    }

    private func processNextIfNeeded() {
        guard !isProcessing, let op = queue.popMin() else { return }
        isProcessing = true
        Task {
            await op.execute()
            isProcessing = false
            processNextIfNeeded()
        }
    }
}
