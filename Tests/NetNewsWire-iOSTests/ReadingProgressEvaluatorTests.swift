//
//  ReadingProgressEvaluatorTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for ReadingProgressEvaluator, the pure math WebViewController's
//  scrollPositionDidChange used to do inline (completion fraction, the
//  "is this article done" threshold, page-counter numbers). WebViewController
//  itself can't be instantiated here -- see
//  WebViewControllerAppearanceToggleTests.swift's header comment -- so this
//  targets the extracted, UIKit-free evaluator directly, the same pattern
//  ProvisionalAO3StubDetectionTests uses.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct ReadingProgressEvaluatorTests {

	private static func sample(scrollY: Double, scrollHeight: Double, viewportHeight: Double) throws -> ReadingProgressSample {
		try #require(ReadingProgressEvaluator.sample(scrollY: scrollY, scrollHeight: scrollHeight, viewportHeight: viewportHeight))
	}

	// MARK: - Threshold

	@Test func thresholdIsNinetyNinePercent() {
		// Pinned on purpose: read-marking and Reading Stats completion both
		// key off this one constant (reading-progress.md). Changing it is a
		// product decision, so make the change visible in review.
		#expect(ReadingProgressEvaluator.completionThreshold == 0.99)
	}

	@Test func isComplete_atAndAroundTheThreshold() {
		#expect(ReadingProgressEvaluator.isComplete(ReadingProgressEvaluator.completionThreshold))
		#expect(ReadingProgressEvaluator.isComplete(1.0))
		#expect(!ReadingProgressEvaluator.isComplete(0.9899))
		#expect(!ReadingProgressEvaluator.isComplete(0))
	}

	@Test func sampleAtThreshold_isComplete_andJustBelowIsNot() throws {
		// (9000 + 900) / 10000 == 0.99; one pixel less is 0.9899.
		let atThreshold = try Self.sample(scrollY: 9000, scrollHeight: 10_000, viewportHeight: 900)
		let justBelow = try Self.sample(scrollY: 8999, scrollHeight: 10_000, viewportHeight: 900)
		#expect(atThreshold.isComplete)
		#expect(!justBelow.isComplete)
	}

	// MARK: - Fraction

	@Test func fraction_atTopOfLongDocument_isViewportOverHeight() throws {
		let s = try Self.sample(scrollY: 0, scrollHeight: 3000, viewportHeight: 1000)
		#expect(abs(s.rawFraction - (1.0 / 3.0)) < 1e-9)
		#expect(s.fraction == s.rawFraction)
		#expect(!s.isComplete)
	}

	@Test func documentThatFitsInViewport_readsAsComplete() throws {
		// A short chapter: the whole document is visible on open. Today this
		// marks the article read on the first accepted sample; this test pins
		// that existing behavior rather than endorsing it.
		let exactFit = try Self.sample(scrollY: 0, scrollHeight: 800, viewportHeight: 800)
		let shorterThanViewport = try Self.sample(scrollY: 0, scrollHeight: 500, viewportHeight: 800)
		#expect(exactFit.isComplete)
		#expect(exactFit.fraction == 1)
		#expect(shorterThanViewport.rawFraction > 1)
		#expect(shorterThanViewport.fraction == 1)
		#expect(shorterThanViewport.isComplete)
	}

	@Test func overscrollPastTop_clampsFractionToZero() throws {
		let s = try Self.sample(scrollY: -1500, scrollHeight: 3000, viewportHeight: 1000)
		#expect(s.rawFraction < 0)
		#expect(s.fraction == 0)
		#expect(!s.isComplete)
	}

	@Test func percentRounded_roundsToNearestWholePercent() throws {
		let half = try Self.sample(scrollY: 0, scrollHeight: 2000, viewportHeight: 1000)
		let full = try Self.sample(scrollY: 1000, scrollHeight: 2000, viewportHeight: 1000)
		let third = try Self.sample(scrollY: 0, scrollHeight: 3000, viewportHeight: 1000)
		#expect(half.percentRounded == 50)
		#expect(full.percentRounded == 100)
		#expect(third.percentRounded == 33)
	}

	// MARK: - Rejected input

	@Test func sample_isNil_forNonPositiveOrNonFiniteInput() {
		#expect(ReadingProgressEvaluator.sample(scrollY: 0, scrollHeight: 0, viewportHeight: 800) == nil)
		#expect(ReadingProgressEvaluator.sample(scrollY: 0, scrollHeight: -1, viewportHeight: 800) == nil)
		#expect(ReadingProgressEvaluator.sample(scrollY: 0, scrollHeight: .nan, viewportHeight: 800) == nil)
		#expect(ReadingProgressEvaluator.sample(scrollY: 0, scrollHeight: .infinity, viewportHeight: 800) == nil)
		#expect(ReadingProgressEvaluator.sample(scrollY: .nan, scrollHeight: 3000, viewportHeight: 800) == nil)
		#expect(ReadingProgressEvaluator.sample(scrollY: 0, scrollHeight: 3000, viewportHeight: .infinity) == nil)
	}

	// MARK: - Page counter

	struct PageCase: Sendable {
		let scrollY: Double
		let scrollHeight: Double
		let viewportHeight: Double
		let current: Int
		let total: Int
	}

	static let pageCases: [PageCase] = [
		PageCase(scrollY: 0, scrollHeight: 3000, viewportHeight: 1000, current: 1, total: 3),
		PageCase(scrollY: 1000, scrollHeight: 3000, viewportHeight: 1000, current: 2, total: 3),
		PageCase(scrollY: 2000, scrollHeight: 3000, viewportHeight: 1000, current: 3, total: 3),
		// Partial last page rounds the total up.
		PageCase(scrollY: 0, scrollHeight: 2500, viewportHeight: 1000, current: 1, total: 3),
		// Current page is capped at the total (2500 / 1000 rounds to 3, +1 == 4).
		PageCase(scrollY: 2500, scrollHeight: 3000, viewportHeight: 1000, current: 3, total: 3),
		// Document shorter than the viewport is one page.
		PageCase(scrollY: 0, scrollHeight: 500, viewportHeight: 1000, current: 1, total: 1),
		// Rubber-band overscroll past the top never shows page 0.
		PageCase(scrollY: -700, scrollHeight: 3000, viewportHeight: 1000, current: 1, total: 3)
	]

	@Test(arguments: ReadingProgressEvaluatorTests.pageCases)
	func pageCounter_matchesExpectedPages(_ testCase: PageCase) throws {
		let s = try Self.sample(scrollY: testCase.scrollY, scrollHeight: testCase.scrollHeight, viewportHeight: testCase.viewportHeight)
		let page = try #require(ReadingProgressEvaluator.pageCounter(for: s))
		#expect(page.current == testCase.current)
		#expect(page.total == testCase.total)
	}

	@Test func pageCounter_isNil_whenViewportHeightIsNotPositive() throws {
		// Regression guard: scrollHeight / 0 is infinity and Int(infinity)
		// traps, which the inline page-counter code used to be exposed to.
		let zero = try Self.sample(scrollY: 0, scrollHeight: 3000, viewportHeight: 0)
		let negative = try Self.sample(scrollY: 0, scrollHeight: 3000, viewportHeight: -10)
		#expect(ReadingProgressEvaluator.pageCounter(for: zero) == nil)
		#expect(ReadingProgressEvaluator.pageCounter(for: negative) == nil)
	}
}
