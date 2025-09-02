import Foundation

public struct PTPContainer {
  public enum Kind: UInt16 { case command = 1, data = 2, response = 3, event = 4 }
  public var length: UInt32 = 12
  public var type: UInt16
  public var code: UInt16
  public var txid: UInt32
  public var params: [UInt32] = []

  public init(length: UInt32 = 12, type: UInt16, code: UInt16, txid: UInt32, params: [UInt32] = []) {
    self.length = length
    self.type = type
    self.code = code
    self.txid = txid
    self.params = params
  }

  public func encode(into buf: UnsafeMutablePointer<UInt8>) -> Int {
    var off = 0
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { m in m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf+off, count: 4)); off += 4 } }
    func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { m in m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf+off, count: 2)); off += 2 } }
    put32(length); put16(type); put16(code); put32(txid)
    for p in params { put32(p) }
    return off
  }
}

public enum PTPOp: UInt16 { case getDeviceInfo = 0x1001, openSession = 0x1002 } // enough for now
