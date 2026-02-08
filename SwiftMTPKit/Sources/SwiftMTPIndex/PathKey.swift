// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Path normalization utilities for consistent, cross-platform path handling
public enum PathKey {
    /// Normalize a storage-relative path with components
    /// - Parameters:
    ///   - storage: Storage ID
    ///   - components: Path components from root to file/folder
    /// - Returns: Normalized path key in format "storageId/component1/component2/..."
    public static func normalize(storage: UInt32, components: [String]) -> String {
        let prefix = String(format: "%08x", storage)
        guard !components.isEmpty else { return prefix }
        let normalized = components.map { normalizeComponent($0) }
        return prefix + "/" + normalized.joined(separator: "/")
    }

    /// Normalize a single path component
    /// - Parameter component: Raw component name
    /// - Returns: Normalized component (NFC, stripped of control chars and slashes)
    public static func normalizeComponent(_ component: String) -> String {
        // Convert to NFC (canonical decomposition followed by canonical composition)
        let nfc = component.precomposedStringWithCanonicalMapping

        // Filter out control characters and path separators
        let filtered = nfc.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && scalar != "/" && scalar != "\\"
        }

        let cleaned = String(String.UnicodeScalarView(filtered))

        // Return underscore for empty components (shouldn't happen but defensive)
        return cleaned.isEmpty ? "_" : cleaned
    }

    /// Split a path key back into storage ID and components
    /// - Parameter pathKey: Normalized path key
    /// - Returns: Tuple of (storageId, components)
    public static func parse(_ pathKey: String) -> (storageId: UInt32, components: [String]) {
        guard let slashIdx = pathKey.firstIndex(of: "/") else {
            // Bare storage ID with no components (e.g. "00010001")
            let storageId = UInt32(pathKey, radix: 16) ?? 0
            return (storageId, [])
        }

        let storageHex = pathKey[pathKey.startIndex..<slashIdx]
        let storageId = UInt32(storageHex, radix: 16) ?? 0
        let rest = pathKey[pathKey.index(after: slashIdx)...]
        let components = rest.split(separator: "/").map(String.init)

        return (storageId, components)
    }

    /// Get the parent path key
    /// - Parameter pathKey: Child path key
    /// - Returns: Parent path key, or nil if already at root
    public static func parent(of pathKey: String) -> String? {
        let (storageId, components) = parse(pathKey)
        guard !components.isEmpty else { return nil }

        let parentComponents = components.dropLast()
        guard !parentComponents.isEmpty else { return nil }

        return normalize(storage: storageId, components: Array(parentComponents))
    }

    /// Get the basename (last component) of a path key
    /// - Parameter pathKey: Path key
    /// - Returns: Basename
    public static func basename(of pathKey: String) -> String {
        let (_, components) = parse(pathKey)
        return components.last ?? ""
    }

    /// Check if one path is a prefix of another
    /// - Parameters:
    ///   - prefix: Potential prefix path
    ///   - path: Full path to check
    /// - Returns: True if prefix is a directory prefix of path
    public static func isPrefix(_ prefix: String, of path: String) -> Bool {
        let (prefixStorage, prefixComponents) = parse(prefix)
        let (pathStorage, pathComponents) = parse(path)

        guard prefixStorage == pathStorage else { return false }
        guard prefixComponents.count < pathComponents.count else { return false }

        return zip(prefixComponents, pathComponents).allSatisfy { $0 == $1 }
    }

    /// Create a path key from a local file URL relative to a root
    /// - Parameters:
    ///   - url: Local file URL
    ///   - rootURL: Root directory URL
    ///   - storage: Storage ID for the device
    /// - Returns: Path key, or nil if URL is not under root
    public static func fromLocalURL(_ url: URL, relativeTo rootURL: URL, storage: UInt32) -> String? {
        guard url.path.hasPrefix(rootURL.path) else { return nil }

        let relativePath = url.path.dropFirst(rootURL.path.count)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        return normalize(storage: storage, components: components)
    }
}
