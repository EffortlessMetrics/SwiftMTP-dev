// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore

/// Predefined format categories for convenient filtering
public enum MTPFormatCategory: String, Sendable, CaseIterable {
  case images
  case audio
  case video
  case documents
  case all
}

/// Format-based filter for mirror/sync operations.
///
/// Supports both include and exclude logic, predefined categories
/// (e.g. `.images`, `.audio`), and explicit format codes resolved
/// from file extensions.
public struct MTPFormatFilter: Sendable {
  /// Format codes to include (empty means include all)
  public let includeCodes: Set<UInt16>
  /// Format codes to exclude
  public let excludeCodes: Set<UInt16>

  public init(includeCodes: Set<UInt16> = [], excludeCodes: Set<UInt16> = []) {
    self.includeCodes = includeCodes
    self.excludeCodes = excludeCodes
  }

  // MARK: - Predefined category sets

  public static let imageFormats: Set<UInt16> = [
    PTPObjectFormat.undefinedImage, PTPObjectFormat.exifJPEG, PTPObjectFormat.tiffEP,
    PTPObjectFormat.bmp, PTPObjectFormat.gif, PTPObjectFormat.jfif,
    PTPObjectFormat.pict, PTPObjectFormat.png, PTPObjectFormat.tiff,
    PTPObjectFormat.jp2, PTPObjectFormat.heif,
  ]

  public static let audioFormats: Set<UInt16> = [
    PTPObjectFormat.aiff, PTPObjectFormat.wav, PTPObjectFormat.mp3,
    PTPObjectFormat.wma, PTPObjectFormat.aac, PTPObjectFormat.audible,
    PTPObjectFormat.flac, PTPObjectFormat.ogg,
  ]

  public static let videoFormats: Set<UInt16> = [
    PTPObjectFormat.undefinedVideo, PTPObjectFormat.avi, PTPObjectFormat.mpeg,
    PTPObjectFormat.asf, PTPObjectFormat.wmv, PTPObjectFormat.mp4Container,
    PTPObjectFormat.mp2, PTPObjectFormat.threeGP, PTPObjectFormat.mkv,
  ]

  public static let documentFormats: Set<UInt16> = [
    PTPObjectFormat.text, PTPObjectFormat.html, PTPObjectFormat.undefinedDocument,
    PTPObjectFormat.xmlDocument, PTPObjectFormat.msWordDocument,
    PTPObjectFormat.msExcelSpreadsheet, PTPObjectFormat.msPowerPointPresentation,
  ]

  // MARK: - Factory methods

  /// A filter that passes all formats.
  public static let all = MTPFormatFilter()

  /// Create a filter for a predefined category.
  public static func category(_ cat: MTPFormatCategory) -> MTPFormatFilter {
    switch cat {
    case .images: return MTPFormatFilter(includeCodes: imageFormats)
    case .audio: return MTPFormatFilter(includeCodes: audioFormats)
    case .video: return MTPFormatFilter(includeCodes: videoFormats)
    case .documents: return MTPFormatFilter(includeCodes: documentFormats)
    case .all: return .all
    }
  }

  /// Create a filter that includes only the formats matching the given file extensions.
  public static func including(extensions: [String]) -> MTPFormatFilter {
    MTPFormatFilter(includeCodes: extensionsToCodes(extensions))
  }

  /// Create a filter that excludes the formats matching the given file extensions.
  public static func excluding(extensions: [String]) -> MTPFormatFilter {
    MTPFormatFilter(excludeCodes: extensionsToCodes(extensions))
  }

  /// Check whether a format code passes this filter.
  public func matches(format: UInt16) -> Bool {
    if excludeCodes.contains(format) { return false }
    if includeCodes.isEmpty { return true }
    return includeCodes.contains(format)
  }

  // MARK: - Private

  private static func extensionsToCodes(_ extensions: [String]) -> Set<UInt16> {
    Set(
      extensions.map { ext in
        let normalized = ext.hasPrefix(".") ? ext : ".\(ext)"
        return PTPObjectFormat.forFilename("file\(normalized)")
      })
  }
}
