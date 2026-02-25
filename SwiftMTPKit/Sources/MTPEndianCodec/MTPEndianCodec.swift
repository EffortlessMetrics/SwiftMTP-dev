// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - MTPEndianCodec

/// A utility for encoding and decoding little-endian values in MTP protocol data.
///
/// MTP (Media Transfer Protocol) uses little-endian byte order for all multi-byte
/// integer values. This codec provides type-safe encoding and decoding operations
/// that handle the byte order conversions transparently.
///
/// ## Overview
///
/// The codec supports:
/// - Encoding `UInt16`, `UInt32`, and `UInt64` values to little-endian byte sequences
/// - Decoding little-endian byte sequences back to integer values
/// - Both `Data` and raw buffer operations for flexibility
///
/// ## Thread Safety
///
/// All methods are static and stateless, making them inherently thread-safe.
/// The codec can be safely used from any concurrency context.
///
/// ## Example Usage
///
/// ```swift
/// // Encoding
/// let bytes = MTPEndianCodec.encode(UInt32(0x12345678))
/// // bytes == [0x78, 0x56, 0x34, 0x12]
///
/// // Decoding
/// let data = Data([0x78, 0x56, 0x34, 0x12, 0x00, 0x00])
/// let value = MTPEndianCodec.decodeUInt32(from: data, at: 0)
/// // value == 0x12345678
/// ```
public enum MTPEndianCodec: Sendable {

  // MARK: - Encoding to Data

  /// Encodes a `UInt16` value as a 2-byte little-endian sequence.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: A `Data` containing 2 bytes in little-endian order.
  @inlinable
  public static func encode(_ value: UInt16) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  /// Encodes a `UInt32` value as a 4-byte little-endian sequence.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: A `Data` containing 4 bytes in little-endian order.
  @inlinable
  public static func encode(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  /// Encodes a `UInt64` value as an 8-byte little-endian sequence.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: A `Data` containing 8 bytes in little-endian order.
  @inlinable
  public static func encode(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  // MARK: - Encoding to Array

  /// Encodes a `UInt16` value as a 2-byte little-endian array.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: An array containing 2 bytes in little-endian order.
  @inlinable
  public static func encodeToBytes(_ value: UInt16) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
  }

  /// Encodes a `UInt32` value as a 4-byte little-endian array.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: An array containing 4 bytes in little-endian order.
  @inlinable
  public static func encodeToBytes(_ value: UInt32) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
  }

