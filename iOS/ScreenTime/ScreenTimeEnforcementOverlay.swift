import UIKit

final class ScreenTimeEnforcementOverlay: UIView {
	private let message = UILabel()

	override init(frame: CGRect = .zero) {
		super.init(frame: frame)
		backgroundColor = .black
		isAccessibilityElement = true
		accessibilityTraits = .staticText
		accessibilityLabel = "Screen Time limit reached"
		message.text = "Screen Time limit reached"
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

	func show(in window: UIWindow) {
		guard superview == nil else { return }
		frame = window.bounds
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		alpha = 0
		window.addSubview(self)
		UIView.animate(withDuration: 0.25) { self.alpha = 1 }
		UIAccessibility.post(notification: .screenChanged, argument: self)
	}

	func hide() {
		UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
	}
}
