//
//  AppDefaults+TextReplacement.swift
//  Nectar
//

import Foundation
import AnnotationsKit

extension AppDefaults {

	/// The master "apply automatically on open" toggle for the rule-driven
	/// text-replacement categories (typo fixes, reader-insert names, and
	/// quote conversion) -- registered default is **off** as of Part 8
	/// (previously on; see registerDefaults()'s own comment on this key
	/// and migrateTextReplacementApplyAutomaticallyDefaultIfNeeded(),
	/// which writes an explicit `true` for every upgrading user so the
	/// flip only affects fresh installs). Categories 1/3's own toggles
	/// are the per-category switch underneath this one; quote
	/// conversion's own toggle below is separately default off.
	var textReplacementApplyAutomatically: Bool {
		get {
			return AppDefaults.bool(for: Key.textReplacementApplyAutomatically)
		}
		set {
			AppDefaults.setBool(for: Key.textReplacementApplyAutomatically, newValue)
		}
	}

	/// Category 1 (common typo fixes). Default **on**, registered in
	/// registerDefaults() below -- see the plan's "Settings screen"
	/// section.
	var textReplacementTypoFixesEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.textReplacementTypoFixesEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.textReplacementTypoFixesEnabled, newValue)
		}
	}

	/// Category 2 (British->American quote conversion). Default **off**
	/// -- a style preference, not a correction, per the plan.
	var textReplacementQuoteConversionEnabled: Bool {
		get {
			return AppDefaults.bool(for: Key.textReplacementQuoteConversionEnabled)
		}
		set {
			AppDefaults.setBool(for: Key.textReplacementQuoteConversionEnabled, newValue)
		}
	}

	/// Category 1's person-editable rule table, seeded from
	/// TextReplacementRuleTable.defaultTypoTable on first read.
	var textReplacementTypoTable: TextReplacementRuleTable {
		get { AppDefaults.decode(TextReplacementRuleTable.self, key: Key.textReplacementTypoTable, default: .defaultTypoTable) }
		set { AppDefaults.encode(newValue, key: Key.textReplacementTypoTable) }
	}

	/// Category 3's person-editable rule table (reader-insert names),
	/// seeded from TextReplacementRuleTable.defaultReaderInsertTable on
	/// first read. The per-work override (TextReplacementPerWorkOverride)
	/// is a separate, additional table layered on top at apply time, not
	/// stored here.
	var textReplacementReaderInsertTable: TextReplacementRuleTable {
		get { AppDefaults.decode(TextReplacementRuleTable.self, key: Key.textReplacementReaderInsertTable, default: .defaultReaderInsertTable) }
		set { AppDefaults.encode(newValue, key: Key.textReplacementReaderInsertTable) }
	}

	/// "Custom rules" (plan's "Settings screen"): arbitrary person-added
	/// pairs not covered by the shipped typo table. Empty by default --
	/// unlike the typo/reader-insert tables, there is no shipped seed.
	var textReplacementCustomTable: TextReplacementRuleTable {
		get { AppDefaults.decode(TextReplacementRuleTable.self, key: Key.textReplacementCustomTable, default: TextReplacementRuleTable()) }
		set { AppDefaults.encode(newValue, key: Key.textReplacementCustomTable) }
	}

	/// Step 7's per-work override, scoped to category 3 (reader-insert
	/// names) only -- see TextReplacementPerWorkOverride's own header
	/// comment for why this doesn't apply to categories 1/2 too. Empty by
	/// default, same reasoning as textReplacementCustomTable above: there's
	/// no shipped seed for a per-work table, since it exists specifically
	/// for a person to fill in once they notice the global table would
	/// clobber something in a particular work.
	var textReplacementPerWorkOverride: TextReplacementPerWorkOverride {
		get { AppDefaults.decode(TextReplacementPerWorkOverride.self, key: Key.textReplacementPerWorkOverride, default: TextReplacementPerWorkOverride()) }
		set { AppDefaults.encode(newValue, key: Key.textReplacementPerWorkOverride) }
	}
}
