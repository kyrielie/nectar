import SwiftUI
import UIKit

/// Wraps UIDatePicker in `.countDownTimer` mode -- the "hours | min"
/// spinning wheel Settings → Screen Time → App Limits → Add Limit uses
/// for this exact screen (also the Clock app's Timer tab). SwiftUI has
/// no native duration-wheel equivalent, hence the wrapper. Same
/// UIViewRepresentable + Coordinator shape as AnchorReadingButton in
/// AnnotationsSettingsView.swift.
///
/// UIDatePicker's countDownTimer mode can only represent 0:00 through
/// 23:59 (`countDownDuration` is documented as 0...86,340 seconds) --
/// there's no way to dial in a full 24:00 on this control. Values are
/// clamped to that range on both display and write; a stored 1440
/// (this feature's pre-existing max, effectively "no limit" in
/// practice) displays and re-saves as 23:59/1439 the moment the wheel
/// is touched. minuteInterval matches the granularity the previous
/// Stepper used (15 minutes).
struct CountDownTimerPicker: UIViewRepresentable {

	@Binding var minutes: Int

	static let minMinutes = 1
	static let maxMinutes = 23 * 60 + 59

	func makeUIView(context: Context) -> UIDatePicker {
		let picker = UIDatePicker()
		picker.datePickerMode = .countDownTimer
		picker.minuteInterval = 15
		picker.countDownDuration = TimeInterval(clampedSeconds)
		picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
		return picker
	}

	func updateUIView(_ uiView: UIDatePicker, context: Context) {
		context.coordinator.minutesBinding = $minutes
		let target = TimeInterval(clampedSeconds)
		if uiView.countDownDuration != target {
			uiView.countDownDuration = target
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(minutesBinding: $minutes)
	}

	private var clampedSeconds: Int {
		min(max(minutes, Self.minMinutes), Self.maxMinutes) * 60
	}

	// @MainActor on the whole type for the same reason as
	// AnchorReadingButton.Coordinator: UIKit's target-action dispatch is
	// main-thread, and the compiler needs the enclosing type isolated to
	// verify that for the @objc method below.
	@MainActor final class Coordinator {
		var minutesBinding: Binding<Int>

		init(minutesBinding: Binding<Int>) {
			self.minutesBinding = minutesBinding
		}

		@objc func valueChanged(_ sender: UIDatePicker) {
			minutesBinding.wrappedValue = Int(sender.countDownDuration / 60)
		}
	}
}
