//
//  ParsedArticle+Database.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 9/18/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSParser
import Articles

extension ParsedItem {

	/// Must be the same calculation `Article`'s own initializer uses
	/// (`Article.init(accountID:articleID:feedID:...)` falling back to
	/// `Article.calculatedArticleID(feedID:uniqueID:)` when `syncServiceID`
	/// is nil) -- and that calculation is keyed on the caller's `feedID`,
	/// not on this item's own `feedURL`. `Feed.swift`'s `feedID`/`url`
	/// split exists specifically so a feed's fetch address can change (e.g.
	/// after a LAN IP change) without changing its identity, and articleID
	/// is documented there as derived from `feedID` for exactly that reason.
	/// This used to default to `feedURL` when no `feedID` was passed in,
	/// which silently produced a different articleID than the `Article`
	/// row actually being saved under (same uniqueID, different key) any
	/// time a caller's `feedID` differed from this item's `feedURL` --
	/// splitting the `articles` and `statuses` rows for the same article
	/// onto two different primary keys and breaking every `natural join`
	/// fetch between them. Requiring `feedID` explicitly here removes the
	/// silent fallback; every call site in this module already has the
	/// real `feedID` in scope.
	func articleID(feedID: String) -> String {
		if let s = syncServiceID {
			return s
		}
		return Article.calculatedArticleID(feedID: feedID, uniqueID: uniqueID)
	}
}
