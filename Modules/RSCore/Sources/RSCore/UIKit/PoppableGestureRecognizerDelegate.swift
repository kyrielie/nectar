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
import os

public final class PoppableGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    public weak var navigationController: UINavigationController?

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PoppableGestureRecognizerDelegate", category: "PoppableGestureRecognizerDelegate")

	/// Optional override for whether there's a logical "back" to go to.
	/// Falls back to `navigationController.viewControllers.count > 1` when
	/// nil. Callers whose navigation controller doesn't reflect the true
	/// navigation depth -- e.g. a UISplitViewController column's own nested
	/// navigation controller, which only ever contains the visible column's
	/// content even though other columns are logically "behind" it -- should
	/// set this to their own notion of navigability instead.
	public var canGoBack: (() -> Bool)?

	public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		let hasBack = canGoBack?() ?? ((navigationController?.viewControllers.count ?? 0) > 1)
		Self.logger.debug("gestureRecognizerShouldBegin: gestureRecognizer=\(String(describing: gestureRecognizer), privacy: .public) gestureRecognizer.isEnabled=\(gestureRecognizer.isEnabled, privacy: .public) hasBack=\(hasBack, privacy: .public) -> returning \(hasBack, privacy: .public)")
		return hasBack
    }

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return true
    }

	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		return otherGestureRecognizer is UIPanGestureRecognizer
	}
}

#endif
