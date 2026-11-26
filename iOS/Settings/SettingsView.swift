//
//  SettingsView.swift
//  NetNewsWire-iOS
//
//  Root SwiftUI Settings shell replacing `SettingsViewController` and `Settings.storyboard`.
//

import SwiftUI
import UIKit
import Account
import ActivityLog
import Articles
import BackupRestore

enum SettingsDestination: Hashable {
	case ao3Account
	case ao3WorksNeedingAttention
	case ao3IgnoreList
	case timelineLayout
	case articleTheme
	case toolbars
	case fullScreenReading
	case annotations
	case textReplacement
	case readingTime
	case readingStats
	case colorPalette
	case accentColor
	case errorLog
	case activityLog
	case accountStats
	case dinosaurs
	case manageStorage
	case about
}

final class SettingsHostingController: UIHostingController<AnyView> {}

@MainActor final class SettingsActionCoordinator: ObservableObject {

	enum AccountExportKind {
		case opml
		case articlesCSV
		case articlesSQLite
		case annotationsCSV
	}

	weak var hostingController: UIViewController?
	weak var presentingParentController: UIViewController?

	@Published var isTransferFormatDialogPresented = false
	@Published var isExportArticlesFormatDialogPresented = false
	@Published var accountPickerKind: AccountExportKind?
	@Published var errorAlert: (title: String, message: String)?

	private var pendingArticlesAccount: Account?

	init(presentingParentController: UIViewController?) {
		self.presentingParentController = presentingParentController
	}

	var currentWorkForTextReplacementOverride: (bookKey: String, title: String)? {
		guard let rootSplit = presentingParentController as? RootSplitViewController,
			  let article = rootSplit.coordinator.currentArticleViewController?.article else {
			return nil
		}
		return (bookKey: article.bookKey, title: article.title ?? "")
	}

	func importOPML() {
		guard let host = hostingController else { return }
		OPMLImportCoordinator.begin(presentingController: host, sourceView: host.view, sourceRect: host.view.bounds)
	}

	func beginExportOPML() {
		let accounts = AccountManager.shared.sortedAccounts
		if accounts.count == 1, let first = accounts.first {
			exportOPMLDocumentPicker(for: first)
		} else {
			accountPickerKind = .opml
		}
	}

	func beginExportArticles() {
		let accounts = AccountManager.shared.sortedAccounts
		if accounts.count == 1, let first = accounts.first {
			pendingArticlesAccount = first
			isExportArticlesFormatDialogPresented = true
		} else {
			accountPickerKind = .articlesCSV
		}
	}

	func beginExportAnnotationsCSV() {
		let accounts = AccountManager.shared.sortedAccounts
		if accounts.count == 1, let first = accounts.first {
			exportAnnotationsCSVDocumentPicker(for: first)
		} else {
			accountPickerKind = .annotationsCSV
		}
	}

	func beginExportAnnotationsSQLite() {
		let accounts = AccountManager.shared.sortedAccounts
		if accounts.count == 1, let first = accounts.first {
			exportArticlesSQLiteDocumentPicker(for: first)
		} else {
			accountPickerKind = .articlesSQLite
		}
	}

	func handleAccountSelected(_ account: Account, for kind: AccountExportKind) {
		switch kind {
		case .opml:
			exportOPMLDocumentPicker(for: account)
		case .articlesCSV:
			pendingArticlesAccount = account
			isExportArticlesFormatDialogPresented = true
		case .articlesSQLite:
			exportArticlesSQLiteDocumentPicker(for: account)
		case .annotationsCSV:
			exportAnnotationsCSVDocumentPicker(for: account)
		}
	}

	func exportPendingArticlesCSV() {
		guard let account = pendingArticlesAccount else { return }
		exportArticlesCSVDocumentPicker(for: account)
	}

	func exportPendingArticlesSQLite() {
		guard let account = pendingArticlesAccount else { return }
		exportArticlesSQLiteDocumentPicker(for: account)
	}

