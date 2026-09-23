//
//  UITestDemoData.swift
//  NetNewsWire
//
//  Subscribes the screenshot demo feed for `fastlane snapshot`. Active only
//  when the app is launched with `-UITestSeedDemoData`
//  (Platform.isUITestingWithSeedDemoData); without that flag `seedIfNeeded()`
//  returns immediately and nothing here runs, so it has no effect on a normal
//  install.
//
//  The feed is a plain JSON Feed hosted on GitHub Pages
//  (https://kyrielie.github.io/nectar/demo-feeds/feed.json, built from
//  demo-feeds/ by .github/workflows/gallery.yml), so screenshots need network
//  access. See docs/ui-test-demo-data.md.
//

import Foundation
import RSCore
import Account
import ArticleTheming

@MainActor
enum UITestDemoData {

	static func seedIfNeeded() {
		guard Platform.isUITestingWithSeedDemoData else {
			return
		}

		applyReadingProfileIfRequested()

		guard let opmlURL = Bundle.main.url(forResource: "DemoFeeds", withExtension: "opml") else {
			assertionFailure("UITestDemoData: DemoFeeds.opml not found in the app bundle.")
			return
		}

		AccountManager.shared.defaultAccount.importOPML(opmlURL) { result in
			if case .failure(let error) = result {
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
}
