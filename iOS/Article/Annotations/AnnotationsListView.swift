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
//  Tapping a row has two cases: if the row's article is the one already
//  open behind this screen, this view can't scroll the live webview
//  itself (it has no reference to WebViewController), so it hands back
//  via onNavigateToAnnotation and lets the presenter (ArticleViewController)
//  decide whether that's a same-article scrollToAnnotation call or a
//  cross-article SceneCoordinator.selectArticleDirectly navigation
//  followed by one.
//

import SwiftUI
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

	private struct Row: Identifiable {
		let annotation: Annotation
		let articleTitle: String

		var id: String { annotation.annotationID }
	}

	/// One section per article/chapter, in the same shape
	/// TableOfContentsViewController.chaptersByBook groups an anthology's
	/// chapters under each book heading -- here every row sharing an
	/// articleID becomes one section, headed by that article's title.
	private struct AnnotationGroup: Identifiable {
		let articleID: String
		let articleTitle: String
		let rows: [Row]

		var id: String { articleID }
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
						rows(for: group)
					} header: {
						Text(group.articleTitle)
					}
				} else {
					// A single group's header would just repeat the
					// navigation title (the common non-anthology case,
					// where there's only ever one chapter) -- omit it
					// rather than show a redundant heading.
					Section {
						rows(for: group)
					}
				}
			}
		}
	}

	@ViewBuilder
	private func rows(for group: AnnotationGroup) -> some View {
		ForEach(group.rows) { row in
			Button {
				onNavigateToAnnotation(row.annotation)
			} label: {
				AnnotationRow(annotation: row.annotation, articleTitle: row.articleTitle)
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

		// Grouped by articleID (chapter order isn't derivable from the
		// annotations table alone -- see loadRows' Account.fetchAnnotations
		// callers -- so groups are ordered by each group's most recently
		// updated annotation, same recency-first ordering the old flat
		// list used).
		let rowsByArticleID = Dictionary(grouping: annotations, by: \.articleID)
		groups = rowsByArticleID
			.map { articleID, articleAnnotations -> AnnotationGroup in
				let articleTitle = titlesByArticleID[articleID] ?? NSLocalizedString("Untitled", comment: "Fallback article title")
				let rows = articleAnnotations
					.sorted { $0.updatedAt > $1.updatedAt }
					.map { Row(annotation: $0, articleTitle: articleTitle) }
				return AnnotationGroup(articleID: articleID, articleTitle: articleTitle, rows: rows)
			}
			.sorted { lhs, rhs in
				let lhsLatest = lhs.rows.first?.annotation.updatedAt ?? .distantPast
				let rhsLatest = rhs.rows.first?.annotation.updatedAt ?? .distantPast
				return lhsLatest > rhsLatest
			}

		isLoading = false
	}

	private func delete(_ annotation: Annotation) {
		for index in groups.indices {
			groups[index] = AnnotationGroup(
				articleID: groups[index].articleID,
				articleTitle: groups[index].articleTitle,
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
	let articleTitle: String

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Circle()
				.fill(annotation.color.swiftUIColor)
				.frame(width: 12, height: 12)
				.padding(.top, 4)

			VStack(alignment: .leading, spacing: 4) {
				Text(truncatedQuote)
					.font(.callout)
					.foregroundStyle(.primary)
					.lineLimit(2)

				if let note = annotation.note, !note.isEmpty {
					Text(note)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				HStack(spacing: 4) {
					Text(articleTitle)
					Text("·")
					Text(annotation.updatedAt, style: .relative)
				}
				.font(.caption2)
				.foregroundStyle(.tertiary)

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

	private var truncatedQuote: String {
		let quote = annotation.quoteExact
		guard quote.count > 120 else { return quote }
		return String(quote.prefix(120)) + "…"
	}
}