	func exportBackup() {
		let includeSettings = AppDefaults.backupEligibleKeys.contains { AppDefaults.store.object(forKey: $0) != nil }
		do {
			let zipURL = try ActivityLog.shared.logActivity(owner: .app, kind: .exportBackup) {
				try BackupManager.exportBackup(includeSettings: includeSettings)
			}
			presentDocumentPicker(for: zipURL)
		} catch {
			errorAlert = (title: "Backup Error", message: error.localizedDescription)
		}
	}

	func restoreBackup() {
		guard let host = hostingController else { return }
		BackupRestoreCoordinator.begin(presentingController: host, sourceView: host.view, sourceRect: host.view.bounds)
	}

	func presentGuide() {
		guard let host = hostingController else { return }
		let guideHosting = UIHostingController(rootView: GuideOverlayView())
		guideHosting.modalPresentationStyle = .overFullScreen
		guideHosting.view.backgroundColor = .clear
		host.present(guideHosting, animated: true)
	}

	func dismissAndDiscloseDinosaur(_ dinosaur: DinosaurRow) {
		guard let host = hostingController else { return }
		host.dismiss(animated: true) { [weak presentingParentController] in
			if let rootSplit = presentingParentController as? RootSplitViewController {
				rootSplit.coordinator.discloseFeed(dinosaur.feed, animations: [.scroll, .navigation])
			}
		}
	}

	func openArticleFromSettings(articleID: String, accountID: String) {
		guard let host = hostingController,
			  let rootSplit = presentingParentController as? RootSplitViewController,
			  let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			return
		}
		let coordinator = rootSplit.coordinator
		host.dismiss(animated: true) {
			Task {
				await coordinator?.selectArticleDirectly(articleID, account: account)
			}
		}
	}

	func navigateToAnnotationFromSettings(_ annotation: Annotation, account: Account) {
		guard let host = hostingController,
			  let rootSplit = presentingParentController as? RootSplitViewController else {
			return
		}
		let coordinator = rootSplit.coordinator
		host.dismiss(animated: true) {
			Task {
				await coordinator?.selectArticleDirectly(annotation.articleID, account: account)
				coordinator?.currentArticleViewController?.navigateToAnnotation(annotation, account: account)
			}
		}
	}

	private func exportOPMLDocumentPicker(for account: Account) {
		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Subscriptions-\(accountName).opml"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		do {
			try account.logActivity(kind: .exportOPML, detail: filename) {
				let opmlString = OPMLExporter.OPMLString(with: account, title: filename)
				try opmlString.write(to: tempFile, atomically: true, encoding: .utf8)
			}
		} catch {
			errorAlert = (title: "OPML Export Error", message: error.localizedDescription)
			return
		}
		presentDocumentPicker(for: tempFile)
	}

	private func exportArticlesCSVDocumentPicker(for account: Account) {
		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Articles-\(accountName).csv"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		do {
			let articles = account.flattenedFeeds().reduce(into: Set<Article>()) { result, feed in
				result.formUnion(feed.fetchArticles())
			}
			let csvString = ArticleCSVExporter.CSVString(with: Array(articles))
			try csvString.write(to: tempFile, atomically: true, encoding: .utf8)
		} catch {
			errorAlert = (title: "CSV Export Error", message: error.localizedDescription)
			return
		}
		presentDocumentPicker(for: tempFile)
	}

	private func exportArticlesSQLiteDocumentPicker(for account: Account) {
		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Articles-\(accountName).sqlite"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
		try? FileManager.default.removeItem(at: tempFile)
		do {
			try account.exportArticlesSQLite(feedIDs: nil, toPath: tempFile.path)
		} catch {
			errorAlert = (title: "SQLite Export Error", message: error.localizedDescription)
			return
		}
		presentDocumentPicker(for: tempFile)
	}

	private func exportAnnotationsCSVDocumentPicker(for account: Account) {
		let accountName = account.nameForDisplay.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
		let filename = "Highlights-\(accountName).csv"
		let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

		Task {
			let annotations = await account.fetchAllAnnotations()
			let articleIDs = Set(annotations.map(\.articleID))
			let articles = await account.fetchArticlesAsync(.articleIDs(articleIDs))
			let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0) })
			let rows = annotations.map { ($0, articlesByID[$0.articleID]) }

			do {
				let csvString = AnnotationCSVExporter.CSVString(with: rows)
				try csvString.write(to: tempFile, atomically: true, encoding: .utf8)
			} catch {
				errorAlert = (title: "CSV Export Error", message: error.localizedDescription)
				return
			}
			presentDocumentPicker(for: tempFile)
		}
	}

	private func presentDocumentPicker(for url: URL) {
		guard let host = hostingController else { return }
		let docPicker = UIDocumentPickerViewController(forExporting: [url])
		docPicker.modalPresentationStyle = .formSheet
		host.present(docPicker, animated: true)
	}
}

