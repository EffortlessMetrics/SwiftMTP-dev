import Foundation
import CLibusb
import SwiftMTPCore
import SwiftMTPObservability
import Atomics

public struct LibUSBTransport: MTPTransport {
  public init() {}
  public func open(_ summary: MTPDeviceSummary) async throws -> MTPLink { StubLink() }
}
struct StubLink: MTPLink { func close() async {} }

public protocol MTPTransport: Sendable { func open(_ summary: MTPDeviceSummary) async throws -> MTPLink }
public protocol MTPLink: Sendable { func close() async }
