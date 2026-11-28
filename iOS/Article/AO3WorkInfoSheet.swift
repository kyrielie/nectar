//
//  AO3WorkInfoSheet.swift
//  Nectar
//
//  Quick modal sheet presenting full AO3 metadata, stats, reading progress,
//  annotation count, series memberships, and quick actions from the reader.
//

import SwiftUI
import UIKit
import Articles
import Account
import AO3Kit
import RSParser

@MainActor
final class AO3WorkInfoViewModel: ObservableObject {

	@Published private(set) var article: Article
	@Published private(set) var annotationCount: Int?
	@Published var isCheckingUpdates = false
	@Published var isExportingEPUB = false
	@Published var statusMessage: String?

	nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

	init(article: Article) {
		self.article = article
		observeChapterFetches()
	}

	deinit {
		for token in observers {
			NotificationCenter.default.removeObserver(token)
		}
	}

	func loadSupplementaryState() async {
		guard let account = article.account else { return }
		let annotations = await account.fetchAnnotations(forBookKey: article.bookKey)
		annotationCount = annotations.count
	}

	var canCheckForUpdates: Bool {
		AO3FetchPolicy.canCheckForUpdates(for: article)
			&& AO3FetchPolicy.isNetworkRequestAllowed(for: article)
	}

	func checkForUpdates() {
		guard canCheckForUpdates, !isCheckingUpdates else { return }
		isCheckingUpdates = true
		statusMessage = nil
		if !AO3ChapterFetcher.shared.checkForUpdates(for: article) {
			isCheckingUpdates = false
			statusMessage = NSLocalizedString("Unable to start update check right now.", comment: "Work info update check fallback")
		}
	}

	func exportEPUB() async {
		guard !isExportingEPUB else { return }
		isExportingEPUB = true
		statusMessage = nil
		defer { isExportingEPUB = false }

		do {
			let epubURL = try await EPUB3Generator.generateEPUB(for: article, account: article.account)
			presentShareSheet(items: [epubURL])
		} catch {
			statusMessage = error.localizedDescription
		}
	}

	private func observeChapterFetches() {
		let completeToken = NotificationCenter.default.addObserver(
			forName: .ao3ChapterFetchDidComplete,
			object: nil,
			queue: .main
		) { [weak self] note in
			guard let articleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String else { return }
			Task { @MainActor [weak self] in
				guard let self, self.article.articleID == articleID else { return }
				self.isCheckingUpdates = false
				if let account = self.article.account,
				   let refreshed = await account.fetchArticlesAsync(.articleIDs([articleID])).first {
					self.article = refreshed
				}
				self.statusMessage = NSLocalizedString("Work metadata updated.", comment: "Work info update success")
			}
		}

		let failToken = NotificationCenter.default.addObserver(
			forName: .ao3ChapterFetchDidFail,
			object: nil,
			queue: .main
		) { [weak self] note in
			guard let articleID = note.userInfo?[AO3ChapterFetchUserInfoKey.articleID] as? String else { return }
			let message = note.userInfo?[AO3ChapterFetchUserInfoKey.message] as? String
			Task { @MainActor [weak self] in
				guard let self, self.article.articleID == articleID else { return }
				self.isCheckingUpdates = false
				self.statusMessage = message ?? NSLocalizedString("Update check failed.", comment: "Work info update failed")
			}
		}

		observers = [completeToken, failToken]
	}

	private func presentShareSheet(items: [Any]) {
		guard let presenter = Self.topMostViewController() else { return }
		let shareVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
		if let popover = shareVC.popoverPresentationController {
			popover.sourceView = presenter.view
			popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
			popover.permittedArrowDirections = []
		}
		presenter.present(shareVC, animated: true)
	}

	private static func topMostViewController() -> UIViewController? {
		let keyWindow = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }
		var top = keyWindow?.rootViewController
		while let presented = top?.presentedViewController {
			top = presented
		}
		return top
	}
}

struct AO3WorkInfoSheet: View {

	@StateObject private var model: AO3WorkInfoViewModel
	private weak var coordinator: SceneCoordinator?
	private let onOpenURL: (URL) -> Void
	@Environment(\.dismiss) private var dismiss

	init(article: Article, coordinator: SceneCoordinator?, onOpenURL: @escaping (URL) -> Void) {
		_model = StateObject(wrappedValue: AO3WorkInfoViewModel(article: article))
		self.coordinator = coordinator
		self.onOpenURL = onOpenURL
	}

	private var article: Article { model.article }

