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

	func show(in window: UIWindow, reasons: Set<ScreenTimeTracker.Reason>) {
		guard superview == nil else {
			message.text = Self.text(for: reasons)
			accessibilityLabel = message.text
			return
		}
		message.text = Self.text(for: reasons)
		accessibilityLabel = message.text
		frame = window.bounds
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		alpha = 0
		window.addSubview(self)
		UIView.animate(withDuration: 0.25) { self.alpha = 1 }
		UIAccessibility.post(notification: .screenChanged, argument: self)
	}

	private static func text(for reasons: Set<ScreenTimeTracker.Reason>) -> String {
		switch (reasons.contains(.limit), reasons.contains(.bedtime)) {
		case (true, true): return "Screen Time limit reached and bedtime has started"
		case (true, false): return "Screen Time limit reached"
		case (false, true): return "Bedtime has started"
		case (false, false): return "Screen Time limit reached"
		}
	}

	func hide() {
		UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
	}
}
