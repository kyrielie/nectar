//
//  CGRectClampedToBoundsTests.swift
//  RSCoreTests
//

import Testing
import Foundation
@testable import RSCore

/// Coverage for CGRect.clamped(toBounds:), extracted from
/// WebViewController.presentHighlightColorPopover's defensive fix for
/// the fullscreen safe-area popover bug (see docs/annotations.md's
/// "Manual edit UI" and the text-replacement feature's own
/// implementation plan, "Fullscreen popover safe-area bug"). Every case
/// here is hand-traced against the exact arithmetic that used to live
/// as WebViewController's own private clampedToBounds(_:bounds:) --
/// this is a straight extraction, not new behavior.
@Suite struct CGRectClampedToBoundsTests {

	private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

	@Test("a rect entirely above bounds (negative y, the reported symptom's actual shape) clamps down to bounds' top edge")
	func rectAboveBoundsClampsToTopEdge() {
		let rect = CGRect(x: 100, y: -50, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == CGRect(x: 100, y: 0, width: 40, height: 20))
	}

	@Test("a rect entirely below bounds clamps up to bounds' bottom edge, preserving height")
	func rectBelowBoundsClampsToBottomEdge() {
		let rect = CGRect(x: 100, y: 850, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == CGRect(x: 100, y: 780, width: 40, height: 20))
	}

	@Test("a rect entirely left of bounds clamps right to bounds' left edge")
	func rectLeftOfBoundsClampsToLeftEdge() {
		let rect = CGRect(x: -100, y: 100, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == CGRect(x: 0, y: 100, width: 40, height: 20))
	}

	@Test("a rect entirely right of bounds clamps left to bounds' right edge, preserving width")
	func rectRightOfBoundsClampsToRightEdge() {
		let rect = CGRect(x: 500, y: 100, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == CGRect(x: 360, y: 100, width: 40, height: 20))
	}

	@Test("a rect off both axes at once (top-left) clamps on both, independently")
	func rectOffBothAxesClampsOnBoth() {
		let rect = CGRect(x: -100, y: -50, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == CGRect(x: 0, y: 0, width: 40, height: 20))
	}

	@Test("a rect already fully inside bounds is unchanged")
	func rectAlreadyInsideBoundsIsUnchanged() {
		let rect = CGRect(x: 100, y: 100, width: 40, height: 20)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped == rect)
	}

	@Test("width/height are always preserved, even after clamping")
	func widthAndHeightArePreserved() {
		let rect = CGRect(x: -100, y: -50, width: 144, height: 56)
		let clamped = rect.clamped(toBounds: bounds)
		#expect(clamped.width == 144)
		#expect(clamped.height == 56)
	}
}
