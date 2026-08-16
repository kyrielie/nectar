//
//  HighlightColorPopover.swift
//  NetNewsWire-iOS
//
//  Shown when the person selects text in an article: a small floating
//  popover anchored above/below the selection (WebViewController presents
//  it via UIPopoverPresentationController with a sourceRect derived from
//  the selection's bounding rect, converted from webview to view
//  coordinates the same way showFullScreenImage's image-transition code
//  already does). WKWebView doesn't expose a supported way to inject a
//  custom item into its native selection callout menu, so this is a
//  separate, custom-presented view rather than an addition to the system
//  edit menu.
//
//  One popover, two exits:
//   - tap a color swatch -> highlight created with that color immediately,
//     popover dismissed. The fast, one-tap path for "just highlight this."
//   - tap the note icon -> highlight created with the last-used color,
//     popover dismissed, and the note editor opens immediately, focused.
//  Tapping an existing highlight always opens the note editor directly
//  (WebViewController.annotationWasTapped), not this popover -- this view
//  only ever handles the "new selection" case.
//

import SwiftUI
import Articles

struct HighlightColorPopover: View {

	/// Called when a color swatch is tapped: create the highlight with
	/// this color, no note editor.
	var onSelectColor: (Annotation.Color) -> Void

	/// Called when the note icon is tapped: create the highlight with the
	/// last-used (or default) color, then open the note editor immediately.
	var onAddNote: () -> Void

	private static let swatchColors: [Annotation.Color] = Annotation.Color.allCases

	var body: some View {
		HStack(spacing: 14) {
			ForEach(Self.swatchColors, id: \.self) { color in
				Button {
					onSelectColor(color)
				} label: {
					Circle()
						.fill(color.swiftUIColor)
						.frame(width: 28, height: 28)
				}
				.accessibilityLabel(color.accessibilityLabel)
			}

			Divider()
				.frame(height: 24)

			Button {
				onAddNote()
			} label: {
				Image(uiImage: Assets.Images.annotationAddNote)
					.resizable()
					.scaledToFit()
					.frame(width: 20, height: 20)
			}
			.accessibilityLabel(NSLocalizedString("Add Note", comment: "Highlight popover: add note button"))
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
	}
}

extension Annotation.Color {

	/// Same five hex values as core.css's mark.nnw-highlight defaults
	/// (Apple's own system palette) -- kept in sync manually since SwiftUI
	/// Color and CSS custom properties have no shared source of truth to
	/// derive from; if core.css's defaults ever change, update this too.
	var swiftUIColor: Color {
		switch self {
		case .yellow:
			return Color(red: 1.00, green: 0.839, blue: 0.039) // #FFD60A
		case .red:
			return Color(red: 1.00, green: 0.271, blue: 0.227) // #FF453A
		case .green:
			return Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
		case .blue:
			return Color(red: 0.039, green: 0.518, blue: 1.00) // #0A84FF
		case .purple:
			return Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2
		}
	}

	var accessibilityLabel: String {
		switch self {
		case .yellow:
			return NSLocalizedString("Yellow", comment: "Highlight color")
		case .red:
			return NSLocalizedString("Red", comment: "Highlight color")
		case .green:
			return NSLocalizedString("Green", comment: "Highlight color")
		case .blue:
			return NSLocalizedString("Blue", comment: "Highlight color")
		case .purple:
			return NSLocalizedString("Purple", comment: "Highlight color")
		}
	}

	/// UIKit equivalent of swiftUIColor, for call sites that can't use a
	/// SwiftUI Color directly (e.g. UIAction.image below). Derived from
	/// swiftUIColor rather than a separate hex literal, so there's still
	/// only one place encoding each color's actual value.
	var uiColor: UIColor {
		UIColor(swiftUIColor)
	}

	/// A small filled-circle swatch, for UIMenu/UIAction images (the
	/// annotations toolbar menu's "Default Highlight Color" submenu) --
	/// UIKit menus can't host a SwiftUI Circle the way HighlightColorPopover
	/// and AnnotationEditorView do.
	var swatchImage: UIImage {
		let diameter: CGFloat = 18
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
		return renderer.image { context in
			uiColor.setFill()
			context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
		}.withRenderingMode(.alwaysOriginal)
	}
}