struct SettingsView: View {

	static func makeHostingController(presentingParentController: UIViewController?, scrollToArticlesSection: Bool = false) -> SettingsHostingController {
		let actions = SettingsActionCoordinator(presentingParentController: presentingParentController)
		let model = SettingsModel()
		let hostingController = SettingsHostingController(rootView: AnyView(EmptyView()))
		actions.hostingController = hostingController
		let observer = SurfacePaletteObserver(traitCollection: hostingController.traitCollection)
		let rootView = SettingsView(
			model: model,
			actions: actions,
			scrollToArticlesSection: scrollToArticlesSection,
			onDismiss: { [weak hostingController] in
				hostingController?.dismiss(animated: true)
			}
		)
		.surfacePaletteAware(observer: observer)
		hostingController.rootView = AnyView(rootView)
		hostingController.modalPresentationStyle = .formSheet
		hostingController.observeTraits([.userInterfaceStyle]) { (vc: SettingsHostingController, previous: UITraitCollection) in
			guard vc.traitCollection.userInterfaceStyle != previous.userInterfaceStyle else { return }
			observer.refresh(for: vc.traitCollection)
		}
		return hostingController
	}

	@ObservedObject var model: SettingsModel
	@ObservedObject var actions: SettingsActionCoordinator
	let scrollToArticlesSection: Bool
	let onDismiss: () -> Void

	@Environment(\.surfacePaletteObserver) private var paletteObserver
	@State private var path: [SettingsDestination] = []
	@State private var didScrollToArticles = false
	@State private var searchText = ""

