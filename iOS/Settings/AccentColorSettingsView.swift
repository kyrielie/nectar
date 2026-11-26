//
//  AccentColorSettingsView.swift
//  NetNewsWire-iOS
//
//  App-wide accent color and badge color palette settings.
//

import SwiftUI
import UIKit
import Articles
import AppChrome
import HexColor
import Images

@MainActor final class AccentColorSettingsModel: ObservableObject {

	@Published var accentColor: AccentColor {
		didSet {
			guard oldValue != accentColor else { return }
			AppDefaults.shared.accentColor = accentColor
		}
	}

	@Published var badgeColorMode: BadgeColorPalette {
		didSet {
			guard oldValue != badgeColorMode else { return }
			AppDefaults.shared.badgeColorMode = badgeColorMode
		}
	}

	nonisolated(unsafe) private var observers = [NSObjectProtocol]()

	init(notificationCenter: NotificationCenter = .default) {
		self.accentColor = AppDefaults.shared.accentColor
		self.badgeColorMode = AppDefaults.shared.badgeColorMode

		let accentObserver = notificationCenter.addObserver(forName: .accentColorDidChange, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				let latest = AppDefaults.shared.accentColor
				if self.accentColor != latest {
					self.accentColor = latest
				}
			}
		}

		let badgeObserver = notificationCenter.addObserver(forName: .badgeColorModeDidChange, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				let latest = AppDefaults.shared.badgeColorMode
				if self.badgeColorMode != latest {
					self.badgeColorMode = latest
				}
			}
		}

		observers = [accentObserver, badgeObserver]
	}

	deinit {
		for observer in observers {
			NotificationCenter.default.removeObserver(observer)
		}
	}
}

struct AccentColorSettingsView: View {

	@StateObject private var model = AccentColorSettingsModel()
	@Environment(\.surfacePaletteObserver) private var surfaceObserver

	private var cellBackground: Color {
		surfaceObserver?.settingsCellBackground ?? Color(uiColor: .secondarySystemGroupedBackground)
	}

	private var accentTint: Color {
		surfaceObserver?.accentColor ?? .accentColor
	}

	var body: some View {
		Form {
			Section {
				ForEach(AccentColor.allCases, id: \.self) { accent in
					Button {
						model.accentColor = accent
					} label: {
						HStack(spacing: 12) {
							AccentColorSwatchView(accentColor: accent)
							Text(accent.description)
								.foregroundStyle(.primary)
							Spacer()
							if model.accentColor == accent {
								Image(systemName: "checkmark")
									.font(.body.weight(.semibold))
									.foregroundStyle(accentTint)
							}
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.accessibilityAddTraits(model.accentColor == accent ? .isSelected : [])
				}
			} header: {
				Text("Accent Color", comment: "Accent color section header")
			}
			.listRowBackground(cellBackground)

			Section {
				ForEach(BadgeColorPalette.allCases, id: \.self) { palette in
					Button {
						model.badgeColorMode = palette
					} label: {
						HStack {
							Text(palette.description)
								.foregroundStyle(.primary)
							Spacer()
							if model.badgeColorMode == palette {
								Image(systemName: "checkmark")
									.font(.body.weight(.semibold))
									.foregroundStyle(accentTint)
							}
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
					.accessibilityAddTraits(model.badgeColorMode == palette ? .isSelected : [])
				}
			} header: {
				Text("Badge Colors", comment: "Badge color palette section header")
			} footer: {
				Text("Badges appear in the timeline when Tag Display is set to Badges in Timeline Layout. Accent palette badges follow your Accent Color choice above.", comment: "Badge color palette section footer")
			}
			.listRowBackground(cellBackground)

			Section {
				BadgeColorPalettePreviewRepresentable(
					accentColor: model.accentColor,
					badgeColorMode: model.badgeColorMode
				)
				.listRowInsets(EdgeInsets())
			} header: {
				Text("Preview", comment: "Badge color palette preview section header")
			}
			.listRowBackground(cellBackground)
		}
		.surfacePaletteListBackground()
		.navigationTitle(Text("Accent Color", comment: "Accent Color navigation title"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct AccentColorSwatchView: View {
	let accentColor: AccentColor

	private static let defaultPrimary = UIColor(named: "primaryAccentColor") ?? .systemBlue
	private static let defaultSecondary = UIColor(named: "secondaryAccentColor") ?? .systemTeal

	private var primary: Color {
		Color(uiColor: accentColor.primaryHex.flatMap { UIColor(cssHex: $0) } ?? Self.defaultPrimary)
	}

	private var secondary: Color {
		Color(uiColor: accentColor.secondaryHex.flatMap { UIColor(cssHex: $0) } ?? Self.defaultSecondary)
	}

	var body: some View {
		VStack(spacing: 0) {
			primary
			secondary
		}
		.frame(width: 28, height: 28)
		.clipShape(Circle())
		.overlay(Circle().stroke(Color(uiColor: .separator), lineWidth: 1))
	}
}

private struct BadgeColorPalettePreviewRepresentable: UIViewRepresentable {
	let accentColor: AccentColor
	let badgeColorMode: BadgeColorPalette

	func makeUIView(context: Context) -> TimelinePreviewContainerView {
		let containerView = TimelinePreviewContainerView()
		containerView.update(
			numberOfLines: AppDefaults.shared.timelineNumberOfLines,
			tagDisplayMode: .badges,
			statsVisible: AppDefaults.shared.statsVisible,
			accentColor: accentColor,
			badgeColorMode: badgeColorMode
		)
		return containerView
	}

	func updateUIView(_ containerView: TimelinePreviewContainerView, context: Context) {
		containerView.update(
			numberOfLines: AppDefaults.shared.timelineNumberOfLines,
			tagDisplayMode: .badges,
			statsVisible: AppDefaults.shared.statsVisible,
			accentColor: accentColor,
			badgeColorMode: badgeColorMode
		)
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView containerView: TimelinePreviewContainerView, context: Context) -> CGSize? {
		let width = proposal.width ?? 320
		let height = containerView.preferredHeight(forWidth: width)
		return CGSize(width: width, height: height)
	}
}
