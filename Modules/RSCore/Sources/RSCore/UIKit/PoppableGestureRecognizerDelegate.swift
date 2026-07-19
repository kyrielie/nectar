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

	/// Optional additional gate on top of the `viewControllers.count > 1`
	/// check below. Set by callers (e.g. ArticleViewController) that need to
	/// block the interactive pop gesture under some app-specific condition
	/// -- RSCore itself has no notion of what that condition is, so this is
	/// left as a closure rather than RSCore depending on an app-level type.
	public var isAdditionallyBlocked: (() -> Bool)?

	public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let stackCount = navigationController?.viewControllers.count ?? 0
        guard stackCount > 1 else {
			print("PoppableGestureRecognizerDelegate: gestureRecognizerShouldBegin -> false (viewControllers.count=\(stackCount), navigationController is \(navigationController == nil ? "nil" : "set"))")
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
