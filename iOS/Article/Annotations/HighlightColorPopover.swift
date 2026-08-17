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
//  edit menu. This is the .popup AnnotationCreationMethod's UI; the
//  .nativeMenu method instead injects into WKWebView's own selection
//  callout -- see PreloadedWebView.buildMenu(with:).
//
//  One tap, one exit: tapping any swatch highlights immediately with that
//  color and dismisses the popover. There is no "add note" affordance here
//  -- notes are added afterward by tapping the resulting mark, which opens
//  AnnotationEditorView the same way tapping any existing highlight does
//  (WebViewController.annotationWasTapped).
//
//  Three swatches, not all five Annotation.Color cases: the person's
//  current default color (AppDefaults.shared.defaultAnnotationColor,
//  which can be any of the 5 -- set via AnnotationsSettingsView's picker),
//  plus fixed blue and red as quick alternates. If the default color is
//  itself blue or red, the duplicate is dropped rather than shown twice,
//  so the popover can show 2 or 3 swatches depending on that setting.
//  AnnotationEditorView's color picker and AnnotationsSettingsView's
//  default-color picker are unaffected by this -- both still offer all 5.
//

import SwiftUI
import Articles

struct HighlightColorPopover: View {

	/// Called when a color swatch is tapped: create the highlight with
	/// this color immediately. The popover has no other exit.
	var onSelectColor: (Annotation.Color) -> Void

	/// The default color plus fixed blue/red, de-duplicated in place so a
	/// default of blue or red doesn't produce a repeated swatch. Order is
	/// preserved (default color first) rather than sorted, so the
	/// person's own choice is always the leftmost/first swatch.
	private var swatchColors: [Annotation.Color] {
		let candidates: [Annotation.Color] = [AppDefaults.shared.defaultAnnotationColor, .blue, .red]
		var seen = Set<Annotation.Color>()
		return candidates.filter { seen.insert($0).inserted }
	}

	var body: some View {
		HStack(spacing: 14) {
			ForEach(swatchColors, id: \.self) { color in
				Button {
					onSelectColor(color)
				} label: {
					Circle()
						.fill(color.swiftUIColor)
						.frame(width: 28, height: 28)
				}
				.accessibilityLabel(color.accessibilityLabel)
			}
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

	/// A small filled-circle swatch, for UIMenu/UIAction images -- UIKit
	/// menus can't host a SwiftUI Circle the way HighlightColorPopover and
	/// AnnotationEditorView do. Currently unused: it backed the toolbar's
	/// "Default Highlight Color" submenu that used to live in
	/// ArticleViewController's annotations UIMenu, before that button
	/// became a direct action (see
	/// ArticleViewController.showAnnotationsList's doc comment) with
	/// color selection moved to AnnotationsSettingsView's picker (SwiftUI,
	/// uses swiftUIColor directly). Left in place as a small,
	/// self-contained UIKit-bridging helper in case a future UIMenu-based
	/// color picker needs it again -- flagging for removal if that
	/// doesn't happen.
	var swatchImage: UIImage {
		let diameter: CGFloat = 18
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
		return renderer.image { context in
			uiColor.setFill()
			context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
		}.withRenderingMode(.alwaysOriginal)
	}
}