	var body: some View {
		NavigationStack(path: $path) {
			ScrollViewReader { proxy in
				List {
					Group {
						if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
							timelineSection
							readingActivitySection
							readerSection
								.id("articles")
							appearanceSection
							ao3Section
							storageAndBackupSection
							importExportSection
							troubleshootingSection
							helpSection
							buildFooterSection
						} else {
							searchResultsSection
						}
					}
					.surfacePaletteRowBackground()
				}
				.listStyle(.insetGrouped)
				.surfacePaletteListBackground()
				.searchable(text: $searchText, prompt: Text("Search Settings", comment: "Search Settings prompt"))
				.overlay {
					if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
					   SettingsSearchIndex.results(for: searchText).isEmpty {
						EmptyStateView.search(text: searchText)
					}
				}
				.navigationTitle(Text("Settings", comment: "Settings navigation title"))
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						doneButton
					}
				}
				.onAppear {
					model.refresh()
					if scrollToArticlesSection && !didScrollToArticles {
						didScrollToArticles = true
						proxy.scrollTo("articles", anchor: .top)
					}
				}
			}
			.navigationDestination(for: SettingsDestination.self) { destination in
				destinationView(for: destination)
			}
			.confirmationDialog(
				NSLocalizedString("Transfer Format", comment: "Feed transfer format picker title"),
				isPresented: $actions.isTransferFormatDialogPresented,
				titleVisibility: .visible
			) {
				Button(NSLocalizedString("JSON", comment: "Feed transfer format")) {
					model.feedTransferFormat = .json
				}
				Button(NSLocalizedString("SQLite", comment: "Feed transfer format")) {
					model.feedTransferFormat = .sqlite
				}
				Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
			} message: {
				Text("Affects only Ambrosia-paired shelves. Most shelves are unaffected.", comment: "Feed transfer format picker explanation")
			}
			.confirmationDialog(
				NSLocalizedString("Choose an export format", comment: "Export Format"),
				isPresented: $actions.isExportArticlesFormatDialogPresented,
				titleVisibility: .visible
			) {
				Button(NSLocalizedString("CSV", comment: "Export format")) {
					actions.exportPendingArticlesCSV()
				}
				Button(NSLocalizedString("SQLite", comment: "Export format")) {
					actions.exportPendingArticlesSQLite()
				}
				Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
			}
			.confirmationDialog(
				NSLocalizedString("Choose an account to export", comment: "Export Account"),
				isPresented: Binding(
					get: { actions.accountPickerKind != nil },
					set: { if !$0 { actions.accountPickerKind = nil } }
				),
				titleVisibility: .visible
			) {
				if let kind = actions.accountPickerKind {
					ForEach(AccountManager.shared.sortedAccounts, id: \.accountID) { account in
						Button(account.nameForDisplay) {
							actions.accountPickerKind = nil
							actions.handleAccountSelected(account, for: kind)
						}
					}
				}
				Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
					actions.accountPickerKind = nil
				}
			}
			.alert(
				actions.errorAlert?.title ?? "",
				isPresented: Binding(
					get: { actions.errorAlert != nil },
					set: { if !$0 { actions.errorAlert = nil } }
				)
			) {
				Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
			} message: {
				Text(actions.errorAlert?.message ?? "")
			}
		}
	}

	// MARK: - Sections

	@ViewBuilder
	private var doneButton: some View {
		if #available(iOS 26, *) {
			Button(NSLocalizedString("Done", comment: "Done button"), systemImage: "checkmark") {
				onDismiss()
			}
		} else {
			Button(NSLocalizedString("Done", comment: "Done button")) {
				onDismiss()
			}
		}
	}

	private var searchResultsSection: some View {
		let results = SettingsSearchIndex.results(for: searchText)
		return Section {
			ForEach(results) { item in
				NavigationLink(value: item.destination) {
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text(item.title)
								.foregroundStyle(.primary)
							HStack(spacing: 4) {
								ForEach(Array(item.breadcrumb.enumerated()), id: \.offset) { index, crumb in
									if index > 0 {
										Image(systemName: "arrow.forward")
											.font(.caption2)
									}
									Text(crumb)
								}
							}
							.font(.footnote)
							.foregroundStyle(.secondary)
						}
					} icon: {
						SettingsIconBadge(systemImage: item.systemImage, color: item.badgeColor)
					}
				}
			}
		}
	}

	private var ao3Section: some View {
		Section {
			NavigationLink(value: SettingsDestination.ao3Account) {
				LabeledContent {
					Text(model.ao3StatusText)
						.foregroundStyle(model.ao3HasSessionEnded || model.ao3HasActiveRateLimit ? Color.orange : Color.secondary)
				} label: {
					Label {
						Text(NSLocalizedString("Archive of Our Own Account", comment: "AO3 account row"))
					} icon: {
						SettingsIconBadge(systemImage: "person.crop.circle.fill", color: .red)
					}
				}
			}
		} header: {
			Text("Archive of Our Own", comment: "AO3 section header")
		}
	}

	private var importExportSection: some View {
		Section {
			Button {
				actions.importOPML()
			} label: {
				Label {
					Text("Import OPML File", comment: "Import OPML File")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "square.and.arrow.down.fill", color: .blue)
				}
			}

			Button {
				actions.beginExportOPML()
			} label: {
				Label {
					Text("Export OPML File", comment: "Export OPML File")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "square.and.arrow.up.fill", color: .teal)
				}
			}

			Button {
				actions.beginExportArticles()
			} label: {
				Label {
					Text("Export Library", comment: "Export Library")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "tray.and.arrow.up.fill", color: .indigo)
				}
			}

			Button {
				actions.isTransferFormatDialogPresented = true
			} label: {
				LabeledContent {
					Text(model.feedTransferFormatText)
						.foregroundStyle(.secondary)
				} label: {
					Label {
						Text(NSLocalizedString("Transfer Format", comment: "Transfer Format"))
							.foregroundStyle(.primary)
					} icon: {
						SettingsIconBadge(systemImage: "arrow.left.arrow.right", color: .purple)
					}
				}
			}
		} header: {
			Text("Import & Export", comment: "Import & Export section header")
		}
	}

	private var timelineSection: some View {
		Section {
			Picker(selection: $model.timelineSortField) {
				ForEach(ArticleSorter.SortField.allCases, id: \.self) { field in
					Text(field.displayName).tag(field)
				}
			} label: {
				Label {
					Text(NSLocalizedString("Sort By", comment: "Sort By"))
				} icon: {
					SettingsIconBadge(systemImage: "arrow.up.arrow.down", color: .blue)
				}
			}

			Picker(selection: $model.timelineSortDirection) {
				ForEach(model.sortDirectionOptions, id: \.direction) { option in
					Text(option.label).tag(option.direction)
				}
			} label: {
				Label {
					Text(NSLocalizedString("Order", comment: "Order"))
				} icon: {
					SettingsIconBadge(systemImage: "line.3.horizontal.decrease", color: .cyan)
				}
			}

			NavigationLink(value: SettingsDestination.timelineLayout) {
				Label {
					Text("Timeline Layout", comment: "Timeline Layout")
				} icon: {
					SettingsIconBadge(systemImage: "list.bullet.rectangle.fill", color: .indigo)
				}
			}

			Toggle(isOn: $model.showLastUpdatedLabel) {
				Label {
					Text(NSLocalizedString("Show Last Updated Label", comment: "Show Last Updated Label"))
				} icon: {
					SettingsIconBadge(systemImage: "clock.fill", color: .teal)
				}
			}
		} header: {
			Text("Timeline", comment: "Timeline section header")
		}
	}

	private var readingActivitySection: some View {
		Section {
			NavigationLink(value: SettingsDestination.readingTime) {
				Label {
					Text("Reading Time", comment: "Reading Time")
				} icon: {
					SettingsIconBadge(systemImage: "hourglass", color: .cyan)
				}
			}
			NavigationLink(value: SettingsDestination.readingStats) {
				Label {
					Text("Reading Stats", comment: "Reading Stats")
				} icon: {
					SettingsIconBadge(systemImage: "chart.bar.fill", color: .indigo)
				}
			}
			NavigationLink(value: SettingsDestination.annotations) {
				Label {
					Text("Highlights & Notes", comment: "Highlights & Notes")
				} icon: {
					SettingsIconBadge(systemImage: "highlighter", color: .orange)
				}
			}
		} header: {
			Text("Reading Activity", comment: "Reading Activity section header")
		}
	}

	private var readerSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.articleTheme) {
				LabeledContent {
					Text(model.currentThemeName)
						.foregroundStyle(.secondary)
				} label: {
					Label {
						Text(NSLocalizedString("Theme", comment: "Theme"))
					} icon: {
						SettingsIconBadge(systemImage: "doc.richtext.fill", color: .purple)
					}
				}
			}

			NavigationLink(value: SettingsDestination.toolbars) {
				Label {
					Text("Toolbars", comment: "Toolbars")
				} icon: {
					SettingsIconBadge(systemImage: "menubar.rectangle", color: .indigo)
				}
			}
			NavigationLink(value: SettingsDestination.fullScreenReading) {
				Label {
					Text("Full Screen Reading", comment: "Full Screen Reading")
				} icon: {
					SettingsIconBadge(systemImage: "arrow.up.left.and.arrow.down.right", color: .green)
				}
			}
			NavigationLink(value: SettingsDestination.textReplacement) {
				Label {
					Text("Text Replacement", comment: "Text Replacement")
				} icon: {
					SettingsIconBadge(systemImage: "textformat.abc", color: .pink)
				}
			}

			Toggle(isOn: $model.openLinksInNectar) {
				Label {
					Text(NSLocalizedString("Open Links in Nectar", comment: "Open Links in Nectar"))
				} icon: {
					SettingsIconBadge(systemImage: "safari.fill", color: .blue)
				}
			}

			Toggle(isOn: $model.disableArticleLinks) {
				Label {
					Text(NSLocalizedString("Disable Links in Works", comment: "Disable Links in Works"))
				} icon: {
					SettingsIconBadge(systemImage: "link.badge.plus", color: .red)
				}
			}

			Toggle(isOn: $model.showFeedNameInReaderView) {
				Label {
					Text(NSLocalizedString("Show Shelf Name in Reader View", comment: "Show Shelf Name in Reader View"))
				} icon: {
					SettingsIconBadge(systemImage: "tag.fill", color: .teal)
				}
			}
		} header: {
			Text("Reader", comment: "Reader section header")
		}
	}

	private var appearanceSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.colorPalette) {
				LabeledContent {
					Text(model.colorPaletteDescription)
						.foregroundStyle(.secondary)
				} label: {
					Label {
						Text(NSLocalizedString("Color Palette", comment: "Color Palette"))
					} icon: {
						SettingsIconBadge(systemImage: "paintpalette.fill", color: .pink)
					}
				}
			}
			NavigationLink(value: SettingsDestination.accentColor) {
				LabeledContent {
					Text(model.accentColorDescription)
						.foregroundStyle(.secondary)
				} label: {
					Label {
						Text(NSLocalizedString("Accent Color", comment: "Accent Color"))
					} icon: {
						SettingsIconBadge(systemImage: "drop.halffull", color: .blue)
					}
				}
			}
		} header: {
			Text("Appearance", comment: "Appearance section header")
		}
	}

	private var troubleshootingSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.errorLog) {
				Label {
					Text("Error Log", comment: "Error Log")
				} icon: {
					SettingsIconBadge(systemImage: "exclamationmark.bubble.fill", color: .red)
				}
			}
			NavigationLink(value: SettingsDestination.activityLog) {
				Label {
					Text("Activity Log", comment: "Activity Log")
				} icon: {
					SettingsIconBadge(systemImage: "clock.arrow.circlepath", color: .orange)
				}
			}
			NavigationLink(value: SettingsDestination.accountStats) {
				Label {
					Text("Library Stats", comment: "Library Stats")
				} icon: {
					SettingsIconBadge(systemImage: "internaldrive.fill", color: .gray)
				}
			}
			NavigationLink(value: SettingsDestination.dinosaurs) {
				Label {
					Text("Dinosaurs", comment: "Dinosaurs")
				} icon: {
					SettingsIconBadge(systemImage: "fossil.shell.fill", color: .green)
				}
			}
		} header: {
			Text("Troubleshooting", comment: "Troubleshooting section header")
		}
	}

	private var helpSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.about) {
				Label {
					Text("About Nectar", comment: "About Nectar")
				} icon: {
					SettingsIconBadge(systemImage: "info.circle.fill", color: .gray)
				}
			}
			Button {
				actions.presentGuide()
			} label: {
				Label {
					Text("Guide", comment: "Guide")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "book.fill", color: .blue)
				}
			}
		} header: {
			Text("Help", comment: "Help section header")
		}
	}

	private var storageAndBackupSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.manageStorage) {
				Label {
					Text("Manage Storage", comment: "Manage Storage")
				} icon: {
					SettingsIconBadge(systemImage: "externaldrive.fill.badge.minus", color: .gray)
				}
			}
			Button {
				actions.exportBackup()
			} label: {
				Label {
					Text("Backup", comment: "Backup")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "externaldrive.fill.badge.plus", color: .blue)
				}
			}
			Button {
				actions.restoreBackup()
			} label: {
				Label {
					Text("Restore from Backup…", comment: "Restore from Backup…")
						.foregroundStyle(.primary)
				} icon: {
					SettingsIconBadge(systemImage: "arrow.counterclockwise", color: .green)
				}
			}
		} header: {
			Text("Storage & Backup", comment: "Storage & Backup section header")
		}
	}

	private var buildFooterSection: some View {
		Section {
		} footer: {
			Text(model.buildVersionText)
				.font(.caption2)
				.foregroundStyle(.secondary)
				.textSelection(.enabled)
		}
	}

	// MARK: - Destinations

	@ViewBuilder
	private func destinationView(for destination: SettingsDestination) -> some View {
		switch destination {
		case .ao3Account:
			AO3AccountSettingsView(
				onShowWorksNeedingAttention: { path.append(.ao3WorksNeedingAttention) },
				onShowIgnoreList: { path.append(.ao3IgnoreList) }
			)
		case .ao3WorksNeedingAttention:
			AO3WorksNeedingAttentionView(onReviewUpdate: { accountID, articleID in
				actions.openArticleFromSettings(articleID: articleID, accountID: accountID)
			})
		case .ao3IgnoreList:
			AO3IgnoreListView()
		case .timelineLayout:
			TimelineCustomizerView()
		case .articleTheme:
			ArticleThemeListView()
		case .toolbars:
			ToolbarsSettingsView()
		case .fullScreenReading:
			FullScreenReadingView()
		case .annotations:
			AnnotationsSettingsView(
				onExportCSV: { _, _ in actions.beginExportAnnotationsCSV() },
				onExportSQLite: { _, _ in actions.beginExportAnnotationsSQLite() },
				onNavigateToAnnotation: { annotation, account in
					actions.navigateToAnnotationFromSettings(annotation, account: account)
				}
			)
		case .textReplacement:
			TextReplacementSettingsView(
				onNavigateToAnnotation: { annotation, account in
					actions.navigateToAnnotationFromSettings(annotation, account: account)
				},
				currentWork: actions.currentWorkForTextReplacementOverride
			)
		case .readingTime:
			ReadingTimeSettingsView()
		case .readingStats:
			ReadingStatsView()
		case .colorPalette:
			ColorPaletteSettingsView()
		case .accentColor:
			AccentColorSettingsView()
		case .errorLog:
			ErrorLogView()
		case .activityLog:
			ActivityLogView()
		case .accountStats:
			AccountStatsView()
		case .dinosaurs:
			DinosaursView(dismissAndPresent: { dinosaur in
				actions.dismissAndDiscloseDinosaur(dinosaur)
			})
		case .manageStorage:
			ManageStorageRepresentable()
				.navigationTitle(Text("Manage Storage", comment: "Manage Storage"))
				.navigationBarTitleDisplayMode(.inline)
		case .about:
			AboutView()
		}
	}
}

private struct SettingsIconBadge: View {
	let systemImage: String
	let color: Color

	var body: some View {
		Image(systemName: systemImage)
			.resizable()
			.renderingMode(.template)
			.foregroundStyle(.white)
			.scaledToFit()
			.padding(5.5)
			.frame(width: 29, height: 29)
			.background(color, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
	}
}

private struct ManageStorageRepresentable: UIViewControllerRepresentable {
	func makeUIViewController(context: Context) -> ManageStorageCollectionViewController {
		ManageStorageCollectionViewController()
	}

	func updateUIViewController(_ uiViewController: ManageStorageCollectionViewController, context: Context) {}
}
