//
//  OPMLNormalizer.swift
//  Account
//
//  Created by Maurice Parker on 3/31/20.
//  Copyright © 2020 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSParser

final class OPMLNormalizer {

	var normalizedOPMLItems = [OPMLItem]()

	static func normalize(_ items: [OPMLItem]) -> [OPMLItem] {
		let opmlNormalizer = OPMLNormalizer()
		opmlNormalizer.normalize(items)
		return opmlNormalizer.normalizedOPMLItems
	}

	/// Recursively walks `items`, deduping feeds by URL within each
	/// folder's own direct children and folding unnamed folders' items
	/// up into their parent's scope. `parentFolder` is the `OPMLItem`
	/// whose `children` newly-discovered top-level feeds/folders should
	/// be appended to -- nil means "append to `normalizedOPMLItems`".
	///
	/// Unlike the original version of this method, `parentFolder` is
	/// passed down as `item` (the just-created/found named folder)
	/// at every level, not only when recursing into the very first
	/// named folder encountered. That original behavior collapsed all
	/// descendants of the first-seen named folder into that single
	/// folder's `children`, discarding real nesting -- a nested named
	/// folder still appeared in the tree as an (empty-looking, since its
	/// own children never got attached to it) sibling entry, while its
	/// feeds silently reappeared one level higher than intended.
	private func normalize(_ items: [OPMLItem], parentFolder: OPMLItem? = nil) {
		var feedsToAdd = [OPMLItem]()

		for item in items {

			if item.feedSpecifier != nil {
				if !feedsToAdd.contains(where: { $0.feedSpecifier?.feedURL == item.feedSpecifier?.feedURL }) {
					feedsToAdd.append(item)
				}
				continue
			}

			guard item.titleFromAttributes != nil else {
				// Folder doesn’t have a name, so it won’t be created, and its items will go one level up.
				if let itemChildren = item.children {
					normalize(itemChildren, parentFolder: parentFolder)
				}
				continue
			}

			feedsToAdd.append(item)
			if let itemChildren = item.children {
				// Recurse with `item` itself as the new parent scope, so
				// this folder's own children get attached to it -- and,
				// transitively, so do any further-nested named folders'
				// children get attached to *them*, not flattened here.
				normalize(itemChildren, parentFolder: item)
			}
		}

		if let parentFolder = parentFolder {
			for feed in feedsToAdd {
				if !(parentFolder.children?.contains(where: { $0.feedSpecifier?.feedURL == feed.feedSpecifier?.feedURL}) ?? false) {
					parentFolder.addChild(feed)
				}
			}
		} else {
			for feed in feedsToAdd {
				normalizedOPMLItems.append(feed)
			}
		}

	}

}