	private var isAO3Work: Bool {
		AO3Link.workID(fromBookKey: article.bookKey) != nil
			|| article.fandoms?.isEmpty == false
			|| article.ratings?.isEmpty == false
			|| article.wordCount != nil
	}

	var body: some View {
		NavigationStack {
			List {
				headerSection
				if let statusMessage = model.statusMessage {
					Section {
						Text(statusMessage)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				if isAO3Work {
					tagsSection
					statsAndProgressSection
					if let series = article.series, !series.isEmpty {
						seriesSection(series)
					}
					if let summaryText = cleanedSummary(article.summary), !summaryText.isEmpty {
						Section("Summary") {
							Text(summaryText)
								.font(.subheadline)
								.textSelection(.enabled)
						}
					}
				} else {
					nonAO3FallbackSection
				}
				actionsSection
			}
			.navigationTitle("Work Info")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task {
				await model.loadSupplementaryState()
			}
		}
	}

	private var headerSection: some View {
		Section {
			VStack(alignment: .leading, spacing: 8) {
				Text(article.title?.isEmpty == false ? article.title! : "Untitled Work")
					.font(.title3.weight(.semibold))
					.textSelection(.enabled)

				authorLinksView

				HStack(spacing: 8) {
					if let isComplete = article.isComplete {
						badge(isComplete ? "Complete" : "In Progress", color: isComplete ? .green : .orange)
					}
					if let current = article.chapterCurrent {
						let total = article.chapterTotal.map(String.init) ?? "?"
						badge("Ch. \(current)/\(total)", color: .secondary)
					}
					if let words = article.wordCount {
						badge("\(words.formatted()) words", color: .secondary)
					}
					if article.isRestricted == true {
						Label("Restricted", systemImage: "lock.fill")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
					}
				}
				.padding(.top, 2)

				if article.pendingUpdateContentHTML != nil {
					Label("Pending content update awaiting review", systemImage: "exclamationmark.triangle.fill")
						.font(.caption)
						.foregroundStyle(.orange)
				} else if article.ao3ConfirmedMissingAt != nil {
					Label("Marked missing on AO3", systemImage: "exclamationmark.circle.fill")
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
			.padding(.vertical, 4)
		}
	}

	@ViewBuilder
	private var authorLinksView: some View {
		let authors = Array(article.authors ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") }
		if authors.isEmpty {
			Text("Unknown Author")
				.font(.subheadline)
				.foregroundStyle(.secondary)
		} else {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 6) {
					Text("By")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					ForEach(authors, id: \.authorID) { author in
						let name = author.name ?? "Unknown"
						if let urlString = author.url, let url = URL(string: urlString) {
							Button(name) { onOpenURL(url) }
								.font(.subheadline.weight(.medium))
								.buttonStyle(.borderless)
						} else {
							Text(name)
								.font(.subheadline.weight(.medium))
						}
					}
				}
			}
		}
	}

	private var tagsSection: some View {
		Section("Tags & Metadata") {
			if let ratings = article.ratings, !ratings.isEmpty {
				tagRow(label: "Rating", tags: ratings)
			}
			if let warnings = article.warnings, !warnings.isEmpty {
				tagRow(label: "Archive Warnings", tags: warnings)
			}
			if let categories = article.categories, !categories.isEmpty {
				tagRow(label: "Category", tags: categories)
			}
			if let fandoms = article.fandoms, !fandoms.isEmpty {
				tagRow(label: "Fandoms", tags: fandoms)
			}
			if let relationships = article.relationships, !relationships.isEmpty {
				tagRow(label: "Relationships", tags: relationships)
			}
			if let characters = article.characters, !characters.isEmpty {
				tagRow(label: "Characters", tags: characters)
			}
			if let additionalTags = article.additionalTags, !additionalTags.isEmpty {
				tagRow(label: "Additional Tags", tags: additionalTags)
			}
			if let language = article.language, !language.isEmpty {
				LabeledContent("Language", value: language)
			}
			if let collections = article.collections, !collections.isEmpty {
				collectionRow(collections)
			}
		}
	}

	private var statsAndProgressSection: some View {
		Section("Stats & Reading State") {
			if let kudos = article.kudosCount {
				LabeledContent("Kudos", value: kudos.formatted())
			}
			if let comments = article.commentCount {
				LabeledContent("Comments", value: comments.formatted())
			}
			if let bookmarks = article.bookmarkCount {
				LabeledContent("Bookmarks", value: bookmarks.formatted())
			}
			if let hits = article.hitCount {
				LabeledContent("Hits", value: hits.formatted())
			}
			if let progress = article.status.readingProgress {
				LabeledContent("Reading Progress", value: "\(Int((progress * 100).rounded()))%")
			}
			if let annotations = model.annotationCount {
				LabeledContent("Annotations", value: annotations.formatted())
			}
			if let lastOpened = article.status.lastOpenedAt {
				LabeledContent("Last Opened", value: lastOpened.formatted(date: .abbreviated, time: .shortened))
			}
			if let lastFetched = article.lastPrefaceFetchDate {
				LabeledContent("Last Fetched", value: lastFetched.formatted(date: .abbreviated, time: .shortened))
			} else if let modified = article.dateModified {
				LabeledContent("Updated", value: modified.formatted(date: .abbreviated, time: .omitted))
			}
		}
	}

	private var nonAO3FallbackSection: some View {
		Section("Details") {
			if let feedName = article.feed?.nameForDisplay {
				LabeledContent("Source", value: feedName)
			}
			if let published = article.datePublished {
				LabeledContent("Published", value: published.formatted(date: .abbreviated, time: .shortened))
			}
			if let progress = article.status.readingProgress {
				LabeledContent("Reading Progress", value: "\(Int((progress * 100).rounded()))%")
			}
			if let annotations = model.annotationCount {
				LabeledContent("Annotations", value: annotations.formatted())
			}
			if let summaryText = cleanedSummary(article.summary), !summaryText.isEmpty {
				Text(summaryText)
					.font(.subheadline)
					.textSelection(.enabled)
			}
		}
	}

	private func seriesSection(_ entries: [ArticleSeriesEntry]) -> some View {
		Section("Series") {
			ForEach(entries, id: \.self) { entry in
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text(entry.name)
							.font(.subheadline.weight(.medium))
						Text("Part \(entry.index)")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					Spacer()
					Button("View Series") {
						let currentArticle = article
						let activeCoordinator = coordinator
						dismiss()
						Task { @MainActor in
							await activeCoordinator?.openAO3SeriesTimeline(for: entry, article: currentArticle)
						}
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
			}
		}
	}

	private var actionsSection: some View {
		Section("Actions") {
			if model.canCheckForUpdates {
				Button {
					model.checkForUpdates()
				} label: {
					HStack {
						Label("Check for Updates", systemImage: "arrow.clockwise")
						Spacer()
						if model.isCheckingUpdates {
							ProgressView()
						}
					}
				}
				.disabled(model.isCheckingUpdates)
			}

			Button {
				Task { await model.exportEPUB() }
			} label: {
				HStack {
					Label("Export as EPUB", systemImage: "book.pages")
					Spacer()
					if model.isExportingEPUB {
						ProgressView()
					}
				}
			}
			.disabled(model.isExportingEPUB)

			if let url = article.preferredURL {
				Button {
					onOpenURL(url)
				} label: {
					Label(AO3Link.isAO3Host(url) ? "Open on AO3" : "Open in Browser", systemImage: "safari")
				}
			}
		}
	}

	private func tagRow(label: String, tags: [String]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(label)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 6) {
					ForEach(tags, id: \.self) { tag in
						Button(tag) {
							if let url = AO3Link.tagURL(for: tag) {
								onOpenURL(url)
							}
						}
						.font(.caption)
						.buttonStyle(.bordered)
						.controlSize(.mini)
					}
				}
			}
		}
		.padding(.vertical, 2)
	}

	private func collectionRow(_ entries: [ArticleCollectionEntry]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Collections")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 6) {
					ForEach(entries, id: \.self) { entry in
						if let slug = entry.slug, let url = AO3Link.collectionURL(slug: slug) {
							Button(entry.name) { onOpenURL(url) }
								.font(.caption)
								.buttonStyle(.bordered)
								.controlSize(.mini)
						} else {
							Text(entry.name)
								.font(.caption)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
						}
					}
				}
			}
		}
		.padding(.vertical, 2)
	}

	private func badge(_ text: String, color: Color) -> some View {
		Text(text)
			.font(.caption.weight(.medium))
			.padding(.horizontal, 8)
			.padding(.vertical, 3)
			.background(color.opacity(0.15), in: Capsule())
			.foregroundStyle(color)
	}

	private func cleanedSummary(_ html: String?) -> String? {
		guard let html, !html.isEmpty else { return nil }
		return html
			.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension ArticleSeriesEntry: @retroactive Identifiable {
	public var id: String { "\(ao3ID ?? name)-\(index)" }
}
