//
//  ArticleThemeDownloader.swift
//  ArticleThemeDownloader
//
//  Created by Stuart Breckenridge on 20/09/2021.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Foundation
import Zip

public final class ArticleThemeDownloader: Sendable {
	public static let shared = ArticleThemeDownloader()

	public enum ArticleThemeDownloaderError: LocalizedError, Equatable {
		case noThemeFile
		case unsupportedURLScheme
		case tooLarge
		case invalidArchive(String)
		case badResponse(Int)

		public var errorDescription: String? {
			switch self {
			case .noThemeFile:
				return "There is no NetNewsWire theme available."
			case .unsupportedURLScheme:
				return "Themes can only be downloaded from http or https addresses."
			case .tooLarge:
				return "The theme is too large to install."
			case .invalidArchive(let reason):
				return "The theme can't be installed. \(reason)"
			case .badResponse(let status):
				return "The server could not provide the theme (HTTP status \(status))."
			}
		}
	}

	/// Throws unless `url` uses the `http` or `https` scheme.
	public static func validateDownloadURL(_ url: URL) throws {
		guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
			throw ArticleThemeDownloaderError.unsupportedURLScheme
		}
	}

	/// Throws unless `response` is an `HTTPURLResponse` with a 2xx status.
	public static func validateDownloadResponse(_ response: URLResponse?) throws {
		guard let http = response as? HTTPURLResponse else {
			throw ArticleThemeDownloaderError.badResponse(0)
		}
		guard (200...299).contains(http.statusCode) else {
			throw ArticleThemeDownloaderError.badResponse(http.statusCode)
		}
	}

	private init() {}

	public func handleFile(at location: URL) throws {
		let movedFileLocation = try moveDownloadedTheme(from: location)
		try finishImportingTheme(at: movedFileLocation)
	}

	/// Moves the just-downloaded `.tmp` file to `downloadDirectory`, renaming it to
	/// `.zip`. Callers driven by `URLSessionDownloadTask`'s completion handler must
	/// call this *synchronously* within that handler -- the system deletes the `.tmp`
	/// file as soon as the handler returns, so hopping to another queue/Task first
	/// (even `Task { @MainActor in ... }`) races the deletion and can fail with
	/// "...tmp couldn't be moved... because either the former doesn't exist...".
	/// See `SceneDelegate`'s theme-URL handler.
	/// - Parameter location: The temporary file location handed to the download's
	///   completion handler.
	/// - Returns: The moved file's new location.
	public func moveDownloadedTheme(from location: URL) throws -> URL {
		let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
		if let size = (attributes[.size] as? NSNumber)?.uint64Value, size > ArticleThemeArchiveValidator.maxCompressedSize {
			throw ArticleThemeDownloaderError.tooLarge
		}
		createDownloadDirectoryIfRequired()
		return try moveTheme(from: location)
	}

	/// Unzips an already-moved theme archive and posts `.didEndDownloadingTheme`.
	/// Safe to call from anywhere (main actor or otherwise) since it no longer
	/// touches the ephemeral download temp file -- see `moveDownloadedTheme(from:)`.
	/// - Parameter location: The moved `.zip` file's location, as returned by
	///   `moveDownloadedTheme(from:)`.
	public func finishImportingTheme(at location: URL) throws {
		let unzippedFileLocation = try unzipFile(at: location)
		NotificationCenter.default.post(name: .didEndDownloadingTheme, object: nil, userInfo: ["url": unzippedFileLocation])
	}

	/// Creates `Application Support/NetNewsWire/Downloads` if needed.
	private func createDownloadDirectoryIfRequired() {
		try? FileManager.default.createDirectory(at: downloadDirectory(), withIntermediateDirectories: true, attributes: nil)
	}

	/// Moves the downloaded `.tmp` file to the `downloadDirectory` and renames it a `.zip`
	/// - Parameter location: The temporary file location.
	/// - Returns: Destination `URL`.
	private func moveTheme(from location: URL) throws -> URL {
		var tmpFileName = location.lastPathComponent
		tmpFileName = tmpFileName.replacingOccurrences(of: ".tmp", with: ".zip")
		let fileUrl = downloadDirectory().appendingPathComponent("\(tmpFileName)")
		try FileManager.default.moveItem(at: location, to: fileUrl)
		return fileUrl
	}

	/// Unzips a downloaded archive into a fresh directory under `Downloads` and
	/// deletes the zip afterwards, on success or failure.
	/// - Parameter location: Location of the zip archive.
	/// - Returns: The enclosed `.nnwtheme` folder.
	private func unzipFile(at location: URL) throws -> URL {
		defer {
			try? FileManager.default.removeItem(at: location)
		}
		let destination = downloadDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
		return try unzipTheme(at: location, to: destination)
	}

	/// Validates, then unzips the archive into `destination`.
	///
	/// The central directory is checked before any byte is written. After
	/// extraction the bundle folder is checked again with `lstat`, junk files
	/// are removed, and the single `.nnwtheme` folder is returned. `destination`
	/// is deleted on failure. The zip itself is left for the caller to delete.
	/// - Parameters:
	///   - zipURL: Location of the zip archive.
	///   - destination: A directory that does not exist yet.
	/// - Returns: The enclosed `.nnwtheme` folder inside `destination`.
	public func unzipTheme(at zipURL: URL, to destination: URL) throws -> URL {
		let fileManager = FileManager.default
		do {
			let validated = try ArticleThemeArchiveValidator.validate(zipURL: zipURL)
			try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

			do {
				try Zip.unzipFile(zipURL, destination: destination, overwrite: true, password: nil, progress: nil, fileOutputHandler: nil)
			} catch {
				throw ArticleThemeDownloaderError.invalidArchive("The archive could not be extracted.")
			}

			// Keep only the validated bundle folder; drop __MACOSX and other junk.
			let expectedName = validated.bundleName.precomposedStringWithCanonicalMapping
			var bundleURL: URL?
			for name in try fileManager.contentsOfDirectory(atPath: destination.path) {
				let itemURL = destination.appendingPathComponent(name)
				if bundleURL == nil, name.precomposedStringWithCanonicalMapping == expectedName {
					bundleURL = itemURL
				} else {
					try? fileManager.removeItem(at: itemURL)
				}
			}
			guard let bundleURL else {
				throw ArticleThemeDownloaderError.noThemeFile
			}

			try ArticleThemeBundleValidator.validate(directory: bundleURL)
			ArticleThemeBundleValidator.removeJunk(in: bundleURL)
			return bundleURL
		} catch {
			try? fileManager.removeItem(at: destination)
			throw error
		}
	}

	/// The download directory used by the theme downloader: `Application Support/NetNewsWire/Downloads`
	/// - Returns: `URL`
	private func downloadDirectory() -> URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("NetNewsWire/Downloads", isDirectory: true)
	}

	/// Removes downloaded themes, where themes == folders, from `Application Support/NetNewsWire/Downloads`.
	public func cleanUp() {
		guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: downloadDirectory().path) else {
			return
		}
		for path in filenames {
			do {
				if FileManager.default.isFolder(atPath: downloadDirectory().appendingPathComponent(path).path) {
					try FileManager.default.removeItem(atPath: downloadDirectory().appendingPathComponent(path).path)
				}
			} catch {
				print(error)
			}
		}
	}
}