  /// Encodes a `UInt64` value as an 8-byte little-endian array.
  ///
  /// - Parameter value: The value to encode.
  /// - Returns: An array containing 8 bytes in little-endian order.
  @inlinable
  public static func encodeToBytes(_ value: UInt64) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
  }

  // MARK: - Encoding to Raw Buffer

  /// Encodes a `UInt16` value into a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - buffer: The destination buffer.
  ///   - offset: The byte offset at which to write.
  /// - Returns: The number of bytes written (always 2).
  @inlinable
  public static func encode(_ value: UInt16, into buffer: UnsafeMutableRawPointer, at offset: Int)
    -> Int
  {
    var le = value.littleEndian
    memcpy(buffer.advanced(by: offset), &le, 2)
    return 2
  }

  /// Encodes a `UInt32` value into a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - buffer: The destination buffer.
  ///   - offset: The byte offset at which to write.
  /// - Returns: The number of bytes written (always 4).
  @inlinable
  public static func encode(_ value: UInt32, into buffer: UnsafeMutableRawPointer, at offset: Int)
    -> Int
  {
    var le = value.littleEndian
    memcpy(buffer.advanced(by: offset), &le, 4)
    return 4
  }

  /// Encodes a `UInt64` value into a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - buffer: The destination buffer.
  ///   - offset: The byte offset at which to write.
  /// - Returns: The number of bytes written (always 8).
  @inlinable
  public static func encode(_ value: UInt64, into buffer: UnsafeMutableRawPointer, at offset: Int)
    -> Int
  {
    var le = value.littleEndian
    memcpy(buffer.advanced(by: offset), &le, 8)
    return 8
  }

  // MARK: - Decoding from Data

  /// Decodes a `UInt16` value from a `Data` buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - data: The source data.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  @inlinable
  public static func decodeUInt16(from data: Data, at offset: Int) -> UInt16? {
    let width = MemoryLayout<UInt16>.size
    guard offset >= 0, offset + width <= data.count else { return nil }
    var value: UInt16 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      data.copyBytes(to: raw, from: offset..<(offset + width))
    }
    return UInt16(littleEndian: value)
  }

  /// Decodes a `UInt32` value from a `Data` buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - data: The source data.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  @inlinable
  public static func decodeUInt32(from data: Data, at offset: Int) -> UInt32? {
    let width = MemoryLayout<UInt32>.size
    guard offset >= 0, offset + width <= data.count else { return nil }
    var value: UInt32 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      data.copyBytes(to: raw, from: offset..<(offset + width))
    }
    return UInt32(littleEndian: value)
  }

  /// Decodes a `UInt64` value from a `Data` buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - data: The source data.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  @inlinable
  public static func decodeUInt64(from data: Data, at offset: Int) -> UInt64? {
    let width = MemoryLayout<UInt64>.size
    guard offset >= 0, offset + width <= data.count else { return nil }
    var value: UInt64 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      data.copyBytes(to: raw, from: offset..<(offset + width))
    }
    return UInt64(littleEndian: value)
  }

  // MARK: - Decoding from Collection

  /// Decodes a `UInt16` value from a byte collection at the specified offset.
  ///
  /// - Parameters:
  ///   - bytes: The source byte collection.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  public static func decodeUInt16(from bytes: some Collection<UInt8>, at offset: Int) -> UInt16? {
    let width = MemoryLayout<UInt16>.size
    guard offset >= 0 else { return nil }
    let bytesArray = Array(bytes)
    guard offset + width <= bytesArray.count else { return nil }
    var value: UInt16 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      bytesArray.withUnsafeBufferPointer { src in
        memcpy(raw.baseAddress!, src.baseAddress!.advanced(by: offset), width)
      }
    }
    return UInt16(littleEndian: value)
  }

  /// Decodes a `UInt32` value from a byte collection at the specified offset.
  ///
  /// - Parameters:
  ///   - bytes: The source byte collection.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  public static func decodeUInt32(from bytes: some Collection<UInt8>, at offset: Int) -> UInt32? {
    let width = MemoryLayout<UInt32>.size
    guard offset >= 0 else { return nil }
    let bytesArray = Array(bytes)
    guard offset + width <= bytesArray.count else { return nil }
    var value: UInt32 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      bytesArray.withUnsafeBufferPointer { src in
        memcpy(raw.baseAddress!, src.baseAddress!.advanced(by: offset), width)
      }
    }
    return UInt32(littleEndian: value)
  }

  /// Decodes a `UInt64` value from a byte collection at the specified offset.
  ///
  /// - Parameters:
  ///   - bytes: The source byte collection.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  public static func decodeUInt64(from bytes: some Collection<UInt8>, at offset: Int) -> UInt64? {
    let width = MemoryLayout<UInt64>.size
    guard offset >= 0 else { return nil }
    let bytesArray = Array(bytes)
    guard offset + width <= bytesArray.count else { return nil }
    var value: UInt64 = 0
    withUnsafeMutableBytes(of: &value) { raw in
      bytesArray.withUnsafeBufferPointer { src in
        memcpy(raw.baseAddress!, src.baseAddress!.advanced(by: offset), width)
      }
    }
    return UInt64(littleEndian: value)
  }

  // MARK: - Decoding from Raw Buffer

  /// Decodes a `UInt16` value from a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - buffer: The source buffer.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value in native byte order.
  @inlinable
  public static func decodeUInt16(from buffer: UnsafeRawPointer, at offset: Int) -> UInt16 {
    var value: UInt16 = 0
    memcpy(&value, buffer.advanced(by: offset), MemoryLayout<UInt16>.size)
    return UInt16(littleEndian: value)
  }

  /// Decodes a `UInt32` value from a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - buffer: The source buffer.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value in native byte order.
  @inlinable
  public static func decodeUInt32(from buffer: UnsafeRawPointer, at offset: Int) -> UInt32 {
    var value: UInt32 = 0
    memcpy(&value, buffer.advanced(by: offset), MemoryLayout<UInt32>.size)
    return UInt32(littleEndian: value)
  }

  /// Decodes a `UInt64` value from a raw buffer at the specified offset.
  ///
  /// - Parameters:
  ///   - buffer: The source buffer.
  ///   - offset: The byte offset at which to read.
  /// - Returns: The decoded value in native byte order.
  @inlinable
  public static func decodeUInt64(from buffer: UnsafeRawPointer, at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    memcpy(&value, buffer.advanced(by: offset), MemoryLayout<UInt64>.size)
    return UInt64(littleEndian: value)
  }

  // MARK: - Generic Decoding

  /// Decodes a little-endian integer value from a `Data` buffer at the specified offset.
  ///
  /// This generic method can decode any `FixedWidthInteger` type.
  ///
  /// - Parameters:
  ///   - data: The source data.
  ///   - offset: The byte offset at which to read.
  ///   - type: The type of integer to decode.
  /// - Returns: The decoded value, or `nil` if insufficient bytes are available.
  @inlinable
  public static func decodeLittleEndian<T: FixedWidthInteger>(
    _ data: Data,
    at offset: Int,
    as type: T.Type = T.self
  ) -> T? {
    let width = MemoryLayout<T>.size
    guard offset >= 0, offset + width <= data.count else { return nil }
    var value: T = 0
    withUnsafeMutableBytes(of: &value) { raw in
      data.copyBytes(to: raw, from: offset..<(offset + width))
    }
    return T(littleEndian: value)
  }
}

// MARK: - MTPDataEncoder

