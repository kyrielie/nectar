//
//  TextReplacementPerWorkOverride.swift
//  Articles
//
//  Step 7 of the text-replacement feature's build order (see the
//  feature's own implementation plan, "Word/placeholder replacement" --
//  "Resolved: stored both globally (default table) and per-work
//  (override)"). Scoped to category 3 (reader-insert names) only: some
//  fandoms' reader-insert fic uses a canon name a global replacement
//  would otherwise incorrectly clobber, so a person can override the
//  reader-insert table for one bookKey without touching the global
//  table or any other work.
//
//  Pure and storage-agnostic, same reasoning TextReplacementRuleTable/
//  TextReplacementOffsetShift live in this module for -- no
//  ArticlesDatabase/AppDefaults dependency. AppDefaults (iOS target) is
//  where this is actually persisted, via the same Codable-in-
//  UserDefaults pattern the other three tables already use (see
//  AppDefaults.textReplacementPerWorkOverride).
//

import Foundation

/// A person-editable map from bookKey to that work's own reader-insert
/// table, layered on top of (never replacing) the global reader-insert
/// table. Empty by default -- there is no shipped seed for this, the
/// same reasoning textReplacementCustomTable has none: it exists purely
/// for a person to fill in once they notice the global table would
/// clobber something in a particular work.
public struct TextReplacementPerWorkOverride: Codable, Sendable, Hashable {
	private var tablesByBookKey: [String: TextReplacementRuleTable]

	public init(tablesByBookKey: [String: TextReplacementRuleTable] = [:]) {
		self.tablesByBookKey = tablesByBookKey
	}

	/// The override table for `bookKey`, or nil if no override has been
	/// set for that work (or `bookKey` itself is nil -- an unresolvable
	/// bookKey, same rare case book-identity.md describes, simply never
	/// has an override).
	public func table(forBookKey bookKey: String?) -> TextReplacementRuleTable? {
		guard let bookKey else { return nil }
		return tablesByBookKey[bookKey]
	}

	/// Whether `bookKey` has an override set. Distinct from
	/// `table(forBookKey:) != nil` only in that this reads more clearly
	/// at call sites that don't need the table itself -- e.g. the
	/// Settings screen deciding whether to show "Edit Override" versus
	/// "Add Override" for the currently open work.
	public func hasOverride(forBookKey bookKey: String?) -> Bool {
		table(forBookKey: bookKey) != nil
	}

	/// Sets `bookKey`'s override table. A table with an empty `rules`
	/// array clears the entry entirely rather than persisting an
	/// explicit empty override -- there is no meaningful difference
	/// between "no override" and "an override with zero rules," and
	/// collapsing them keeps `hasOverride`/`table(forBookKey:)` from
	/// ever needing to distinguish the two.
	public mutating func setTable(_ table: TextReplacementRuleTable, forBookKey bookKey: String) {
		if table.rules.isEmpty {
			tablesByBookKey.removeValue(forKey: bookKey)
		} else {
			tablesByBookKey[bookKey] = table
		}
	}

	/// The table to actually match against for `bookKey`: this work's
	/// override prepended ahead of `global`, if one exists, otherwise
	/// `global` unchanged. Prepending (rather than replacing outright)
	/// means an override that only covers some tokens (e.g. just Y/N,
	/// leaving L/N to the global table) still lets the global table's
	/// own rows resolve for anything the override doesn't mention --
	/// TextReplacementRuleEngine's existing "earlier rule in the array
	/// wins for an overlapping span" behavior gives the override
	/// precedence for free, with no separate precedence mechanism
	/// needed here.
	public func mergedReaderInsertTable(forBookKey bookKey: String?, global: TextReplacementRuleTable) -> TextReplacementRuleTable {
		guard let overrideTable = table(forBookKey: bookKey) else { return global }
		return TextReplacementRuleTable(rules: overrideTable.rules + global.rules)
	}
}
