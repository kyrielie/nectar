//
//  TraitChangeObserving.swift
//  NetNewsWire-iOS
//
//  `observeTraits(_:handler:)` is the one place the app watches trait changes.
//  `registerForTraitChanges` is iOS 17+, and `traitCollectionDidChange`, its
//  predecessor, is deprecated from 17, so this helper uses the first where it
//  exists and a hidden observer view (an override of the second) on iOS 16.
//
//  The handler shape matches `registerForTraitChanges`: it receives the owner
//  (typed by the closure's first parameter) and the previous trait collection.
//  The owner is passed in, never captured, so handlers don't retain it.
//
//  Call from `viewDidLoad` or later on a view controller: on iOS 16 the observer
//  is installed in the controller's view.
//

import UIKit

/// The traits `observeTraits` can watch.
enum ObservedTrait {
	case userInterfaceStyle
	case preferredContentSizeCategory

	/// True when `previous` and `current` differ in this trait.
	func differs(between previous: UITraitCollection, and current: UITraitCollection) -> Bool {
		switch self {
		case .userInterfaceStyle:
			return previous.userInterfaceStyle != current.userInterfaceStyle
		case .preferredContentSizeCategory:
			return previous.preferredContentSizeCategory != current.preferredContentSizeCategory
		}
	}

	@available(iOS 17, *)
	var traitType: UITrait {
		switch self {
		case .userInterfaceStyle:
			return UITraitUserInterfaceStyle.self
		case .preferredContentSizeCategory:
			return UITraitPreferredContentSizeCategory.self
		}
	}
}

extension UIView {

	/// Calls `handler` with this view and the previous trait collection when
	/// one of `traits` changes, including the first change when the view joins a
	/// window (the previous collection is then unspecified). Handlers that only
	/// care about a real change should compare against `traitCollection`, as the
	/// existing ones do.
	func observeTraits<Owner: UIView>(_ traits: [ObservedTrait], handler: @escaping @MainActor (Owner, UITraitCollection) -> Void) {
		if #available(iOS 17, *) {
			registerForTraitChanges(traits.map(\.traitType)) { (view: UIView, previousTraitCollection: UITraitCollection) in
				guard let owner = view as? Owner else {
					return
				}
				handler(owner, previousTraitCollection)
			}
		} else {
			installTraitObserverView(traits: traits) { [weak self] previousTraitCollection in
				guard let owner = self as? Owner else {
					return
				}
				handler(owner, previousTraitCollection)
			}
		}
	}

	fileprivate func installTraitObserverView(traits: [ObservedTrait], onChange: @escaping @MainActor (UITraitCollection) -> Void) {
		addSubview(TraitChangeObserverView(traits: traits, onChange: onChange))
	}
}

extension UIViewController {

	/// View controller form of `observeTraits`. Registers on the controller on
	/// iOS 17+; on iOS 16 installs the observer in `view`, which loads it.
	func observeTraits<Owner: UIViewController>(_ traits: [ObservedTrait], handler: @escaping @MainActor (Owner, UITraitCollection) -> Void) {
		if #available(iOS 17, *) {
			registerForTraitChanges(traits.map(\.traitType)) { (viewController: UIViewController, previousTraitCollection: UITraitCollection) in
				guard let owner = viewController as? Owner else {
					return
				}
				handler(owner, previousTraitCollection)
			}
		} else {
			view.installTraitObserverView(traits: traits) { [weak self] previousTraitCollection in
				guard let owner = self as? Owner else {
					return
				}
				handler(owner, previousTraitCollection)
			}
		}
	}
}

/// The iOS 16 mechanism: a zero-size, non-interactive subview that inherits
/// the owner's traits and reports changes through `traitCollectionDidChange`.
/// Internal (not private) so tests can drive `handleTraitChange(from:to:)`.
final class TraitChangeObserverView: UIView {

	private let traits: [ObservedTrait]
	private let onChange: @MainActor (UITraitCollection) -> Void

	init(traits: [ObservedTrait], onChange: @escaping @MainActor (UITraitCollection) -> Void) {
		self.traits = traits
		self.onChange = onChange
		super.init(frame: .zero)
		isUserInteractionEnabled = false
		isAccessibilityElement = false
		accessibilityElementsHidden = true
		backgroundColor = .clear
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	/// Calls `onChange` with `previous` when any observed trait differs
	/// between `previous` and `current`.
	func handleTraitChange(from previous: UITraitCollection, to current: UITraitCollection) {
		guard traits.contains(where: { $0.differs(between: previous, and: current) }) else {
			return
		}
		onChange(previous)
	}

	// Deprecated from iOS 17, which is why the iOS 17+ path doesn't use it. It
	// is the only trait callback available to a UIView on iOS 16. No super call:
	// this is a direct UIView subclass and the base implementation does nothing
	// (Unverified), and calling it would warn at a 17+ target.
	@available(iOS, introduced: 16.0, deprecated: 17.0, message: "iOS 16 path only; iOS 17+ uses registerForTraitChanges")
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		handleTraitChange(from: previousTraitCollection ?? UITraitCollection(), to: traitCollection)
	}
}
