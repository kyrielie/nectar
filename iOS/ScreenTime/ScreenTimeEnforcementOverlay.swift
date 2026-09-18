import UIKit

final class ScreenTimeEnforcementOverlay: UIView {
	private let message = UILabel()

	override init(frame: CGRect = .zero) {
		super.init(frame: frame)
		backgroundColor = .black
		isAccessibilityElement = true
		accessibilityTraits = .staticText
		message.textColor = .white
		message.font = .preferredFont(forTextStyle: .title2)
		message.textAlignment = .center
		message.translatesAutoresizingMaskIntoConstraints = false
		addSubview(message)
		NSLayoutConstraint.activate([
			message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
			message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
			message.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func show(in window: UIWindow, reasons: Set<ScreenTimeTracker.Reason>, bedtimeEndMinutesFromMidnight: Int) {
		guard superview == nil else {
			message.text = Self.text(for: reasons, bedtimeEndMinutesFromMidnight: bedtimeEndMinutesFromMidnight)
			accessibilityLabel = message.text
			return
		}
		message.text = Self.text(for: reasons, bedtimeEndMinutesFromMidnight: bedtimeEndMinutesFromMidnight)
		accessibilityLabel = message.text
		frame = window.bounds
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		alpha = 0
		window.addSubview(self)
		UIView.animate(withDuration: 0.25) { self.alpha = 1 }
		UIAccessibility.post(notification: .screenChanged, argument: self)
	}

	/// Delegates to ScreenTimeTracker.lockoutStatus so this overlay and the
	/// ScreenTimeSettingsView status banner never drift out of sync again
	/// -- see that function's doc comment. Falls back to the pre-existing
	/// generic copy only for the reasons-empty case, which show(in:reasons:)
	/// is never actually called with in practice (SceneDelegate only shows
	/// the overlay once ScreenTimeTracker.activeReasons is non-empty).
	private static func text(for reasons: Set<ScreenTimeTracker.Reason>, bedtimeEndMinutesFromMidnight: Int) -> String {
		ScreenTimeTracker.lockoutStatus(for: reasons, bedtimeEndMinutesFromMidnight: bedtimeEndMinutesFromMidnight)?.message ?? "Screen Time limit reached"
	}

	func hide() {
		UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
	}
}
