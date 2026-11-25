//
//  SettingsModel.swift
//  NetNewsWire-iOS
//
//  Observable state behind `SettingsView`: owns app-wide preference bindings,
//  detail labels, availability gating, and notification observation.
//

import Foundation
import SwiftUI
import Account
import Articles
import ArticleTheming
import AppChrome
import AO3Kit

@MainActor final class SettingsModel: ObservableObject {

	@Published var feedTransferFormat: AmbrosiaTransferFormat {
		didSet {
			guard oldValue != feedTransferFormat else { return }
			AmbrosiaTransferFormatPreference.current = feedTransferFormat
		}
	}

	@Published var timelineSortField: ArticleSorter.SortField {
		didSet {
			guard oldValue != timelineSortField else { return }
			AppDefaults.shared.timelineSortField = timelineSortField
		}
	}

	@Published var timelineSortDirection: ComparisonResult {
		didSet {
			guard oldValue != timelineSortDirection else { return }
			AppDefaults.shared.timelineSortDirection = timelineSortDirection
		}
	}

	@Published var timelineGroupByFeed: Bool {
		didSet {
			guard oldValue != timelineGroupByFeed else { return }
			AppDefaults.shared.timelineGroupByFeed = timelineGroupByFeed
		}
	}

	@Published var refreshClearsReadArticles: Bool {
		didSet {
			guard oldValue != refreshClearsReadArticles else { return }
			AppDefaults.shared.refreshClearsReadArticles = refreshClearsReadArticles
		}
	}

	@Published var showLastUpdatedLabel: Bool {
		didSet {
			guard oldValue != showLastUpdatedLabel else { return }
			AppDefaults.shared.showLastUpdatedLabel = showLastUpdatedLabel
		}
	}

	@Published var openLinksInNectar: Bool {
		didSet {
			guard oldValue != openLinksInNectar else { return }
			AppDefaults.shared.useSystemBrowser = !openLinksInNectar
		}
	}

	@Published var disableArticleLinks: Bool {
		didSet {
			guard oldValue != disableArticleLinks else { return }
			AppDefaults.shared.disableArticleLinks = disableArticleLinks
		}
	}

	@Published var showFeedNameInReaderView: Bool {
		didSet {
			guard oldValue != showFeedNameInReaderView else { return }
			AppDefaults.shared.showFeedNameInReaderView = showFeedNameInReaderView
		}
	}

	@Published private(set) var isAO3SignedIn: Bool
	@Published private(set) var currentThemeName: String
	@Published private(set) var colorPaletteDescription: String
	@Published private(set) var accentColorDescription: String
	@Published private(set) var isReadArticlesFiltered: Bool

	private weak var presentingParentController: UIViewController?
	nonisolated(unsafe) private var observers = [NSObjectProtocol]()

	init(
		presentingParentController: UIViewController? = nil,
		notificationCenter: NotificationCenter = .default
	) {
		self.presentingParentController = presentingParentController
		self.feedTransferFormat = AmbrosiaTransferFormatPreference.current
		self.timelineSortField = AppDefaults.shared.timelineSortField
		self.timelineSortDirection = AppDefaults.shared.timelineSortDirection
		self.timelineGroupByFeed = AppDefaults.shared.timelineGroupByFeed
		self.refreshClearsReadArticles = AppDefaults.shared.refreshClearsReadArticles
		self.showLastUpdatedLabel = AppDefaults.shared.showLastUpdatedLabel
		self.openLinksInNectar = !AppDefaults.shared.useSystemBrowser
		self.disableArticleLinks = AppDefaults.shared.disableArticleLinks
		self.showFeedNameInReaderView = AppDefaults.shared.showFeedNameInReaderView
		self.isAO3SignedIn = AO3SessionStore.isSignedIn
		self.currentThemeName = ArticleThemesManager.shared.currentTheme.name
		self.colorPaletteDescription = String(describing: AppDefaults.userInterfaceColorPalette)
		self.accentColorDescription = AppDefaults.shared.accentColor.description
		self.isReadArticlesFiltered = (presentingParentController as? RootSplitViewController)?.coordinator.isReadArticlesFiltered ?? false

		let names: [Notification.Name] = [
			.ao3SessionDidChange,
			.CurrentArticleThemeDidChangeNotification,
			.ArticleThemeNamesDidChangeNotification,
			.accentColorDidChange,
			.surfaceTintDidChange,
			UserDefaults.didChangeNotification
		]
		observers = names.map { name in
			notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.refresh()
				}
			}
		}
	}

	deinit {
		for observer in observers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	var ao3StatusText: String {
		isAO3SignedIn
			? NSLocalizedString("Signed In", comment: "AO3 status: signed in")
			: NSLocalizedString("Not Signed In", comment: "AO3 status: not signed in")
	}

	var feedTransferFormatText: String {
		feedTransferFormat == .sqlite
			? NSLocalizedString("SQLite", comment: "Feed transfer format")
			: NSLocalizedString("JSON", comment: "Feed transfer format")
	}

	var isGroupByFeedEnabled: Bool {
		timelineSortField == .date
	}

	var groupByFeedDisabledReason: String? {
		isGroupByFeedEnabled ? nil : NSLocalizedString("Only applies when sorted by Date", comment: "Group by Feed inapplicable reason")
	}

	var clearReadArticlesReason: String? {
		isReadArticlesFiltered ? nil : NSLocalizedString("Only applies when the Read Works filter is on", comment: "Clear read articles inapplicable reason")
	}

	var sortDirectionOptions: [(direction: ComparisonResult, label: String)] {
		[
			(.orderedDescending, timelineSortField.descendingLabel),
			(.orderedAscending, timelineSortField.ascendingLabel)
		]
	}

	var buildVersionText: String {
		"\(Bundle.main.appName) \(Bundle.main.versionNumber) (Build \(Bundle.main.buildNumber))"
	}

	func refresh() {
		let latestTransfer = AmbrosiaTransferFormatPreference.current
		if feedTransferFormat != latestTransfer {
			feedTransferFormat = latestTransfer
		}
		isAO3SignedIn = AO3SessionStore.isSignedIn
		currentThemeName = ArticleThemesManager.shared.currentTheme.name
		colorPaletteDescription = String(describing: AppDefaults.userInterfaceColorPalette)
		accentColorDescription = AppDefaults.shared.accentColor.description
		isReadArticlesFiltered = (presentingParentController as? RootSplitViewController)?.coordinator.isReadArticlesFiltered ?? false
	}
}
