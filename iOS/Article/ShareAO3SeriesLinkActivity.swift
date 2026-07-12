//
//  ShareAO3SeriesLinkActivity.swift
//  Nectar
//
//  Phase 7 fork addition. Follows OpenInBrowserActivity.swift's method
//  shape (that file is misleadingly named OpenInSafariActivity.swift --
//  don't let the file name mislead this one's naming too).
//
//  Unlike OpenInBrowserActivity, this ignores the passed-in activityItems
//  entirely and operates on a series URL captured at init time, same as
//  FindInArticleActivity's ambient-state approach -- the custom
//  UIActivityViewController(url:title:applicationActivities:) convenience
//  init only threads a single URL through activityItems, so a second,
//  independent URL (the series link, as opposed to the story link) has to
//  be supplied out of band.
//

import UIKit

final class ShareAO3SeriesLinkActivity: UIActivity {

	private let seriesURL: URL?

	init(seriesURL: URL?) {
		self.seriesURL = seriesURL
		super.init()
	}

	override var activityTitle: String? {
		return NSLocalizedString("Share AO3 Series Link", comment: "Command")
	}

	override var activityImage: UIImage? {
		return UIImage(systemName: "books.vertical", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
	}

	override var activityType: UIActivity.ActivityType? {
		return UIActivity.ActivityType(rawValue: "com.ambrosia.Nectar.shareSeriesLink")
	}

	override static var activityCategory: UIActivity.Category {
		return .action
	}

	override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
		// Gates visibility on there being a series to share -- this is what makes
		// "always offer when series data exists" work without extra conditionals
		// at the call site.
		return seriesURL != nil
	}

	override func prepare(withActivityItems activityItems: [Any]) {
		// Deliberately ignored -- seriesURL was captured at init, not derived
		// from the shared item.
	}

	override func perform() {
		guard let seriesURL else {
			activityDidFinish(false)
			return
		}

		Task { @MainActor in
			UIApplication.shared.open(seriesURL, options: [:], completionHandler: nil)
		}

		activityDidFinish(true)
	}
}
