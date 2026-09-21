//
//  AppDefaults+ReadingStats.swift
//  NetNewsWire
//
//  Reading Stats' persisted settings and accounting data, split out of
//  AppDefaults.swift so the feature's keys and properties live next to
//  ReadingStatsTracker and ReadingStatsView. A pure move: key strings,
//  property names, and behavior are unchanged, so no UserDefaults migration
//  is involved. `AppDefaults.decode`/`encode` (internal, in AppDefaults.swift)
//  back the Codable-valued properties.
//

import Foundation

extension AppDefaults.Key {
	static let readingStatsTrackingEnabled = "readingStatsTrackingEnabled"
	static let readingStatsDailyHistory = "readingStatsDailyHistory"
	static let readingStatsDailyWords = "readingStatsDailyWords"
	static let readingStatsProgressByBookKey = "readingStatsProgressByBookKey"
	static let readingStatsAllTimeWords = "readingStatsAllTimeWords"
}

extension AppDefaults {

	var readingStatsTrackingEnabled: Bool {
		get { AppDefaults.bool(for: Key.readingStatsTrackingEnabled) }
		set { AppDefaults.setBool(for: Key.readingStatsTrackingEnabled, newValue) }
	}

	var readingStatsDailyHistory: [String: ReadingStatsDailyEntry] {
		get { AppDefaults.decode([String: ReadingStatsDailyEntry].self, key: Key.readingStatsDailyHistory, default: [:]) }
		set { AppDefaults.encode(Dictionary(uniqueKeysWithValues: newValue.sorted { $0.key < $1.key }.suffix(35)), key: Key.readingStatsDailyHistory) }
	}

	/// Words credited per day (`"yyyy-MM-dd"` -> words), trimmed to 371 days
	/// (53 weeks) on every write -- the most `ReadingHeatmapView`'s
	/// year-of-activity grid can span (365 days plus up to 6 to align to
	/// the week's first day; see `ReadingHeatmapData.daysAndStartDate`).
	/// Deliberately a separate, tiny store rather than widening
	/// `readingStatsDailyHistory`'s 35-day cap: that dictionary is decoded,
	/// mutated, and re-encoded in full by `ReadingStatsTracker.tick()` every
	/// second while reading, and each day's entry carries per-fandom/per-tag
	/// maps and per-work sets, so keeping a year of it would make every one
	/// of those writes roughly ten times larger. Read via
	/// `readingStatsDailyWordCounts`, not directly, so days that predate
	/// this store still appear.
	var readingStatsDailyWords: [String: Int] {
		get { AppDefaults.decode([String: Int].self, key: Key.readingStatsDailyWords, default: [:]) }
		set { AppDefaults.encode(Dictionary(uniqueKeysWithValues: newValue.sorted { $0.key < $1.key }.suffix(371)), key: Key.readingStatsDailyWords) }
	}

	/// What the Streaks/Monthly UI reads: `readingStatsDailyWords`, with any
	/// day where `readingStatsDailyHistory` recorded more words filled in
	/// from there. That covers days recorded before `readingStatsDailyWords`
	/// existed (no migration step needed) and the day of the upgrade itself,
	/// where the new store only saw the words read after upgrading. Per-day
	/// word counts only ever grow within a day, so `max` is safe.
	var readingStatsDailyWordCounts: [String: Int] {
		var merged = readingStatsDailyWords
		for (key, entry) in readingStatsDailyHistory where entry.wordsRead > merged[key, default: 0] {
			merged[key] = entry.wordsRead
		}
		return merged
	}

	var readingStatsProgressByBookKey: [String: Double] {
		get { AppDefaults.decode([String: Double].self, key: Key.readingStatsProgressByBookKey, default: [:]) }
		set { AppDefaults.encode(newValue, key: Key.readingStatsProgressByBookKey) }
	}

	var readingStatsAllTimeWords: Int {
		get { AppDefaults.int(for: Key.readingStatsAllTimeWords) }
		set { AppDefaults.setInt(for: Key.readingStatsAllTimeWords, newValue) }
	}

	/// Wipes all recorded reading-stats data -- the daily history the
	/// charts/streak are built from, per-book reading progress, and the
	/// all-time word counter -- but leaves `readingStatsTrackingEnabled`
	/// untouched, mirroring resetToolbarDefaults(for:)'s scoping (that
	/// resets placement/order but not the feature's own on/off switch).
	/// Implemented as key removal, not re-writing to `[:]`/`0`, for the
	/// same reason as resetToolbarDefaults(for:): removing the key falls
	/// back to whatever default already applies (empty dictionary, zero),
	/// so there's nothing to keep in sync here if those defaults ever
	/// change. This is destructive and not recoverable -- callers should
	/// confirm with the user first.
	func resetReadingStats() {
		AppDefaults.store.removeObject(forKey: Key.readingStatsDailyHistory)
		AppDefaults.store.removeObject(forKey: Key.readingStatsDailyWords)
		AppDefaults.store.removeObject(forKey: Key.readingStatsProgressByBookKey)
		AppDefaults.store.removeObject(forKey: Key.readingStatsAllTimeWords)
	}
}
