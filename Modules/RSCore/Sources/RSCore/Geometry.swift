//
//  Geometry.swift
//  RSCore
//
//  Created by Nate Weaver on 2020-01-01.
//  Copyright © 2020 Ranchero Software, LLC. All rights reserved.
//

import Foundation

public extension CGRect {

	/// Centers a rectangle vertically in another rectangle.
	///
	/// - Parameter containerRect: The rectangle in which to be centered.
	/// - Returns: A new rectangle, cenetered vertically in `containerRect`,
	///   with the same size as the source rectangle.
	func centeredVertically(in containerRect: CGRect) -> CGRect {
		var r = self
		r.origin.y = containerRect.midY - (r.height / 2.0)
		r = r.integral
		r.size = self.size
		return r
	}

	/// Centers a rectangle horizontally in another rectangle.
	///
	/// - Parameter containerRect: The rectangle in which to be centered.
	/// - Returns: A new rectangle, cenetered horizontally in `containerRect`,
	///   with the same size as the source rectangle.
	func centeredHorizontally(in containerRect: CGRect) -> CGRect {
		var r = self
		r.origin.x = containerRect.midX - (r.width / 2.0)
		r = r.integral
		r.size = self.size
		return r
	}

	/// Centers a rectangle in another rectangle.
	/// 
	/// - Parameter containerRect: The rectangle in which to be centered.
	/// - Returns: A new rectangle, cenetered both horizontally and vertically
	///   in `containerRect`, with the same size as the source rectangle.
	func centered(in containerRect: CGRect) -> CGRect {
		self.centeredHorizontally(in: self.centeredVertically(in: containerRect))
	}

	/// Clamps `self` to the nearest point still inside `bounds`, preserving
	/// width/height, so a caller anchoring UI to a rect (e.g. a popover's
	/// sourceRect) still gets a sensible-sized anchor even when the rect
	/// as computed doesn't overlap `bounds` at all. Pulled out of
	/// WebViewController.presentHighlightColorPopover's defensive fix for
	/// the fullscreen safe-area popover bug (see docs/annotations.md's
	/// "Manual edit UI" and the text-replacement feature's own
	/// implementation plan, "Fullscreen popover safe-area bug") so it's
	/// directly testable without a UIViewController/
	/// UIPopoverPresentationController in the loop -- see
	/// CGRectClampedToBoundsTests in this module's own test target.
	///
	/// Only meaningful when `self` doesn't already overlap `bounds`;
	/// applying it to an already-overlapping rect can still shift it
	/// (whenever bounds is narrower/shorter than self), so callers should
	/// check for the non-overlapping case first (as
	/// presentHighlightColorPopover does) rather than calling this
	/// unconditionally.
	func clamped(toBounds bounds: CGRect) -> CGRect {
		let clampedX = min(max(origin.x, bounds.minX), bounds.maxX - width)
		let clampedY = min(max(origin.y, bounds.minY), bounds.maxY - height)
		return CGRect(x: clampedX, y: clampedY, width: width, height: height)
	}
}

public extension Array where Element == CGRect {
	func maxY() -> CGFloat {
		var y: CGFloat = 0.0
		for r in self {
			y = Swift.max(y, r.maxY)
		}
		return y
	}
}
