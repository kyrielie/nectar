//
//  UITestDemoData.swift
//  NetNewsWire
//
//  Seeds deterministic, offline, PG/teen-safe placeholder fic content for
//  `fastlane snapshot`. Active only when the app is launched with
//  `-UITestSeedDemoData` (see Platform.isUITestingWithSeedDemoData). No
//  network request this makes is real: TestingURLProtocol intercepts every
//  request Downloader/URLSession.webservice/DownloadSession issue while
//  that flag is set (see the RSWeb changes accompanying this file), and
//  every feed URL here is on the `.invalid` TLD (RFC 2606 -- guaranteed
//  never to resolve on the real internet).
//
//  Content is entirely original (not reproduced from any real AO3 work):
//  ratings never exceed Teen And Up Audiences, warnings are limited to "No
//  Archive Warnings Apply"/"Creator Chose Not To Use Archive Warnings". See
//  docs/ui-test-demo-data.md.
//

import Foundation
import RSCore
import RSWeb
import Account
import Articles
import ArticleTheming

@MainActor
enum UITestDemoData {

	private static let feedBaseURL = "https://nectar-demo.invalid"

	private static let seededFeedPaths = [
		"/tags/tos-academy-days/feed.atom",
		"/tags/tng-diplomatic-corps/feed.atom",
		"/tags/ds9-promenade-life/feed.atom",
		"/feed/collection/demo-focus.json"
	]

	/// Marked "Read Later" (ArticleStatus.Key.starred).
	private static let starredTitles: Set<String> = [
		"Letters Home",
		"A Study in Empathy",
		"Old Friends, New Symbiont",
		"Letters from the Wormhole"
	]

	/// Marked "Loved" (ArticleStatus.Key.loved). Deliberately overlaps
	/// "Letters Home" with starredTitles above.
	private static let lovedTitles: Set<String> = [
		"Letters Home",
		"Shore Leave, Interrupted",
		"The Long Way to Betazed",
		"Dabo Night"
	]

	/// Marked read, so the timeline shows a real read/unread mix rather
	/// than an all-unread inbox.
	private static let readTitles: Set<String> = [
		"The Command Track",
		"Vulcan Mathematics",
		"Sickbay Politics",
		"The Ambassador's Request",
		"Ten Forward, After Hours",
		"The Cartography Club",
		"Promenade Hours",
		"The Replimat Incident"
	]

	/// Title of the one Ambrosia-sourced item, opened by the UI test for
	/// the Article screenshot. Left unread and un-annotated by this list
	/// (its highlight is seeded separately in saveSeededHighlight()) so
	/// the test finds it in a "haven't read this yet" state.
	static let focusArticleTitle = "A Quiet Kind of Orbit"

	static func seedIfNeeded() {
		guard Platform.isUITestingWithSeedDemoData else {
			return
		}

		// Force the JSON transfer route explicitly. It already defaults to
		// .json, but pinning it here means a future change to that default
		// can't silently route the Ambrosia focus feed through
		// AmbrosiaSQLiteTransferFetcher, which uses its own URLSession and
		// isn't wired to TestingURLProtocol.
		AmbrosiaTransferFormatPreference.current = .json

		applyReadingProfileIfRequested()
		registerCannedResponses()

		guard let opmlURL = Bundle.main.url(forResource: "DemoFeeds", withExtension: "opml") else {
			assertionFailure("UITestDemoData: DemoFeeds.opml not found in the app bundle.")
			return
		}

		AccountManager.shared.defaultAccount.importOPML(opmlURL) { result in
			switch result {
			case .success:
				Task { @MainActor in
					await markSeededArticleStatuses()
					await saveSeededHighlight()
				}
			case .failure(let error):
				assertionFailure("UITestDemoData: importOPML failed: \(error)")
			}
		}
	}

