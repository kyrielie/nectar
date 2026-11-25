//
//  ColorPaletteSettingsView.swift
//  NetNewsWire-iOS
//
//  App-wide interface style, toolbar style, and surface palette settings.
//

import SwiftUI
import AppChrome
import HexColor

@MainActor final class ColorPaletteSettingsModel: ObservableObject {

	@Published var userInterfaceColorPalette: UserInterfaceColorPalette {
		didSet {
			guard oldValue != userInterfaceColorPalette else { return }
			AppDefaults.userInterfaceColorPalette = userInterfaceColorPalette
		}
	}

	@Published var toolbarStyle: ToolbarStyle {
		didSet {
			guard oldValue != toolbarStyle else { return }
			AppDefaults.shared.toolbarStyle = toolbarStyle
		}
	}

	@Published var surfaceTint: SurfacePalette {
		didSet {
			guard oldValue != surfaceTint else { return }
			AppDefaults.shared.surfaceTint = surfaceTint
		}
	}

	nonisolated(unsafe) private var observer: NSObjectProtocol?

	init(notificationCenter: NotificationCenter = .default) {
		self.userInterfaceColorPalette = AppDefaults.userInterfaceColorPalette
		self.toolbarStyle = AppDefaults.shared.toolbarStyle
		self.surfaceTint = AppDefaults.shared.surfaceTint

		observer = notificationCenter.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				let latestToolbarStyle = AppDefaults.shared.toolbarStyle
				if self.toolbarStyle != latestToolbarStyle {
					self.toolbarStyle = latestToolbarStyle
				}
				let latestSurfaceTint = AppDefaults.shared.surfaceTint
				if self.surfaceTint != latestSurfaceTint {
					self.surfaceTint = latestSurfaceTint
				}
			}
		}
	}

	deinit {
		if let observer {
			NotificationCenter.default.removeObserver(observer)
		}
	}
}

struct ColorPaletteSettingsView: View {

	@StateObject private var model = ColorPaletteSettingsModel()

	var body: some View {
		Form {
			Section {
				ForEach(UserInterfaceColorPalette.allCases, id: \.self) { palette in
					SelectionRow(
						title: String(describing: palette),
						isSelected: model.userInterfaceColorPalette == palette
					) {
						model.userInterfaceColorPalette = palette
					}
				}
			}

			Section {
				ForEach(ToolbarStyle.allCases, id: \.self) { style in
					SelectionRow(
						title: style.description,
						isSelected: model.toolbarStyle == style
					) {
						model.toolbarStyle = style
					}
				}
			} footer: {
				Text("Default: the top navigation bar and bottom toolbar use plain system appearance. Blend: both bars match the current work's background color. Tinted: both bars pick up the Surface Palette's tint color.", comment: "Toolbar style picker footer")
			}

			Section {
				ForEach(SurfacePalette.allCases, id: \.self) { palette in
					SelectionRow(
						title: palette.description,
						isSelected: model.surfaceTint == palette
					) {
						model.surfaceTint = palette
					}
				}
			} header: {
				Text("Surface Palette", comment: "Surface palette section header")
			}

			Section {
				SurfacePalettePreviewView(surfaceTint: model.surfaceTint, toolbarStyle: model.toolbarStyle)
			} header: {
				Text("Preview", comment: "Surface palette preview section header")
			}
		}
		.navigationTitle(Text("Color Palette", comment: "Color Palette navigation title"))
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct SelectionRow: View {
	let title: String
	let isSelected: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack {
				Text(title)
					.foregroundStyle(.primary)
				Spacer()
				if isSelected {
					Image(systemName: "checkmark")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
}

private struct SurfacePalettePreviewView: View {
	let surfaceTint: SurfacePalette
	let toolbarStyle: ToolbarStyle

	@Environment(\.colorScheme) private var colorScheme

	private var traitCollection: UITraitCollection {
		UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
	}

	private var navBarColors: (background: Color, dot: Color?) {
		let hexSet = colorScheme == .dark ? surfaceTint.darkHexSet : surfaceTint.lightHexSet
		let isTinted = toolbarStyle == .tinted
		let bg = (isTinted ? hexSet?.navigationBarBackground : nil).flatMap { UIColor(cssHex: $0) } ?? .systemBackground
		let tint = (isTinted ? hexSet?.navigationBarTint : nil).flatMap { UIColor(cssHex: $0) } ?? .label
		return (Color(uiColor: bg), Color(uiColor: tint))
	}

	var body: some View {
		let traits = traitCollection
		let navColors = navBarColors

		VStack(spacing: 12) {
			HStack(spacing: 12) {
				SurfaceSwatchItem(
					background: Color(uiColor: Assets.Colors.barBackground(for: traits)),
					dot: Color(uiColor: Assets.Colors.vibrantText(for: traits)),
					caption: NSLocalizedString("Search Bar", comment: "Surface palette preview: search bar swatch caption")
				)
				SurfaceSwatchItem(
					background: navColors.background,
					dot: navColors.dot,
					caption: NSLocalizedString("Nav Bar", comment: "Surface palette preview: nav bar swatch caption")
				)
				SurfaceSwatchItem(
					background: Color(uiColor: Assets.Colors.fullScreenBackground(for: traits)),
					dot: nil,
					caption: NSLocalizedString("Full Screen", comment: "Surface palette preview: full screen swatch caption")
				)
			}

			HStack(spacing: 12) {
				SurfaceSwatchItem(
					background: Color(uiColor: Assets.Colors.settingsBackground(for: traits)),
					dot: nil,
					caption: NSLocalizedString("Settings", comment: "Surface palette preview: settings background swatch caption")
				)
				SurfaceSwatchItem(
					background: Color(uiColor: Assets.Colors.settingsCellBackground(for: traits)),
					dot: nil,
					caption: NSLocalizedString("Settings Cell", comment: "Surface palette preview: settings cell swatch caption")
				)
				SurfaceSwatchItem(
					background: Color(uiColor: Assets.Colors.listBackground(for: traits)),
					dot: nil,
					caption: NSLocalizedString("List", comment: "Surface palette preview: list background swatch caption")
				)
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 6)
	}
}

private struct SurfaceSwatchItem: View {
	let background: Color
	let dot: Color?
	let caption: String

	var body: some View {
		VStack(spacing: 4) {
			ZStack {
				RoundedRectangle(cornerRadius: 8)
					.fill(background)
					.frame(width: 80, height: 44)
					.overlay(
						RoundedRectangle(cornerRadius: 8)
							.stroke(Color(uiColor: .separator), lineWidth: 1)
					)
				if let dot {
					Circle()
						.fill(dot)
						.frame(width: 12, height: 12)
				}
			}
			Text(caption)
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
	}
}
