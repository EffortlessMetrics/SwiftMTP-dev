public enum MTPError: Error, Sendable {
  case deviceDisconnected, permissionDenied
  case notSupported(String)
  case transport(TransportError)
  case protocolError(code: UInt16, message: String?)
  case objectNotFound, storageFull, readOnly, timeout, busy
  case preconditionFailed(String)
}
public enum TransportError: Error, Sendable {
  case noDevice, timeout, busy, accessDenied
  case io(String)
}