	/// `-UITestReadingProfile personal` sets the article font/line-height
	/// directly in Swift rather than through a fastlane launch argument:
	/// ArticleThemeOverrides is stored as one JSON-encoded UserDefaults
	/// string, and SnapshotHelper's launch-argument parser (a whitespace
	/// split with a `"..."`-quoted-token exception) can't carry a value
	/// that itself contains embedded double quotes.
	private static func applyReadingProfileIfRequested() {
		let arguments = ProcessInfo.processInfo.arguments
		guard let flagIndex = arguments.firstIndex(of: "-UITestReadingProfile"),
			  arguments.indices.contains(flagIndex + 1),
			  arguments[flagIndex + 1] == "personal" else {
			return
		}
		AppDefaults.shared.articleThemeOverrides = ArticleThemeOverrides(serifFontFamilyName: "Iowan Old Style", lineHeight: 1.2)
	}

	private static func registerCannedResponses() {
		for resourceName in ["tos-academy-days", "tng-diplomatic-corps", "ds9-promenade-life"] {
			guard let fileURL = Bundle.main.url(forResource: resourceName, withExtension: "atom"),
				  let data = try? Data(contentsOf: fileURL) else {
				assertionFailure("UITestDemoData: missing fixture \(resourceName).atom")
				continue
			}
			TestingURLProtocol.responses[feedBaseURL + "/tags/\(resourceName)/feed.atom"] = TestingURLProtocol.Response(statusCode: 200, data: data)
		}

		guard let jsonURL = Bundle.main.url(forResource: "focus-work", withExtension: "json"),
			  let jsonData = try? Data(contentsOf: jsonURL) else {
			assertionFailure("UITestDemoData: missing fixture focus-work.json")
			return
		}
		TestingURLProtocol.responses[feedBaseURL + "/feed/collection/demo-focus.json"] = TestingURLProtocol.Response(statusCode: 200, data: jsonData)
	}

	private static func seededArticles(in account: Account) async -> Set<Article> {
		let seededURLs = Set(seededFeedPaths.map { feedBaseURL + $0 })
		let seededFeeds = account.flattenedFeeds().filter { seededURLs.contains($0.url) }

		var articles = Set<Article>()
		for feed in seededFeeds {
			articles.formUnion(await account.fetchArticlesAsync(.feed(feed)))
		}
		return articles
	}

	private static func markSeededArticleStatuses() async {
		let account = AccountManager.shared.defaultAccount
		let articles = await seededArticles(in: account)

		func articleIDs(titledIn titles: Set<String>) -> Set<String> {
			Set(articles.filter { titles.contains($0.title ?? "") }.map { $0.articleID })
		}

		do {
			try await account.markArticles(articleIDs: articleIDs(titledIn: starredTitles), statusKey: .starred, flag: true)
			try await account.markArticles(articleIDs: articleIDs(titledIn: lovedTitles), statusKey: .loved, flag: true)
			try await account.markArticles(articleIDs: articleIDs(titledIn: readTitles), statusKey: .read, flag: true)
		} catch {
			assertionFailure("UITestDemoData: markArticles failed: \(error)")
		}
	}

	/// Highlights one full sentence in the focus work's prose. The
	/// start/endOffset pair is a best-effort computation against the
	/// paragraphs as authored (joined with single spaces) rather than the
	/// real DOM canonicalization -- per docs/annotations.md, quoteExact is
	/// stored alongside the offsets specifically so a quote search recovers
	/// the correct anchor even if the position drifts, so exact offsets
	/// aren't load-bearing here the way quoteExact is.
	private static func saveSeededHighlight() async {
		let account = AccountManager.shared.defaultAccount
		let articles = await seededArticles(in: account)
		guard let focusArticle = articles.first(where: { $0.title == focusArticleTitle }) else {
			assertionFailure("UITestDemoData: focus article \(focusArticleTitle) not found after import.")
			return
		}

		let now = Date()
		let annotation = Annotation(
			annotationID: "uitest-demo-highlight-1",
			articleID: focusArticle.articleID,
			bookKey: nil,
			quoteExact: "Some things just needed the room to keep happening.",
			quotePrefix: "e preferred it too. Some things didn't need a report filed. ",
			quoteSuffix: "",
			startOffset: 1188,
			endOffset: 1239,
			color: .yellow,
			note: nil,
			createdAt: now,
			updatedAt: now
		)
		await account.saveAnnotation(annotation)
	}
}
