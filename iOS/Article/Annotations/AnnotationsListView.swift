//
//  AnnotationsListView.swift
//  NetNewsWire-iOS
//
//  Reachable two ways: from the reader's annotations toolbar menu
//  (ArticleViewController.annotationsMenu(), scoped to one chapter or one
//  book) and from Settings (unscoped, "everything I've ever highlighted").
//  One implementation either way -- the only difference between the three
//  entry points is which Account fetch method Scope.fetch(from:) below
//  calls, matching fetchAnnotations(forArticleID:)/fetchAnnotations(forBookKey:)/
//  fetchAllAnnotations() 1:1.
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
		case article(articleID: String)
		case book(bookKey: String)
		case everything

		var navigationTitle: String {
			switch self {
			case .article:
				return NSLocalizedString("This Chapter", comment: "Annotations list navigation title: single article")
			case .book:
				return NSLocalizedString("This Book", comment: "Annotations list navigation title: whole book")
			case .everything:
				return NSLocalizedString("All Highlights", comment: "Annotations list navigation title: everything")
			}
		}
	}

	let account: Account
	let scope: Scope

	/// Called when the person taps a row: navigate to (and, once there,
	/// flash) this annotation. The caller owns both the cross-article
	/// navigation and the same-article scroll -- see this file's header
	/// comment.
	var onNavigateToAnnotation: (Annotation) -> Void

	@State private var rows: [Row] = []
	@State private var isLoading = true
	@State private var pendingDeleteAnnotationID: String?

	private struct Row: Identifiable {
		let annotation: Annotation
		let articleTitle: String

		var id: String { annotation.annotationID }
	}

	var body: some View {
		Group {
			if isLoading {
				ProgressView()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if rows.isEmpty {
				emptyState
			} else {
				list
			}
		}
		.navigationTitle(Text(scope.navigationTitle))
		.navigationBarTitleDisplayMode(.inline)
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
			ForEach(rows) { row in
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
	}

	private func loadRows() async {
		isLoading = true

		let annotations: [Annotation]
		switch scope {
		case .article(let articleID):
			annotations = await account.fetchAnnotations(forArticleID: articleID)
		case .book(let bookKey):
			annotations = await account.fetchAnnotations(forBookKey: bookKey)
		case .everything:
			annotations = await account.fetchAllAnnotations()
		}

		guard !annotations.isEmpty else {
			rows = []
			isLoading = false
			return
		}

		// Titles are looked up once per unique articleID, not once per
		// annotation -- a chapter with several highlights would otherwise
		// fetch the same Article repeatedly.
		let articleIDs = Set(annotations.map(\.articleID))
		let articles = await account.fetchArticlesAsync(.articleIDs(articleIDs))
		let titlesByArticleID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0.title ?? NSLocalizedString("Untitled", comment: "Fallback article title")) })

		rows = annotations
			.sorted { $0.updatedAt > $1.updatedAt }
			.map { annotation in
				Row(annotation: annotation, articleTitle: titlesByArticleID[annotation.articleID] ?? NSLocalizedString("Untitled", comment: "Fallback article title"))
			}

		isLoading = false
	}

	private func delete(_ annotation: Annotation) {
		rows.removeAll { $0.annotation.annotationID == annotation.annotationID }
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
