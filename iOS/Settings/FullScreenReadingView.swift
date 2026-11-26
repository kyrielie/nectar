//
//  FullScreenReadingView.swift
//  NetNewsWire-iOS
//
//  SwiftUI replacement for `FullScreenReadingViewController`.
//

import SwiftUI

@MainActor final class FullScreenReadingModel: ObservableObject {

	@Published var articleFullscreenAvailable: Bool {
		didSet {
			guard oldValue != articleFullscreenAvailable else { return }
			AppDefaults.shared.articleFullscreenAvailable = articleFullscreenAvailable
		}
	}

	@Published var articleBackSwipeEnabled: Bool {
		didSet {
			guard oldValue != articleBackSwipeEnabled else { return }
			AppDefaults.shared.articleBackSwipeEnabled = articleBackSwipeEnabled
		}
	}

	@Published var articlePagingSwipeEnabled: Bool {
		didSet {
			guard oldValue != articlePagingSwipeEnabled else { return }
			AppDefaults.shared.articlePagingSwipeEnabled = articlePagingSwipeEnabled
		}
	}

	@Published var articleFullscreenContextMenuEnabled: Bool {
		didSet {
			guard oldValue != articleFullscreenContextMenuEnabled else { return }
			AppDefaults.shared.articleFullscreenContextMenuEnabled = articleFullscreenContextMenuEnabled
		}
	}

	@Published var articleScrollbarVisibility: ArticleScrollbarVisibility {
		didSet {
			guard oldValue != articleScrollbarVisibility else { return }
			AppDefaults.shared.articleScrollbarVisibility = articleScrollbarVisibility
		}
	}

	@Published var pageCounterDisplayMode: PageCounterDisplayMode {
		didSet {
			guard oldValue != pageCounterDisplayMode else { return }
			AppDefaults.shared.pageCounterDisplayMode = pageCounterDisplayMode
		}
	}

	@Published var hideNotchInFullScreen: Bool {
		didSet {
			guard oldValue != hideNotchInFullScreen else { return }
			AppDefaults.shared.hideNotchInFullScreen = hideNotchInFullScreen
		}
	}

	init() {
		let defaults = AppDefaults.shared
		self.articleFullscreenAvailable = defaults.articleFullscreenAvailable
		self.articleBackSwipeEnabled = defaults.articleBackSwipeEnabled
		self.articlePagingSwipeEnabled = defaults.articlePagingSwipeEnabled
		self.articleFullscreenContextMenuEnabled = defaults.articleFullscreenContextMenuEnabled
		self.articleScrollbarVisibility = defaults.articleScrollbarVisibility
		self.pageCounterDisplayMode = defaults.pageCounterDisplayMode
		self.hideNotchInFullScreen = defaults.hideNotchInFullScreen
	}

	var isHideNotchDisabled: Bool {
		pageCounterDisplayMode != .off
	}

	var effectiveHideNotch: Bool {
		isHideNotchDisabled ? true : hideNotchInFullScreen
	}
}

struct FullScreenReadingView: View {

	@StateObject private var model = FullScreenReadingModel()

	var body: some View {
		Form {
			Section {
				ToggleRow(
					title: "Enable Full Screen Works",
					subtitle: "Tap the work top bar to enter Full Screen. Tap the top or bottom to exit.",
					isOn: $model.articleFullscreenAvailable
				)
				ToggleRow(
					title: "Enable Swipe Back",
					subtitle: "Swipe from the left edge of a work to go back to the timeline.",
					isOn: $model.articleBackSwipeEnabled
				)
				ToggleRow(
					title: "Enable Paging Swipe",
					subtitle: "Swipe left or right anywhere in a work to move to the next or previous work.",
					isOn: $model.articlePagingSwipeEnabled
				)
				ToggleRow(
					title: "Long-Press Context Menu",
					subtitle: "While full screen, long-press a work to show quick actions. Turn off to select text instead.",
					isOn: $model.articleFullscreenContextMenuEnabled
				)
				Picker("Work Scrollbar", selection: $model.articleScrollbarVisibility) {
					ForEach(ArticleScrollbarVisibility.allCases, id: \.self) { mode in
						Text(mode.title).tag(mode)
					}
				}
			}

			Section {
				Picker("Page Counter", selection: $model.pageCounterDisplayMode) {
					Text("Off").tag(PageCounterDisplayMode.off)
					Text("Percentage").tag(PageCounterDisplayMode.percentage)
					Text("Page Count").tag(PageCounterDisplayMode.pageCount)
				}

				Toggle(
					"Hide Notch in Full Screen",
					isOn: Binding(
						get: { model.effectiveHideNotch },
						set: { model.hideNotchInFullScreen = $0 }
					)
				)
				.disabled(model.isHideNotchDisabled)
			} footer: {
				Text("Hide Notch turns on automatically, and can't be turned off, while Page Counter is on.")
			}
		}
		.navigationTitle("Reading Gestures & Layout")
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct ToggleRow: View {
	let title: String
	let subtitle: String
	@Binding var isOn: Bool

	var body: some View {
		Toggle(isOn: $isOn) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
				Text(subtitle)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
		}
	}
}
