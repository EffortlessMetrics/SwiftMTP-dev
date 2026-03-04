// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPSync

final class FormatFilterUnitTests: XCTestCase {

  // MARK: - Category contents

  func testImageFormatsContainsExpectedCodes() {
    let images = MTPFormatFilter.imageFormats
    XCTAssertTrue(images.contains(PTPObjectFormat.exifJPEG))
    XCTAssertTrue(images.contains(PTPObjectFormat.png))
    XCTAssertTrue(images.contains(PTPObjectFormat.bmp))
    XCTAssertTrue(images.contains(PTPObjectFormat.gif))
    XCTAssertTrue(images.contains(PTPObjectFormat.tiff))
    XCTAssertTrue(images.contains(PTPObjectFormat.heif))
  }

  func testAudioFormatsContainsExpectedCodes() {
    let audio = MTPFormatFilter.audioFormats
    XCTAssertTrue(audio.contains(PTPObjectFormat.mp3))
    XCTAssertTrue(audio.contains(PTPObjectFormat.wav))
    XCTAssertTrue(audio.contains(PTPObjectFormat.aac))
    XCTAssertTrue(audio.contains(PTPObjectFormat.flac))
    XCTAssertTrue(audio.contains(PTPObjectFormat.ogg))
  }

  func testVideoFormatsContainsExpectedCodes() {
    let video = MTPFormatFilter.videoFormats
    XCTAssertTrue(video.contains(PTPObjectFormat.avi))
    XCTAssertTrue(video.contains(PTPObjectFormat.mpeg))
    XCTAssertTrue(video.contains(PTPObjectFormat.mp4Container))
    XCTAssertTrue(video.contains(PTPObjectFormat.mkv))
  }

  func testDocumentFormatsContainsExpectedCodes() {
    let docs = MTPFormatFilter.documentFormats
    XCTAssertTrue(docs.contains(PTPObjectFormat.text))
    XCTAssertTrue(docs.contains(PTPObjectFormat.html))
    XCTAssertTrue(docs.contains(PTPObjectFormat.xmlDocument))
    XCTAssertTrue(docs.contains(PTPObjectFormat.msWordDocument))
  }

  // MARK: - Category sets are disjoint

  func testCategoriesAreDisjoint() {
    let sets: [Set<UInt16>] = [
      MTPFormatFilter.imageFormats,
      MTPFormatFilter.audioFormats,
      MTPFormatFilter.videoFormats,
      MTPFormatFilter.documentFormats,
    ]
    for i in 0..<sets.count {
      for j in (i + 1)..<sets.count {
        XCTAssertTrue(
          sets[i].isDisjoint(with: sets[j]),
          "Category \(i) and \(j) overlap")
      }
    }
  }

  // MARK: - Include / exclude logic

  func testEmptyFilterMatchesEverything() {
    let filter = MTPFormatFilter.all
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertTrue(filter.matches(format: 0x0000))
    XCTAssertTrue(filter.matches(format: 0xFFFF))
  }

  func testIncludeOnlyMatchesIncludedCodes() {
    let filter = MTPFormatFilter(includeCodes: [PTPObjectFormat.png, PTPObjectFormat.exifJPEG])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.text))
  }

  func testExcludeRejectsExcludedCodes() {
    let filter = MTPFormatFilter(excludeCodes: [PTPObjectFormat.mp3])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  func testExcludeTakesPrecedenceOverInclude() {
    let filter = MTPFormatFilter(
      includeCodes: [PTPObjectFormat.png, PTPObjectFormat.exifJPEG],
      excludeCodes: [PTPObjectFormat.png])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.png))
  }

  // MARK: - Factory methods

  func testCategoryFactoryImages() {
    let filter = MTPFormatFilter.category(.images)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  func testCategoryFactoryAll() {
    let filter = MTPFormatFilter.category(.all)
    XCTAssertTrue(filter.includeCodes.isEmpty)
    XCTAssertTrue(filter.excludeCodes.isEmpty)
  }

  func testIncludingExtensions() {
    let filter = MTPFormatFilter.including(extensions: ["jpg", "png"])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  func testExcludingExtensions() {
    let filter = MTPFormatFilter.excluding(extensions: [".mp3"])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  // MARK: - Case sensitivity

  func testExtensionWithDotPrefix() {
    let filter1 = MTPFormatFilter.including(extensions: [".jpg"])
    let filter2 = MTPFormatFilter.including(extensions: ["jpg"])
    XCTAssertEqual(filter1.includeCodes, filter2.includeCodes)
  }
}