/// A stateful encoder for building MTP protocol data packets.
///
/// Use `MTPDataEncoder` when you need to encode multiple values sequentially
/// into a single buffer. The encoder maintains an internal offset and provides
/// convenience methods for appending little-endian values.
///
/// ## Example
///
/// ```swift
/// var encoder = MTPDataEncoder()
/// encoder.append(UInt32(12))  // length
/// encoder.append(UInt16(1))   // type
/// encoder.append(UInt16(0x1001))  // code
/// let data = encoder.data
/// ```
public struct MTPDataEncoder: Sendable {
  @usableFromInline
  var data: Data

  /// Creates a new encoder with an empty buffer.
  public init() {
    self.data = Data()
  }

  /// Creates a new encoder with the specified initial capacity.
  public init(capacity: Int) {
    self.data = Data()
    self.data.reserveCapacity(capacity)
  }

  /// The current encoded data.
  public var encodedData: Data {
    data
  }

  /// The number of bytes encoded so far.
  public var count: Int {
    data.count
  }

  /// Appends a `UInt16` value in little-endian order.
  public mutating func append(_ value: UInt16) {
    data.append(MTPEndianCodec.encode(value))
  }

  /// Appends a `UInt32` value in little-endian order.
  public mutating func append(_ value: UInt32) {
    data.append(MTPEndianCodec.encode(value))
  }

  /// Appends a `UInt64` value in little-endian order.
  public mutating func append(_ value: UInt64) {
    data.append(MTPEndianCodec.encode(value))
  }

  /// Appends raw bytes to the buffer.
  public mutating func append(contentsOf bytes: [UInt8]) {
    data.append(contentsOf: bytes)
  }

  /// Appends raw data to the buffer.
  public mutating func append(_ other: Data) {
    data.append(other)
  }

  /// Appends a single byte to the buffer.
  public mutating func append(_ byte: UInt8) {
    data.append(byte)
  }

  /// Resets the encoder to an empty state.
  public mutating func reset() {
    data.removeAll(keepingCapacity: true)
  }
}

// MARK: - MTPDataDecoder

/// A stateful decoder for reading MTP protocol data packets.
///
/// Use `MTPDataDecoder` when you need to decode multiple values sequentially
/// from a buffer. The decoder maintains an internal offset and provides
/// convenience methods for reading little-endian values.
///
/// ## Example
///
/// ```swift
/// var decoder = MTPDataDecoder(data: packetData)
/// let length = decoder.readUInt32()  // reads 4 bytes
/// let type = decoder.readUInt16()    // reads 2 bytes
/// let code = decoder.readUInt16()    // reads 2 bytes
/// ```
public struct MTPDataDecoder: Sendable {
  @usableFromInline
  let data: Data
  @usableFromInline
  var offset: Int

  /// Creates a new decoder for the given data.
  public init(data: Data) {
    self.data = data
    self.offset = 0
  }

  /// The current read offset.
  public var currentOffset: Int {
    offset
  }

  /// The number of bytes remaining to be read.
  public var remainingBytes: Int {
    data.count - offset
  }

  /// Whether there are any bytes remaining to be read.
  public var hasRemaining: Bool {
    offset < data.count
  }

  /// Reads a `UInt8` value and advances the offset.
  public mutating func readUInt8() -> UInt8? {
    guard offset + 1 <= data.count else { return nil }
    defer { offset += 1 }
    return data[offset]
  }

  /// Reads a `UInt16` value in little-endian order and advances the offset.
  public mutating func readUInt16() -> UInt16? {
    guard let value = MTPEndianCodec.decodeUInt16(from: data, at: offset) else { return nil }
    offset += 2
    return value
  }

  /// Reads a `UInt32` value in little-endian order and advances the offset.
  public mutating func readUInt32() -> UInt32? {
    guard let value = MTPEndianCodec.decodeUInt32(from: data, at: offset) else { return nil }
    offset += 4
    return value
  }

  /// Reads a `UInt64` value in little-endian order and advances the offset.
  public mutating func readUInt64() -> UInt64? {
    guard let value = MTPEndianCodec.decodeUInt64(from: data, at: offset) else { return nil }
    offset += 8
    return value
  }

  /// Reads the specified number of bytes and advances the offset.
  public mutating func readBytes(_ count: Int) -> Data? {
    guard offset + count <= data.count else { return nil }
    defer { offset += count }
    return data.subdata(in: offset..<(offset + count))
  }

  /// Peeks at a `UInt16` value without advancing the offset.
  public func peekUInt16(at relativeOffset: Int = 0) -> UInt16? {
    MTPEndianCodec.decodeUInt16(from: data, at: offset + relativeOffset)
  }

  /// Peeks at a `UInt32` value without advancing the offset.
  public func peekUInt32(at relativeOffset: Int = 0) -> UInt32? {
    MTPEndianCodec.decodeUInt32(from: data, at: offset + relativeOffset)
  }

  /// Skips the specified number of bytes.
  public mutating func skip(_ count: Int) {
    offset = min(offset + count, data.count)
  }

  /// Resets the offset to the beginning.
  public mutating func reset() {
    offset = 0
  }

  /// Sets the offset to the specified position.
  public mutating func seek(to newOffset: Int) {
    offset = max(0, min(newOffset, data.count))
  }
}
