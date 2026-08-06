//
//  ArticleRenderer.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/8/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import UIKit
import RSCore
import RSParser
import Articles
import Account
import os

@MainActor struct ArticleRenderer {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleRenderer")

	typealias Rendering = (importStyle: String, style: String, html: String, title: String, baseURL: String)

	struct Page {
		let url: URL
		let baseURL: URL
		let html: String

		init(name: String) {
			url = Bundle.main.url(forResource: name, withExtension: "html")!
			baseURL = url.deletingLastPathComponent()
			html = try! String(contentsOfFile: url.path, encoding: .utf8)
		}
	}

	static var imageIconScheme = "nnwImageIcon"

	static var blank = Page(name: "blank")
	static var page = Page(name: "page")

	private let article: Article?
	private let articleTheme: ArticleTheme
	private let title: String
	private let body: String
	private let baseURL: String?
	private let timelineFeed: SidebarItem?

	private static let longDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .long
		formatter.timeStyle = .none
		return formatter
	}()

	private static let mediumDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()

	private static let shortDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .none
		return formatter
	}()

	private static let longTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .long
		return formatter
	}()

	private static let mediumTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .medium
		return formatter
	}()

	private static let shortTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter
	}()

	/// yyyy-MM-dd, matching AO3's own "Stats:" date format exactly (see
	/// entire.html's `<dd class="published">2026-07-07</dd>`), so the
	/// synthesized preface's Published/Updated rows read the same as both
	/// AO3's live page and Ambrosia's own epub-derived preface.
	private static let ao3StatsDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}()

	private init(article: Article?, theme: ArticleTheme, timelineFeed: SidebarItem? = nil) {
		self.article = article
		self.articleTheme = theme
		self.title = ArticleStringFormatter.sanitizedTitle(article?.title, forHTML: true) ?? ""

		var bodyPrefix = ""
		if let article, let prefaceHTML = Self.ao3SyntheticPrefaceHTML(for: article) {
			bodyPrefix += prefaceHTML
		}

		if let article, article.contentHTML == nil,
		   let failureMessage = AO3ChapterFetcher.shared.lastFetchFailureMessage(forArticleID: article.articleID) {
			// contentHTML is nil (full chapter text never landed) and the
			// most recent fetch attempt for this article is known to have
			// failed -- surface why inline, above the feed-derived summary
			// article.body falls back to, rather than leaving the person to
			// guess or dig through the Activity Log. Escaped defensively even
			// though every current message is one of this app's own fixed
			// strings, not fetched/user content.
			let escapedMessage = failureMessage
				.replacingOccurrences(of: "&", with: "&amp;")
				.replacingOccurrences(of: "<", with: "&lt;")
				.replacingOccurrences(of: ">", with: "&gt;")
			bodyPrefix += "<p class='ao3ChapterFetchNotice'>Full text unavailable: \(escapedMessage)</p>"
		}
		self.body = bodyPrefix + (article?.body ?? "")
		self.baseURL = article?.baseURL?.absoluteString
		self.timelineFeed = timelineFeed
		if let article {
			// article.body is contentHTML ?? contentText ?? summary. Logging which
			// one won tells us directly whether a "missing images, plain text"
			// report is contentHTML actually being nil for that item (server/
			// parser issue) versus something else further down the pipeline.
			let source: String
			if article.contentHTML != nil {
				source = "contentHTML"
			} else if article.contentText != nil {
				source = "contentText"
			} else if article.summary != nil {
				source = "summary"
			} else {
				source = "none"
			}
			Self.logger.debug("ArticleRenderer: articleID=\(article.articleID, privacy: .public) bodySource=\(source, privacy: .public) contentHTMLLength=\(article.contentHTML?.count ?? -1, privacy: .public) contentTextLength=\(article.contentText?.count ?? -1, privacy: .public)")
		}
	}

	// MARK: - API

	static func articleHTML(article: Article, theme: ArticleTheme, timelineFeed: SidebarItem? = nil) -> Rendering {
		let renderer = ArticleRenderer(article: article, theme: theme, timelineFeed: timelineFeed)
		return (renderer.importStyle, renderer.articleCSS, renderer.articleHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func multipleSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.importStyle, renderer.articleCSS, renderer.multipleSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func loadingHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.importStyle, renderer.articleCSS, renderer.loadingHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.importStyle, renderer.articleCSS, renderer.noSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noContentHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.importStyle, renderer.articleCSS, renderer.noContentHTML, renderer.title, renderer.baseURL ?? "")
	}
}

