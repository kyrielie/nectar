//
//  ArticleThemeImportHardeningTests.swift
//  NetNewsWire-iOSTests
//
//  Covers the theme import rules: the pre-flight archive validator
//  (ArticleThemeArchiveValidator), the on-disk bundle validator
//  (ArticleThemeBundleValidator), and the download checks. Safety rules
//  (paths, links, sizes, zip features) reject; layout never does: extra files,
//  subfolders, wrapper folders, several bundles and missing theme files all
//  load. The only layout failure is an archive with no .nnwtheme folder. The upstream
//  fixtures at the bottom are copied verbatim from NetNewsWire
//  `Tests/NetNewsWireTests/ThemeUnzipTests.swift` (tag mac-7.2b4). Every other
//  archive is built in this file by `ZipBuilder`, so each fixture is reviewable.
//

import Testing
import Foundation
@testable import Nectar
@testable import ArticleTheming

@Suite struct ArticleThemeImportHardeningTests {

	typealias DownloaderError = ArticleThemeDownloader.ArticleThemeDownloaderError

	// MARK: - Upstream fixtures

	@Test func upstreamBenignArchiveExtracts() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let zipURL = try writeZip(Data(base64Encoded: Self.benignThemeZipBase64, options: .ignoreUnknownCharacters)!, to: root)
		let destination = root.appendingPathComponent("extract")
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: destination)

		#expect(themeURL.lastPathComponent == "Good Theme.nnwtheme")
		#expect(FileManager.default.fileExists(atPath: themeURL.appendingPathComponent("Info.plist").path))
	}

	@Test func upstreamPathTraversalArchiveIsRejected() throws {
		let data = Data(base64Encoded: Self.pathTraversalZipBase64, options: .ignoreUnknownCharacters)!
		try expectRejected(data)
	}

	// MARK: - Accepted shapes

	@Test func finderStyleArchiveWithJunkIsAccepted() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = ZipBuilder()
		zip.addDirectory("Good.nnwtheme/")
		zip.addFile("Good.nnwtheme/Info.plist", "plist")
		zip.addFile("Good.nnwtheme/stylesheet.css", "body {}")
		zip.addFile("Good.nnwtheme/template.html", "[[body]]")
		zip.addFile("Good.nnwtheme/License.md", "MIT")
		zip.addFile("Good.nnwtheme/.DS_Store", "junk")
		zip.addDirectory("__MACOSX/")
		zip.addFile("__MACOSX/._Good.nnwtheme", "junk")
		zip.addFile("__MACOSX/Good.nnwtheme/._Info.plist", "junk")

		let validated = try ArticleThemeArchiveValidator.validate(data: zip.build())
		#expect(validated.bundleName == "Good.nnwtheme")
		#expect(validated.fileNames == ["Info.plist", "License.md", "stylesheet.css", "template.html"])

		let zipURL = try writeZip(zip.build(), to: root)
		let destination = root.appendingPathComponent("extract")
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: destination)

		let names = try FileManager.default.contentsOfDirectory(atPath: themeURL.path).sorted()
		#expect(names == ["Info.plist", "License.md", "stylesheet.css", "template.html"])
		#expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["Good.nnwtheme"])
	}

	// MARK: - Rejected archives

	@Test func absolutePathIsRejected() throws {
		var zip = validBundle()
		zip.addFile("/etc/evil", "x")
		try expectRejected(zip.build())
	}

	@Test func backslashTraversalIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme\\..\\..\\evil.txt", "x")
		try expectRejected(zip.build())
	}

	@Test func dotComponentAndEmptyComponentAreRejected() throws {
		var dot = validBundle()
		dot.addFile("Good.nnwtheme/./extra.txt", "x")
		try expectRejected(dot.build())

		var empty = validBundle()
		empty.addFile("Good.nnwtheme//extra.txt", "x")
		try expectRejected(empty.build())
	}

	@Test func controlCharacterInNameIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme/License\u{0}.md", "x")
		try expectRejected(zip.build())
	}

	@Test func symlinkEntryIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme/License.md", "/etc/passwd", externalAttributes: UInt32(0o120777) << 16)
		try expectRejected(zip.build())
	}

	@Test func duplicatePathIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme/Info.plist", "again")
		try expectRejected(zip.build())
	}

	@Test func caseFoldedDuplicateIsRejected() throws {
		var zip = validBundle()
		zip.addFile("good.nnwtheme/info.plist", "again")
		try expectRejected(zip.build())
	}

	@Test func unicodeNormalizationDuplicateIsRejected() throws {
		var zip = ZipBuilder()
		zip.addFile("Loter\u{00ED}a.nnwtheme/Info.plist", "a")           // precomposed i-acute
		zip.addFile("Loteri\u{0301}a.nnwtheme/Info.plist", "b")          // i + combining acute
		try expectRejected(zip.build())
	}

	@Test func twoTopLevelBundlesPickOneDeterministically() throws {
		// The same two bundles in either archive order give the same answer.
		for order in [["Good", "Other"], ["Other", "Good"]] {
			var zip = ZipBuilder()
			for name in order {
				zip.addFile("\(name).nnwtheme/Info.plist", "x")
				zip.addFile("\(name).nnwtheme/stylesheet.css", "x")
				zip.addFile("\(name).nnwtheme/template.html", "x")
			}
			let validated = try ArticleThemeArchiveValidator.validate(data: zip.build())
			#expect(validated.bundleName == "Good.nnwtheme")
			#expect(validated.fileNames == ["Info.plist", "stylesheet.css", "template.html"])
		}
	}

	@Test func bundleWithThemeFilesBeatsEmptyBundle() throws {
		var zip = ZipBuilder()
		zip.addFile("Aaa.nnwtheme/readme.txt", "x")
		zip.addFile("Zzz.nnwtheme/stylesheet.css", "x")
		let validated = try ArticleThemeArchiveValidator.validate(data: zip.build())
		#expect(validated.bundleName == "Zzz.nnwtheme")
	}

	@Test func nestedBundleIsAccepted() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = ZipBuilder()
		zip.addFile("Wrapper/Good.nnwtheme/Info.plist", "x")
		zip.addFile("Wrapper/Good.nnwtheme/stylesheet.css", "x")
		zip.addFile("Wrapper/Good.nnwtheme/template.html", "x")
		zip.addFile("Wrapper/notes.txt", "x")

		let validated = try ArticleThemeArchiveValidator.validate(data: zip.build())
		#expect(validated.bundleName == "Good.nnwtheme")
		#expect(validated.bundlePath == "Wrapper/Good.nnwtheme")

		let zipURL = try writeZip(zip.build(), to: root)
		let destination = root.appendingPathComponent("extract")
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: destination)
		#expect(themeURL.lastPathComponent == "Good.nnwtheme")
		#expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["Good.nnwtheme"])
	}

	@Test func extraFilesAreIgnoredNotRejected() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = validBundle()
		zip.addFile("Good.nnwtheme/readme.txt", "x")
		zip.addFile("Good.nnwtheme/screenshot.png", "x")
		zip.addFile("Good.nnwtheme/script.js", "x")

		let zipURL = try writeZip(zip.build(), to: root)
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: root.appendingPathComponent("extract"))
		let names = try FileManager.default.contentsOfDirectory(atPath: themeURL.path).sorted()
		#expect(names == ["Info.plist", "stylesheet.css", "template.html"])
	}

	@Test func subfolderIsIgnoredNotRejected() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = validBundle()
		zip.addFile("Good.nnwtheme/img/logo.png", "x")
		zip.addFile("Good.nnwtheme/fonts/a/b/font.woff", "x")

		let zipURL = try writeZip(zip.build(), to: root)
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: root.appendingPathComponent("extract"))
		let names = try FileManager.default.contentsOfDirectory(atPath: themeURL.path).sorted()
		#expect(names == ["Info.plist", "stylesheet.css", "template.html"])
	}

	@Test func wrongCaseThemeFilesAreKeptUnderCanonicalNames() throws {
		var zip = ZipBuilder()
		zip.addFile("Good.nnwtheme/info.plist", "x")
		zip.addFile("Good.nnwtheme/Stylesheet.CSS", "x")
		zip.addFile("Good.nnwtheme/TEMPLATE.HTML", "x")
		let validated = try ArticleThemeArchiveValidator.validate(data: zip.build())
		#expect(validated.fileNames == ["Info.plist", "stylesheet.css", "template.html"])
	}

	@Test func uppercaseBundleSuffixIsNormalizedOnInstall() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = ZipBuilder()
		zip.addFile("Good.NNWTHEME/Info.plist", "x")
		zip.addFile("Good.NNWTHEME/stylesheet.css", "x")
		zip.addFile("Good.NNWTHEME/template.html", "x")
		let zipURL = try writeZip(zip.build(), to: root)
		let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: root.appendingPathComponent("extract"))
		#expect(themeURL.lastPathComponent == "Good.nnwtheme")
	}

	@Test func missingThemeFilesAreAccepted() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		var zip = ZipBuilder()
		zip.addFile("Good.nnwtheme/Info.plist", "x")
		zip.addFile("Good.nnwtheme/template.html", "x")
		var onlyCSS = ZipBuilder()
		onlyCSS.addFile("Only.nnwtheme/stylesheet.css", "x")

		for (index, builder) in [zip, onlyCSS].enumerated() {
			let dir = root.appendingPathComponent("case\(index)")
			try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			let zipURL = try writeZip(builder.build(), to: dir)
			let themeURL = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: dir.appendingPathComponent("extract"))
			#expect(themeURL.lastPathComponent.hasSuffix(".nnwtheme"))
		}
	}

	@Test func archiveWithNoBundleFolderReportsNoThemeFile() throws {
		var zip = ZipBuilder()
		zip.addFile("readme.txt", "x")
		zip.addFile("Pack/stylesheet.css", "x")
		#expect(throws: DownloaderError.self) {
			_ = try ArticleThemeArchiveValidator.validate(data: zip.build())
		}
	}

	@Test func bundleNameTricksAreRejected() throws {
		// A file, not a folder, named like a bundle.
		var file = ZipBuilder()
		file.addFile("Good.nnwtheme", "x")
		try expectRejected(file.build())

		// An empty stem.
		var emptyStem = ZipBuilder()
		emptyStem.addFile(".nnwtheme/Info.plist", "x")
		emptyStem.addFile(".nnwtheme/stylesheet.css", "x")
		emptyStem.addFile(".nnwtheme/template.html", "x")
		try expectRejected(emptyStem.build())

		// Trailing characters after the suffix.
		for suffix in [" ", ".", ".bak"] {
			var zip = ZipBuilder()
			for name in ["Info.plist", "stylesheet.css", "template.html"] {
				zip.addFile("Good.nnwtheme\(suffix)/\(name)", "x")
			}
			try expectRejected(zip.build())
		}
	}

	@Test func zip64MarkersAreRejected() throws {
		var extra = validBundle()
		extra.addFile("Good.nnwtheme/License.md", "x", extra: Data([0x01, 0x00, 0x00, 0x00]))
		try expectRejected(extra.build())

		var sentinel = validBundle()
		sentinel.addFile("Good.nnwtheme/License.md", "x", declaredCompressedSize: 0xFFFFFFFF, declaredUncompressedSize: 0xFFFFFFFF)
		try expectRejected(sentinel.build())

		var locator = validBundle()
		locator.zip64Locator = true
		try expectRejected(locator.build())
	}

	@Test func encryptedEntryIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme/License.md", "x", flags: 0x0001)
		try expectRejected(zip.build())
	}

	@Test func compressedSizeOverCapIsRejected() throws {
		var zip = validBundle()
		zip.addFile("Good.nnwtheme/License.md", Data(count: Int(ArticleThemeArchiveValidator.maxCompressedSize) + 1))
		let data = zip.build()
		#expect(throws: DownloaderError.tooLarge) {
			_ = try ArticleThemeArchiveValidator.validate(data: data)
		}
		try expectRejected(data)
	}

	@Test func declaredExpandedSizeOverCapIsRejected() throws {
		var zip = validBundle()
		let overCap = UInt32(ArticleThemeArchiveValidator.maxExpandedSize) + 1
		zip.addFile("Good.nnwtheme/License.md", "x", method: 8, declaredUncompressedSize: overCap)
		let data = zip.build()
		#expect(throws: DownloaderError.tooLarge) {
			_ = try ArticleThemeArchiveValidator.validate(data: data)
		}
		try expectRejected(data)
	}

	@Test func truncatedAndGarbageDataAreRejected() throws {
		#expect(throws: DownloaderError.self) {
			_ = try ArticleThemeArchiveValidator.validate(data: Data("not a zip".utf8))
		}
		let good = validBundle().build()
		#expect(throws: DownloaderError.self) {
			_ = try ArticleThemeArchiveValidator.validate(data: good.prefix(good.count - 10))
		}
	}

	// MARK: - Local bundle directories

	@Test func localBundleWithSymlinkIsRejected() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root)
		try ArticleThemeBundleValidator.validate(directory: bundle)

		let link = bundle.appendingPathComponent("License.md")
		try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/etc/passwd")
		#expect(throws: DownloaderError.self) {
			try ArticleThemeBundleValidator.validate(directory: bundle)
		}
	}

	@Test func localBundleWithSymlinkedRequiredFileIsRejected() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root)
		let stylesheet = bundle.appendingPathComponent("stylesheet.css")
		let real = root.appendingPathComponent("real.css")
		try FileManager.default.moveItem(at: stylesheet, to: real)
		try FileManager.default.createSymbolicLink(atPath: stylesheet.path, withDestinationPath: real.path)
		#expect(throws: DownloaderError.self) {
			try ArticleThemeBundleValidator.validate(directory: bundle)
		}
	}

	@Test func localBundleWithSubfolderOrExtraFileIsAcceptedAndPruned() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root)
		try FileManager.default.createDirectory(at: bundle.appendingPathComponent("img"), withIntermediateDirectories: false)
		try Data("x".utf8).write(to: bundle.appendingPathComponent("script.js"))
		try Data("x".utf8).write(to: bundle.appendingPathComponent("License.md"))
		try ArticleThemeBundleValidator.validate(directory: bundle)

		let copy = root.appendingPathComponent("copy.nnwtheme")
		try ArticleThemeBundleValidator.copyInstallableFiles(from: bundle, to: copy)
		let names = try FileManager.default.contentsOfDirectory(atPath: copy.path).sorted()
		#expect(names == ["Info.plist", "License.md", "stylesheet.css", "template.html"])
	}

	@Test func localBundleMissingThemeFilesIsAccepted() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root)
		try FileManager.default.removeItem(at: bundle.appendingPathComponent("template.html"))
		try FileManager.default.removeItem(at: bundle.appendingPathComponent("Info.plist"))
		try ArticleThemeBundleValidator.validate(directory: bundle)
	}

	@Test func themeWithoutUsableInfoPlistStillLoads() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root) // Info.plist holds "x", which is not a plist
		let theme = try ArticleTheme(url: bundle, isAppTheme: false)
		#expect(theme.name == "Local")
		#expect(theme.creatorName == "Unknown")
		#expect(theme.creatorHomePage == "Unknown")

		try FileManager.default.removeItem(at: bundle.appendingPathComponent("Info.plist"))
		let noPlist = try ArticleTheme(url: bundle, isAppTheme: false)
		#expect(noPlist.name == "Local")
	}

	@Test func localBundleJunkIsToleratedButMustBeRegular() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let bundle = try makeLocalBundle(in: root)
		try Data("x".utf8).write(to: bundle.appendingPathComponent(".DS_Store"))
		try ArticleThemeBundleValidator.validate(directory: bundle)

		try FileManager.default.removeItem(at: bundle.appendingPathComponent(".DS_Store"))
		try FileManager.default.createSymbolicLink(atPath: bundle.appendingPathComponent("._Info.plist").path, withDestinationPath: "/etc/passwd")
		#expect(throws: DownloaderError.self) {
			try ArticleThemeBundleValidator.validate(directory: bundle)
		}
	}

	// MARK: - Download checks

	@Test func downloadURLSchemeMustBeHTTPOrHTTPS() throws {
		try ArticleThemeDownloader.validateDownloadURL(URL(string: "https://example.com/t.zip")!)
		try ArticleThemeDownloader.validateDownloadURL(URL(string: "http://example.com/t.zip")!)
		for bad in ["ftp://example.com/t.zip", "file:///etc/passwd", "data:text/plain,hi"] {
			#expect(throws: DownloaderError.unsupportedURLScheme) {
				try ArticleThemeDownloader.validateDownloadURL(URL(string: bad)!)
			}
		}
	}

	@Test func downloadResponseMustBe2xx() throws {
		let url = URL(string: "https://example.com/t.zip")!
		func response(_ status: Int) -> URLResponse {
			HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
		}
		try ArticleThemeDownloader.validateDownloadResponse(response(200))
		try ArticleThemeDownloader.validateDownloadResponse(response(204))
		#expect(throws: DownloaderError.badResponse(404)) {
			try ArticleThemeDownloader.validateDownloadResponse(response(404))
		}
		#expect(throws: DownloaderError.badResponse(0)) {
			try ArticleThemeDownloader.validateDownloadResponse(nil)
		}
	}

	@Test func oversizedDownloadIsRejectedBeforeMove() throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let big = root.appendingPathComponent("big.tmp")
		try Data(count: Int(ArticleThemeArchiveValidator.maxCompressedSize) + 1).write(to: big)
		#expect(throws: DownloaderError.tooLarge) {
			_ = try ArticleThemeDownloader.shared.moveDownloadedTheme(from: big)
		}
		#expect(FileManager.default.fileExists(atPath: big.path))
	}
}

