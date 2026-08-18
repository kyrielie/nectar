//
//  AnnotationsListView.swift
//  NetNewsWire-iOS
//
//  Reachable two ways: from the reader's annotations toolbar button
//  (ArticleViewController.showAnnotationsList(_:), always the whole open
//  book, grouped by chapter) and from Settings (unscoped, "everything
//  I've ever highlighted"). One implementation either way -- the only
//  difference between the two entry points is which Account fetch method
//  loadRows() below calls, matching fetchAnnotations(forBookKey:)/
//  fetchAllAnnotations() 1:1. There used to be a third, per-chapter scope
//  reachable from a toolbar menu with two choices; that menu is gone (see
//  ArticleViewController.showAnnotationsList's doc comment) since a
//  single grouped-by-chapter view covers the same need without asking
//  which scope to open first.
//
//  Groups are keyed by (bookKey ?? articleID, chapterTitle) -- NOT by
//  articleID alone. Two reasons this matters (see docs/book-identity.md,
//  docs/annotations.md):
//   1. The same book can have more than one articleID sharing one bookKey
//      (duplicate collection feeds, resubscriptions) -- grouping by
//      articleID alone split those into separate sections that repeated
//      the same book title as both the nav bar title and a section
//      header. Falling back to bookKey collapses genuine duplicates while
//      still falling back to articleID for the rare unresolvable-bookKey
//      case (see Annotation.bookKey's doc comment).
//   2. A single book's chapters can themselves span more than one
//      articleID (confirmed against a real multi-chapter book -- chapter
//      identity here is carried by chapterTitle, not by articleID
//      boundaries), so chapterTitle has to be part of the key too, or
//      distinct chapters of the same book would incorrectly collapse into
//      one section once grouping moved to bookKey.
//
//  Tapping a row has two cases: if the row's article is the one already
//  open behind this screen, this view can't scroll the live webview
//  itself (it has no reference to WebViewController), so it hands back
//  via onNavigateToAnnotation and lets the presenter (ArticleViewController)
//  decide whether that's a same-article scrollToAnnotation call or a
//  cross-article SceneCoordinator.selectArticleDirectly navigation
//  followed by one.
//

import SwiftUI
import NaturalLanguage
import Articles
import Account

struct AnnotationsListView: View {

	enum Scope {
		case book(bookKey: String)
		case everything
	}

	let account: Account
	let scope: Scope

	/// The screen's navigation title, supplied by the caller rather than
	/// derived here. For the .book case this is the currently-open
	/// article's own title (already in memory at the call site -- see
	/// ArticleViewController.showAnnotationsList) rather than a fixed
	/// placeholder string; nil (or empty) falls back to a generic title
	/// below, the same fallback shape TableOfContentsViewController uses
	/// for its own bookTitle parameter.
	let title: String?

	/// Called when the person taps a row: navigate to (and, once there,
	/// flash) this annotation. The caller owns both the cross-article
	/// navigation and the same-article scroll -- see this file's header
	/// comment.
	var onNavigateToAnnotation: (Annotation) -> Void

	/// Explicit close handler for callers that present this view
	/// imperatively via UIKit (ArticleViewController.showAnnotationsList
	/// wraps this in a UIHostingController inside a UINavigationController
	/// and calls present(_:animated:) directly, entirely outside SwiftUI's
	/// own presentation machinery) -- @Environment(\.dismiss) only gets a
	/// working handler wired up when SwiftUI itself performed the
	/// presentation/push, so it's a silent no-op there. nil (the default)
	/// falls back to dismiss(), which is correct for the Settings entry
	/// point below: that one reaches this view through a real SwiftUI
	/// NavigationLink push, so dismiss() (pop, in that context) already
	/// works.
	var onClose: (() -> Void)? = nil

	@Environment(\.dismiss) private var dismiss

	init(account: Account, scope: Scope, title: String? = nil, onClose: (() -> Void)? = nil, onNavigateToAnnotation: @escaping (Annotation) -> Void) {
		self.account = account
		self.scope = scope
		self.title = title
		self.onClose = onClose
		self.onNavigateToAnnotation = onNavigateToAnnotation
	}

