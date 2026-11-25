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
		let model = SettingsModel(presentingParentController: presentingParentController)
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

	@State private var path: [SettingsDestination] = []
	@State private var didScrollToArticles = false

	var body: some View {
		NavigationStack(path: $path) {
			ScrollViewReader { proxy in
				List {
					ao3Section
					librarySection
					timelineSection
					worksSection
						.id("articles")
					appearanceSection
					troubleshootingSection
					helpSection
					backupSection
					buildFooterSection
				}
				.navigationTitle(Text("Settings", comment: "Settings navigation title"))
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button(NSLocalizedString("Done", comment: "Done button")) {
							onDismiss()
						}
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

	private var ao3Section: some View {
		Section {
			NavigationLink(value: SettingsDestination.ao3Account) {
				DetailRow(
					title: NSLocalizedString("Archive of Our Own Account", comment: "AO3 account row"),
					detail: model.ao3StatusText
				)
			}
		} header: {
			Text("Archive of Our Own", comment: "AO3 section header")
		} footer: {
			Text("Sign in to read works that are restricted to registered AO3 users. Nectar never sees your password -- only the resulting session.", comment: "AO3 section footer")
		}
	}

	private var librarySection: some View {
		Section {
			Button {
				actions.importOPML()
			} label: {
				Text("Import OPML File", comment: "Import OPML File")
					.foregroundStyle(.primary)
			}

			Button {
				actions.beginExportOPML()
			} label: {
				Text("Export OPML File", comment: "Export OPML File")
					.foregroundStyle(.primary)
			}

			Button {
				actions.beginExportArticles()
			} label: {
				Text("Export Library", comment: "Export Library")
					.foregroundStyle(.primary)
			}

			Button {
				actions.isTransferFormatDialogPresented = true
			} label: {
				DetailRow(
					title: NSLocalizedString("Transfer Format", comment: "Transfer Format"),
					detail: model.feedTransferFormatText
				)
			}
		} header: {
			Text("Library", comment: "Library section header")
		} footer: {
			Text("Exporting includes everything in your library.", comment: "Library section footer")
		}
	}

	private var timelineSection: some View {
		Section {
			Picker(NSLocalizedString("Sort By", comment: "Sort By"), selection: $model.timelineSortField) {
				ForEach(ArticleSorter.SortField.allCases, id: \.self) { field in
					Text(field.displayName).tag(field)
				}
			}

			Picker(NSLocalizedString("Order", comment: "Order"), selection: $model.timelineSortDirection) {
				ForEach(model.sortDirectionOptions, id: \.direction) { option in
					Text(option.label).tag(option.direction)
				}
			}

			Toggle(isOn: $model.timelineGroupByFeed) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Group by Shelf", comment: "Group by Shelf")
					if let reason = model.groupByFeedDisabledReason {
						Text(reason)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}
			.disabled(!model.isGroupByFeedEnabled)

			Toggle(isOn: $model.refreshClearsReadArticles) {
				VStack(alignment: .leading, spacing: 2) {
					Text("Clear Read Works on Refresh", comment: "Clear Read Works on Refresh")
					if let reason = model.clearReadArticlesReason {
						Text(reason)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}

			NavigationLink(value: SettingsDestination.timelineLayout) {
				Text("Timeline Layout", comment: "Timeline Layout")
			}

			Toggle(NSLocalizedString("Show Last Updated Label", comment: "Show Last Updated Label"), isOn: $model.showLastUpdatedLabel)
		} header: {
			Text("Timeline", comment: "Timeline section header")
		}
	}

	private var worksSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.articleTheme) {
				DetailRow(
					title: NSLocalizedString("Theme", comment: "Theme"),
					detail: model.currentThemeName
				)
			}

			Toggle(NSLocalizedString("Open Links in Nectar", comment: "Open Links in Nectar"), isOn: $model.openLinksInNectar)
			Toggle(NSLocalizedString("Disable Links in Works", comment: "Disable Links in Works"), isOn: $model.disableArticleLinks)
			Toggle(NSLocalizedString("Show Shelf Name in Reader View", comment: "Show Shelf Name in Reader View"), isOn: $model.showFeedNameInReaderView)

			NavigationLink(value: SettingsDestination.fullScreenReading) {
				Text("Toolbars, Gestures & Layout", comment: "Toolbars, Gestures & Layout")
			}
			NavigationLink(value: SettingsDestination.annotations) {
				Text("Highlights & Notes", comment: "Highlights & Notes")
			}
			NavigationLink(value: SettingsDestination.textReplacement) {
				Text("Text Replacement", comment: "Text Replacement")
			}
			NavigationLink(value: SettingsDestination.readingTime) {
				Text("Reading Time", comment: "Reading Time")
			}
			NavigationLink(value: SettingsDestination.readingStats) {
				Text("Reading Stats", comment: "Reading Stats")
			}
		} header: {
			Text("Works", comment: "Works section header")
		}
	}

	private var appearanceSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.colorPalette) {
				DetailRow(
					title: NSLocalizedString("Color Palette", comment: "Color Palette"),
					detail: model.colorPaletteDescription
				)
			}
			NavigationLink(value: SettingsDestination.accentColor) {
				DetailRow(
					title: NSLocalizedString("Accent Color", comment: "Accent Color"),
					detail: model.accentColorDescription
				)
			}
		} header: {
			Text("Appearance", comment: "Appearance section header")
		}
	}

	private var troubleshootingSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.errorLog) {
				Text("Error Log", comment: "Error Log")
			}
			NavigationLink(value: SettingsDestination.activityLog) {
				Text("Activity Log", comment: "Activity Log")
			}
			NavigationLink(value: SettingsDestination.accountStats) {
				Text("Account Stats", comment: "Account Stats")
			}
			NavigationLink(value: SettingsDestination.dinosaurs) {
				Text("Dinosaurs", comment: "Dinosaurs")
			}
			NavigationLink(value: SettingsDestination.manageStorage) {
				Text("Manage Storage", comment: "Manage Storage")
			}
		} header: {
			Text("Troubleshooting", comment: "Troubleshooting section header")
		}
	}

	private var helpSection: some View {
		Section {
			NavigationLink(value: SettingsDestination.about) {
				Text("About Nectar", comment: "About Nectar")
			}
			Button {
				actions.presentGuide()
			} label: {
				Text("Guide", comment: "Guide")
					.foregroundStyle(.primary)
			}
		} header: {
			Text("Help", comment: "Help section header")
		}
	}

	private var backupSection: some View {
		Section {
			Button {
				actions.exportBackup()
			} label: {
				Text("Backup", comment: "Backup")
					.foregroundStyle(.primary)
			}
			Button {
				actions.restoreBackup()
			} label: {
				Text("Restore from Backup…", comment: "Restore from Backup…")
					.foregroundStyle(.primary)
			}
		} header: {
			Text("Backup", comment: "Backup section header")
		} footer: {
			Text("Restoring never deletes or overwrites your existing shelves, works, or annotations -- it only adds what's missing. Settings are only replaced if you opt in during restore. AO3 sign-in isn't included; you'll need to sign in again after restoring.", comment: "Backup section footer")
		}
	}

	private var buildFooterSection: some View {
		Section {
		} footer: {
			Text(model.buildVersionText)
				.font(.caption2)
				.foregroundStyle(.secondary)
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
			TimelineCustomizerRepresentable()
				.navigationTitle(Text("Timeline Layout", comment: "Timeline Layout"))
				.navigationBarTitleDisplayMode(.inline)
		case .articleTheme:
			ArticleThemeListView()
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

private struct DetailRow: View {
	let title: String
	let detail: String

	var body: some View {
		HStack {
			Text(title)
				.foregroundStyle(.primary)
			Spacer()
			Text(detail)
				.foregroundStyle(.secondary)
		}
	}
}

private struct TimelineCustomizerRepresentable: UIViewControllerRepresentable {
	func makeUIViewController(context: Context) -> TimelineCustomizerCollectionViewController {
		TimelineCustomizerCollectionViewController()
	}

	func updateUIViewController(_ uiViewController: TimelineCustomizerCollectionViewController, context: Context) {}
}

private struct ManageStorageRepresentable: UIViewControllerRepresentable {
	func makeUIViewController(context: Context) -> ManageStorageCollectionViewController {
		ManageStorageCollectionViewController()
	}

	func updateUIViewController(_ uiViewController: ManageStorageCollectionViewController, context: Context) {}
}
