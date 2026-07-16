//
//  ArticleRenderer.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/8/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
#if os(iOS)
import UIKit
#endif
import RSCore
import Articles
import Account
import os

@MainActor struct ArticleRenderer {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleRenderer")

	typealias Rendering = (style: String, html: String, title: String, baseURL: String)

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

	private static let longDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .long
		formatter.timeStyle = .medium
		return formatter
	}()

	private static let mediumDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}()

	private static let shortDateTimeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .short
		return formatter
	}()

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

	private init(article: Article?, theme: ArticleTheme, timelineFeed: SidebarItem? = nil) {
		self.article = article
		self.articleTheme = theme
		self.title = ArticleStringFormatter.sanitizedTitle(article?.title, forHTML: true) ?? ""
		self.body = article?.body ?? ""
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
		return (renderer.articleCSS, renderer.articleHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func multipleSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.articleCSS, renderer.multipleSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func loadingHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.articleCSS, renderer.loadingHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noSelectionHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.articleCSS, renderer.noSelectionHTML, renderer.title, renderer.baseURL ?? "")
	}

	static func noContentHTML(theme: ArticleTheme) -> Rendering {
		let renderer = ArticleRenderer(article: nil, theme: theme)
		return (renderer.articleCSS, renderer.noContentHTML, renderer.title, renderer.baseURL ?? "")
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
		#if os(iOS)
		// Appended after the theme's own CSS (not merged into styleSubstitutions'
		// macro dictionary) so it applies to every theme, including third-party
		// imported ones that have no idea this feature exists -- same reasoning as
		// removeFeedNameLink() in main_ios.js being theme-agnostic rather than
		// keyed to a specific theme's markup.
		let overrides = AppDefaults.shared.articleThemeOverrides
		if !overrides.isEmpty {
			return base + "\n" + overrides.cssOverrideBlock
		}
		#endif
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

		#if os(macOS)
		d["text_size_class"] = AppDefaults.shared.articleTextSize.cssClass
		#endif

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
		#if os(iOS)
		if AppDefaults.shared.showFeedNameInReaderView {
			d["feed_link_title"] = ArticleFeedNaming.displayName(for: article, timelineFeed: timelineFeed) ?? ""
		} else {
			d["feed_link_title"] = ""
		}
		#else
		d["feed_link_title"] = article.feed?.nameForDisplay ?? ""
		#endif
		d["feed_link"] = article.feed?.homePageURL ?? ""

		d["byline"] = byline()

		let datePublished = article.logicalDatePublished
		d["datetime_long"] = Self.longDateTimeFormatter.string(from: datePublished)
		d["datetime_medium"] = Self.mediumDateTimeFormatter.string(from: datePublished)
		d["datetime_short"] = Self.shortDateTimeFormatter.string(from: datePublished)
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

	#if os(iOS)
	func styleSubstitutions() -> [String: String] {
		var d = [String: String]()
		let bodyFont = UIFont.preferredFont(forTextStyle: .body)
		d["font-size"] = String(describing: bodyFont.pointSize)
		return d
	}
	#else
	func styleSubstitutions() -> [String: String] {
		return [String: String]()
	}
	#endif

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
