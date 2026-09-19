import UIKit

final class ScreenTimeEnforcementOverlay: UIView {
	private let iconView = UIImageView()
	private let message = UILabel()
	private let stack = UIStackView()

	override init(frame: CGRect = .zero) {
		super.init(frame: frame)
		backgroundColor = .black
		isAccessibilityElement = true
		accessibilityTraits = .staticText

		iconView.tintColor = .white
		iconView.contentMode = .scaleAspectFit
		iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)

		message.textColor = .white
		message.font = .preferredFont(forTextStyle: .title2)
		message.textAlignment = .center
		// Was unset (defaults to 1 line), which truncated/clipped rather
		// than wrapped -- the two-reason message ("It's bedtime, and
		// today's reading time is up too...") is long enough on smaller
		// screens to need more than one line.
		message.numberOfLines = 0

		stack.axis = .vertical
		// .fill, not .center: a vertical UIStackView's alignment governs
		// cross-axis (horizontal) sizing of arranged subviews. .center
		// leaves each subview at its own intrinsic width and just centers
		// it -- for a UILabel with numberOfLines = 0, that intrinsic width
		// is whatever fits the text on one line, so the label never
		// actually gets narrow enough to wrap and instead overflows past
		// the stack's (and screen's) bounds. .fill stretches the label to
		// the stack's already-constrained width, which is what forces the
		// wrap. iconView is unaffected -- scaleAspectFit keeps the symbol
		// undistorted regardless of the frame width it's stretched into.
		stack.alignment = .fill
		stack.spacing = 16
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.addArrangedSubview(iconView)
		stack.addArrangedSubview(message)
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	func show(in window: UIWindow, reasons: Set<ScreenTimeTracker.Reason>, bedtimeEndMinutesFromMidnight: Int) {
		apply(reasons: reasons, bedtimeEndMinutesFromMidnight: bedtimeEndMinutesFromMidnight)
		guard superview == nil else { return }
		frame = window.bounds
		autoresizingMask = [.flexibleWidth, .flexibleHeight]
		alpha = 0
		window.addSubview(self)
		UIView.animate(withDuration: 0.25) { self.alpha = 1 }
		UIAccessibility.post(notification: .screenChanged, argument: self)
	}

	/// Delegates to ScreenTimeTracker.lockoutStatus for both the icon and
	/// the message, so this overlay and the ScreenTimeSettingsView status
	/// banner can't drift out of sync with each other -- see that
	/// function's doc comment. Falls back to the pre-existing generic
	/// copy (no icon) only for the reasons-empty case, which
	/// show(in:reasons:bedtimeEndMinutesFromMidnight:) is never actually
	/// called with in practice (SceneDelegate only shows the overlay once
	/// ScreenTimeTracker.activeReasons is non-empty).
	private func apply(reasons: Set<ScreenTimeTracker.Reason>, bedtimeEndMinutesFromMidnight: Int) {
		let status = ScreenTimeTracker.lockoutStatus(for: reasons, bedtimeEndMinutesFromMidnight: bedtimeEndMinutesFromMidnight)
		message.text = status?.message ?? "Screen Time limit reached"
		iconView.image = status.map { UIImage(systemName: $0.systemImageName) } ?? nil
		accessibilityLabel = message.text
	}

	func hide() {
		UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
	}
}
