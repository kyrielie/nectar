//
//  AO3RegressionThresholdTests.swift
//  ArticlesTests
//
//  Nectar remediation plan, Part 1.2: direct coverage of
//  AO3RegressionThreshold.isRegression (AO3RegressionThreshold.swift:42),
//  Task 8's core destructive-update-detection mechanism, shared by
//  AO3ChapterFetcher's content-level guard and Article+Database's
//  metadata-level watch. Previously exercised only incidentally through
//  ArticlesTableUpdateTests/ClearContentHTMLTests -- this is the direct
//  unit coverage of the threshold logic itself, including both boundary
//  values (10% relative drop AND 300-count absolute drop, both required).
//

import Foundation
import Testing

@testable import Articles

@Suite("AO3RegressionThreshold.isRegression")
struct AO3RegressionThresholdTests {

	// A drop that clears both the 10% relative and 300-count absolute
	// floors is a regression.
	@Test("a large drop past both thresholds is flagged")
	func largeDropIsRegression() {
		#expect(AO3RegressionThreshold.isRegression(from: 5000, to: 100))
	}

	// An increase, of any size, is never a regression.
	@Test("an increase is never flagged, regardless of magnitude")
	func increaseIsNeverRegression() {
		#expect(!AO3RegressionThreshold.isRegression(from: 1000, to: 1001))
		#expect(!AO3RegressionThreshold.isRegression(from: 1000, to: 50000))
	}

	// A drop under the 10% relative floor, even with a large absolute
	// count, is an ordinary copy-edit, not a regression.
	@Test("a small relative drop under the percentage floor is not flagged")
	func smallRelativeDropIsNotRegression() {
		// 10,000 -> 9,500 is a 5% drop (500-count absolute, clears the
		// absolute floor) but doesn't clear the 10% relative floor.
		#expect(!AO3RegressionThreshold.isRegression(from: 10_000, to: 9_500))
	}

	// A drop that clears the percentage floor but not the absolute floor
	// (a short work trimmed by a meaningful percentage but a trivial
	// word count) is not a regression -- this is the exact false-positive
	// case the absolute floor exists to prevent, per the type's own doc
	// comment.
	@Test("a large relative drop under the absolute-count floor is not flagged")
	func smallAbsoluteDropIsNotRegression() {
		// 1,000 -> 800 is a 20% relative drop (clears the percentage
		// floor) but only a 200-count absolute drop (under the 300 floor).
		#expect(!AO3RegressionThreshold.isRegression(from: 1_000, to: 800))
	}

	// Exact boundary values on both sides. Read directly against the
	// implementation (AO3RegressionThreshold.swift:47): both comparisons
	// are inclusive (`>=`), so a drop landing exactly on either threshold
	// counts as a regression, not just strictly past it.
	@Test("relative-drop boundary: exactly 10% qualifies (inclusive), just under it does not")
	func relativeDropBoundary() {
		// 10,000 -> 9,000 is exactly a 10% relative drop and a 1,000-count
		// absolute drop (comfortably clears the absolute floor), isolating
		// the relative-threshold comparison specifically.
		#expect(AO3RegressionThreshold.isRegression(from: 10_000, to: 9_000))
		// 10,000 -> 9,001 is a 9.99% relative drop -- just under the floor.
		#expect(!AO3RegressionThreshold.isRegression(from: 10_000, to: 9_001))
	}

	@Test("absolute-drop boundary: exactly 300 qualifies (inclusive), just under it does not")
	func absoluteDropBoundary() {
		// 2,000 -> 1,700 is a 15% relative drop (clears the 10% floor
		// comfortably) and exactly a 300-count absolute drop, isolating
		// the absolute-threshold comparison specifically.
		#expect(AO3RegressionThreshold.isRegression(from: 2_000, to: 1_700))
		// 2,000 -> 1,701 is a 299-count absolute drop -- just under the floor.
		#expect(!AO3RegressionThreshold.isRegression(from: 2_000, to: 1_701))
	}

	// oldCount <= 0 is a degenerate/never-set-before case, not a regression.
	@Test("a non-positive oldCount is never flagged")
	func nonPositiveOldCountIsNotRegression() {
		#expect(!AO3RegressionThreshold.isRegression(from: 0, to: 100))
	}
}
