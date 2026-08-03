//
//  AO3PrefaceRenderer.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

/// One value in an `AO3PrefaceRow` -- a tag/fandom/series/etc entry. `href`
/// is nil for plain text (language, and every field of the pre-fetch
/// synthetic preface, which has no AO3 URLs to link to) and populated for
/// AO3's own real tag/series links, read directly off the fetched page's
/// `<a>` elements. `prefix` is unlinked text that sits ahead of `text` in
/// the same value -- used only by series rows ("Part 1 of " ahead of the
/// linked series name); every other row leaves it empty.
public struct AO3TagEntry: Sendable, Equatable {
	public let text: String
	public let href: String?
	public let prefix: String

	public init(text: String, href: String? = nil, prefix: String = "") {
		self.text = text
		self.href = href
		self.prefix = prefix
	}
}

/// One renderable row of the preface -- rating/warning/category/fandom/
/// relationships/characters/freeform/language/series/collections. `label`
/// already carries its own trailing colon (AO3's own `<dt>` text does, e.g.
/// "Rating:", and the pre-fetch synthetic path supplies it the same way),
/// so the renderer doesn't add one.
public struct AO3PrefaceRow: Sendable, Equatable {
	public let label: String
	public let values: [AO3TagEntry]

	/// True for rows that can carry a large, unbounded number of values --
	/// Fandom, Relationships, Characters, Additional Tags (freeform) -- as
	/// opposed to short/bounded rows like Rating or Category. A wide row
	/// renders its `<dd>` spanning the full preface width on its own line
	/// below the label, instead of squeezed into the label-adjacent grid
	/// column alongside every other row: a work with dozens of relationship
	/// or freeform tags otherwise wraps its tag list inside a column that's
	/// only as wide as "1fr" of the label column leaves free, wasting the
	/// row's own label-height line and most of the preface's width.
	public let isWide: Bool

	public init(label: String, values: [AO3TagEntry], isWide: Bool = false) {
		self.label = label
		self.values = values
		self.isWide = isWide
	}
}

/// One stats line (Published/Updated/Words/Chapters/Comments/Kudos/
/// Bookmarks/Hits) as an already-formatted label/value pair, rendered as
/// its own inline `<dt>`/`<dd>` row rather than bundled together, so a
/// long value never wraps under its label.
public struct AO3PrefaceStatsRow: Sendable, Equatable {
	public let label: String
	public let value: String

	public init(label: String, value: String) {
		self.label = label
		self.value = value
	}
}

/// Everything needed to render one preface: the tag-style rows, then the
/// stats rows, in that order.
public struct AO3PrefaceData: Sendable, Equatable {
	public let rows: [AO3PrefaceRow]
	public let statsRows: [AO3PrefaceStatsRow]

	public init(rows: [AO3PrefaceRow], statsRows: [AO3PrefaceStatsRow]) {
		self.rows = rows
		self.statsRows = statsRows
	}
}

/// Renders `AO3PrefaceData` into the same markup shape regardless of
/// caller: `AO3ChapterHTMLExtractor` feeds it real, structured data parsed
/// off a fetched AO3 page (real tag hrefs included); `ArticleRenderer`
/// feeds it a synthesized `AO3PrefaceData` built from `Article`'s
/// already-parsed fields, before any chapter fetch has ever succeeded
/// (plain text only -- this app doesn't encode AO3's tag-URL scheme
/// itself). Only the caller-supplied `id` (`ao3Preface` vs
/// `ao3SyntheticPreface`) distinguishes them, so the stylesheet can share
/// one rule set (see stylesheet.css) instead of two.
///
/// No sanitizer exists anywhere in this app's rendering pipeline (see
/// `ArticleRenderer`/`MacroProcessor`) -- every value substituted here is
/// escaped by hand, whether it came from a live AO3 fetch or from
/// already-parsed feed content.
public enum AO3PrefaceRenderer {

	public static func html(id: String, data: AO3PrefaceData) -> String? {
		var rowsHTML = ""

		for row in data.rows {
			let joined = row.values.map(renderedEntry).joined(separator: ", ")
			guard !joined.isEmpty else { continue }
			let classAttribute = row.isWide ? " class='wide'" : ""
			rowsHTML += "<dt\(classAttribute)>\(escape(row.label))</dt><dd\(classAttribute)>\(joined)</dd>"
		}
		for stat in data.statsRows {
			guard !stat.value.isEmpty else { continue }
			rowsHTML += "<dt>\(escape(stat.label))</dt><dd>\(escape(stat.value))</dd>"
		}

		guard !rowsHTML.isEmpty else {
			return nil
		}
		return "<div id='\(escapeAttribute(id))'><dl class='tags'>\(rowsHTML)</dl></div>"
	}

	private static func renderedEntry(_ entry: AO3TagEntry) -> String {
		let prefix = escape(entry.prefix)
		let text = escape(entry.text)
		guard let href = entry.href else {
			return prefix + text
		}
		return "\(prefix)<a href='\(escapeAttribute(href))'>\(text)</a>"
	}

	static func escape(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}

	private static func escapeAttribute(_ string: String) -> String {
		escape(string).replacingOccurrences(of: "'", with: "&#39;")
	}
}
