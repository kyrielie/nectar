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
///
/// `ao3ID`/`previousWorkURL`/`nextWorkURL` are inline-series-navigation
/// data, populated only on entries belonging to a `AO3PrefaceRow` with
/// `isSeriesNavigation == true` -- every other row's entries leave all
/// three nil. Carried here (rather than as a separate parallel array)
/// so the renderer can build each series entry's own First/Previous/Next
/// links right alongside its name in a single per-entry pass.
public struct AO3TagEntry: Sendable, Equatable {
	public let text: String
	public let href: String?
	public let prefix: String
	public let ao3ID: String?
	public let previousWorkURL: String?
	public let nextWorkURL: String?

	public init(text: String, href: String? = nil, prefix: String = "", ao3ID: String? = nil, previousWorkURL: String? = nil, nextWorkURL: String? = nil) {
		self.text = text
		self.href = href
		self.prefix = prefix
		self.ao3ID = ao3ID
		self.previousWorkURL = previousWorkURL
		self.nextWorkURL = nextWorkURL
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

	/// True only for the Series row. Inline series navigation needs one
	/// `<dt>Series:</dt><dd>...</dd>` pair *per entry* (each with its own
	/// trailing First/Previous/Next links), not the generic
	/// comma-joined-into-one-`<dd>` shape every other row uses -- a work
	/// in two series has two separately-navigable rows, not one row
	/// listing two names. `AO3PrefaceRenderer.html(id:data:)` special-cases
	/// this flag rather than joining `values` with the generic renderer.
	public let isSeriesNavigation: Bool

	public init(label: String, values: [AO3TagEntry], isWide: Bool = false, isSeriesNavigation: Bool = false) {
		self.label = label
		self.values = values
		self.isWide = isWide
		self.isSeriesNavigation = isSeriesNavigation
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

	// MARK: - Inline series navigation footer (Phase 3b groundwork)

	/// "This work is part of ..." block, appended after the article body --
	/// one entry per series membership, each with its own First / Previous /
	/// Next links (inline-series-navigation plan, Phase 3a/3b). Typed
	/// against `[ParsedSeriesEntry]`, not `[ArticleSeriesEntry]`, since this
	/// module (RSParser) can't depend on the Articles module -- the two
	/// types carry identical navigation fields, so nothing is lost typing
	/// against the RSParser-local one here. Both `AO3ChapterHTMLExtractor.
	/// serializedContentHTML` (real-fetch path) and, once Phase 3b's
	/// synthetic-preface caller is wired up, `ArticleRenderer` call this
	/// same builder so a future markup tweak only happens once.
	///
	/// Returns nil (renders nothing) when `entries` is empty, matching the
	/// no-fandom/no-warnings "don't emit an empty row" precedent elsewhere
	/// in this preface pipeline -- there is no bare `#ao3SeriesFooter` div
	/// for a non-series work.
	///
	/// NOTE: this is the footer (bottom) half of Phase 3 only. The
	/// preface's own top Series row still renders the pre-Phase-3 way (one
	/// comma-joined `<dd>`, no inline links) -- `AO3PrefaceRow.
	/// isSeriesNavigation` exists on the model already but `html(id:data:)`
	/// doesn't yet special-case it. That rework, the `nectar-series:`
	/// scheme's `WebViewController` handling (Phase 3a/3c), and Phase 4's
	/// tap-to-navigate flow are follow-up work, not done here.
	public static func seriesFooterHTML(entries: [ParsedSeriesEntry]) -> String? {
		guard !entries.isEmpty else {
			return nil
		}

		var entriesHTML = ""
		for entry in entries {
			entriesHTML += "<div class='ao3SeriesFooterEntry'>"
			entriesHTML += "<span class='ao3SeriesFooterName'>Part \(entry.index) of \(escape(entry.name))</span>"
			entriesHTML += "<span class='ao3SeriesFooterLinks'>\(seriesNavigationLinksHTML(entry: entry))</span>"
			entriesHTML += "</div>"
		}

		return "<div id='ao3SeriesFooter'><p class='ao3SeriesFooterHeading'>This work is part of a series:</p>\(entriesHTML)</div>"
	}

	/// Builds the "First · Previous · Next" line for one series entry,
	/// linked via the `nectar-series:` scheme (Phase 3a) so
	/// `WebViewController` can act on a tap without a JS bridge. First is
	/// tappable whenever `ao3ID` is known -- its target is resolved lazily
	/// on tap (Phase 4), since AO3's work page has no "first work" link to
	/// read a URL off directly, unlike Previous/Next. Previous/Next are
	/// only tappable when their URL was actually captured off the live
	/// fetch; otherwise they render as plain, unlinked muted text (Phase
	/// 3c) rather than being hidden outright, so a per-row label still
	/// communicates "you're at the start/end of *this* series."
	static func seriesNavigationLinksHTML(entry: ParsedSeriesEntry) -> String {
		var parts: [String] = []

		if let ao3ID = entry.ao3ID {
			parts.append(link(label: "First", href: "nectar-series:first?ao3id=\(percentEncodedQueryValue(ao3ID))"))
		} else {
			parts.append(disabledLabel("First"))
		}

		parts.append(directionLink(label: "Previous", direction: "previous", ao3ID: entry.ao3ID, workURL: entry.previousWorkURL))
		parts.append(directionLink(label: "Next", direction: "next", ao3ID: entry.ao3ID, workURL: entry.nextWorkURL))

		return parts.joined(separator: " · ")
	}

	private static func directionLink(label: String, direction: String, ao3ID: String?, workURL: String?) -> String {
		guard let ao3ID, let workURL else {
			return disabledLabel(label)
		}
		let href = "nectar-series:\(direction)?ao3id=\(percentEncodedQueryValue(ao3ID))&workurl=\(percentEncodedQueryValue(workURL))"
		return link(label: label, href: href)
	}

	private static func link(label: String, href: String) -> String {
		"<a href='\(escapeAttribute(href))'>\(escape(label))</a>"
	}

	private static func disabledLabel(_ label: String) -> String {
		"<span class='ao3SeriesNavDisabled'>\(escape(label))</span>"
	}

	/// Percent-encodes one query value before the assembled href reaches
	/// `escapeAttribute`'s HTML-attribute escaping. `escapeAttribute` only
	/// escapes `&`/`<`/`>`/`'` for safe HTML embedding -- it does not
	/// percent-encode URL-reserved characters, so a series name or work
	/// permalink containing `&` (or `?`/`=`) would otherwise corrupt this
	/// query string's own delimiters before HTML-escaping ever runs (Phase
	/// 3a's escaping-gap note).
	private static func percentEncodedQueryValue(_ value: String) -> String {
		value.addingPercentEncoding(withAllowedCharacters: .nectarSeriesQueryValueAllowed) ?? value
	}
}

private extension CharacterSet {
	/// `.urlQueryAllowed` still permits `&`/`=`/`?`, which would corrupt
	/// this app's own `nectar-series:` query string if present in an
	/// encoded value (e.g. a work permalink containing a query already, or
	/// -- defensively -- a series id). Stripped from the allowed set so
	/// every occurrence gets percent-encoded instead.
	static let nectarSeriesQueryValueAllowed: CharacterSet = {
		var set = CharacterSet.urlQueryAllowed
		set.remove(charactersIn: "&=?")
		return set
	}()
}
