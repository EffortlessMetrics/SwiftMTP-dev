import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

@Suite("File Transfer Scenario Tests")
struct FileTransferScenarioTests {

    @Test("Mock device file download works")
    func testMockFileDownload() async throws {
        // Create mock transport
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        // Open device
        let link = try await transport.open(deviceSummary)
        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Find a file to download (first file in mock data)
        guard let firstObject = mockData.objects.first(where: { $0.sizeBytes != nil }) else {
            Issue.record("No files found in mock data")
            return
        }

        // Create temp output file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_download.tmp")

        do {
            // Download file
            let progress = try await device.read(handle: firstObject.handle, range: nil, to: tempURL)

            // Verify download
            let fileData = try Data(contentsOf: tempURL)
            #expect(fileData.count > 0)
            #expect(Int64(fileData.count) == progress.completedUnitCount)

            // Verify file exists
            #expect(FileManager.default.fileExists(atPath: tempURL.path))

        } catch {
            Issue.record("Mock file download test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
        await link.close()
    }

    @Test("Mock device file upload works")
    func testMockFileUpload() async throws {
        // Create mock transport
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        // Open device
        let link = try await transport.open(deviceSummary)
        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Create a test file to upload
        let testFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_upload.tmp")
        let testData: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        try Data(testData).write(to: testFileURL)

        do {
            // Upload file (use root as parent)
            let progress = try await device.write(parent: nil, name: "test_upload.tmp",
                                                 size: UInt64(testData.count), from: testFileURL)

            // Verify upload progress
            #expect(progress.completedUnitCount == Int64(testData.count))

        } catch {
            Issue.record("Mock file upload test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testFileURL)
        await link.close()
    }

    @Test("Transfer cancellation works")
    func testTransferCancellation() async throws {
        // Create mock transport
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        // Open device
        let link = try await transport.open(deviceSummary)
        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Find a file to download
        guard let firstObject = mockData.objects.first(where: { $0.sizeBytes != nil }) else {
            Issue.record("No files found in mock data")
            return
        }

        // Create temp output file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_cancel.tmp")

        do {
            // Start download in a task that we'll cancel
            let downloadTask = Task {
                try await device.read(handle: firstObject.handle, range: nil, to: tempURL)
            }

            // Cancel immediately
            downloadTask.cancel()

            // Wait for cancellation
            do {
                _ = try await downloadTask.value
                Issue.record("Expected task to be cancelled")
            } catch {
                // Expected to catch cancellation
                if !Task.isCancelled && !(error is CancellationError) {
                    Issue.record("Unexpected error: \(error)")
                }
            }

        } catch {
            Issue.record("Transfer cancellation test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
        await link.close()
    }
}
