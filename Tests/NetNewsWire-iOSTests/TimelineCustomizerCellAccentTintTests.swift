//
//  TimelineCustomizerCellAccentTintTests.swift
//  NetNewsWire-iOSTests
//
//  Regression coverage for the slider half of bug #3 ("accent color doesn't
//  apply to toggle sliders"): TimelineCustomizerCell's TickMarkSlider had
//  its thumbTintColor bound in Settings.storyboard to the static
//  primaryAccentColor asset, same underlying problem as the UISwitches
//  covered in SettingsAccentColorLiveUpdateTests.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct TimelineCustomizerCellAccentTintTests {

	@MainActor
	private func makeConfiguredCell() -> TimelineCustomizerCell {
		let cell = TimelineCustomizerCell(frame: CGRect(x: 0, y: 0, width: 320, height: 54))
		cell.slider = TickMarkSlider(frame: cell.contentView.bounds)
		cell.sliderConfiguration = .numberOfLines
		return cell
	}

	@MainActor
	@Test func sliderThumbTintMatchesLiveAccentColorOnConfigure() {
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .sepia
		let cell = makeConfiguredCell()

		#expect(cell.slider.thumbTintColor == Assets.Colors.primaryAccent)
	}

	@MainActor
	@Test func sliderThumbTintUpdatesWhenReconfiguredAfterAccentColorChanges() {
		defer { AppDefaults.shared.accentColor = .default }

		let cell = makeConfiguredCell()
		let firstTint = cell.slider.thumbTintColor

		AppDefaults.shared.accentColor = .lavender
		cell.sliderConfiguration = .numberOfLines // re-runs didSet, as TimelineCustomizerCollectionViewController's
												   // .accentColorDidChange observer triggers via collectionView.reloadData()
		#expect(cell.slider.thumbTintColor != firstTint)
		#expect(cell.slider.thumbTintColor == Assets.Colors.primaryAccent)
	}
}
