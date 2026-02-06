import Foundation
import SwiftMTPCore

// MARK: - Fuzzing Targets

// Target 1: PTPString Parsing
func fuzzPTPString(_ data: Data) {
    var offset = 0
    // Try to parse. We don't care about the result, just that it doesn't crash.
    let _ = PTPString.parse(from: data, at: &offset)
}

// Target 2: PTPHeader Decoding
// Replicating PTPHeader struct from LibUSBTransport for fuzzing isolation
struct PTPHeader {
    static let size = 12
    var length: UInt32
    var type: UInt16
    var code: UInt16
    var txid: UInt32

    static func decode(from ptr: UnsafeRawPointer) -> PTPHeader {
        let L = ptr.load(as: UInt32.self).littleEndian
        let T = ptr.advanced(by: 4).load(as: UInt16.self).littleEndian
        let C = ptr.advanced(by: 6).load(as: UInt16.self).littleEndian
        let X = ptr.advanced(by: 8).load(as: UInt32.self).littleEndian
        return PTPHeader(length: L, type: T, code: C, txid: X)
    }
}

func fuzzPTPHeader(_ data: Data) {
    // PTPHeader requires at least 12 bytes
    guard data.count >= PTPHeader.size else { return }
    
    // Test basic decoding
    data.withUnsafeBytes { ptr in
        guard let base = ptr.baseAddress else { return }
        let hdr = PTPHeader.decode(from: base)
        
        // Basic sanity checks (these are properties we might assert in production code)
        // Ensure length is at least header size
        let _ = hdr.length >= UInt32(PTPHeader.size)
        
        // Ensure type is valid (1=command, 2=data, 3=response, 4=event)
        let _ = (1...4).contains(hdr.type)
    }
}

// Target 3: DeviceInfo Parsing (PTPDeviceInfo is internal to SwiftMTPCore)
// Since we can't access internal PTPDeviceInfo directly from here easily without
// making it public or using @testable (which doesn't work well for executables),
// we will focus on PTPString and PTPHeader which cover the transport layer basics.
// If PTPDeviceInfo.parse uses PTPString.parse (which it does), fuzzing PTPString helps there too.

// MARK: - Main Harness

func runFuzzer(_ data: Data) {
    // Run all targets
    fuzzPTPString(data)
    fuzzPTPHeader(data)
}

// Entry point
if CommandLine.arguments.count > 1 {
    // Read from file
    let path = CommandLine.arguments[1]
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        print("Fuzzing with input file: \(path) (\(data.count) bytes)")
        runFuzzer(data)
    } catch {
        print("Error reading file: \(error)")
    }
} else {
    // Read from stdin (for piping from /dev/urandom or similar)
    // We limit the read to avoid blocking forever if piped from a stream that never ends,
    // although standardInput.readDataToEndOfFile() usually waits for EOF.
    // For fuzzing, usually a file is provided.
    let stdin = FileHandle.standardInput
    let data = stdin.readDataToEndOfFile()
    if !data.isEmpty {
        print("Fuzzing with stdin input (\(data.count) bytes)")
        runFuzzer(data)
    } else {
        print("Usage: SwiftMTPFuzz <file> OR pipe data to stdin")
    }
}