import UIKit

/// A minimal pie-fill circle mirroring Apple's own countdown-timer glyph
/// (Clock app's Timer tab, Reminders' countdown icon): a plain circle
/// outline with a filled pie wedge sweeping clockwise from 12 o'clock,
/// one flat color, no gradient, no hand, no translucency. Sits on the
/// trailing edge of WebViewController's notchCoverView, mirroring
/// pageCounterLabel's leading placement.
///
/// Deliberately Core Graphics (draw(_:)) rather than CAShapeLayer: at
/// this size (~18pt) the difference is invisible either way, but
/// draw(_:) is the simplest correct implementation for a shape that
/// only needs to redraw when `fraction` changes, not animate
/// continuously -- and it renders the outline and the pie's edge as
/// actual vector paths at full display resolution, so neither has the
/// soft/fuzzy edge a CSS conic-gradient approximation can show.
final class ScreenTimePieIndicatorView: UIView {

	/// 0 = empty, 1 = full. Values outside 0...1 are clamped before
	/// comparing/storing, so out-of-range writes below don't cause a
	/// spurious redraw when the clamped value hasn't actually changed.
	var fraction: CGFloat {
		get { storedFraction }
		set {
			let clamped = min(max(newValue, 0), 1)
			guard clamped != storedFraction else { return }
			storedFraction = clamped
			setNeedsDisplay()
		}
	}
	private var storedFraction: CGFloat = 0

	override init(frame: CGRect = .zero) {
		super.init(frame: frame)
		backgroundColor = .clear
		isOpaque = false
		contentMode = .redraw
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func tintColorDidChange() {
		super.tintColorDidChange()
		setNeedsDisplay()
	}

	override func draw(_ rect: CGRect) {
		let lineWidth: CGFloat = 1.5
		let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
		let center = CGPoint(x: bounds.midX, y: bounds.midY)

		let outline = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
		outline.lineWidth = lineWidth
		tintColor.setStroke()
		outline.stroke()

		guard storedFraction > 0 else { return }
		// -pi/2 is 12 o'clock; sweeping clockwise matches both a clock
		// face and the pie-countdown glyphs this is modeled on. The
		// fill radius is inset by half the stroke width so the wedge's
		// curved edge lands directly under the outline stroke rather
		// than stopping short of it (a visible gap) or drawing past it
		// (fighting the stroke's own anti-aliasing).
		let fillRadius = radius - lineWidth / 2
		let startAngle = -CGFloat.pi / 2
		let endAngle = startAngle + storedFraction * 2 * .pi
		let pie = UIBezierPath()
		pie.move(to: center)
		pie.addArc(withCenter: center, radius: fillRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
		pie.close()
		tintColor.setFill()
		pie.fill()
	}
}
