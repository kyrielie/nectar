//
//  ReadingProgressEvaluator.swift
//  NetNewsWire
//
//  The pure math behind the reader's per-scroll-sample progress: turning a raw
//  (scrollY, scrollHeight, viewport height) reading from the article web view
//  into a completion fraction, the "is this article done" decision, and the
//  page-counter numbers. No UIKit or WebKit, so it can be unit-tested without
//  a live WKWebView (see ReadingProgressEvaluatorTests), the same reason
//  WebViewController.isProvisionalAO3Stub(_:) is a static function.
//
//  What this deliberately does NOT own: the guards that decide whether a
//  sample is trustworthy at all (the 33554432 sentinel, in-flight scroll
//  restore, shrinking scrollHeight, provisional AO3 stub content), and what
//  to do with the result (persist, mark read, credit Reading Stats, update
//  the page counter). Those stay in WebViewController.scrollPositionDidChange
//  because they depend on its private state. See reading-progress.md.
//

import Foundation

/// One accepted scroll reading, in CSS pixels.
struct ReadingProgressSample: Equatable, Sendable {
	let scrollY: Double
	let scrollHeight: Double
	let viewportHeight: Double

	/// Bottom edge of the viewport as a fraction of the whole document. Not
	/// clamped: a document shorter than the viewport reads above 1, and
	/// rubber-band overscroll past the top can read below 0.
	var rawFraction: Double {
		(scrollY + viewportHeight) / scrollHeight
	}

	/// `rawFraction` clamped to 0...1. This is the value that is persisted as
	/// reading progress and shown in the page counter.
	var fraction: Double {
		min(max(rawFraction, 0), 1)
	}

	/// True once the bottom of the viewport has reached the completion
	/// threshold. Drives both marking the article read and, via
	/// `ReadingStatsTracker`, crediting a completed work.
	var isComplete: Bool {
		ReadingProgressEvaluator.isComplete(fraction)
	}

	/// `fraction` as a whole percentage, rounded to nearest, for the
	/// percentage page counter.
	var percentRounded: Int {
		Int((fraction * 100).rounded())
	}
}

enum ReadingProgressEvaluator {

	/// The single definition of "a work is complete": the fraction of the
	/// document at which it is marked read AND counted as completed in
	/// Reading Stats. `WebViewController` and `ReadingStatsTracker` both go
	/// through `isComplete(_:)` so the two cannot drift apart. Changing this
	/// changes read-state behavior and stats together (see reading-progress.md).
	static let completionThreshold = 0.99

	static func isComplete(_ fraction: Double) -> Bool {
		fraction >= completionThreshold
	}

	/// Returns nil when the reading can't describe a document: a
	/// non-positive `scrollHeight` (nothing rendered yet) or any non-finite
	/// input. Non-finite values are rejected here so nothing downstream can
	/// hit a trapping Double-to-Int conversion.
	static func sample(scrollY: Double, scrollHeight: Double, viewportHeight: Double) -> ReadingProgressSample? {
		guard scrollHeight > 0, scrollHeight.isFinite, scrollY.isFinite, viewportHeight.isFinite else {
			return nil
		}
		return ReadingProgressSample(scrollY: scrollY, scrollHeight: scrollHeight, viewportHeight: viewportHeight)
	}

	/// Page-count display numbers ("3/12"). Nil when the viewport height is
	/// not positive: dividing by it would produce infinity or NaN, and
	/// converting either to Int traps. `current` is always within 1...`total`.
	static func pageCounter(for sample: ReadingProgressSample) -> (current: Int, total: Int)? {
		guard sample.viewportHeight > 0 else {
			return nil
		}
		let total = max(1, Int((sample.scrollHeight / sample.viewportHeight).rounded(.up)))
		let current = min(total, max(1, Int((sample.scrollY / sample.viewportHeight).rounded()) + 1))
		return (current, total)
	}
}
