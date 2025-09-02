import Foundation

protocol ByteSink {
    mutating func write(_ chunk: UnsafeRawBufferPointer) throws
    mutating func close() throws
}

protocol ByteSource {
    mutating func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int
    mutating func close() throws
    var fileSize: UInt64? { get }
}

// --- File sink/source (atomic host semantics)

struct FileSink: ByteSink {
    private var fh: FileHandle
    init(url: URL, truncate: Bool = true) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if truncate { FileManager.default.createFile(atPath: url.path, contents: nil) }
        fh = try FileHandle(forWritingTo: url)
    }
    init(url: URL, append: Bool) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fh = try FileHandle(forUpdating: url)
        if append {
            try fh.seekToEnd()
        }
    }
    mutating func write(_ chunk: UnsafeRawBufferPointer) throws {
        try fh.write(contentsOf: Data(bytes: chunk.baseAddress!, count: chunk.count))
    }
    mutating func close() throws {
        try fh.synchronize()
        try fh.close()
    }
}

struct FileSource: ByteSource {
    private var fh: FileHandle
    let fileSize: UInt64?
    init(url: URL) throws {
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attr[.size] as? NSNumber).map { $0.uint64Value }
        fh = try FileHandle(forReadingFrom: url)
    }
    mutating func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let data = try fh.read(upToCount: buffer.count) ?? Data()
        guard !data.isEmpty else { return 0 }
        data.copyBytes(to: buffer)
        return data.count
    }
    mutating func close() throws {
        try fh.close()
    }
}

// --- Atomic commit (temp → replace)
func atomicReplace(temp: URL, final: URL) throws {
    _ = try FileManager.default.replaceItemAt(final, withItemAt: temp, backupItemName: nil, options: [])
}
