//
//  Assets.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/18/25.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit

import RSCore
import Account
import Images

typealias RSColor = UIColor

struct Assets {
	@MainActor struct Images {

		// Named starOpen/starClosed for historical reasons — these back the "Read
		// Later" action (Phase 3), not literal starring; the internal ArticleStatus.Key
		// is still `.starred` deliberately (see Phase 3 in the fork plan: UI-copy/icon
		// only, no internal rename, to keep the diff small and behavior unchanged).
		static let starOpen = RSImage(symbol: "bookmark")!
		static let starClosed = RSImage(symbol: "bookmark.fill")!
		static let copy = RSImage(symbol: "document.on.document")
		static var markAllAsRead: RSImage { RSImage(named: "markAllAsRead")! }
		static let nextUnread = RSImage(symbol: "chevron.down.circle")!

		nonisolated static var nnwFeedIcon: RSImage { RSImage(named: "nnwFeedIcon")! }
		// Default per-feed placeholder, colorized per-feed by FaviconGenerator.
		// A book, not a globe -- Nectar feeds are books, not blogs.
		//
		// FaviconGenerator masks this via a raw CGImage (RSImage.maskWithColor),
		// not the live SwiftUI symbol-rendering path the sidebar's other SF
		// Symbol icons (todayFeed, unreadFeed, etc.) use -- so unlike those,
		// this one gets rasterized to a fixed pixel size exactly once and
		// reused for every feed. RSImage(symbol:)'s default point size (~17pt,
		// the system font size) is too small a source to upscale to
		// IconSize.large (48pt) without blurring, so request it explicitly
		// large instead of relying on the default.
		static let faviconTemplate: RSImage = RSImage.symbolImage("book.closed.fill", pointSize: 120)!

		static let share = RSImage(symbol: "square.and.arrow.up")!
		static let folder = RSImage(symbol: "folder")!
		static let starredFeed = IconImage(starClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.star)

		static var accountLocalPadImage: RSImage { RSImage(named: "accountLocalPad")! }
		static var accountLocalPhoneImage: RSImage { RSImage(named: "accountLocalPhone")! }

		static let circleClosed = RSImage(symbol: "largecircle.fill.circle")!
		static let markBelowAsRead = RSImage(symbol: "arrowtriangle.down.circle")!
		static let markAboveAsRead = RSImage(symbol: "arrowtriangle.up.circle")!
		static let more = RSImage(symbol: "ellipsis.circle")!
		static let nextArticle = RSImage(symbol: "chevron.down")!
		static let circleOpen = RSImage(symbol: "circle")!
		static var disclosure: RSImage { RSImage(named: "disclosure")! }
		static let deactivate = RSImage(symbol: "minus.circle")!
		static let currentActivity = RSImage(symbol: "text.pad.header")!
		static let edit = RSImage(symbol: "square.and.pencil")!
		static let filter = RSImage(symbol: "line.3.horizontal.decrease")!
		static let folderOutlinePlus = RSImage(symbol: "folder.badge.plus")!
		static let info = RSImage(symbol: "info.circle")!
		static let opmlImport = RSImage(symbol: "square.and.arrow.down.on.square")!
		static let plus = RSImage(symbol: "plus")!
		static let prevArticle = RSImage(symbol: "chevron.up")!
		static let openInSidebar = RSImage(symbol: "arrow.turn.down.left")!
		static let safari = RSImage(symbol: "safari")!
		static let smartFeed = RSImage(symbol: "gear")!
		static let trash = RSImage(symbol: "trash")!

		// Phase 5/6 fork additions: Loved toolbar/action icons and the Theme
		// nav-bar icon. Symbol-backed like the rest of this section pending a
		// dedicated asset catalog entry (not part of this text-only patch series).
		static let heartOpen = RSImage(symbol: "heart")!
		static let heartClosed = RSImage(symbol: "heart.fill")!
		static let theme = RSImage(symbol: "doc.richtext")!
		static let findInArticle = RSImage(symbol: "magnifyingglass")!
		static let tableOfContents = RSImage(symbol: "list.bullet")!

		// Loved smart feed icon: filled heart, system red -- replaces the
		// starredFeed-borrowed placeholder in LovedFeedDelegate.swift.
		static let lovedFeed = IconImage(heartClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: RSColor.systemRed)

		static let searchFeed = IconImage(RSImage(symbol: "magnifyingglass")!, isSymbol: true)
		static let mainFolder = IconImage(folder, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.secondaryAccent)
		static let todayFeed = IconImage(RSImage(symbol: "tray.and.arrow.down.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: UIColor.systemOrange)
		static let unreadFeed = IconImage(RSImage(symbol: "largecircle.fill.circle")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.secondaryAccent)
		static let readFeed = IconImage(RSImage(symbol: "checkmark.circle.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.secondaryAccent)
		// Last Opened smart feed icon. Placeholder symbol choice -- swap for
		// whatever SF Symbol fits the icon set; not cross-checked against the
		// app's actual icon conventions beyond "recently opened" being a
		// reasonable read for it.
		static let lastOpenedFeed = IconImage(RSImage(symbol: "clock.arrow.circlepath")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.secondaryAccent)
		static var timelineStar: RSImage {
			let image = RSImage(symbol: "star.fill")!
			return image.withTintColor(Assets.Colors.star, renderingMode: .alwaysOriginal)
		}
		static let unreadCellIndicator = IconImage(RSImage(symbol: "circle.fill")!, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.secondaryAccent)
	}

	@MainActor static func accountImage(_ accountType: AccountType) -> RSImage {
		switch accountType {
		case .onMyMac:
			if UIDevice.current.userInterfaceIdiom == .pad {
				return Assets.Images.accountLocalPadImage
			} else {
				return Assets.Images.accountLocalPhoneImage
			}
		}
	}

	@MainActor struct Colors {
		static let primaryAccent = RSColor(named: "primaryAccentColor")!
		static let secondaryAccent = RSColor(named: "secondaryAccentColor")!
		static let star = RSColor(named: "starColor")!
		static let vibrantText = RSColor(named: "vibrantTextColor")!
		static let controlBackground = RSColor(named: "controlBackgroundColor")!
		static let iconBackground = RSColor(named: "iconBackgroundColor")!
		static let fullScreenBackground = RSColor(named: "fullScreenBackgroundColor")!
		static let sectionHeader = RSColor(named: "sectionHeaderColor")!
	}
}

extension RSImage {

	convenience init?(symbol: String) {
		self.init(systemName: symbol)
	}

	/// Same as `init?(symbol:)`, but rendered at an explicit point size rather
	/// than the SF Symbol default (~17pt, the system font size). Needed for
	/// any symbol that gets rasterized once and reused at a larger fixed
	/// size (e.g. masked into a colored placeholder via `maskWithColor`)
	/// instead of rendered live through SwiftUI/UIKit's vector
	/// symbol-rendering path, which scales for free at any size.
	static func symbolImage(_ symbol: String, pointSize: CGFloat) -> RSImage? {
		let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
		return UIImage(systemName: symbol, withConfiguration: config)
	}
}