// MARK: - Helpers

private extension ArticleThemeImportHardeningTests {

	func makeRoot() throws -> URL {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	func writeZip(_ data: Data, to directory: URL) throws -> URL {
		let url = directory.appendingPathComponent("theme.zip")
		try data.write(to: url)
		return url
	}

	func validBundle() -> ZipBuilder {
		var zip = ZipBuilder()
		zip.addFile("Good.nnwtheme/Info.plist", "plist")
		zip.addFile("Good.nnwtheme/stylesheet.css", "body {}")
		zip.addFile("Good.nnwtheme/template.html", "[[body]]")
		return zip
	}

	func makeLocalBundle(in root: URL) throws -> URL {
		let bundle = root.appendingPathComponent("Local.nnwtheme", isDirectory: true)
		try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
		for name in ArticleThemeArchiveValidator.requiredFileNames {
			try Data("x".utf8).write(to: bundle.appendingPathComponent(name))
		}
		return bundle
	}

	/// Asserts the archive is refused by the validator and by the full extraction path,
	/// that nothing is written outside the destination, and that the destination is gone.
	func expectRejected(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
		let root = try makeRoot()
		defer { try? FileManager.default.removeItem(at: root) }

		let zipURL = try writeZip(data, to: root)
		let destination = root.appendingPathComponent("extract")

		do {
			_ = try ArticleThemeDownloader.shared.unzipTheme(at: zipURL, to: destination)
			Issue.record("Expected the archive to be rejected.", sourceLocation: sourceLocation)
		} catch {
			#expect(error is DownloaderError, "Unexpected error: \(error)", sourceLocation: sourceLocation)
		}

		#expect(!FileManager.default.fileExists(atPath: destination.path), sourceLocation: sourceLocation)
		let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
		#expect(remaining == [zipURL.lastPathComponent], "Nothing may be written beside the archive.", sourceLocation: sourceLocation)
	}
}

// MARK: - In-test zip writer

/// A minimal ZIP writer. Entries are stored (method 0) unless a test asks to
/// declare otherwise; sizes and flags can be falsified per entry.
private struct ZipBuilder {

