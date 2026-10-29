//
//  TimelineCustomizerCell.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 21/08/2025.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import UIKit

enum SliderConfiguration {
	case numberOfLines
	case tagDisplayMode
}

final class TimelineCustomizerCell: UICollectionViewCell {
	@IBOutlet var slider: TickMarkSlider!

	private var segmentedControl: UISegmentedControl?

	var sliderConfiguration: SliderConfiguration! {
		didSet {
			// Settings.storyboard binds the slider's thumbTintColor to the static
			// primaryAccentColor asset, which never changes -- setting it here from
			// the live Assets.Colors.primaryAccent on every configure keeps the
			// thumb in sync with the person's accent choice, both on first layout
			// and whenever the cell is reconfigured after an accent color change
			// (see TimelineCustomizerCollectionViewController's accentColorDidChange
			// observer, which triggers that reconfiguration).
			slider.thumbTintColor = Assets.Colors.primaryAccent
			switch sliderConfiguration {
			case .numberOfLines:
				slider.isHidden = false
				segmentedControl?.isHidden = true
				slider.minimumValue = 1
				slider.maximumValue = 6
				if #available(iOS 26, *) {
					slider.trackConfiguration = .init(allowsTickValuesOnly: true, numberOfTicks: 6)
				}
				slider.value = Float(AppDefaults.shared.timelineNumberOfLines)
				slider.addTickMarks()
			case .tagDisplayMode:
				slider.isHidden = true
				let control = setupSegmentedControlIfNeeded()
				control.isHidden = false
				let modes: [TagDisplayMode] = [.compact, .expanded, .badges]
				if let index = modes.firstIndex(of: AppDefaults.shared.timelineTagDisplayMode) {
					control.selectedSegmentIndex = index
				}
			case .none:
				return
			}
		}
	}

	private func setupSegmentedControlIfNeeded() -> UISegmentedControl {
		if let segmentedControl { return segmentedControl }
		let items = [
			TagDisplayMode.compact.description,
			TagDisplayMode.expanded.description,
			TagDisplayMode.badges.description
		]
		let control = UISegmentedControl(items: items)
		control.translatesAutoresizingMaskIntoConstraints = false
		control.addTarget(self, action: #selector(segmentedControlChanged(_:)), for: .valueChanged)
		contentView.addSubview(control)
		NSLayoutConstraint.activate([
			control.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			control.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			control.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
		])
		self.segmentedControl = control
		return control
	}

	@objc private func segmentedControlChanged(_ sender: UISegmentedControl) {
		let modes: [TagDisplayMode] = [.compact, .expanded, .badges]
		guard sender.selectedSegmentIndex >= 0, sender.selectedSegmentIndex < modes.count else { return }
		AppDefaults.shared.timelineTagDisplayMode = modes[sender.selectedSegmentIndex]
	}

	@IBAction func sliderValueChanges(_ sender: Any) {
		switch sliderConfiguration {
		case .numberOfLines:
			AppDefaults.shared.timelineNumberOfLines = Int(slider.value.rounded())
		case .tagDisplayMode:
			guard let tagDisplayMode = TagDisplayMode(rawValue: Int(slider.value.rounded())) else { return }
			AppDefaults.shared.timelineTagDisplayMode = tagDisplayMode
		case .none:
			return
		}
	}

	override func updateConfiguration(using state: UICellConfigurationState) {
		var backgroundConfig: UIBackgroundConfiguration
		if #available(iOS 18, *) {
			backgroundConfig = UIBackgroundConfiguration.listCell().updated(for: state)
		} else {
			backgroundConfig = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
		}
		backgroundConfig.backgroundColor = Assets.Colors.settingsCellBackground(for: traitCollection)
		backgroundConfig.cornerRadius = 20
		self.backgroundConfiguration = backgroundConfig
	}

}
