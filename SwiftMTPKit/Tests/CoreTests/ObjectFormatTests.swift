import XCTest

@testable import SwiftMTPCore

final class ObjectFormatTests: XCTestCase {

  // MARK: - Standard extension → format code

  func testJPEGExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpeg"), 0x3801)
  }

  func testPNGExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), PTPObjectFormat.png)
  }

  func testGIFExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("anim.gif"), PTPObjectFormat.gif)
  }

  func testBMPExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("bitmap.bmp"), PTPObjectFormat.bmp)
  }

  func testTIFFExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("scan.tiff"), PTPObjectFormat.tiff)
    XCTAssertEqual(PTPObjectFormat.forFilename("scan.tif"), PTPObjectFormat.tiff)
  }

  func testHEIFExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("live.heic"), PTPObjectFormat.heif)
    XCTAssertEqual(PTPObjectFormat.forFilename("live.heif"), PTPObjectFormat.heif)
  }

  func testJP2Extension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("image.jp2"), PTPObjectFormat.jp2)
  }

  func testPICTExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("legacy.pict"), PTPObjectFormat.pict)
    XCTAssertEqual(PTPObjectFormat.forFilename("legacy.pct"), PTPObjectFormat.pict)
  }

  func testJFIFExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jfif"), PTPObjectFormat.jfif)
  }

  // MARK: - Audio formats

  func testMP3Extension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), PTPObjectFormat.mp3)
  }

  func testWAVExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("clip.wav"), PTPObjectFormat.wav)
  }

  func testFLACExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("lossless.flac"), PTPObjectFormat.flac)
  }

  func testAACExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("stream.aac"), PTPObjectFormat.aac)
  }

  func testOGGExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.ogg"), PTPObjectFormat.ogg)
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.oga"), PTPObjectFormat.ogg)
  }

  func testWMAExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("track.wma"), PTPObjectFormat.wma)
  }

  func testAIFFExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("sound.aiff"), PTPObjectFormat.aiff)
    XCTAssertEqual(PTPObjectFormat.forFilename("sound.aif"), PTPObjectFormat.aiff)
  }

  func testAudibleExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("book.aa"), PTPObjectFormat.audible)
    XCTAssertEqual(PTPObjectFormat.forFilename("book.aax"), PTPObjectFormat.audible)
  }

  // MARK: - Video formats

  func testMP4Extensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("movie.mp4"), PTPObjectFormat.mp4Container)
    XCTAssertEqual(PTPObjectFormat.forFilename("movie.m4v"), PTPObjectFormat.mp4Container)
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.m4a"), PTPObjectFormat.mp4Container)
  }

  func testAVIExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("clip.avi"), PTPObjectFormat.avi)
  }

  func testWMVExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("video.wmv"), PTPObjectFormat.wmv)
  }

  func testMKVExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mkv"), PTPObjectFormat.mkv)
  }

  func testThreeGPExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("phone.3gp"), PTPObjectFormat.threeGP)
    XCTAssertEqual(PTPObjectFormat.forFilename("phone.3g2"), PTPObjectFormat.threeGP)
  }

  func testMPEGExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("film.mov"), PTPObjectFormat.mpeg)
    XCTAssertEqual(PTPObjectFormat.forFilename("film.mpg"), PTPObjectFormat.mpeg)
    XCTAssertEqual(PTPObjectFormat.forFilename("film.mpeg"), PTPObjectFormat.mpeg)
  }

  func testMP2Extension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("old.mp2"), PTPObjectFormat.mp2)
  }

  func testASFExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("stream.asf"), PTPObjectFormat.asf)
  }

  // MARK: - Document formats

  func testWordExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("report.doc"), PTPObjectFormat.msWordDocument)
    XCTAssertEqual(PTPObjectFormat.forFilename("report.docx"), PTPObjectFormat.msWordDocument)
  }

  func testExcelExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("data.xls"), PTPObjectFormat.msExcelSpreadsheet)
    XCTAssertEqual(PTPObjectFormat.forFilename("data.xlsx"), PTPObjectFormat.msExcelSpreadsheet)
  }

  func testPowerPointExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("slides.ppt"), PTPObjectFormat.msPowerPointPresentation)
    XCTAssertEqual(PTPObjectFormat.forFilename("slides.pptx"), PTPObjectFormat.msPowerPointPresentation)
  }

  func testXMLExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("config.xml"), PTPObjectFormat.xmlDocument)
  }

  func testTextExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("readme.txt"), PTPObjectFormat.text)
  }

  func testHTMLExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("page.html"), PTPObjectFormat.html)
    XCTAssertEqual(PTPObjectFormat.forFilename("page.htm"), PTPObjectFormat.html)
  }

  func testPlaylistExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("songs.m3u"), PTPObjectFormat.m3uPlaylist)
    XCTAssertEqual(PTPObjectFormat.forFilename("songs.m3u8"), PTPObjectFormat.m3uPlaylist)
    XCTAssertEqual(PTPObjectFormat.forFilename("songs.wpl"), PTPObjectFormat.wplPlaylist)
  }

  // MARK: - Executable / Script

  func testScriptExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("run.sh"), PTPObjectFormat.script)
    XCTAssertEqual(PTPObjectFormat.forFilename("run.bat"), PTPObjectFormat.script)
  }

  func testExecutableExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("app.exe"), PTPObjectFormat.executable)
  }

  // MARK: - Case-insensitive matching

  func testCaseInsensitiveUppercase() {
    XCTAssertEqual(PTPObjectFormat.forFilename("PHOTO.JPG"), PTPObjectFormat.exifJPEG)
    XCTAssertEqual(PTPObjectFormat.forFilename("IMAGE.PNG"), PTPObjectFormat.png)
    XCTAssertEqual(PTPObjectFormat.forFilename("SONG.MP3"), PTPObjectFormat.mp3)
    XCTAssertEqual(PTPObjectFormat.forFilename("MOVIE.MP4"), PTPObjectFormat.mp4Container)
  }

  func testCaseInsensitiveMixedCase() {
    XCTAssertEqual(PTPObjectFormat.forFilename("Photo.Jpg"), PTPObjectFormat.exifJPEG)
    XCTAssertEqual(PTPObjectFormat.forFilename("Image.Png"), PTPObjectFormat.png)
    XCTAssertEqual(PTPObjectFormat.forFilename("Track.FlaC"), PTPObjectFormat.flac)
    XCTAssertEqual(PTPObjectFormat.forFilename("Report.DOCX"), PTPObjectFormat.msWordDocument)
  }

  // MARK: - Unknown extension → undefined

  func testUnknownExtensionReturnsUndefined() {
    XCTAssertEqual(PTPObjectFormat.forFilename("archive.zip"), PTPObjectFormat.undefined)
    XCTAssertEqual(PTPObjectFormat.forFilename("data.bin"), PTPObjectFormat.undefined)
    XCTAssertEqual(PTPObjectFormat.forFilename("model.obj"), PTPObjectFormat.undefined)
    XCTAssertEqual(PTPObjectFormat.forFilename("noext"), PTPObjectFormat.undefined)
    XCTAssertEqual(PTPObjectFormat.forFilename(""), PTPObjectFormat.undefined)
  }

  // MARK: - MIME types

  func testImageMIMETypes() {
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.exifJPEG), "image/jpeg")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.png), "image/png")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.gif), "image/gif")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.bmp), "image/bmp")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.tiff), "image/tiff")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.heif), "image/heif")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.jp2), "image/jp2")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.pict), "image/x-pict")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.jfif), "image/jpeg")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.tiffEP), "image/tiff")
  }

  func testAudioMIMETypes() {
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.mp3), "audio/mpeg")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.wav), "audio/wav")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.flac), "audio/flac")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.aac), "audio/aac")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.ogg), "audio/ogg")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.wma), "audio/x-ms-wma")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.aiff), "audio/aiff")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.audible), "audio/vnd.audible.aax")
  }

  func testVideoMIMETypes() {
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.mp4Container), "video/mp4")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.avi), "video/x-msvideo")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.wmv), "video/x-ms-wmv")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.mkv), "video/x-matroska")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.threeGP), "video/3gpp")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.mpeg), "video/mpeg")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.asf), "video/x-ms-asf")
  }

  func testDocumentMIMETypes() {
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.msWordDocument), "application/msword")
    XCTAssertEqual(
      PTPObjectFormat.mimeType(for: PTPObjectFormat.msExcelSpreadsheet), "application/vnd.ms-excel")
    XCTAssertEqual(
      PTPObjectFormat.mimeType(for: PTPObjectFormat.msPowerPointPresentation),
      "application/vnd.ms-powerpoint")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.text), "text/plain")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.html), "text/html")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.xmlDocument), "text/xml")
  }

  func testUnknownFormatMIMEFallback() {
    XCTAssertEqual(PTPObjectFormat.mimeType(for: 0xFFFF), "application/octet-stream")
    XCTAssertEqual(PTPObjectFormat.mimeType(for: PTPObjectFormat.undefined), "application/octet-stream")
  }

  // MARK: - describe() human-readable names

  func testDescribeImageFormats() {
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.exifJPEG), "EXIF/JPEG (0x3801)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.png), "PNG (0x3808)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.gif), "GIF (0x3805)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.bmp), "BMP (0x3804)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.tiff), "TIFF (0x3809)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.heif), "HEIF (0x380d)")
  }

  func testDescribeAudioFormats() {
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.mp3), "MP3 (0x3009)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.wav), "WAV (0x3008)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.flac), "FLAC (0xb906)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.aac), "AAC (0xb903)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.ogg), "OGG (0xb980)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.wma), "WMA (0xb901)")
  }

  func testDescribeVideoFormats() {
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.mp4Container), "MP4 (0xb802)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.avi), "AVI (0x300a)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.wmv), "WMV (0xb801)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.mkv), "MKV (0xb982)")
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.threeGP), "3GP (0xb804)")
  }

  func testDescribeDocumentFormats() {
    XCTAssertEqual(
      PTPObjectFormat.describe(PTPObjectFormat.msWordDocument), "MSWordDocument (0xba83)")
    XCTAssertEqual(
      PTPObjectFormat.describe(PTPObjectFormat.msExcelSpreadsheet), "MSExcelSpreadsheet (0xba85)")
    XCTAssertEqual(
      PTPObjectFormat.describe(PTPObjectFormat.msPowerPointPresentation),
      "MSPowerPointPresentation (0xba86)")
  }

  func testDescribeUnknownCode() {
    XCTAssertEqual(PTPObjectFormat.describe(0xFFFF), "Unknown (0xffff)")
  }

  func testDescribeUndefined() {
    XCTAssertEqual(PTPObjectFormat.describe(PTPObjectFormat.undefined), "Undefined (0x3000)")
  }

  // MARK: - Round-trip: forFilename → describe

  func testRoundTripJPEG() {
    let code = PTPObjectFormat.forFilename("photo.jpg")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("EXIF/JPEG"))
  }

  func testRoundTripPNG() {
    let code = PTPObjectFormat.forFilename("image.png")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("PNG"))
  }

  func testRoundTripMP3() {
    let code = PTPObjectFormat.forFilename("song.mp3")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("MP3"))
  }

  func testRoundTripMP4() {
    let code = PTPObjectFormat.forFilename("movie.mp4")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("MP4"))
  }

  func testRoundTripWord() {
    let code = PTPObjectFormat.forFilename("report.docx")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("MSWordDocument"))
  }

  func testRoundTripFLAC() {
    let code = PTPObjectFormat.forFilename("album.flac")
    let description = PTPObjectFormat.describe(code)
    XCTAssertTrue(description.contains("FLAC"))
  }

  func testRoundTripHEIC() {
    let code = PTPObjectFormat.forFilename("photo.heic")
    let mime = PTPObjectFormat.mimeType(for: code)
    let description = PTPObjectFormat.describe(code)
    XCTAssertEqual(mime, "image/heif")
    XCTAssertTrue(description.contains("HEIF"))
  }

  // MARK: - Format code constants

  func testFormatCodeValues() {
    XCTAssertEqual(PTPObjectFormat.undefined, 0x3000)
    XCTAssertEqual(PTPObjectFormat.association, 0x3001)
    XCTAssertEqual(PTPObjectFormat.exifJPEG, 0x3801)
    XCTAssertEqual(PTPObjectFormat.png, 0x3808)
    XCTAssertEqual(PTPObjectFormat.mp3, 0x3009)
    XCTAssertEqual(PTPObjectFormat.mp4Container, 0xB802)
    XCTAssertEqual(PTPObjectFormat.wmv, 0xB801)
    XCTAssertEqual(PTPObjectFormat.wma, 0xB901)
    XCTAssertEqual(PTPObjectFormat.flac, 0xB906)
    XCTAssertEqual(PTPObjectFormat.ogg, 0xB980)
    XCTAssertEqual(PTPObjectFormat.mkv, 0xB982)
    XCTAssertEqual(PTPObjectFormat.threeGP, 0xB804)
    XCTAssertEqual(PTPObjectFormat.heif, 0x380D)
    XCTAssertEqual(PTPObjectFormat.xmlDocument, 0xBA82)
    XCTAssertEqual(PTPObjectFormat.msWordDocument, 0xBA83)
    XCTAssertEqual(PTPObjectFormat.msExcelSpreadsheet, 0xBA85)
    XCTAssertEqual(PTPObjectFormat.msPowerPointPresentation, 0xBA86)
  }
}