	var zip64Locator = false
	private var items: [Item] = []

	private struct Item {
		var name: String
		var data: Data
		var method: UInt16
		var flags: UInt16
		var externalAttributes: UInt32
		var extra: Data
		var declaredCompressedSize: UInt32?
		var declaredUncompressedSize: UInt32?
	}

	mutating func addFile(_ name: String,
	                      _ content: String,
	                      method: UInt16 = 0,
	                      flags: UInt16 = 0,
	                      externalAttributes: UInt32 = UInt32(0o100644) << 16,
	                      extra: Data = Data(),
	                      declaredCompressedSize: UInt32? = nil,
	                      declaredUncompressedSize: UInt32? = nil) {
		addFile(name, Data(content.utf8), method: method, flags: flags, externalAttributes: externalAttributes,
				extra: extra, declaredCompressedSize: declaredCompressedSize, declaredUncompressedSize: declaredUncompressedSize)
	}

	mutating func addFile(_ name: String,
	                      _ data: Data,
	                      method: UInt16 = 0,
	                      flags: UInt16 = 0,
	                      externalAttributes: UInt32 = UInt32(0o100644) << 16,
	                      extra: Data = Data(),
	                      declaredCompressedSize: UInt32? = nil,
	                      declaredUncompressedSize: UInt32? = nil) {
		items.append(Item(name: name, data: data, method: method, flags: flags, externalAttributes: externalAttributes,
						  extra: extra, declaredCompressedSize: declaredCompressedSize, declaredUncompressedSize: declaredUncompressedSize))
	}

