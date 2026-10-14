//
//  ArticleThemeArchiveValidator.swift
//  ArticleTheming
//
//  Validates a downloaded theme archive by reading only its central directory,
//  before any byte is extracted. The rules mirror the upstream `nnw-theme`
//  validator (D15, D16 in the theme color probe plan): exactly one top-level
//  `<Name>.nnwtheme` folder holding only `Info.plist`, `template.html`,
//  `stylesheet.css` and optional `LICENSE*` / `NOTICE*` files.
//

import Foundation

/// The outcome of a successful archive validation.
public struct ValidatedArchive: Sendable, Equatable {
	/// The single top-level bundle folder, for example `Sepia.nnwtheme`.
	public let bundleName: String
	/// Names of the files inside the bundle folder (junk entries excluded).
	public let fileNames: [String]
	/// Sum of the declared uncompressed sizes of every entry, junk included.
	public let totalUncompressedSize: UInt64
}

public enum ArticleThemeArchiveValidator {

	public static let maxCompressedSize: UInt64 = 10_000_000
	public static let maxExpandedSize: UInt64 = 50 * 1024 * 1024

	public static let requiredFileNames: [String] = ["Info.plist", "template.html", "stylesheet.css"]

	private typealias Failure = ArticleThemeDownloader.ArticleThemeDownloaderError

	// MARK: - Entry points

	public static func validate(zipURL: URL) throws -> ValidatedArchive {
		let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
		if let size = (attributes[.size] as? NSNumber)?.uint64Value, size > maxCompressedSize {
			throw Failure.tooLarge
		}
		let data = try Data(contentsOf: zipURL)
		return try validate(data: data)
	}

	public static func validate(data: Data) throws -> ValidatedArchive {
		guard UInt64(data.count) <= maxCompressedSize else {
			throw Failure.tooLarge
		}
		let bytes = [UInt8](data)
		let entries = try parseCentralDirectory(bytes)
		return try checkLayout(entries)
	}

	// MARK: - Central directory

	private struct Entry {
		let path: String          // normalized, no trailing slash
		let isDirectory: Bool
		let uncompressedSize: UInt64
	}