// MARK: - Private

private extension ArticleRenderer {

	private var articleHTML: String {
		return try! MacroProcessor.renderedText(withTemplate: template(), substitutions: articleSubstitutions())
	}

	private var multipleSelectionHTML: String {
		let body = "<h3 class='systemMessage'>Multiple selection</h3>"
		return body
	}

	private var loadingHTML: String {
		let body = "<h3 class='systemMessage'>Loading...</h3>"
		return body
	}

	private var noSelectionHTML: String {
		let body = "<h3 class='systemMessage'>No selection</h3>"
		return body
	}

	private var noContentHTML: String {
		return ""
	}

	private var articleCSS: String {
		return try! MacroProcessor.renderedText(withTemplate: styleString(), substitutions: styleSubstitutions())
	}

	private var importStyle: String {
		guard let importCSS = articleTheme.importCSS, !importCSS.isEmpty else {
			return ""
		}

		return """
		<style>
			\(importCSS)
		</style>
		"""
	}

	static var defaultStyleSheet: String = {
		let path = Bundle.main.path(forResource: "stylesheet", ofType: "css")!
		let s = try! String(contentsOfFile: path, encoding: .utf8)
		return "\n\(s)\n"
	}()

	static let defaultTemplate: String = {
		let path = Bundle.main.path(forResource: "template", ofType: "html")!
		let s = try! String(contentsOfFile: path, encoding: .utf8)
		return s as String
	}()

	func styleString() -> String {
		let base = articleTheme.css ?? ArticleRenderer.defaultStyleSheet
		// Appended after the theme's own CSS (not merged into styleSubstitutions'
		// macro dictionary) so it applies to every theme, including third-party
		// imported ones that have no idea this feature exists -- same reasoning as
		// removeFeedNameLink() in main_ios.js being theme-agnostic rather than
		// keyed to a specific theme's markup.
		let overrides = AppDefaults.shared.articleThemeOverrides
		if !overrides.isEmpty {
			return base + "\n" + overrides.cssOverrideBlock
		}
		return base
	}

	func template() -> String {
		return articleTheme.template ?? ArticleRenderer.defaultTemplate
	}

	func articleSubstitutions() -> [String: String] {
		var d = [String: String]()

		guard let article = article else {
			assertionFailure("Article should have been set before calling this function.")
			return d
		}

		d["title"] = title
		d["preferred_link"] = article.preferredLink ?? ""

		if let externalLink = article.externalLink, externalLink != article.preferredLink {
			d["external_link_label"] = NSLocalizedString("Link:", comment: "Link")
			d["external_link_stripped"] = externalLink.strippingHTTPOrHTTPSScheme
			d["external_link"] = externalLink
		} else {
			d["external_link_label"] = ""
			d["external_link_stripped"] = ""
			d["external_link"] = ""
		}

		d["body"] = body

		var components = URLComponents()
		components.scheme = Self.imageIconScheme
		components.path = article.articleID
		if let imageIconURLString = components.string {
			d["avatar_src"] = imageIconURLString
		} else {
			d["avatar_src"] = ""
		}

		if self.title.isEmpty {
			d["dateline_style"] = "articleDatelineTitle"
		} else {
			d["dateline_style"] = "articleDateline"
		}

		// Off by default (AppDefaults.shared.showFeedNameInReaderView): once
		// SmartFeedArticleGrouping can surface a book from more than one
		// feed, crediting it to just one feed's name is misleading, so the
		// reader view hides the feed name entirely unless the user turns it
		// back on. When on, ArticleFeedNaming resolves the same single-feed
		// vs. combined-feeds ("Fandom A, Search Results") name the timeline
		// cell shows, based on whichever smart feed (if any) this article is
		// currently being viewed from. Leaving feed_link_title empty here
		// (rather than skipping the template's own [[feed_link_title]]
		// token) is what lets main.js's removeFeedNameLink() strip the
		// link generically for every theme -- see that function's comment.
		if AppDefaults.shared.showFeedNameInReaderView {
			d["feed_link_title"] = ArticleFeedNaming.displayName(for: article, timelineFeed: timelineFeed) ?? ""
		} else {
			d["feed_link_title"] = ""
		}
		d["feed_link"] = article.feed?.homePageURL ?? ""

		d["byline"] = byline()

		let datePublished = article.logicalDatePublished
		// datetime_* used to include a time component, but every article's time
		// is auto-set to 12:00, so it never carried real information. All themes
		// (including future ones) reference these same tokens, so fixing them
		// here fixes every theme without editing each one.
		d["datetime_long"] = Self.longDateFormatter.string(from: datePublished)
		d["datetime_medium"] = Self.mediumDateFormatter.string(from: datePublished)
		d["datetime_short"] = Self.shortDateFormatter.string(from: datePublished)
		d["date_long"] = Self.longDateFormatter.string(from: datePublished)
		d["date_medium"] = Self.mediumDateFormatter.string(from: datePublished)
		d["date_short"] = Self.shortDateFormatter.string(from: datePublished)
		d["time_long"] = Self.longTimeFormatter.string(from: datePublished)
		d["time_medium"] = Self.mediumTimeFormatter.string(from: datePublished)
		d["time_short"] = Self.shortTimeFormatter.string(from: datePublished)

		return d
	}

