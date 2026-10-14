//
//  ArticleThemeBundleValidator.swift
//  ArticleTheming
//
//  Validates an on-disk `.nnwtheme` folder: either one just extracted from an
//  archive (defense in depth after `ArticleThemeArchiveValidator`) or one the
//  user opened from Files (D17). Uses `lstat` so symlinks are never followed.
//

import Foundation

public enum ArticleThemeBundleValidator {

	private typealias Failure = ArticleThemeDownloader.ArticleThemeDownloaderError

	/// Throws `invalidArchive` if the folder is not a plain theme bundle.
	/// Junk (`.DS_Store`, `._*`) is tolerated but must still be a regular file.
	public static func validate(directory: URL) throws {
		let path = directory.path

		guard let rootMode = mode(atPath: path), isDirectory(rootMode) else {
			throw Failure.invalidArchive("The theme is not a folder.")
		}

		let names = try FileManager.default.contentsOfDirectory(atPath: path)
		var present = Set<String>()
		var total: UInt64 = 0

		for name in names {
			guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
				  !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
				throw Failure.invalidArchive("The theme contains an invalid file name.")
			}
			let child = (path as NSString).appendingPathComponent(name)
			guard let childStat = statInfo(atPath: child) else {
				throw Failure.invalidArchive("The theme could not be read.")
			}
			guard isRegularFile(childStat.mode) else {
				throw Failure.invalidArchive("The theme contains a link, folder or special file: \(name).")
			}

			let isJunk = name == ".DS_Store" || name.hasPrefix("._")
			if !isJunk {
				guard ArticleThemeArchiveValidator.isAllowedFileName(name) else {
					throw Failure.invalidArchive("The theme folder contains an unexpected file: \(name).")
				}
				present.insert(name)
			}

			let (sum, overflow) = total.addingReportingOverflow(childStat.size)
			guard !overflow, sum <= ArticleThemeArchiveValidator.maxExpandedSize else {
				throw Failure.tooLarge
			}
			total = sum
		}

		for required in ArticleThemeArchiveValidator.requiredFileNames where !present.contains(required) {
			throw Failure.invalidArchive("The theme is missing \(required).")
		}
	}

	/// Removes `.DS_Store` and `._*` files from a validated bundle folder.
	public static func removeJunk(in directory: URL) {
		let fileManager = FileManager.default
		guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
			return
		}
		for name in names where name == ".DS_Store" || name.hasPrefix("._") {
			try? fileManager.removeItem(at: directory.appendingPathComponent(name))
		}
	}

	// MARK: - lstat helpers

	private static func statInfo(atPath path: String) -> (mode: mode_t, size: UInt64)? {
		var info = stat()
		guard lstat(path, &info) == 0 else {
			return nil
		}
		return (info.st_mode, UInt64(max(0, Int64(info.st_size))))
	}

	private static func mode(atPath path: String) -> mode_t? {
		statInfo(atPath: path)?.mode
	}

	private static func isDirectory(_ mode: mode_t) -> Bool {
		mode & S_IFMT == S_IFDIR
	}

	private static func isRegularFile(_ mode: mode_t) -> Bool {
		mode & S_IFMT == S_IFREG
	}
}