	private static func parseCentralDirectory(_ bytes: [UInt8]) throws -> [Entry] {
		let reader = Reader(bytes: bytes)
		let eocdSize = 22
		let eocdSignature: UInt64 = 0x06054b50
		let cdSignature: UInt64 = 0x02014b50
		let localSignature: UInt64 = 0x04034b50

		guard bytes.count >= eocdSize else {
			throw fail("The file is too small to be a zip archive.")
		}

		// Find the end-of-central-directory record in the last 65,557 bytes.
		// A candidate is accepted only if its comment length reaches exactly to
		// the end of the file, so a signature inside a comment cannot win.
		let lowest = max(0, bytes.count - (0xFFFF + eocdSize))
		var eocd: Int?
		var index = bytes.count - eocdSize
		while index >= lowest {
			if try reader.u32(index) == eocdSignature {
				let commentLength = try reader.u16(index + 20)
				if index + eocdSize + commentLength == bytes.count {
					eocd = index
					break
				}
			}
			index -= 1
		}
		guard let eocd else {
			throw fail("The file is not a zip archive.")
		}

		// ZIP64 locator sits immediately before the EOCD.
		if eocd >= 20, try reader.u32(eocd - 20) == 0x07064b50 {
			throw fail("ZIP64 archives are not supported.")
		}

		let diskNumber = try reader.u16(eocd + 4)
		let directoryDisk = try reader.u16(eocd + 6)
		let entriesOnDisk = try reader.u16(eocd + 8)
		let totalEntries = try reader.u16(eocd + 10)
		let directorySize = try reader.u32(eocd + 12)
		let directoryOffset = try reader.u32(eocd + 16)

		if totalEntries == 0xFFFF || directorySize == 0xFFFFFFFF || directoryOffset == 0xFFFFFFFF {
			throw fail("ZIP64 archives are not supported.")
		}
		guard diskNumber == 0, directoryDisk == 0, entriesOnDisk == totalEntries else {
			throw fail("Multi-part archives are not supported.")
		}
		guard totalEntries > 0 else {
			throw fail("The archive is empty.")
		}
		let cdStart = Int(directoryOffset)
		let cdEnd = cdStart + Int(directorySize)
		guard cdEnd <= eocd else {
			throw fail("The archive directory is damaged.")
		}

		var entries: [Entry] = []
		var position = cdStart
		for _ in 0..<totalEntries {
			guard try reader.u32(position) == cdSignature else {
				throw fail("The archive directory is damaged.")
			}
			let madeBy = try reader.u16(position + 4)
			let flags = try reader.u16(position + 8)
			let method = try reader.u16(position + 10)
			let compressedSize = try reader.u32(position + 20)
			let uncompressedSize = try reader.u32(position + 24)
			let nameLength = try reader.u16(position + 28)
			let extraLength = try reader.u16(position + 30)
			let commentLength = try reader.u16(position + 32)
			let startDisk = try reader.u16(position + 34)
			let externalAttributes = try reader.u32(position + 38)
			let localOffset = try reader.u32(position + 42)

			let nameStart = position + 46
			let extraStart = nameStart + nameLength
			let next = extraStart + extraLength + commentLength
			guard next <= cdEnd else {
				throw fail("The archive directory is damaged.")
			}

			if flags & 0x0001 != 0 || flags & 0x0040 != 0 || flags & 0x2000 != 0 {
				throw fail("Encrypted archives are not supported.")
			}
			guard method == 0 || method == 8 else {
				throw fail("The archive uses an unsupported compression method.")
			}
			guard startDisk == 0 else {
				throw fail("Multi-part archives are not supported.")
			}
			if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
				throw fail("ZIP64 archives are not supported.")
			}
			if method == 0 && compressedSize != uncompressedSize {
				throw fail("The archive directory is damaged.")
			}

			// Reject the ZIP64 extended information extra field (id 0x0001).
			var extra = extraStart
			while extra + 4 <= extraStart + extraLength {
				let id = try reader.u16(extra)
				let size = try reader.u16(extra + 2)
				if id == 0x0001 {
					throw fail("ZIP64 archives are not supported.")
				}
				extra += 4 + size
			}

			// Entries written on a Unix host carry the file mode in the high
			// half of the external attributes. Only regular files and
			// directories are acceptable; this rejects symlinks.
			if madeBy >> 8 == 3 {
				let fileType = (externalAttributes >> 16) & 0o170000
				guard fileType == 0 || fileType == 0o100000 || fileType == 0o040000 else {
					throw fail("The archive contains a link or special file.")
				}
			}

			let nameBytes = Array(bytes[nameStart..<extraStart])
			guard let rawName = String(bytes: nameBytes, encoding: .utf8) else {
				throw fail("The archive contains a file name that is not valid UTF-8.")
			}
			let (path, isDirectory) = try normalize(rawName)

			// The local header must agree with the directory, and the data
			// must lie before the central directory.
			let local = Int(localOffset)
			guard try reader.u32(local) == localSignature else {
				throw fail("The archive is damaged.")
			}
			let localNameLength = try reader.u16(local + 26)
			let localExtraLength = try reader.u16(local + 28)
			let localNameStart = local + 30
			guard localNameStart + localNameLength <= bytes.count,
				  Array(bytes[localNameStart..<(localNameStart + localNameLength)]) == nameBytes else {
				throw fail("The archive is damaged.")
			}
			let dataStart = localNameStart + localNameLength + localExtraLength
			guard dataStart + Int(compressedSize) <= cdStart else {
				throw fail("The archive is damaged.")
			}

			entries.append(Entry(path: path, isDirectory: isDirectory, uncompressedSize: uncompressedSize))
			position = next
		}
		return entries
	}

	/// Normalizes `\` to `/` first, because the extraction library does the same,
	/// then checks the name component by component.
	private static func normalize(_ rawName: String) throws -> (path: String, isDirectory: Bool) {
		let name = rawName.replacingOccurrences(of: "\\", with: "/")
		guard !name.isEmpty else {
			throw fail("The archive contains an empty file name.")
		}
		for scalar in name.unicodeScalars where scalar.value < 0x20 || scalar.value == 0x7F {
			throw fail("The archive contains a file name with control characters.")
		}
		guard !name.hasPrefix("/") else {
			throw fail("The archive contains an absolute path.")
		}
		let characters = Array(name)
		if characters.count >= 2, characters[1] == ":" {
			throw fail("The archive contains an absolute path.")
		}
		var components = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		let isDirectory = components.last == ""
		if isDirectory {
			components.removeLast()
		}
		for component in components {
			if component.isEmpty {
				throw fail("The archive contains an invalid path.")
			}
			if component == "." || component == ".." {
				throw fail("The archive contains a path that leaves its folder.")
			}
		}
		return (components.joined(separator: "/"), isDirectory)
	}

	// MARK: - Layout rules

	static func isJunk(path: String) -> Bool {
		let components = path.split(separator: "/").map(String.init)
		guard let first = components.first, let last = components.last else {
			return false
		}
		return first == "__MACOSX" || last == ".DS_Store" || last.hasPrefix("._")
	}

	static func isAllowedFileName(_ name: String) -> Bool {
		if requiredFileNames.contains(name) {
			return true
		}
		let lowered = name.lowercased()
		for stem in ["license", "notice"] where lowered == stem || lowered.hasPrefix(stem + ".") {
			return true
		}
		return false
	}

	private static func checkLayout(_ entries: [Entry]) throws -> ValidatedArchive {
		// Duplicates, compared after NFC and case folding, junk included.
		var seen = Set<String>()
		var total: UInt64 = 0
		for entry in entries {
			let key = entry.path.precomposedStringWithCanonicalMapping.lowercased()
			guard seen.insert(key).inserted else {
				throw fail("The archive contains duplicate paths.")
			}
			let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
			guard !overflow, sum <= maxExpandedSize else {
				throw Failure.tooLarge
			}
			total = sum
		}

		let kept = entries.filter { !isJunk(path: $0.path) }
		var topLevel = Set<String>()
		for entry in kept {
			topLevel.insert(String(entry.path.split(separator: "/", maxSplits: 1)[0]))
		}
		guard topLevel.count == 1, let bundleName = topLevel.first else {
			throw fail("The archive must contain exactly one .nnwtheme folder.")
		}
		let lowered = bundleName.lowercased()
		guard lowered.hasSuffix(".nnwtheme"), lowered != ".nnwtheme" else {
			throw fail("The archive must contain exactly one .nnwtheme folder.")
		}

		var fileNames: [String] = []
		for entry in kept {
			let components = entry.path.split(separator: "/").map(String.init)
			if components.count == 1 {
				guard entry.isDirectory else {
					throw fail("The .nnwtheme item in the archive is a file, not a folder.")
				}
				continue
			}
			guard components.count == 2, !entry.isDirectory else {
				throw fail("The theme folder must not contain subfolders.")
			}
			guard isAllowedFileName(components[1]) else {
				throw fail("The theme folder contains an unexpected file: \(components[1]).")
			}
			fileNames.append(components[1])
		}
		for required in requiredFileNames where !fileNames.contains(required) {
			throw fail("The theme is missing \(required).")
		}
		return ValidatedArchive(bundleName: bundleName, fileNames: fileNames.sorted(), totalUncompressedSize: total)
	}

	// MARK: - Helpers

	private static func fail(_ reason: String) -> Failure {
		.invalidArchive(reason)
	}

	private struct Reader {
		let bytes: [UInt8]

		func u16(_ offset: Int) throws -> Int {
			guard offset >= 0, offset + 2 <= bytes.count else {
				throw Failure.invalidArchive("The archive is truncated.")
			}
			return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
		}

		func u32(_ offset: Int) throws -> UInt64 {
			guard offset >= 0, offset + 4 <= bytes.count else {
				throw Failure.invalidArchive("The archive is truncated.")
			}
			var value: UInt64 = 0
			for i in 0..<4 {
				value |= UInt64(bytes[offset + i]) << (8 * UInt64(i))
			}
			return value
		}
	}
}