	func byline() -> String {
		guard let authors = article?.authors ?? article?.feed?.authors, !authors.isEmpty else {
			return ""
		}

		// If the author's name is the same as the feed, then we don't want to display it.
		// This code assumes that multiple authors would never match the feed name so that
		// if there feed owner has an article co-author all authors are given the byline.
		if authors.count == 1, let author = authors.first {
			if author.name == article?.feed?.nameForDisplay {
				return ""
			}
		}

		var byline = ""
		var isFirstAuthor = true

		for author in authors {
			if !isFirstAuthor {
				byline += ", "
			}
			isFirstAuthor = false

			var authorEmailAddress: String?
			if let emailAddress = author.emailAddress, !(emailAddress.contains("noreply@") || emailAddress.contains("no-reply@")) {
				authorEmailAddress = emailAddress
			}

			if let emailAddress = authorEmailAddress, emailAddress.contains(" ") {
				byline += emailAddress // probably name plus email address
			} else if let name = author.name, let url = author.url {
				byline += name.htmlByAddingLink(url)
			} else if let name = author.name, let emailAddress = authorEmailAddress {
				byline += "\(name) &lt;\(emailAddress)&gt;"
			} else if let name = author.name {
				byline += name
			} else if let emailAddress = authorEmailAddress {
				byline += "&lt;\(emailAddress)&gt;" // TODO: mailto link
			} else if let url = author.url {
				byline += String.htmlWithLink(url)
			}
		}

		return byline
	}

	func styleSubstitutions() -> [String: String] {
		var d = [String: String]()
		let bodyFont = UIFont.preferredFont(forTextStyle: .body)
		d["font-size"] = String(describing: bodyFont.pointSize)
		return d
	}

}

// MARK: - Article extension

@MainActor private extension Article {

	var baseURL: URL? {
		var s = link
		if s == nil {
			s = feed?.homePageURL
		}
		if s == nil {
			s = feed?.url
		}

		guard let urlString = s else {
			return nil
		}
		var urlComponents = URLComponents(string: urlString)
		if urlComponents == nil {
			return nil
		}

		// Can’t use url-with-fragment as base URL. The webview won’t load. See scripting.com/rss.xml for example.
		urlComponents!.fragment = nil
		guard let url = urlComponents!.url, url.scheme == "http" || url.scheme == "https" else {
			return nil
		}
		return url
	}
}

// MARK: - Synthesized AO3 preface

private extension ArticleRenderer {