	@State private var groups: [AnnotationGroup] = []
	@State private var isLoading = true
	/// Section headers are collapsible (see `list`/`sectionHeader(for:)`
	/// below) -- a group's key present here means its rows are hidden.
	/// Starts empty so every section opens expanded by default; not
	/// persisted across screen presentations, same as the rest of this
	/// view's transient @State.
	@State private var collapsedGroupKeys: Set<GroupKey> = []

	private struct Row: Identifiable {
		let annotation: Annotation

		var id: String { annotation.annotationID }
	}

	/// Grouping key: bookKey when the owning article resolves one, else
	/// articleID (Annotation.bookKey's own fallback shape), paired with
	/// chapterTitle so a book's distinct chapters don't collapse into one
	/// section just because they share a bookKey -- see this file's header
	/// comment.
	private struct GroupKey: Hashable {
		let bookOrArticleID: String
		let chapterTitle: String?
	}

	/// One section per (book, chapter). `heading` is the text to show in
	/// the section header when there's more than one group on screen:
	/// chapterTitle when this group has one (the real-anthology case --
	/// see mockup discussed with the person), otherwise the group's own
	/// book/article title (the cross-book case in the .everything scope,
	/// where different books need their own headers even though none of
	/// them has chapters).
	private struct AnnotationGroup: Identifiable {
		let key: GroupKey
		let heading: String
		let rows: [Row]

		var id: GroupKey { key }
	}

