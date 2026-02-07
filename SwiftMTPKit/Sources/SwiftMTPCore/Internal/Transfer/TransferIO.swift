// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public protocol ByteSink: Sendable {
    func write(_ buf: UnsafeRawBufferPointer) throws
    func close() throws
}

public protocol ByteSource: Sendable {
    func read(into buf: UnsafeMutableRawBufferPointer) throws -> Int
    func close() throws
    var fileSize: UInt64? { get }
}

public final class FileSink: ByteSink, @unchecked Sendable {
    private let handle: FileHandle
    private let url: URL
    private let lock = NSLock()

    public init(url: URL, append: Bool = false) throws {
        self.url = url
        if !append {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            } else {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
        }
        self.handle = try FileHandle(forWritingTo: url)
        if append {
            try handle.seekToEnd()
        }
    }

    public func write(_ buf: UnsafeRawBufferPointer) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = Data(bytes: buf.baseAddress!, count: buf.count)
        try handle.write(contentsOf: data)
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try handle.close()
    }
}

public final class FileSource: ByteSource, @unchecked Sendable {
    private let handle: FileHandle
    private let url: URL
    private let lock = NSLock()
    public let fileSize: UInt64?

    public init(url: URL) throws {
        self.url = url
        self.handle = try FileHandle(forReadingFrom: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = attrs[.size] as? UInt64
    }

    public func read(into buf: UnsafeMutableRawBufferPointer) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let data = try handle.read(upToCount: buf.count) ?? Data()
        if data.isEmpty { return 0 }
        data.copyBytes(to: buf)
        return data.count
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try handle.close()
    }
}

public func atomicReplace(temp: URL, final: URL) throws {
    if FileManager.default.fileExists(atPath: final.path) {
        _ = try FileManager.default.replaceItemAt(final, withItemAt: temp)
    } else {
        try FileManager.default.moveItem(at: temp, to: final)
    }
}
