// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

// MARK: - Connection State

/// Tracks the lifecycle state of an XPC connection.
public enum XPCConnectionState: String, Sendable, Equatable {
  /// Connection is active and usable.
  case connected
  /// Service process crashed or was suspended; connection will auto-resume.
  case interrupted
  /// Actively attempting to re-establish the connection.
  case reconnecting
  /// Connection permanently invalidated; no reconnect possible.
  case invalidated
}

// MARK: - Connection Monitor

/// Reports XPC connection state changes.
public protocol XPCConnectionMonitor: AnyObject, Sendable {
  func connectionStateDidChange(_ state: XPCConnectionState)
}

// MARK: - XPCConnectionManager

/// Manages an NSXPCConnection with automatic reconnection on interruption,
/// exponential backoff, and operation queuing during reconnect windows.
///
/// Runs as an actor to serialize all state mutations (connection lifecycle,
/// pending queue, backoff state) without external locking.
public actor XPCConnectionManager {

  // MARK: - Configuration

  /// Parameters controlling reconnection behaviour.
  public struct Configuration: Sendable {
    /// Base delay before the first reconnection attempt.
    public var baseDelay: TimeInterval
    /// Multiplier applied after each failed attempt.
    public var multiplier: Double
    /// Upper bound on the backoff delay.
    public var maxDelay: TimeInterval
    /// Maximum queued operations before new ones are rejected.
    public var maxQueueSize: Int

    public init(
      baseDelay: TimeInterval = 1.0,
      multiplier: Double = 2.0,
      maxDelay: TimeInterval = 30.0,
      maxQueueSize: Int = 64
    ) {
      self.baseDelay = baseDelay
      self.multiplier = multiplier
      self.maxDelay = maxDelay
      self.maxQueueSize = maxQueueSize
    }
  }

  // MARK: - Stored Properties

  private let serviceName: String
  private let configuration: Configuration
  private let log = Logger(subsystem: "SwiftMTP", category: "XPCConnectionManager")

  /// The live NSXPCConnection; nil when invalidated or before first use.
  private var connection: NSXPCConnection?

  /// Current connection state.
  public private(set) var state: XPCConnectionState = .invalidated

  /// Weak monitor for state change notifications.
  private weak var monitor: (any XPCConnectionMonitor)?

  /// Current backoff delay for the next reconnect attempt.
  private var currentDelay: TimeInterval

  /// Number of consecutive reconnection attempts without success.
  private var reconnectAttempts: Int = 0

  /// Whether a reconnect loop is already running.
  private var isReconnecting: Bool = false

  /// Pending operations queued while reconnecting.
  private var pendingOperations: [CheckedContinuation<ServiceProxy, Error>] = []

  /// Factory that builds the connection; injectable for testing.
  private let connectionFactory: @Sendable (String) -> NSXPCConnection

  // MARK: - Init

  /// Creates a connection manager.
  ///
  /// - Parameters:
  ///   - serviceName: Mach service name for the XPC endpoint.
  ///   - configuration: Reconnection parameters.
  ///   - monitor: Optional observer for state changes.
  ///   - connectionFactory: Override for testing (default creates a real NSXPCConnection).
  public init(
    serviceName: String = MTPXPCServiceName,
    configuration: Configuration = .init(),
    monitor: (any XPCConnectionMonitor)? = nil,
    connectionFactory: (@Sendable (String) -> NSXPCConnection)? = nil
  ) {
    self.serviceName = serviceName
    self.configuration = configuration
    self.monitor = monitor
    self.currentDelay = configuration.baseDelay
    self.connectionFactory = connectionFactory ?? { name in
      NSXPCConnection(machServiceName: name, options: [])
    }
  }

  // MARK: - Public API

  /// Wraps a non-Sendable XPC proxy for safe cross-isolation transfer.
  /// The underlying NSXPCConnection proxy is inherently thread-safe (XPC serialization).
  public struct ServiceProxy: @unchecked Sendable {
    public let value: MTPXPCService
  }

  /// Returns a proxy conforming to `MTPXPCService` wrapped for Sendable transfer.
  ///
  /// If the connection is interrupted or reconnecting, the caller is
  /// suspended until a connection is re-established (or the connection
  /// is permanently invalidated, in which case an error is thrown).
  public func service() async throws -> ServiceProxy {
    switch state {
    case .connected:
      if let proxy = connection?.remoteObjectProxy as? MTPXPCService {
        return ServiceProxy(value: proxy)
      }
      break
    case .invalidated:
      throw XPCConnectionError.connectionInvalidated
    case .interrupted, .reconnecting:
      return try await enqueue()
    }

    try await connect()
    guard let proxy = connection?.remoteObjectProxy as? MTPXPCService else {
      throw XPCConnectionError.connectionInvalidated
    }
    return ServiceProxy(value: proxy)
  }

  /// Explicitly connect (or reconnect) the XPC connection.
  public func connect() async throws {
    if state == .invalidated && connection != nil {
      throw XPCConnectionError.connectionInvalidated
    }
    buildConnection()
  }

  /// Permanently tears down the connection. No further reconnection will occur.
  public func invalidate() {
    connection?.invalidate()
    connection = nil
    setState(.invalidated)
    drainPendingOperations(with: XPCConnectionError.connectionInvalidated)
  }

  /// The current connection state.
  public var connectionState: XPCConnectionState { state }

  /// Number of queued operations waiting for reconnect.
  public var pendingOperationCount: Int { pendingOperations.count }

  /// Resets the backoff counter (e.g. after a successful operation).
  public func resetBackoff() {
    reconnectAttempts = 0
    currentDelay = configuration.baseDelay
  }

  // MARK: - Internal: Connection Lifecycle

  private func buildConnection() {
    // Detach handlers before invalidating to prevent re-entrant state changes.
    if let old = connection {
      old.interruptionHandler = nil
      old.invalidationHandler = nil
      old.invalidate()
    }
    connection = nil

    let conn = connectionFactory(serviceName)
    conn.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)

    // Capture `self` weakly to avoid retain cycles with the connection handlers.
    // Handlers are dispatched onto an arbitrary queue, so we hop back into the actor.
    conn.interruptionHandler = { [weak self] in
      guard let self else { return }
      Task { await self.handleInterruption() }
    }
    conn.invalidationHandler = { [weak self] in
      guard let self else { return }
      Task { await self.handleInvalidation() }
    }

    conn.resume()
    connection = conn
    setState(.connected)
    reconnectAttempts = 0
    currentDelay = configuration.baseDelay
    resumePendingOperations()
  }

  // MARK: - Interruption / Invalidation Handlers

  private func handleInterruption() {
    guard state != .invalidated else { return }
    log.warning("XPC connection interrupted")
    setState(.interrupted)
    scheduleReconnect()
  }

  private func handleInvalidation() {
    log.error("XPC connection invalidated")
    connection = nil
    setState(.invalidated)
    drainPendingOperations(with: XPCConnectionError.connectionInvalidated)
  }

  // MARK: - Reconnection with Backoff

  private func scheduleReconnect() {
    guard !isReconnecting else { return }
    isReconnecting = true
    setState(.reconnecting)

    Task { [weak self] in
      guard let self else { return }
      await self.reconnectLoop()
    }
  }

  private func reconnectLoop() async {
    while state == .reconnecting {
      let delay = currentDelay
      reconnectAttempts += 1
      log.info("Reconnect attempt \(self.reconnectAttempts) in \(delay, format: .fixed(precision: 1))s")

      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

      // After sleep, check we're still supposed to reconnect.
      guard state == .reconnecting else { break }

      buildConnection()

      if state == .connected {
        log.info("XPC reconnected after \(self.reconnectAttempts) attempt(s)")
        isReconnecting = false
        return
      }

      // Exponential backoff.
      currentDelay = min(currentDelay * configuration.multiplier, configuration.maxDelay)
    }
    isReconnecting = false
  }

  // MARK: - Operation Queue

  private func enqueue() async throws -> sending ServiceProxy {
    guard pendingOperations.count < configuration.maxQueueSize else {
      throw XPCConnectionError.queueFull
    }
    return try await withCheckedThrowingContinuation { continuation in
      pendingOperations.append(continuation)
    }
  }

  private func resumePendingOperations() {
    guard let proxy = connection?.remoteObjectProxy as? MTPXPCService else { return }
    let ops = pendingOperations
    pendingOperations.removeAll()
    for continuation in ops {
      continuation.resume(returning: ServiceProxy(value: proxy))
    }
  }

  private func drainPendingOperations(with error: Error) {
    let ops = pendingOperations
    pendingOperations.removeAll()
    for continuation in ops {
      continuation.resume(throwing: error)
    }
  }

  // MARK: - State Mutation

  private func setState(_ newState: XPCConnectionState) {
    guard state != newState else { return }
    state = newState
    let monitor = self.monitor
    Task { @Sendable in
      monitor?.connectionStateDidChange(newState)
    }
  }
}

// MARK: - Errors

/// Errors specific to XPC connection management.
public enum XPCConnectionError: Error, Sendable, CustomStringConvertible {
  /// The connection was permanently invalidated and cannot be reused.
  case connectionInvalidated
  /// The operation queue is full; the service is unreachable.
  case queueFull

  public var description: String {
    switch self {
    case .connectionInvalidated:
      return "XPC connection permanently invalidated"
    case .queueFull:
      return "XPC operation queue full — service unreachable"
    }
  }
}
