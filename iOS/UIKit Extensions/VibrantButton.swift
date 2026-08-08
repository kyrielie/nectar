//
//  VibrantButton.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 10/22/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit

final class VibrantButton: UIButton {

	@IBInspectable var backgroundHighlightColor: UIColor = Assets.Colors.secondaryAccent

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		updateVibrantTextColor()
		let disabledColor = Assets.Colors.secondaryAccent.withAlphaComponent(0.5)
		setTitleColor(disabledColor, for: .disabled)
	}

	// commonInit() runs from init(), before this button is in a window, so
	// traitCollection there reflects the default/unspecified trait
	// collection rather than the one this button will actually be drawn
	// with -- re-resolve once the button joins a real window/view hierarchy.
	override func didMoveToWindow() {
		super.didMoveToWindow()
		updateVibrantTextColor()
	}

	private func updateVibrantTextColor() {
		setTitleColor(Assets.Colors.vibrantText(for: traitCollection), for: .highlighted)
	}

	override var isHighlighted: Bool {
		didSet {
			backgroundColor = isHighlighted ? backgroundHighlightColor : nil
		}
	}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = true
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
        super.touchesCancelled(touches, with: event)
    }

}
