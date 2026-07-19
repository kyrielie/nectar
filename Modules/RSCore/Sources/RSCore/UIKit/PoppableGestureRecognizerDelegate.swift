//
//  PoppableGestureRecognizerDelegate.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 11/18/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//
// https://stackoverflow.com/a/41248703

#if os(iOS)

import UIKit

public final class PoppableGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    public weak var navigationController: UINavigationController?

	/// Optional additional gate on top of the "is there something to pop
	/// back to" check below. Set by callers (e.g. ArticleViewController) that
	/// need to block the interactive pop gesture under some app-specific
	/// condition -- RSCore itself has no notion of what that condition is,
	/// so this is left as a closure rather than RSCore depending on an
	/// app-level type.
	public var isAdditionallyBlocked: (() -> Bool)?

	/// Optional override for whether there's a logical "back" to go to.
	/// Falls back to `navigationController.viewControllers.count > 1` when
	/// nil. Callers whose navigation controller doesn't reflect the true
	/// navigation depth -- e.g. a UISplitViewController column's own nested
	/// navigation controller, which only ever contains the visible column's
	/// content even though other columns are logically "behind" it -- should
	/// set this to their own notion of navigability instead.
	public var canGoBack: (() -> Bool)?

	public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		let stackCount = navigationController?.viewControllers.count ?? 0
		let hasBack = canGoBack?() ?? (stackCount > 1)
		guard hasBack else {
			print("PoppableGestureRecognizerDelegate: gestureRecognizerShouldBegin -> false (viewControllers.count=\(stackCount), canGoBack override \(canGoBack == nil ? "is nil" : "returned false"), navigationController is \(navigationController == nil ? "nil" : "set"))")
			return false
		}
		let blocked = isAdditionallyBlocked?() ?? false
		print("PoppableGestureRecognizerDelegate: gestureRecognizerShouldBegin -> \(!blocked) (isAdditionallyBlocked closure \(isAdditionallyBlocked == nil ? "is nil" : "returned \(blocked)"))")
		return !blocked
    }

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
    }

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		if otherGestureRecognizer is UIPanGestureRecognizer {
			return true
		}
		return false
	}
}

#endif
