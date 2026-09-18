import UIKit

final class ScreenTimeBreakView: UIView {
	private let message = UILabel()
	private let continueButton = UIButton(type: .system)

	override init(frame: CGRect = .zero) {
		super.init(frame: frame)
		backgroundColor = .black
		isAccessibilityElement = false

		message.text = "Take a break"
		message.textColor = .white
		message.font = .preferredFont(forTextStyle: .title2)
		message.textAlignment = .center
		message.translatesAutoresizingMaskIntoConstraints = false
		message.isAccessibilityElement = true
		message.accessibilityTraits = .staticText

		continueButton.setTitle("Continue Reading", for: .normal)
		continueButton.tintColor = .white
		continueButton.translatesAutoresizingMaskIntoConstraints = false
		continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

		addSubview(message)
		addSubview(continueButton)
		NSLayoutConstraint.activate([
			message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
			message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
			message.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
			continueButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			continueButton.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 24)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	@objc private func continueTapped() {
		ScreenTimeTracker.shared.dismissBreak()
	}

	func show(in window: UIWindow) {
		guard superview == nil else { return }
		frame = window.bounds
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		alpha = 0
		window.addSubview(self)
		UIView.animate(withDuration: 0.25) { self.alpha = 1 }
		UIAccessibility.post(notification: .screenChanged, argument: message)
	}

	func hide() {
		UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
	}
}