	mutating func addDirectory(_ name: String) {
		items.append(Item(name: name, data: Data(), method: 0, flags: 0, externalAttributes: (UInt32(0o040755) << 16) | 0x10,
						  extra: Data(), declaredCompressedSize: nil, declaredUncompressedSize: nil))
	}

	func build() -> Data {
		var out = Data()
		var central = Data()

		for item in items {
			let offset = UInt32(out.count)
			let nameBytes = Data(item.name.utf8)
			let crc = Self.crc32(item.data)
			let compressed = item.declaredCompressedSize ?? UInt32(item.data.count)
			let uncompressed = item.declaredUncompressedSize ?? UInt32(item.data.count)

			out.le32(0x04034b50)
			out.le16(20)
			out.le16(item.flags)
			out.le16(item.method)
			out.le16(0)
			out.le16(0x21)
			out.le32(crc)
			out.le32(compressed)
			out.le32(uncompressed)
			out.le16(UInt16(nameBytes.count))
			out.le16(0)
			out.append(nameBytes)
			out.append(item.data)

			central.le32(0x02014b50)
			central.le16(0x031E)          // made by: Unix, version 3.0
			central.le16(20)
			central.le16(item.flags)
			central.le16(item.method)
			central.le16(0)
			central.le16(0x21)
			central.le32(crc)
			central.le32(compressed)
			central.le32(uncompressed)
			central.le16(UInt16(nameBytes.count))
			central.le16(UInt16(item.extra.count))
			central.le16(0)
			central.le16(0)
			central.le16(0)
			central.le32(item.externalAttributes)
			central.le32(offset)
			central.append(nameBytes)
			central.append(item.extra)
		}

		let directoryOffset = UInt32(out.count)
		out.append(central)

		if zip64Locator {
			// 20 bytes: signature, disk, 8-byte offset, total disks.
			out.le32(0x07064b50)
			out.le32(0)
			out.le32(0)
			out.le32(0)
			out.le32(1)
		}

		out.le32(0x06054b50)
		out.le16(0)
		out.le16(0)
		out.le16(UInt16(items.count))
		out.le16(UInt16(items.count))
		out.le32(UInt32(central.count))
		out.le32(directoryOffset)
		out.le16(0)
		return out
	}