	/// A front-matter block mirroring AO3's own metadata table
	/// (rating/warning/category/fandom/relationships/characters/language/
	/// series/stats), synthesized from Workstream 1's already-parsed
	/// metadata on `article` -- used only as a fallback for the window
	/// before a chapter fetch has ever succeeded.
	///
	/// Once `AO3ChapterFetcher` succeeds once, the real `<dl class="work
	/// meta group">` block is captured verbatim by `AO3ChapterHTMLExtractor`
	/// and baked directly into the front of `article.contentHTML` -- at that
	/// point this function must return nil, or the real block and this
	/// synthesized approximation would both show, stacked. That's the
	/// `article.contentHTML == nil` guard below: it's not just "don't
	/// crash on missing data", it's the actual real-vs-synthesized switch.
	///
	/// Before that first successful fetch, this is still worth showing --
	/// it's the strongest available check that Workstream 1's feed parsing
	/// itself is correct, since it doesn't depend on a successful chapter
	/// fetch at all. It also means real AO3 tag links are only available
	/// post-fetch; this fallback intentionally doesn't attempt to
	/// reconstruct AO3's tag-URL encoding scheme (see the design discussion
	/// that led to full extraction instead of synthesis, for the case where
	/// contentHTML does exist) -- rows here are plain text.
	///
	/// This guard also happens to be exactly the right check for Ambrosia
	/// items, which always arrive with contentHTML already populated
	/// (Ambrosia's JSON feed sets content_html directly, including its own
	/// complete preface) -- they never have a nil contentHTML to fall back
	/// from, so this never fires for them and there's no risk of stacking a
	/// second preface above Ambrosia's own.
	static func ao3SyntheticPrefaceHTML(for article: Article) -> String? {
		guard article.contentHTML == nil else {
			return nil
		}
		// Personalization plan item 6 ("Stats-visibility toggles"): this
		// entire function exists to synthesize the same rating/warning/
		// category/fandom/relationships/characters/series/stats block the
		// toggle is meant to hide, so when it's off there's nothing left
		// here worth rendering -- same shared AppDefaults.shared.statsVisible
		// gate MainTimelineCellData.init(article:...) uses, so hiding stats
		// in the timeline and hiding them in the reader always agree.
		guard AppDefaults.shared.statsVisible else {
			return nil
		}
		guard article.fandoms != nil || article.ratings != nil || article.warnings != nil || article.categories != nil else {
			return nil
		}

		var rows: [AO3PrefaceRow] = []
		func appendRow(_ label: String, _ values: [String]?, isWide: Bool = false) {
			guard let values, !values.isEmpty else {
				return
			}
			rows.append(AO3PrefaceRow(label: label, values: values.map { AO3TagEntry(text: $0) }, isWide: isWide))
		}

		appendRow("Rating:", article.ratings)
		appendRow("Archive Warning:", article.warnings)
		appendRow("Category:", article.categories)
		// Fandom/Relationships/Characters render wide (full preface width,
		// own line below the label) -- matching AO3ChapterHTMLExtractor's
		// real-fetch path, since these can carry dozens of values just as
		// easily in Ambrosia's own parsed fields as off a live AO3 page.
		appendRow("Fandom:", article.fandoms, isWide: true)
		appendRow("Relationships:", article.relationships, isWide: true)
		appendRow("Characters:", article.characters, isWide: true)
		// Additional Tags (AO3's freeform tags) has no home on Article at
		// all -- Workstream 1 doesn't parse a distinct freeform-tags bucket
		// from the Atom feed, so there's nothing to synthesize this row
		// from. Flagged here rather than silently dropped: if this becomes
		// a priority, it needs a Workstream 1 change first, not a change
		// here.

		if let series = article.series, !series.isEmpty {
			let entries = series.map { entry in
				AO3TagEntry(text: entry.name, prefix: "Part \(entry.index) of ")
			}
			rows.append(AO3PrefaceRow(label: "Series:", values: entries))
		}

		// Collections: deliberately not synthesized here -- flagged as an
		// open decision (no Workstream 1 field exists for it; Ambrosia's
		// own collections list comes from a different data source than the
		// Atom feed this app parses). Revisit once that's decided.

		// Each stat is its own row -- matching AO3's own dt/dd-per-stat
		// shape (and AO3PrefaceRenderer's rendering of it) rather than the
		// single bundled "Stats:" row this used to synthesize, so the two
		// paths produce identical markup (see AO3PrefaceRenderer).
		var statsRows: [AO3PrefaceStatsRow] = []
		if let datePublished = article.datePublished {
			statsRows.append(AO3PrefaceStatsRow(label: "Published:", value: ao3StatsDateFormatter.string(from: datePublished)))
		}
		if let dateModified = article.dateModified, dateModified != article.datePublished {
			statsRows.append(AO3PrefaceStatsRow(label: "Updated:", value: ao3StatsDateFormatter.string(from: dateModified)))
		}
		if let wordCount = article.wordCount {
			statsRows.append(AO3PrefaceStatsRow(label: "Words:", value: String(wordCount)))
		}
		if let chapterCurrent = article.chapterCurrent {
			// "?" for an unposted/unknown total, matching AO3's own
			// "Chapters: N/?" convention for an in-progress work whose
			// planned length the author hasn't declared.
			let total = article.chapterTotal.map(String.init) ?? "?"
			statsRows.append(AO3PrefaceStatsRow(label: "Chapters:", value: "\(chapterCurrent)/\(total)"))
		}

		return AO3PrefaceRenderer.html(id: "ao3SyntheticPreface", data: AO3PrefaceData(rows: rows, statsRows: statsRows))
	}
}