	private var navigationTitleText: String {
		if let title, !title.isEmpty {
			return title
		}
		switch scope {
		case .book:
			return NSLocalizedString("This Book", comment: "Annotations list navigation title: whole book, title unavailable")
		case .everything:
			return NSLocalizedString("All Highlights", comment: "Annotations list navigation title: everything")
		}
	}

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if groups.isEmpty {
				emptyState
			} else {
				list
			}
		}
		.navigationTitle(Text(navigationTitleText))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			// From the toolbar-button entry point this screen is presented
			// modally, full-screen, with no system back chevron (see
			// ArticleViewController.showAnnotationsList) -- same close
			// affordance TableOfContentsViewController uses for the same
			// reason (system .close item, trailing placement: an "×"
			// glyph, not text -- xmark here matches that rather than
			// spelling out "Close"), and from Settings' NavigationLink
			// entry point a back chevron is already present, but showing
			// this too is harmless and keeps one behavior for both entry
			// points.
			ToolbarItem(placement: .confirmationAction) {
				Button {
					if let onClose {
						onClose()
					} else {
						dismiss()
					}
				} label: {
					Image(systemName: "xmark")
				}
				.accessibilityLabel(Text("Close", comment: "Annotations list: close button accessibility label"))
			}
		}
		.task {
			await loadRows()
		}
	}

	private var emptyState: some View {
		ContentUnavailableView(
			NSLocalizedString("No Highlights", comment: "Annotations list empty state title"),
			systemImage: "highlighter",
			description: Text("Select text in an article to highlight it.", comment: "Annotations list empty state message")
		)
	}

	private var list: some View {
		List {
			ForEach(groups) { group in
				if groups.count > 1 {
					Section {
						if !collapsedGroupKeys.contains(group.key) {
							rows(for: group)
						}
					} header: {
						sectionHeader(for: group)
					}
				} else {
					// A single group's header would just repeat the
					// navigation title (the common non-anthology case,
					// where there's only ever one chapter) -- omit it
					// rather than show a redundant heading. Nothing to
					// collapse when it's the only section on screen.
					Section {
						rows(for: group)
					}
				}
			}
		}
	}

	/// A tappable section header that toggles `collapsedGroupKeys` for
	/// this group. Plain-styled (not the system disclosure-button look)
	/// to match the existing header's typography -- only the chevron
	/// communicates state.
	private func sectionHeader(for group: AnnotationGroup) -> some View {
		let isCollapsed = collapsedGroupKeys.contains(group.key)
		return Button {
			withAnimation(.default) {
				if isCollapsed {
					collapsedGroupKeys.remove(group.key)
				} else {
					collapsedGroupKeys.insert(group.key)
				}
			}
		} label: {
			HStack {
				Text(group.heading)
				Spacer()
				Image(systemName: "chevron.down")
					.rotationEffect(.degrees(isCollapsed ? -90 : 0))
					.font(.caption2.weight(.semibold))
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityValue(isCollapsed
			? Text("Collapsed", comment: "Annotations list: collapsed section header accessibility value")
			: Text("Expanded", comment: "Annotations list: expanded section header accessibility value"))
	}

	@ViewBuilder
	private func rows(for group: AnnotationGroup) -> some View {
		ForEach(group.rows) { row in
			Button {
				onNavigateToAnnotation(row.annotation)
			} label: {
				AnnotationRow(annotation: row.annotation)
			}
			.buttonStyle(.plain)
			.swipeActions(edge: .trailing, allowsFullSwipe: true) {
				Button(role: .destructive) {
					delete(row.annotation)
				} label: {
					Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
				}
			}
		}
	}

	private func loadRows() async {
		isLoading = true

		let annotations: [Annotation]
		switch scope {
		case .book(let bookKey):
			annotations = await account.fetchAnnotations(forBookKey: bookKey)
		case .everything:
			annotations = await account.fetchAllAnnotations()
		}

		guard !annotations.isEmpty else {
			groups = []
			isLoading = false
			return
		}

		// Titles are looked up once per unique articleID, not once per
		// annotation -- a chapter with several highlights would otherwise
		// fetch the same Article repeatedly.
		let articleIDs = Set(annotations.map(\.articleID))
		let articles = await account.fetchArticlesAsync(.articleIDs(articleIDs))
		let titlesByArticleID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0.title ?? NSLocalizedString("Untitled", comment: "Fallback article title")) })

		// Grouped by (bookKey ?? articleID, chapterTitle) -- see this file's
		// header comment.
		func normalizedChapterTitle(_ chapterTitle: String?) -> String? {
			guard let trimmed = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
				return nil
			}
			return trimmed
		}

		// Books/clusters (bookOrArticleID) are still ordered by recency --
		// "which book did I highlight in most recently" is still the right
		// question across different books in the .everything scope. But
		// chapters *within* one book are reading order, not recency --
		// annotations table has no stored chapter-position column (see
		// docs/annotations.md), so this falls back to the leading integer
		// in chapterTitle itself ("Chapter 9" -> 9), which is what
		// annotations.js's nearestChapterTitle actually captures for a
		// Calibre-style TOC heading. A chapterTitle with no leading number
		// sorts after every group that has one, rather than crashing the
		// whole book's ordering back to recency; a nil chapterTitle (no
		// heading before this annotation at all -- front matter, or the
		// single-heading non-anthology case) sorts first, ahead of
		// Chapter 1, matching where that content actually sits in the book.
		func leadingInteger(in string: String) -> Int? {
			var digits = ""
			for character in string {
				if character.isNumber {
					digits.append(character)
				} else if !digits.isEmpty {
					break
				}
			}
			return digits.isEmpty ? nil : Int(digits)
		}

		func chapterSortOrder(_ chapterTitle: String?) -> Int {
			guard let chapterTitle else { return Int.min }
			return leadingInteger(in: chapterTitle) ?? Int.max
		}

		let clusterRecency = Dictionary(grouping: annotations, by: { $0.bookKey ?? $0.articleID })
			.mapValues { clusterAnnotations in clusterAnnotations.map(\.updatedAt).max() ?? Date.distantPast }

		let rowsByGroupKey = Dictionary(grouping: annotations) { annotation in
			GroupKey(
				bookOrArticleID: annotation.bookKey ?? annotation.articleID,
				chapterTitle: normalizedChapterTitle(annotation.chapterTitle)
			)
		}
		groups = rowsByGroupKey
			.map { key, groupAnnotations -> AnnotationGroup in
				let sortedAnnotations = groupAnnotations.sorted { $0.updatedAt > $1.updatedAt }
				// Fallback heading when this group has no chapterTitle of
				// its own: the owning article's title (the cross-book case
				// in .everything, or a plain non-chaptered book). Any
				// article's title in the group works here -- every
				// annotation sharing a bookKey is understood to be the
				// same book (see book-identity.md), so their titles should
				// already agree.
				let fallbackTitle = sortedAnnotations
					.lazy
					.compactMap { titlesByArticleID[$0.articleID] }
					.first ?? NSLocalizedString("Untitled", comment: "Fallback article title")
				let heading = key.chapterTitle ?? fallbackTitle
				let rows = sortedAnnotations.map { Row(annotation: $0) }
				return AnnotationGroup(key: key, heading: heading, rows: rows)
			}
			.sorted { lhs, rhs in
				let lhsClusterRecency = clusterRecency[lhs.key.bookOrArticleID] ?? .distantPast
				let rhsClusterRecency = clusterRecency[rhs.key.bookOrArticleID] ?? .distantPast
				if lhsClusterRecency != rhsClusterRecency {
					return lhsClusterRecency > rhsClusterRecency
				}
				let lhsOrder = chapterSortOrder(lhs.key.chapterTitle)
				let rhsOrder = chapterSortOrder(rhs.key.chapterTitle)
				if lhsOrder != rhsOrder {
					return lhsOrder < rhsOrder
				}
				// Same cluster, same (unparseable-or-absent) chapter order --
				// stable tiebreaker so groups don't reshuffle from one
				// loadRows() call to the next.
				return lhs.heading < rhs.heading
			}

		isLoading = false
	}

	private func delete(_ annotation: Annotation) {
		for index in groups.indices {
			groups[index] = AnnotationGroup(
				key: groups[index].key,
				heading: groups[index].heading,
				rows: groups[index].rows.filter { $0.annotation.annotationID != annotation.annotationID }
			)
		}
		groups.removeAll { $0.rows.isEmpty }
		Task {
			await account.deleteAnnotation(annotationID: annotation.annotationID)
		}
	}
}

