//
//  Annotation.swift
//  Articles
//
//  A highlighted range of an article's rendered text, plus an optional
//  free-text note attached to it. See docs/annotations.md for the anchor-
//  resolution algorithm this selector feeds (W3C Web Annotation Data
//  Model-style quote + position selector, stored together so re-rendering
//  can try the cheap position first and only fall back to a full quote
//  search when the DOM has shifted underneath it).
//
//  Lives here, not in ArticlesDatabase, for the same reason Article itself
//  does: it's a value type UI code (WebViewController, the annotations
//  list/editor screens) consumes directly and shouldn't need to link the
//  database module just to hold one in memory.
//

import Foundation

public struct Annotation: Codable, Sendable, Hashable, Identifiable {

	public enum Color: String, Codable, Sendable, CaseIterable {
		case yellow
		case red
		case green
		case blue
		case purple
	}

	public let annotationID: String
	public let articleID: String
	/// Resolved the same way BookStateTable resolves it (bookKeysForArticleIDs);
	/// nil when the owning article has no resolvable bookKey. An annotation with
	/// a nil bookKey is still fully functional -- it just can't be grouped into
	/// a cross-chapter "all highlights in this book" listing.
	public let bookKey: String?

	// Anchor: W3C-style quote + position selector, stored together. See
	// AnnotationsTable's table-creation SQL for column-level detail.
	public let quoteExact: String
	public let quotePrefix: String
	public let quoteSuffix: String
	public let rootSelector: String
	public let startOffset: Int
	public let endOffset: Int

	public let color: Color
	/// nil = highlight with no note attached.
	public let note: String?
	/// The nearest preceding `<h1>`/`<h2 class="heading">`/`<h2
	/// class="toc-heading">` heading inside the annotation's own
	/// rootSelector, at the time this selector was last computed (initial
	/// highlight, or a later re-anchor) -- see annotations.js's
	/// nearestChapterTitle. nil when there's no such heading before this
	/// annotation (front matter, or an ordinary single-heading book, where
	/// that one heading is the book's own chrome-level title rendered
	/// outside .articleBody and therefore never matched). Not recomputed
	/// except at those two points, so it can go stale the same way
	/// quotePrefix/quoteSuffix can -- self-heals on next re-anchor.
	public let chapterTitle: String?
	public let createdAt: Date
	public let updatedAt: Date

	/// Non-nil once anchor resolution has failed to relocate this
	/// annotation's quote against current content (see docs/annotations.md's
	/// re-anchoring section) -- surfaced, not dropped, so a note is never
	/// silently lost.
	public let orphanedAt: Date?
	public let lastReanchoredAt: Date?

	public var id: String { annotationID }

	public init(
		annotationID: String,
		articleID: String,
		bookKey: String?,
		quoteExact: String,
		quotePrefix: String,
		quoteSuffix: String,
		rootSelector: String = ".articleBody",
		startOffset: Int,
		endOffset: Int,
		color: Color,
		note: String?,
		chapterTitle: String? = nil,
		createdAt: Date,
		updatedAt: Date,
		orphanedAt: Date? = nil,
		lastReanchoredAt: Date? = nil
	) {
		self.annotationID = annotationID
		self.articleID = articleID
		self.bookKey = bookKey
		self.quoteExact = quoteExact
		self.quotePrefix = quotePrefix
		self.quoteSuffix = quoteSuffix
		self.rootSelector = rootSelector
		self.startOffset = startOffset
		self.endOffset = endOffset
		self.color = color
		self.note = note
		self.chapterTitle = chapterTitle
		self.createdAt = createdAt
		self.updatedAt = updatedAt
		self.orphanedAt = orphanedAt
		self.lastReanchoredAt = lastReanchoredAt
	}
}
