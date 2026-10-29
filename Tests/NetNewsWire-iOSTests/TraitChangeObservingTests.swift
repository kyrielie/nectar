//
//  TraitChangeObservingTests.swift
//  NetNewsWire-iOSTests
//
//  `observeTraits` uses `registerForTraitChanges` on iOS 17+ and a hidden
//  `TraitChangeObserverView` on iOS 16. Like WebViewControllerAppearanceToggleTests,
//  these avoid live trait propagation: they drive the observer view's
//  `handleTraitChange(from:to:)` directly with explicit trait collections.
//
//  Not covered: the iOS 17 branch cannot run on an iOS 16 runtime, and the iOS 16
//  branch cannot be reached through the public API on a 17+ runtime (only its
//  decision logic and the installation shape are tested here).
//

import Testing
import UIKit
@testable import Nectar

@Suite struct TraitChangeObservingTests {

	@MainActor
	private final class Recorder {
		var previousCollections = [UITraitCollection]()
		var count: Int { previousCollections.count }
	}

	@MainActor
	private func makeObserver(_ traits: [ObservedTrait], recorder: Recorder) -> TraitChangeObserverView {
		TraitChangeObserverView(traits: traits) { previous in
			recorder.previousCollections.append(previous)
		}
	}

	private let light = UITraitCollection(userInterfaceStyle: .light)
	private let dark = UITraitCollection(userInterfaceStyle: .dark)

	@MainActor
	@Test func firesOnceWhenStyleChanges() {
		let recorder = Recorder()
		let observer = makeObserver([.userInterfaceStyle], recorder: recorder)

		observer.handleTraitChange(from: light, to: dark)

		#expect(recorder.count == 1)
		#expect(recorder.previousCollections.first?.userInterfaceStyle == .light)
	}

	@MainActor
	@Test func doesNotFireWhenStyleIsUnchanged() {
		let recorder = Recorder()
		let observer = makeObserver([.userInterfaceStyle], recorder: recorder)

		observer.handleTraitChange(from: dark, to: dark)

		#expect(recorder.count == 0)
	}

	@MainActor
	@Test func firesWhenPreviousIsUnspecifiedOnFirstAttach() {
		// A view first joining a window reports an empty previous collection.
		let recorder = Recorder()
		let observer = makeObserver([.userInterfaceStyle], recorder: recorder)

		observer.handleTraitChange(from: UITraitCollection(), to: dark)

		#expect(recorder.count == 1)
	}

	@MainActor
	@Test func contentSizeCategoryFiresOnlyWhenItChanges() {
		let recorder = Recorder()
		let observer = makeObserver([.preferredContentSizeCategory], recorder: recorder)
		let large = UITraitCollection(preferredContentSizeCategory: .large)
		let extraLarge = UITraitCollection(preferredContentSizeCategory: .extraLarge)

		observer.handleTraitChange(from: large, to: extraLarge)
		#expect(recorder.count == 1)

		observer.handleTraitChange(from: large, to: large)
		#expect(recorder.count == 1)
	}

	@MainActor
	@Test func observerIgnoresTraitsItWasNotAskedToWatch() {
		let recorder = Recorder()
		let observer = makeObserver([.preferredContentSizeCategory], recorder: recorder)

		observer.handleTraitChange(from: light, to: dark)

		#expect(recorder.count == 0)
	}

	@MainActor
	@Test func observerViewIsInertAndInvisibleToAccessibility() {
		let observer = makeObserver([.userInterfaceStyle], recorder: Recorder())

		#expect(observer.frame == .zero)
		#expect(!observer.isUserInteractionEnabled)
		#expect(!observer.isAccessibilityElement)
		#expect(observer.accessibilityElementsHidden)
	}

	@MainActor
	@Test func observeTraitsInstallsAnObserverViewOnlyBelowIOS17() {
		let host = UIView()
		host.observeTraits([.userInterfaceStyle]) { (_: UIView, _: UITraitCollection) in }

		if #available(iOS 17, *) {
			#expect(host.subviews.isEmpty)
		} else {
			#expect(host.subviews.count == 1)
			#expect(host.subviews.first is TraitChangeObserverView)
		}
	}
}
