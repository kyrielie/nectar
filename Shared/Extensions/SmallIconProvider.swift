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
		// AO3's own feeds don't declare a meaningful per-feed icon -- every
		// AO3 feed's resolved favicon is the same generic, low-res site mark
		// -- so the bundled icon always wins for an AO3 feed, unconditionally,
		// rather than being gated behind "only if the feed has no icon of its
		// own." (An earlier version of this gated on `faviconURL == nil`;
		// that check never actually excluded AO3 feeds in practice --
		// RSSParser never populates faviconURL from feed XML -- so it wasn't
		// the cause of AO3 feeds showing the low-res icon. The real cause was
		// IconImageCache.imageForFeed(_:_:) never calling this property at
		// all for Feed sidebar items; see archiveOfOurOwnBundledIcon below.)
		if let icon = archiveOfOurOwnBundledIcon {
			return icon
		}
		if let iconImage = FaviconDownloader.shared.favicon(for: self) {
			return iconImage
		}
		return FaviconGenerator.shared.favicon(self)
	}

	/// The bundled AO3 mark, if this feed is an AO3 feed -- `nil` for every
	/// other feed. Split out from `smallIcon` so `IconImageCache.imageForFeed`
	/// can check it directly: that method has its own icon-resolution order
	/// for `Feed` and never calls `smallIcon` (that's only reached for
	/// non-`Feed` `SmallIconProvider`s, e.g. `PseudoFeed`/`Folder`), so
	/// without this, AO3's bundled icon was unreachable from the feed
	/// list/timeline rows that actually render feed icons.
	var archiveOfOurOwnBundledIcon: IconImage? {
		guard isArchiveOfOurOwnFeed else { return nil }
		return Self.archiveOfOurOwnIcon
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