	private static let crcTable: [UInt32] = (0..<256).map { index in
		var value = UInt32(index)
		for _ in 0..<8 {
			value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
		}
		return value
	}

	private static func crc32(_ data: Data) -> UInt32 {
		var crc: UInt32 = 0xFFFFFFFF
		for byte in data {
			crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
		}
		return crc ^ 0xFFFFFFFF
	}
}

private extension Data {

	mutating func le16(_ value: UInt16) {
		append(UInt8(value & 0xFF))
		append(UInt8(value >> 8))
	}

	mutating func le32(_ value: UInt32) {
		for shift in stride(from: 0, to: 32, by: 8) {
			append(UInt8((value >> UInt32(shift)) & 0xFF))
		}
	}
}

// MARK: - Upstream fixtures (verbatim)

// benignThemeZip:   Good Theme.nnwtheme/{Info.plist, stylesheet.css, template.html}
// pathTraversalZip: Good Theme.nnwtheme/Info.plist, then ../escaped.txt
private extension ArticleThemeImportHardeningTests {

	static let benignThemeZipBase64 = """
	UEsDBBQAAAAAAGejH10lf2Ft4wAAAOMAAAAeAAAAR29vZCBUaGVtZS5ubnd0aGVtZS9JbmZvLnBsaXN0PD94bWwgdmVyc2lvbj0i
	MS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VO
	IiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPjxk
	aWN0PjxrZXk+bmFtZTwva2V5PjxzdHJpbmc+R29vZCBUaGVtZTwvc3RyaW5nPjwvZGljdD48L3BsaXN0PgpQSwMEFAAAAAAAZ6Mf
	XVokqGUXAAAAFwAAACIAAABHb29kIFRoZW1lLm5ud3RoZW1lL3N0eWxlc2hlZXQuY3NzYm9keSB7IGNvbG9yOiBibGFjazsgfQpQ
	SwMEFAAAAAAAZ6MfXZN1YIIjAAAAIwAAACEAAABHb29kIFRoZW1lLm5ud3RoZW1lL3RlbXBsYXRlLmh0bWw8aHRtbD48Ym9keT5b
	W2JvZHldXTwvYm9keT48L2h0bWw+ClBLAQIUAxQAAAAAAGejH10lf2Ft4wAAAOMAAAAeAAAAAAAAAAAAAACAAQAAAABHb29kIFRo
	ZW1lLm5ud3RoZW1lL0luZm8ucGxpc3RQSwECFAMUAAAAAABnox9dWiSoZRcAAAAXAAAAIgAAAAAAAAAAAAAAgAEfAQAAR29vZCBU
	aGVtZS5ubnd0aGVtZS9zdHlsZXNoZWV0LmNzc1BLAQIUAxQAAAAAAGejH12TdWCCIwAAACMAAAAhAAAAAAAAAAAAAACAAXYBAABH
	b29kIFRoZW1lLm5ud3RoZW1lL3RlbXBsYXRlLmh0bWxQSwUGAAAAAAMAAwDrAAAA2AEAAAAA
	"""

	static let pathTraversalZipBase64 = """
	UEsDBBQAAAAAAA2mH10lf2Ft4wAAAOMAAAAeAAAAR29vZCBUaGVtZS5ubnd0aGVtZS9JbmZvLnBsaXN0PD94bWwgdmVyc2lvbj0i
	MS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VO
	IiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPjxk
	aWN0PjxrZXk+bmFtZTwva2V5PjxzdHJpbmc+R29vZCBUaGVtZTwvc3RyaW5nPjwvZGljdD48L3BsaXN0PgpQSwMEFAAAAAAADaYf
	XVsM+JIHAAAABwAAAA4AAAAuLi9lc2NhcGVkLnR4dGVzY2FwZWRQSwECFAMUAAAAAAANph9dJX9hbeMAAADjAAAAHgAAAAAAAAAA
	AAAAgAEAAAAAR29vZCBUaGVtZS5ubnd0aGVtZS9JbmZvLnBsaXN0UEsBAhQDFAAAAAAADaYfXVsM+JIHAAAABwAAAA4AAAAAAAAA
	AAAAAIABHwEAAC4uL2VzY2FwZWQudHh0UEsFBgAAAAACAAIAiAAAAFIBAAAAAA==
	"""
}
