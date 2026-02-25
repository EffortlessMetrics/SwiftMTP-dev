// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

/// A @unchecked Sendable box for ObjC-style completion handler closures.
///
/// NSFileProvider protocol callbacks are designed to be called from any thread,
/// but their closure types are not annotated @Sendable. This box asserts that
/// invariant, satisfying Swift 6.2's strict sending checks.
final class SendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}
