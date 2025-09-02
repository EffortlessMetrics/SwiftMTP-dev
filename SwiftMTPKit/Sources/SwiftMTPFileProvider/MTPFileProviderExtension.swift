import FileProvider
import SwiftMTPXPC

/// Main File Provider extension for MTP devices
/// This handles domain management and content hydration
public final class MTPFileProviderExtension: NSFileProviderReplicatedExtension {
    private var xpcConnection: NSXPCConnection?

    public override init() {
        super.init()
    }

    // MARK: - Domain Management

    public override func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        // Parse the identifier to determine what type of item this is
        guard let components = MTPFileProviderItem.parseItemIdentifier(identifier) else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            return
        }

        // For tech preview, create a basic item based on the identifier
        // In full implementation, you'd query the device for current metadata
        let item = MTPFileProviderItem(
            deviceId: components.deviceId,
            storageId: components.storageId,
            objectHandle: components.objectHandle,
            name: components.objectHandle != nil ? "Object \(components.objectHandle!)" : (components.storageId != nil ? "Storage \(components.storageId!)" : "Device \(components.deviceId)"),
            size: nil, // Would query device
            isDirectory: components.objectHandle == nil, // Simplified assumption
            modifiedDate: nil
        )

        completionHandler(item, nil)
    }

    public override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier, completionHandler: @escaping (URL?, Error?) -> Void) {
        // For tech preview, return nil (items are virtual)
        // In full implementation, you'd return a URL to a local cache or temp file
        completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
    }

    public override func persistentIdentifierForItem(at url: URL, completionHandler: @escaping (NSFileProviderItemIdentifier?, Error?) -> Void) {
        // For tech preview, not implemented
        completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
    }

    public override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        // Create a placeholder file for the item
        // This allows Finder to show the item before it's downloaded
        do {
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            let itemIdentifier = NSFileProviderItemIdentifier(url.lastPathComponent) // Simplified

            let placeholderData = try NSFileProviderManager.writePlaceholder(at: placeholderURL,
                                                                           withMetadata: [:]) // Would include item metadata
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    // MARK: - Enumeration

    public override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let components = MTPFileProviderItem.parseItemIdentifier(containerItemIdentifier) else {
            throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
        }

        return DomainEnumerator(
            deviceId: components.deviceId,
            storageId: components.storageId,
            parentHandle: components.objectHandle
        )
    }

    // MARK: - Content Hydration

    public override func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let components = MTPFileProviderItem.parseItemIdentifier(itemIdentifier),
              let objectHandle = components.objectHandle else {
            completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            return Progress()
        }

        // Ensure we have an XPC connection
        ensureXPCConnection()

        guard let xpcService = xpcConnection?.remoteObjectProxy as? MTPXPCService else {
            completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.serverUnreachable.rawValue))
            return Progress()
        }

        let progress = Progress(totalUnitCount: 1)

        // Request the file from the XPC service
        let readRequest = ReadRequest(deviceId: components.deviceId, objectHandle: objectHandle)

        xpcService.readObject(readRequest) { response in
            if response.success, let tempFileURL = response.tempFileURL {
                // Create the item with metadata from the response
                let item = MTPFileProviderItem(
                    deviceId: components.deviceId,
                    storageId: components.storageId,
                    objectHandle: objectHandle,
                    name: "Downloaded Object", // Would get from device
                    size: response.fileSize,
                    isDirectory: false,
                    modifiedDate: nil
                )

                completionHandler(tempFileURL, item, nil)
                progress.completedUnitCount = 1
            } else {
                let error = NSError(
                    domain: NSFileProviderErrorDomain,
                    code: NSFileProviderError.cannotSynchronize.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: response.errorMessage ?? "Download failed"]
                )
                completionHandler(nil, nil, error)
                progress.completedUnitCount = 1
            }
        }

        return progress
    }

    // MARK: - Private Helpers

    private func ensureXPCConnection() {
        if xpcConnection == nil {
            xpcConnection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
            xpcConnection?.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
            xpcConnection?.resume()
        }
    }

    deinit {
        xpcConnection?.invalidate()
    }
}

// MARK: - Domain Setup

/// Helper for setting up File Provider domains for MTP devices
public struct MTPFileProviderDomain {
    public static func domainIdentifier(for deviceId: String) -> NSFileProviderDomainIdentifier {
        return NSFileProviderDomainIdentifier("com.example.SwiftMTP.\(deviceId)")
    }

    public static func displayName(for deviceId: String) -> String {
        return "MTP Device \(deviceId)"
    }

    public static func createDomain(for deviceId: String) -> NSFileProviderDomain {
        let identifier = domainIdentifier(for: deviceId)
        let displayName = displayName(for: deviceId)
        return NSFileProviderDomain(identifier: identifier, displayName: displayName)
    }
}
