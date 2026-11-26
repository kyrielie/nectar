//
//  EPUB3Generator.swift
//  Nectar
//
//  Generates Standard Ebooks & AO3 compliant EPUB 3.3 archives from Nectar articles,
//  preserving complete metadata, author workskins, personal annotations, and typography.
//

import Foundation
import UIKit
import RSCore
import Articles
import Account
import AnnotationsKit
import ArticlesDatabase
import AO3Kit
import SwiftSoup
import ZIPFoundation

public enum EPUBExportError: LocalizedError {
	case noContent(String)
	case compressionFailed(String)
	case packagingFailed(String)

	public var errorDescription: String? {
		switch self {
		case .noContent(let message):
			return message
		case .compressionFailed(let message):
			return "Decompression failed: \(message)"
		case .packagingFailed(let message):
			return "EPUB packaging failed: \(message)"
		}
	}
}

@MainActor
public final class EPUB3Generator {

	public struct Chapter {
		public let title: String
		public let bodyHTML: String
		public let chapterID: String

		public init(title: String, bodyHTML: String, chapterID: String) {
			self.title = title
			self.bodyHTML = bodyHTML
			self.chapterID = chapterID
		}
	}

	// MARK: - Public Export API

	public static func generateEPUB(for article: Article, account: Account?) async throws -> URL {
		// 1. Decompress Story Content
		guard let storedHTML = article.contentHTML, !storedHTML.isEmpty else {
			throw EPUBExportError.noContent(
				NSLocalizedString("This work's story text has not been downloaded yet. Open the work in the reader first to load chapters.", comment: "Error message")
			)
		}

		let decompressedHTML = ContentHTMLCompression.decompress(storedHTML) ?? storedHTML
		guard hasStoryContent(decompressedHTML) else {
			throw EPUBExportError.noContent(
				NSLocalizedString("The cached content does not contain body text. Open the work to refresh chapters.", comment: "Error message")
			)
		}

		// 2. Fetch User Annotations
		var annotations: [Annotation] = []
		if let account {
			annotations = await account.fetchAnnotations(forArticleID: article.articleID)
		}

		// 3. Prepare Work Directory
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("EPUBExport-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tempDir) }

		let epubPayloadDir = tempDir.appendingPathComponent("payload")
		let metaInfDir = epubPayloadDir.appendingPathComponent("META-INF")
		let epubDir = epubPayloadDir.appendingPathComponent("EPUB")
		let cssDir = epubDir.appendingPathComponent("css")
		let textDir = epubDir.appendingPathComponent("text")

		try FileManager.default.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)

		// 4. Extract Workskin & Chapters
		let workTitle = article.title ?? "Untitled"
		let (chapters, workskinCSS, afterwordHTML, extractedPrefaceHTML) = extractWorkskinAndChapters(from: decompressedHTML, workTitle: workTitle)
		guard !chapters.isEmpty else {
			throw EPUBExportError.noContent(NSLocalizedString("Could not extract any chapters from story text.", comment: "Error message"))
		}

		let hasWorkskin = !workskinCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let hasAnnotations = !annotations.isEmpty

		// 5. Write mimetype (uncompressed application/epub+zip)
		let mimetypeURL = epubPayloadDir.appendingPathComponent("mimetype")
		try "application/epub+zip".write(to: mimetypeURL, atomically: true, encoding: .utf8)

		// 6. Write META-INF/container.xml
		let containerURL = metaInfDir.appendingPathComponent("container.xml")
		let containerXML = """
		<?xml version="1.0" encoding="UTF-8"?>
		<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
		  <rootfiles>
		    <rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/>
		  </rootfiles>
		</container>
		"""
		try containerXML.write(to: containerURL, atomically: true, encoding: .utf8)

		// 7. Write Stylesheets
		try coreCSS.write(to: cssDir.appendingPathComponent("core.css"), atomically: true, encoding: .utf8)
		try seCSS.write(to: cssDir.appendingPathComponent("se.css"), atomically: true, encoding: .utf8)
		try pageStylesCSS.write(to: cssDir.appendingPathComponent("page_styles.css"), atomically: true, encoding: .utf8)

		if hasWorkskin {
			try workskinCSS.write(to: cssDir.appendingPathComponent("workskin.css"), atomically: true, encoding: .utf8)
		}
		if hasAnnotations {
			try annotationsCSS.write(to: cssDir.appendingPathComponent("annotations.css"), atomically: true, encoding: .utf8)
		}

		// 8. Write Text Partitions
		let authorStr = article.authors?.compactMap(\.name).joined(separator: ", ") ?? "Anonymous"
		let language = normalizeLanguage(article.language)
		var splitFiles: [(relPath: String, title: String, props: String?)] = []

		// 8.1 Preface
		let prefaceHTML = buildPrefaceHTML(
			article: article,
			authorStr: authorStr,
			language: language,
			hasWorkskin: hasWorkskin,
			extractedPrefaceHTML: extractedPrefaceHTML
		)
		try prefaceHTML.write(to: textDir.appendingPathComponent("preface.xhtml"), atomically: true, encoding: .utf8)
		splitFiles.append(("text/preface.xhtml", "Preface", nil))

		// 8.2 Chapters with Workskin Wrapper Preserved
		for (index, ch) in chapters.enumerated() {
			let filename = "chapter-\(index + 1).xhtml"
			let formattedBody = ensureXHTML(ch.bodyHTML)
			let workskinLink = hasWorkskin ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"../css/workskin.css\"/>" : ""

			let chapterXHTML = """
			<?xml version="1.0" encoding="UTF-8"?>
			<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
			  <head>
			    <title>\(escapeXML(ch.title)) - \(escapeXML(workTitle))</title>
			    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
			    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
			    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
			    \(workskinLink)
			  </head>
			  <body epub:type="bodymatter">
			    <section id="\(ch.chapterID)" epub:type="chapter" role="doc-chapter">
			      <header class="chapter-header">
			        <h2 class="chapter-title">\(escapeXML(ch.title))</h2>
			      </header>
			      <div id="workskin" class="userstuff">
			        \(formattedBody)
			      </div>
			    </section>
			  </body>
			</html>
			"""
			try chapterXHTML.write(to: textDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
			splitFiles.append(("text/\(filename)", ch.title, nil))
		}

		// 8.3 Afterword
		if let afterwordHTML, hasStoryContent(afterwordHTML) {
			let formattedAfterword = ensureXHTML(afterwordHTML)
			let workskinLink = hasWorkskin ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"../css/workskin.css\"/>" : ""
			let afterwordXHTML = """
			<?xml version="1.0" encoding="UTF-8"?>
			<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
			  <head>
			    <title>Afterword - \(escapeXML(workTitle))</title>
			    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
			    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
			    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
			    \(workskinLink)
			  </head>
			  <body epub:type="backmatter">
			    <section id="afterword" epub:type="afterword" role="doc-afterword" class="endnotes-section">
			      <header class="chapter-header">
			        <h2 class="chapter-title">Afterword</h2>
			      </header>
			      <div id="workskin" class="userstuff">
			        \(formattedAfterword)
			      </div>
			    </section>
			  </body>
			</html>
			"""
			try afterwordXHTML.write(to: textDir.appendingPathComponent("afterword.xhtml"), atomically: true, encoding: .utf8)
			splitFiles.append(("text/afterword.xhtml", "Afterword", nil))
		}

		// 8.4 Reader Annotations Chapter
		if hasAnnotations {
			let annotationsHTML = buildAnnotationsHTML(annotations: annotations, workTitle: workTitle, language: language)
			try annotationsHTML.write(to: textDir.appendingPathComponent("reader-notes.xhtml"), atomically: true, encoding: .utf8)
			splitFiles.append(("text/reader-notes.xhtml", "Reader Highlights & Notes", nil))
		}

		// 9. Write Navigation Document (toc.xhtml) & NCX (toc.ncx)
		let tocXHTML = buildNavigationDocument(splitFiles: splitFiles, language: language)
		try tocXHTML.write(to: epubDir.appendingPathComponent("toc.xhtml"), atomically: true, encoding: .utf8)

		let canonicalID = article.preferredURL?.absoluteString.components(separatedBy: "?").first ?? "urn:uuid:\(UUID().uuidString)"
		let tocNCX = buildNCXDocument(splitFiles: splitFiles, workTitle: workTitle, canonicalID: canonicalID, language: language)
		try tocNCX.write(to: epubDir.appendingPathComponent("toc.ncx"), atomically: true, encoding: .utf8)

		// 10. Write Package Document (content.opf)
		let contentOPF = buildContentOPF(
			article: article,
			authorStr: authorStr,
			splitFiles: splitFiles,
			canonicalID: canonicalID,
			language: language,
			hasWorkskin: hasWorkskin,
			hasAnnotations: hasAnnotations
		)
		try contentOPF.write(to: epubDir.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

		// 11. Bundle EPUB Container
		let safeAuthor = sanitizeFilename(authorStr)
		let safeTitle = sanitizeFilename(workTitle)
		let finalFileName = "\(safeAuthor) — \(safeTitle).epub"

		let exportsDir = FileManager.default.temporaryDirectory.appendingPathComponent("NectarExports", isDirectory: true)
		try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
		let finalEPUBURL = exportsDir.appendingPathComponent(finalFileName)
		try? FileManager.default.removeItem(at: finalEPUBURL)

		try packageEPUB(from: epubPayloadDir, to: finalEPUBURL)
		return finalEPUBURL
	}

	/// Packages an EPUB 3.3 payload directory into an archive where `mimetype`
	/// is the first entry and stored uncompressed (`.none`), followed by
	/// `META-INF/` and `EPUB/` entries compressed with `.deflate`.
	private static func packageEPUB(from payloadDir: URL, to destinationURL: URL) throws {
		let archive = try Archive(url: destinationURL, accessMode: .create)
		try archive.addEntry(with: "mimetype", relativeTo: payloadDir, compressionMethod: .none)

		let fileManager = FileManager.default
		for subdir in ["META-INF", "EPUB"] {
			let subdirURL = payloadDir.appendingPathComponent(subdir, isDirectory: true)
			guard let enumerator = fileManager.enumerator(
				at: subdirURL,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]
			) else {
				continue
			}

			var filePaths: [String] = []
			for case let fileURL as URL in enumerator {
				let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
				if values.isDirectory == true { continue }
				let relPath = fileURL.path.replacingOccurrences(of: payloadDir.path + "/", with: "")
				filePaths.append(relPath)
			}

			for relPath in filePaths.sorted() {
				try archive.addEntry(with: relPath, relativeTo: payloadDir, compressionMethod: .deflate)
			}
		}
	}

	// MARK: - Workskin & Chapter Parsing

	private static func extractWorkskinAndChapters(from html: String, workTitle: String) -> ([Chapter], String, String?, String?) {
		guard let doc = try? SwiftSoup.parse(html) else {
			return ([Chapter(title: workTitle, bodyHTML: html.trimmingCharacters(in: .whitespacesAndNewlines), chapterID: "chapter-1")], "", nil, nil)
		}

		// 0. Extract AO3 Preface block if present
		let extractedPrefaceHTML: String? = try? doc.select("#ao3Preface, #ao3SyntheticPreface").first()?.outerHtml()

		// 1. Extract <style> blocks and remove them from the DOM
		var workskinRules: [String] = []
		if let styleElements = try? doc.select("style") {
			for styleEl in styleElements.array() {
				let rule = styleEl.data().trimmingCharacters(in: .whitespacesAndNewlines)
				if !rule.isEmpty {
					workskinRules.append(rule)
				}
				try? styleEl.remove()
			}
		}

		var workskinCSS = ""
		if !workskinRules.isEmpty {
			let rawWorkskin = workskinRules.joined(separator: "\n\n")
			workskinCSS = """
			/* Author Workskin Stylesheet Preserved from AO3 */
			\(rawWorkskin)

			/* Workskin Dark-Mode & Viewport Contrast Guard */
			@media (prefers-color-scheme: dark) {
			  #workskin {
			    color: #e4e4e7;
			    background-color: transparent;
			  }
			  #workskin [style*="color: #000"],
			  #workskin [style*="color: black"],
			  #workskin [style*="color:#000000"] {
			    color: #f4f4f5 !important;
			  }
			}
			#workskin {
			  max-width: 100%;
			  box-sizing: border-box;
			  overflow-wrap: break-word;
			}
			"""
		}

		// 2. Extract Afterword
		let afterwordHTML: String? = try? doc.select("#afterword").first()?.outerHtml()

		// 3. Extract Chapters
		var chapters: [Chapter] = []
		if let chapterElements = try? doc.select("div.chapter[id^=chapter-]") {
			for (index, chapterEl) in chapterElements.array().enumerated() {
				let chapterID = chapterEl.id().isEmpty ? "chapter-\(index + 1)" : chapterEl.id()
				let chNum = chapterID.hasPrefix("chapter-") ? String(chapterID.dropFirst("chapter-".count)) : "\(index + 1)"

				var chTitle = "Chapter \(chNum)"
				if let titleEl = try? chapterEl.select("h3.title").first() {
					let rawTitle = ((try? titleEl.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
					if !rawTitle.isEmpty {
						chTitle = rawTitle
					}
					try? titleEl.remove()
				}

				let chBody = ((try? chapterEl.html()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
				chapters.append(Chapter(title: chTitle, bodyHTML: chBody, chapterID: chapterID))
			}
		}

		if !chapters.isEmpty {
			return (chapters, workskinCSS, afterwordHTML, extractedPrefaceHTML)
		}

		// Fallback single chapter
		_ = try? doc.select("#afterword").remove()
		let container = (try? doc.select("#chapters").first()) ?? doc.body()
		let singleBody = ((try? container?.html()) ?? html).trimmingCharacters(in: .whitespacesAndNewlines)

		return ([Chapter(title: workTitle, bodyHTML: singleBody, chapterID: "chapter-1")], workskinCSS, afterwordHTML, extractedPrefaceHTML)
	}

	// MARK: - HTML & XML Helpers

	public static func escapeXML(_ s: String) -> String {
		s.escapingSpecialXMLCharacters
	}

	public static func ensureXHTML(_ html: String) -> String {
		guard !html.isEmpty else { return html }
		guard let doc = try? SwiftSoup.parseBodyFragment(html) else {
			return html
		}
		doc.outputSettings()
			.syntax(syntax: .xml)
			.escapeMode(.xhtml)
			.prettyPrint(pretty: false)
		return (try? doc.body()?.html()) ?? html
	}

	private static func hasStoryContent(_ html: String) -> Bool {
		let textOnly = html.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines)
		return textOnly.count >= 80
	}

	private static func sanitizeFilename(_ name: String, maxLen: Int = 80) -> String {
		let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
		var cleaned = name.components(separatedBy: invalidChars).joined(separator: "-")
		cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
		if cleaned.isEmpty { return "Unknown" }
		if cleaned.count > maxLen {
			cleaned = String(cleaned.prefix(maxLen)).trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return cleaned
	}

	private static func normalizeLanguage(_ lang: String?) -> String {
		guard let lang, !lang.isEmpty else { return "en" }
		let lower = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
		if lower.contains("english") { return "en" }
		if lower.contains("spanish") || lower.contains("español") { return "es" }
		if lower.contains("french") || lower.contains("français") { return "fr" }
		if lower.contains("german") || lower.contains("deutsch") { return "de" }
		if lower.contains("chinese") { return "zh" }
		if lower.contains("japanese") { return "ja" }
		return lower.count <= 8 ? lower : "en"
	}

	// MARK: - Partition Builders

	private static func ao3TagLink(_ tag: String) -> String {
		let escaped = escapeXML(tag)
		let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
		return "<a href=\"https://\(AO3Link.canonicalHost)/tags/\(encoded)/works\">\(escaped)</a>"
	}

	private static func buildPrefaceHTML(
		article: Article,
		authorStr: String,
		language: String,
		hasWorkskin: Bool,
		extractedPrefaceHTML: String? = nil
	) -> String {
		let workTitle = article.title ?? "Untitled"
		var tagsDL: [String] = []

		if let ratings = article.ratings, !ratings.isEmpty {
			let links = ratings.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Rating:</dt><dd>\(links)</dd>")
		}
		if let warnings = article.warnings, !warnings.isEmpty {
			let links = warnings.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Archive Warning:</dt><dd>\(links)</dd>")
		}
		if let categories = article.categories, !categories.isEmpty {
			let links = categories.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Category:</dt><dd>\(links)</dd>")
		}
		if let fandoms = article.fandoms, !fandoms.isEmpty {
			let links = fandoms.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Fandom:</dt><dd>\(links)</dd>")
		}
		if let relationships = article.relationships, !relationships.isEmpty {
			let links = relationships.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Relationship:</dt><dd>\(links)</dd>")
		}
		if let characters = article.characters, !characters.isEmpty {
			let links = characters.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Characters:</dt><dd>\(links)</dd>")
		}
		if let additionalTags = article.additionalTags, !additionalTags.isEmpty {
			let links = additionalTags.map(ao3TagLink).joined(separator: ", ")
			tagsDL.append("<dt>Additional Tags:</dt><dd>\(links)</dd>")
		}
		if let series = article.series?.first {
			let sIdx = " #\(series.index)"
			let sNameEscaped = escapeXML(series.name)
			let sLink: String
			if let ao3ID = series.ao3ID {
				sLink = "<a href=\"https://\(AO3Link.canonicalHost)/series/\(ao3ID)\">\(sNameEscaped)</a>"
			} else {
				sLink = sNameEscaped
			}
			tagsDL.append("<dt>Series:</dt><dd>Part\(sIdx) of \(sLink)</dd>")
		}
		if let collections = article.collections, !collections.isEmpty {
			let cLinks = collections.map { col -> String in
				let nameEscaped = escapeXML(col.name)
				if let slug = col.slug {
					return "<a href=\"https://\(AO3Link.canonicalHost)/collections/\(slug)\">\(nameEscaped)</a>"
				}
				return nameEscaped
			}.joined(separator: ", ")
			tagsDL.append("<dt>Collections:</dt><dd>\(cLinks)</dd>")
		}

		var statsSpans: [String] = []
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		if let pubDate = article.datePublished {
			statsSpans.append("Published: \(formatter.string(from: pubDate))")
		}
		if let modDate = article.dateModified, modDate != article.datePublished {
			let label = (article.isComplete == true) ? "Completed" : "Updated"
			statsSpans.append("\(label): \(formatter.string(from: modDate))")
		}
		if let wc = article.wordCount {
			statsSpans.append("Words: \(NumberFormatter.localizedString(from: NSNumber(value: wc), number: .decimal))")
		}
		if let chCurr = article.chapterCurrent, let chTot = article.chapterTotal {
			statsSpans.append("Chapters: \(chCurr)/\(chTot)")
		}
		if let kudos = article.kudosCount {
			statsSpans.append("Kudos: \(NumberFormatter.localizedString(from: NSNumber(value: kudos), number: .decimal))")
		}
		if let bookmarks = article.bookmarkCount {
			statsSpans.append("Bookmarks: \(NumberFormatter.localizedString(from: NSNumber(value: bookmarks), number: .decimal))")
		}
		if let hits = article.hitCount {
			statsSpans.append("Hits: \(NumberFormatter.localizedString(from: NSNumber(value: hits), number: .decimal))")
		}
		if article.isRestricted == true {
			statsSpans.append("🔒 Restricted")
		}

		let statsHTML = statsSpans.isEmpty ? "" : "<div class=\"stats-block\">\(statsSpans.joined(separator: " &nbsp;•&nbsp; "))</div>"
		let tagsHTML: String = {
			if let extractedPrefaceHTML,
			   let doc = try? SwiftSoup.parseBodyFragment(extractedPrefaceHTML),
			   let dlElement = try? doc.select("dl.tags").first(),
			   let dlHTML = try? dlElement.outerHtml() {
				return ensureXHTML(dlHTML)
			}
			return tagsDL.isEmpty ? "" : "<dl class=\"tags-dl\">\n\(tagsDL.joined(separator: "\n"))\n</dl>"
		}()

		let authorBylineHTML: String = {
			if let authors = article.authors, !authors.isEmpty {
				let authorLinks = authors.compactMap { author -> String? in
					guard let name = author.name, !name.isEmpty else { return nil }
					let escaped = escapeXML(name)
					let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
					return "<a rel=\"author\" href=\"https://\(AO3Link.canonicalHost)/users/\(encoded)/pseuds/\(encoded)\">\(escaped)</a>"
				}
				if !authorLinks.isEmpty {
					return authorLinks.joined(separator: ", ")
				}
			}
			return escapeXML(authorStr)
		}()

		var summaryHTML = ""
		if let summary = article.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			let cleanSummary = ensureXHTML(summary)
			summaryHTML = """
			<div class="meta-section" epub:type="abstract">
			  <h3>Summary</h3>
			  <blockquote>\(cleanSummary)</blockquote>
			</div>
			"""
		}

		let workskinLink = hasWorkskin ? "<link rel=\"stylesheet\" type=\"text/css\" href=\"../css/workskin.css\"/>" : ""

		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
		  <head>
		    <title>\(escapeXML(workTitle)) - Preface</title>
		    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
		    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
		    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
		    \(workskinLink)
		  </head>
		  <body epub:type="frontmatter">
		    <section id="preface" epub:type="preface">
		      <header class="title-header">
		        <h1 class="fulltitle" epub:type="fulltitle">\(escapeXML(workTitle))</h1>
		        <p class="byline">by \(authorBylineHTML)</p>
		      </header>
		      \(statsHTML)
		      \(tagsHTML)
		      \(summaryHTML)
		    </section>
		  </body>
		</html>
		"""
	}

	private static func buildAnnotationsHTML(annotations: [Annotation], workTitle: String, language: String) -> String {
		var cards: [String] = []
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short

		for anno in annotations {
			let quote = escapeXML(anno.quoteExact)
			let note = escapeXML(anno.note ?? "")
			let colorHex: String
			switch anno.color {
			case .yellow: colorHex = "#f59e0b"
			case .red: colorHex = "#ef4444"
			case .green: colorHex = "#22c55e"
			case .blue: colorHex = "#3b82f6"
			case .purple: colorHex = "#a855f7"
			}
			let dateStr = formatter.string(from: anno.createdAt)

			let quoteBlock = quote.isEmpty ? "" : "<blockquote class=\"annotation-quote\">\(quote)</blockquote>"
			let noteBlock = note.isEmpty ? "" : "<p class=\"annotation-note\"><strong>Note:</strong> \(note)</p>"

			let card = """
			<div class="annotation-card" style="border-left-color: \(colorHex);">
			  \(quoteBlock)
			  \(noteBlock)
			  <span class="annotation-date">Saved on \(dateStr)</span>
			</div>
			"""
			cards.append(card)
		}

		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
		  <head>
		    <title>Reader Highlights &amp; Notes - \(escapeXML(workTitle))</title>
		    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
		    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
		    <link rel="stylesheet" type="text/css" href="../css/annotations.css"/>
		    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
		  </head>
		  <body epub:type="backmatter">
		    <section id="reader-notes" epub:type="annotation" role="doc-endnotes">
		      <header class="annotations-header">
		        <h2 class="chapter-title">Reader Highlights &amp; Notes</h2>
		        <p class="annotation-summary">Preserved personal reader annotations from Nectar.</p>
		      </header>
		      \(cards.joined(separator: "\n"))
		    </section>
		  </body>
		</html>
		"""
	}

	private static func buildNavigationDocument(splitFiles: [(relPath: String, title: String, props: String?)], language: String) -> String {
		var navItems: [String] = []
		for item in splitFiles {
			navItems.append("        <li><a href=\"\(item.relPath)\">\(escapeXML(item.title))</a></li>")
		}

		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
		  <head>
		    <title>Table of Contents</title>
		    <link rel="stylesheet" type="text/css" href="css/core.css"/>
		    <link rel="stylesheet" type="text/css" href="css/se.css"/>
		  </head>
		  <body epub:type="frontmatter">
		    <nav id="toc" epub:type="toc" role="doc-toc">
		      <h2>Table of Contents</h2>
		      <ol>
		\(navItems.joined(separator: "\n"))
		      </ol>
		    </nav>
		    <nav id="landmarks" epub:type="landmarks">
		      <h2>Landmarks</h2>
		      <ol>
		        <li><a href="text/preface.xhtml" epub:type="preface">Preface</a></li>
		        <li><a href="text/chapter-1.xhtml" epub:type="bodymatter">Start of Content</a></li>
		      </ol>
		    </nav>
		  </body>
		</html>
		"""
	}

	private static func buildNCXDocument(splitFiles: [(relPath: String, title: String, props: String?)], workTitle: String, canonicalID: String, language: String) -> String {
		var navPoints: [String] = []
		for (index, item) in splitFiles.enumerated() {
			let order = index + 1
			navPoints.append("""
			    <navPoint id="np_\(order)" playOrder="\(order)">
			      <navLabel><text>\(escapeXML(item.title))</text></navLabel>
			      <content src="\(item.relPath)"/>
			    </navPoint>
			""")
		}

		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="\(language)">
		  <head>
		    <meta name="dtb:uid" content="\(canonicalID)"/>
		    <meta name="dtb:depth" content="2"/>
		    <meta name="dtb:generator" content="Nectar"/>
		    <meta name="dtb:totalPageCount" content="0"/>
		    <meta name="dtb:maxPageNumber" content="0"/>
		  </head>
		  <docTitle>
		    <text>\(escapeXML(workTitle))</text>
		  </docTitle>
		  <navMap>
		\(navPoints.joined(separator: "\n"))
		  </navMap>
		</ncx>
		"""
	}

	private static func buildContentOPF(
		article: Article,
		authorStr: String,
		splitFiles: [(relPath: String, title: String, props: String?)],
		canonicalID: String,
		language: String,
		hasWorkskin: Bool,
		hasAnnotations: Bool
	) -> String {
		let workTitle = article.title ?? "Untitled"

		var manifestItems = [
			"    <item id=\"toc\" href=\"toc.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
			"    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>",
			"    <item id=\"css-core\" href=\"css/core.css\" media-type=\"text/css\"/>",
			"    <item id=\"css-se\" href=\"css/se.css\" media-type=\"text/css\"/>",
			"    <item id=\"css-page\" href=\"css/page_styles.css\" media-type=\"text/css\"/>"
		]
		if hasWorkskin {
			manifestItems.append("    <item id=\"css-workskin\" href=\"css/workskin.css\" media-type=\"text/css\"/>")
		}
		if hasAnnotations {
			manifestItems.append("    <item id=\"css-annotations\" href=\"css/annotations.css\" media-type=\"text/css\"/>")
		}

		var spineItems: [String] = []
		for item in splitFiles {
			let itemID = item.relPath.replacingOccurrences(of: "text/", with: "").replacingOccurrences(of: ".xhtml", with: "")
			let propAttr = item.props.map { " properties=\"\($0)\"" } ?? ""
			manifestItems.append("    <item id=\"\(itemID)\" href=\"\(item.relPath)\" media-type=\"application/xhtml+xml\"\(propAttr)/>")
			spineItems.append("    <itemref idref=\"\(itemID)\"/>")
		}

		var subjectTags: [String] = ["    <dc:subject>Fanworks</dc:subject>"]
		for f in article.fandoms ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(f))</dc:subject>")
		}
		for r in article.ratings ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(r))</dc:subject>")
		}
		for w in article.warnings ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(w))</dc:subject>")
		}
		for c in article.categories ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(c))</dc:subject>")
		}
		for rel in article.relationships ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(rel))</dc:subject>")
		}
		for ch in article.characters ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(ch))</dc:subject>")
		}
		for tag in article.additionalTags ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(tag))</dc:subject>")
		}
		for coll in article.collections ?? [] {
			subjectTags.append("    <dc:subject>\(escapeXML(coll.name))</dc:subject>")
		}

		var seriesMeta = ""
		if let s = article.series?.first {
			seriesMeta += "    <meta name=\"calibre:series\" content=\"\(escapeXML(s.name))\"/>\n"
			seriesMeta += "    <meta name=\"calibre:series_index\" content=\"\(s.index)\"/>\n"
		}

		var statsMeta = ""
		if let kudos = article.kudosCount {
			statsMeta += "    <meta property=\"nectar:kudos\">\(kudos)</meta>\n"
		}
		if let bookmarks = article.bookmarkCount {
			statsMeta += "    <meta property=\"nectar:bookmarks\">\(bookmarks)</meta>\n"
		}
		if let comments = article.commentCount {
			statsMeta += "    <meta property=\"nectar:comments\">\(comments)</meta>\n"
		}
		if let hits = article.hitCount {
			statsMeta += "    <meta property=\"nectar:hits\">\(hits)</meta>\n"
		}

		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd"
		let datePub = dateFormatter.string(from: article.datePublished ?? article.dateModified ?? Date())

		let isoFormatter = ISO8601DateFormatter()
		let modTimestamp = isoFormatter.string(from: article.dateModified ?? Date())

		let summaryText = escapeXML(article.summary?.strippingHTML().trimmingCharacters(in: .whitespacesAndNewlines) ?? "")

		return """
		<?xml version="1.0" encoding="UTF-8"?>
		<package xmlns="http://www.idpf.org/2007/opf" version="3.0" xml:lang="\(language)" unique-identifier="pub-id">
		  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
		    <dc:identifier id="pub-id">\(canonicalID)</dc:identifier>
		    <dc:title id="title">\(escapeXML(workTitle))</dc:title>
		    <dc:creator id="author_1">\(escapeXML(authorStr))</dc:creator>
		    <meta refines="#author_1" property="role" scheme="marc:relators">aut</meta>
		    <meta refines="#author_1" property="file-as">\(escapeXML(authorStr))</meta>
		    <dc:publisher id="publisher">Archive of Our Own</dc:publisher>
		    <link refines="#publisher" rel="record" href="https://\(AO3Link.canonicalHost)/"/>
		    <dc:language>\(language)</dc:language>
		    <dc:date>\(datePub)</dc:date>
		    <meta property="dcterms:modified">\(modTimestamp)</meta>
		    <dc:description>\(summaryText)</dc:description>
		\(subjectTags.joined(separator: "\n"))
		\(seriesMeta)\(statsMeta)  </metadata>
		  <manifest>
		\(manifestItems.joined(separator: "\n"))
		  </manifest>
		  <spine toc="ncx">
		\(spineItems.joined(separator: "\n"))
		  </spine>
		</package>
		"""
	}

	// MARK: - Stylesheets

	private static let pageStylesCSS = """
	@page {
	  margin-bottom: 5pt;
	  margin-top: 5pt;
	}
	"""

	private static let coreCSS = """
	/* Standard Ebooks Core CSS Reset */
	html {
	  font-family: serif;
	}
	body {
	  margin: 0;
	  padding: 0;
	  color: #111;
	  background-color: #fff;
	  text-rendering: optimizeLegibility;
	}
	p {
	  margin: 0;
	  text-align: justify;
	  text-justify: inter-word;
	  hyphens: auto;
	  -webkit-hyphens: auto;
	}
	p + p {
	  text-indent: 1.5em;
	}
	h1, h2, h3, h4, h5, h6 {
	  font-family: sans-serif;
	  font-weight: 600;
	  line-height: 1.25;
	  text-align: center;
	  text-indent: 0;
	  break-after: avoid;
	  page-break-after: avoid;
	}
	h1 + p, h2 + p, h3 + p, h4 + p {
	  text-indent: 0;
	}
	blockquote {
	  margin: 1.25em 2em;
	  font-style: italic;
	}
	hr {
	  border: 0;
	  height: 1px;
	  background: #ccc;
	  margin: 2em auto;
	  width: 40%;
	}
	a {
	  color: inherit;
	  text-decoration: underline;
	}

	@media (prefers-color-scheme: dark) {
	  body {
	    background-color: #121212;
	    color: #e4e4e7;
	  }
	  hr {
	    background: #444;
	  }
	}
	"""

	private static let seCSS = """
	/* Standard Ebooks Semantic Layout & Section Patterns */
	.byline {
	  display: block;
	  text-align: center;
	  font-style: italic;
	  margin: 0.5em 0 2em 0;
	}
	.title-header {
	  margin-top: 2em;
	  margin-bottom: 1em;
	}
	.fulltitle {
	  font-size: 1.8em;
	  margin-bottom: 0.25em;
	}
	.message {
	  display: block;
	  text-align: center;
	  margin: 1.5em 0;
	  font-style: italic;
	}
	.tags-dl {
	  margin: 1.5em 0;
	  padding: 0;
	  font-size: 0.9em;
	  line-height: 1.5;
	}
	.tags-dl dt {
	  font-weight: bold;
	  float: left;
	  clear: left;
	  width: 9em;
	  margin-bottom: 0.5em;
	}
	.tags-dl dd {
	  margin-left: 9.5em;
	  margin-bottom: 0.5em;
	}
	.tags-dl dd:after {
	  content: "";
	  display: table;
	  clear: both;
	}
	.stats-block {
	  border-top: 1px solid #ccc;
	  border-bottom: 1px solid #ccc;
	  padding: 0.75em 0;
	  margin: 1.5em 0;
	  font-size: 0.85em;
	  text-align: center;
	  line-height: 1.6;
	}
	.meta-section {
	  margin: 2em 0;
	}
	.meta-section h3 {
	  font-size: 1.1em;
	  text-transform: uppercase;
	  letter-spacing: 0.05em;
	  margin-bottom: 0.5em;
	  color: #555;
	}
	.chapter-header {
	  margin: 2em 0 1.5em 0;
	  text-align: center;
	}
	.chapter-title {
	  font-size: 1.4em;
	  margin: 0.25em 0;
	}
	.endnotes-section {
	  margin-top: 3em;
	  padding-top: 1.5em;
	  border-top: 1px dashed #ccc;
	}

	@media (prefers-color-scheme: dark) {
	  .stats-block {
	    border-color: #333;
	  }
	  .tags-dl dt {
	    color: #a1a1aa;
	  }
	  .meta-section h3 {
	    color: #a1a1aa;
	  }
	  .endnotes-section {
	    border-color: #333;
	  }
	}
	"""

	private static let annotationsCSS = """
	/* Nectar Reader Highlights & Notes Styling */
	.annotations-header {
	  margin-top: 2em;
	  margin-bottom: 1.5em;
	}
	.annotation-summary {
	  font-size: 0.9em;
	  text-align: center;
	  color: #71717a;
	  margin-bottom: 2em;
	}
	.annotation-card {
	  margin: 1.5em 0;
	  padding: 1em 1.25em;
	  border-left: 4px solid #f59e0b;
	  background-color: #fbfbfb;
	  border-radius: 0 4px 4px 0;
	}
	.annotation-location {
	  font-size: 0.8em;
	  text-transform: uppercase;
	  letter-spacing: 0.05em;
	  color: #71717a;
	  margin-bottom: 0.5em;
	}
	.annotation-quote {
	  font-style: italic;
	  margin: 0.5em 0;
	  color: #27272a;
	  text-align: left;
	}
	.annotation-note {
	  font-weight: 500;
	  margin: 0.5em 0;
	  color: #18181b;
	  text-align: left;
	}
	.annotation-date {
	  display: block;
	  font-size: 0.75em;
	  color: #a1a1aa;
	  margin-top: 0.5em;
	}

	@media (prefers-color-scheme: dark) {
	  .annotation-card {
	    background-color: #1f1f23;
	  }
	  .annotation-quote {
	    color: #e4e4e7;
	  }
	  .annotation-note {
	    color: #f4f4f5;
	  }
	  .annotation-summary, .annotation-location {
	    color: #a1a1aa;
	  }
	}
	"""
}
