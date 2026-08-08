//
//  SmallIconProvider.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 12/16/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import Articles
import Account
import RSCore
import Images
import UIKit

protocol SmallIconProvider {
	@MainActor var smallIcon: IconImage? { get }
}

@MainActor extension Account: SmallIconProvider {
	var smallIcon: IconImage? {
		let image = Assets.accountImage(type)
		return IconImage(image)
	}
}

@MainActor extension Feed: SmallIconProvider {
	var smallIcon: IconImage? {
		// Feature request: AO3 feeds get the bundled high-resolution vector
		// mark instead of whatever low-res favicon.ico the site serves.
		// This only applies when the feed has no icon of its own -- a
		// locally/feed-provided icon (feed.faviconURL, set from the feed's
		// own <icon>/favicon metadata during parsing, or a favicon already
		// resolved via FaviconDownloader) must still take priority over the
		// bundled mark. Otherwise the bundled AO3 icon would unconditionally
		// shadow a real icon the feed declares. The bundled icon still
		// takes priority over the generated placeholder below.
		if isArchiveOfOurOwnFeed, faviconURL == nil, let icon = Self.archiveOfOurOwnIcon {
			return icon
		}
		if let iconImage = FaviconDownloader.shared.favicon(for: self) {
			return iconImage
		}
		if isArchiveOfOurOwnFeed, let icon = Self.archiveOfOurOwnIcon {
			return icon
		}
		return FaviconGenerator.shared.favicon(self)
	}

	/// Exact-match host check, deliberately narrower than
	/// `AO3LinkListImporter.permittedHosts` (which also covers mirror/legacy
	/// domains like archiveofourown.com/.net and the raw IP addresses) --
	/// this only needs to catch the host a *feed* URL would actually use,
	/// not every host a pasted permalink might use.
	private var isArchiveOfOurOwnFeed: Bool {
		for candidate in [homePageURL, url] {
			guard let candidate, let host = URL(string: candidate)?.host?.lowercased() else { continue }
			if host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org") {
				return true
			}
		}
		return false
	}

	private static let archiveOfOurOwnIcon: IconImage? = {
		guard let image = UIImage(named: "archiveOfOurOwnFeedIcon") else { return nil }
		return IconImage(image, isBackgroundSuppressed: true)
	}()
}

@MainActor extension Folder: SmallIconProvider {
	var smallIcon: IconImage? {
		Assets.Images.mainFolder
	}
}