private struct AnnotationRow: View {

	let annotation: Annotation

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Circle()
				.fill(annotation.color.swiftUIColor)
				.frame(width: 12, height: 12)
				.padding(.top, 4)

			VStack(alignment: .leading, spacing: 4) {
				// No lineLimit here -- chapterTitle is now the section
				// header (AnnotationsListView.list), not a per-row caption,
				// so there's nothing else competing for space in this row;
				// truncating the one thing being shown just hides context
				// the row exists to provide.
				Text(sentenceContext)
					.font(.callout)
					.foregroundStyle(.primary)

				if let note = annotation.note, !note.isEmpty {
					Text(note)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				if annotation.orphanedAt != nil {
					Label(
						NSLocalizedString("Couldn't relocate this highlight", comment: "Annotation row: orphaned highlight caption"),
						systemImage: "exclamationmark.triangle"
					)
					.font(.caption2)
					.foregroundStyle(.orange)
				}
			}
		}
		.padding(.vertical, 4)
		// Dimmed, not hidden -- an orphaned annotation's note is still
		// real, saved user data (see markAnnotationOrphaned's doc comment
		// in WebViewController), so it stays visible and tappable (the
		// caller can still show the editor/article even if scrollToAnnotation
		// itself finds nothing to scroll to there).
		.opacity(annotation.orphanedAt != nil ? 0.5 : 1.0)
	}

	/// Collapses runs of whitespace (including the newlines/indentation
	/// annotations.js's buildTextIndex deliberately leaves untouched, since
	/// its offsets have to stay byte-exact against the source HTML for
	/// anchor resolution -- see docs/annotations.md's "Anchor resolution")
	/// down to a single space, for display only. Doesn't trim the ends,
	/// so quotePrefix/quoteExact/quoteSuffix still concatenate cleanly.
	private func normalizedForDisplay(_ string: String) -> String {
		string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
	}

	/// The full sentence surrounding the highlight, built from the stored
	/// quotePrefix/quoteExact/quoteSuffix selector (see docs/annotations.md)
	/// rather than just the raw quote -- gives the row real reading context
	/// instead of a mid-sentence fragment. Each of the three pieces is
	/// whitespace-normalized independently before concatenation (see
	/// normalizedForDisplay), then the quote's location within `combined`
	/// is found by direct search rather than by offsetting `prefix.count`
	/// Characters in: quotePrefix/quoteExact/quoteSuffix are three
	/// independently-sliced UTF-16 substrings on the JS side, and if a
	/// slice boundary lands mid-grapheme-cluster, decoding and
	/// re-concatenating them in Swift can merge or split a Character
	/// differently than the JS side counted it -- so a Character count
	/// carried over from one string doesn't reliably locate a position in
	/// the concatenation of a different pair of strings. Searching for the
	/// literal quote text sidesteps that: `combined` is built to contain
	/// `quote` by construction, so the search always succeeds. Search
	/// starts as close as possible to the expected position (still using
	/// prefix's length only as a starting *hint*, not as a trusted index)
	/// so that a quote which happens to recur inside quotePrefix doesn't
	/// win over the real occurrence.
	private var sentenceContext: AttributedString {
		let prefix = normalizedForDisplay(annotation.quotePrefix)
		let quote = normalizedForDisplay(annotation.quoteExact)
		let suffix = normalizedForDisplay(annotation.quoteSuffix)
		let combined = prefix + quote + suffix

		guard !combined.isEmpty, !quote.isEmpty else {
			return AttributedString(quote)
		}

		// A grapheme-boundary mismatch (see doc comment above) can only be
		// off by a character or two, never by prefix's whole length -- 8
		// characters of slack is generous cover for that while still
		// skipping past an earlier, unrelated recurrence of `quote` inside
		// a long quotePrefix.
		let searchHintOffset = max(0, prefix.count - 8)
		let searchStart = combined.index(combined.startIndex, offsetBy: searchHintOffset, limitedBy: combined.endIndex) ?? combined.startIndex
		let quoteRange = combined.range(of: quote, range: searchStart..<combined.endIndex) ?? combined.range(of: quote)
		guard let quoteRange else {
			return AttributedString(combined)
		}
		let quoteStart = quoteRange.lowerBound
		let quoteEnd = quoteRange.upperBound

		let tokenizer = NLTokenizer(unit: .sentence)
		tokenizer.string = combined
		var sentenceRange = combined.startIndex..<combined.endIndex
		tokenizer.enumerateTokens(in: combined.startIndex..<combined.endIndex) { range, _ in
			if range.contains(quoteStart) || range.lowerBound == quoteStart {
				sentenceRange = range
				return false
			}
			return true
		}

		let sentenceString = String(combined[sentenceRange])
		var attributed = AttributedString(sentenceString)

		let clippedStart = max(quoteStart, sentenceRange.lowerBound)
		let clippedEnd = min(quoteEnd, sentenceRange.upperBound)
		guard clippedStart < clippedEnd else {
			return attributed
		}

		// Re-base clippedStart/clippedEnd from `combined`-relative indices
		// onto `sentenceString`-relative indices (AttributedString.Index
		// lookup requires indices from the exact string the AttributedString
		// was initialized from, not from `combined`).
		let startDistance = combined.distance(from: sentenceRange.lowerBound, to: clippedStart)
		let endDistance = combined.distance(from: sentenceRange.lowerBound, to: clippedEnd)
		guard
			let localStart = sentenceString.index(sentenceString.startIndex, offsetBy: startDistance, limitedBy: sentenceString.endIndex),
			let localEnd = sentenceString.index(sentenceString.startIndex, offsetBy: endDistance, limitedBy: sentenceString.endIndex),
			let attrStart = AttributedString.Index(localStart, within: attributed),
			let attrEnd = AttributedString.Index(localEnd, within: attributed)
		else {
			return attributed
		}

		attributed[attrStart..<attrEnd].backgroundColor = annotation.color.swiftUIColor.opacity(0.3)
		return attributed
	}
}
