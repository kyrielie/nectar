//
//  AO3RegressionThreshold.swift
//  Articles
//
//  Nectar Task 8 ("Content archival & destructive-update protection").
//
//  Shared by two independent call sites that must not drift apart:
//  AO3ChapterFetcher's content-level regression guard (Account module,
//  comparing a live chapter fetch's re-derived chapter/word counts against
//  the stored content's own re-derived counts) and Article+Database's
//  metadata-level watch (ArticlesDatabase module, comparing a feed-reported
//  wordCount alone, no contentHTML involved). Lives here, in Articles,
//  since both ArticlesDatabase and Account depend on Articles but neither
//  depends on the other.
//
//  Deliberately not a Settings-exposed slider -- a threshold the person has
//  to personally tune without visibility into how often it fires is a worse
//  default than a sane fixed number, adjustable later.
//

import Foundation

public enum AO3RegressionThreshold {

	/// Ordinary AO3 copy-edits move word/chapter counts well under 1% -- no
	/// false positives at 10%. Legitimate non-alarming revisions (reworking
	/// a chapter's back half) can plausibly move 5-15%; 10% is meaningfully
	/// safer against those than a flatter 5% threshold. Real regressions (a
	/// deleted chapter, a gutted/orphaned work) are typically 30%+ drops --
	/// both thresholds catch these fine, so the choice here is about
	/// false-positive rate on benign edits, not catch rate.
	private static let percentDropThreshold = 0.10

	/// A percentage-only rule is noisy on short works (a 200-word ficlet
	/// trimmed by 20 words is a meaningless 10% drop). 300 is a starting
	/// constant, not data-backed.
	private static let absoluteDropFloor = 300

	/// True if `newCount` looks like a destructive-edit regression against
	/// `oldCount`: at least a 10% relative drop AND at least a 300-count
	/// absolute drop, not a percentage alone.
	public static func isRegression(from oldCount: Int, to newCount: Int) -> Bool {
		guard oldCount > 0, newCount < oldCount else {
			return false
		}
		let percentDrop = Double(oldCount - newCount) / Double(oldCount)
		return percentDrop >= percentDropThreshold && (oldCount - newCount) >= absoluteDropFloor
	}
}
