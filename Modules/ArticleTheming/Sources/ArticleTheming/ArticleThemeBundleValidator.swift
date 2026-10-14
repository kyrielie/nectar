//
//  ArticleThemeBundleValidator.swift
//  ArticleTheming
//
//  Checks an on-disk `.nnwtheme` folder: either one just extracted from an
//  archive (defense in depth after `ArticleThemeArchiveValidator`) or one the
//  user opened from Files. Uses `lstat` so symlinks are never followed.
//
//  Safety rules reject: a link or special file at the top level, an unreadable
//  entry, or kept files that add up past the size cap. Layout never rejects:
//  subfolders, unknown files and missing theme files are tolerated, and
//  `copyInstallableFiles(from:to:)` leaves them behind, so only the three theme
//  files and `LICENSE*` / `NOTICE*` ever reach the Themes folder.
//

import Foundation

public enum ArticleThemeBundleValidator {

	private typealias Failure = ArticleThemeDownloader.ArticleThemeDownloaderError

	/// Throws `invalidArchive` only for safety problems. Subfolders are ignored and never
	/// entered. Junk (`.DS_Store`, `._*`) and unknown files are tolerated but, like
	/// every other top-level entry, must not be a link or special file.
	public static func validate(directory: URL) throws {
		let path = directory.path

		guard let rootMode = mode(atPath: path), isDirectory(rootMode) else {
			throw Failure.invalidArchive("The theme is not a folder.")
		}

		let names = try FileManager.default.contentsOfDirectory(atPath: path)
		var keptTotal: UInt64 = 0

		for name in names {
			let child = (path as NSString).appendingPathComponent(name)
			guard let childStat = statInfo(atPath: child) else {
				throw Failure.invalidArchive("The theme could not be read.")
			}
			if isDirectory(childStat.mode) {
				continue // ignored, not entered
			}
			guard isRegularFile(childStat.mode) else {
				throw Failure.invalidArchive("The theme contains a link or special file: \(name).")
			}
			guard ArticleThemeArchiveValidator.canonicalFileName(for: name) != nil else {
				continue // regular but not kept: ignored
			}

			let (sum, overflow) = keptTotal.addingReportingOverflow(childStat.size)
			guard !overflow, sum <= ArticleThemeArchiveValidator.maxExpandedSize else {
				throw Failure.tooLarge
			}
			keptTotal = sum
		}
	}

	/// Copies the kept files of `source` into a new folder at `destination`, using their
	/// canonical names. Anything else is left behind: subfolders, junk, unknown files,
	/// and any entry that is not a regular file (checked with `lstat`, never followed).
	/// Call `validate(directory:)` first; this only guarantees what it copies.
	public static func copyInstallableFiles(from source: URL, to destination: URL) throws {
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

		for name in try fileManager.contentsOfDirectory(atPath: source.path).sorted() {
			guard let canonical = ArticleThemeArchiveValidator.canonicalFileName(for: name) else {
				continue
			}
			let from = source.appendingPathComponent(name)
			guard let info = statInfo(atPath: from.path), isRegularFile(info.mode) else {
				continue
			}
			let to = destination.appendingPathComponent(canonical)
			// Two spellings of one name can coexist on a case-sensitive volume; first wins.
			guard !fileManager.fileExists(atPath: to.path) else {
				continue
			}
			try fileManager.copyItem(at: from, to: to)
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
