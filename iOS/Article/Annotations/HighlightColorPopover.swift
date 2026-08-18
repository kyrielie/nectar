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

	/// @AppStorage, not a plain AppDefaults.shared read, so a live palette
	/// change (e.g. switching it on the Accent Color screen while this
	/// popover happens to be up) recomputes body -- same convention
	/// AnnotationsSettingsView already uses for annotationCreationMethod.
	@AppStorage(AppDefaults.Key.highlightPalette) private var highlightPaletteRawValue = HighlightPalette.default.rawValue
	@Environment(\.colorScheme) private var colorScheme

	private var highlightPalette: HighlightPalette {
		HighlightPalette(rawValue: highlightPaletteRawValue) ?? .default
	}

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
						.fill(color.swiftUIColor(palette: highlightPalette, isDark: colorScheme == .dark))
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

	/// The live hex value for this color under the given palette/appearance
	/// -- HighlightPalette.HexSet's own subscript does the actual lookup;
	/// this just spells out the two params as named arguments at call
	/// sites instead of a bare subscript. Takes palette/isDark explicitly
	/// rather than reading AppDefaults.shared.highlightPalette or an
	/// ambient trait collection internally, so every call site's result is
	/// visibly tied to the exact palette/appearance it was computed
	/// against -- see HighlightColorPopover's own call sites below for why
	/// that matters for live SwiftUI updates (a computed property with a
	/// hidden global read wouldn't trigger a body re-evaluation on its own
	/// when the palette changes).
	func hex(palette: HighlightPalette, isDark: Bool) -> String {
		palette.hexSet(isDark: isDark)[self]
	}

	/// SwiftUI Color for this color under the given palette/appearance.
	func swiftUIColor(palette: HighlightPalette, isDark: Bool) -> Color {
		Color(uiColor(palette: palette, isDark: isDark))
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

	/// UIKit equivalent of swiftUIColor(palette:isDark:), for call sites
	/// that can't use a SwiftUI Color directly (e.g. UIAction.image
	/// below). Falls back to the fixed pre-palette hex if `UIColor(cssHex:)`
	/// somehow fails to parse a palette's hex (shouldn't happen for any
	/// hardcoded HexSet literal, but keeps this non-optional the same way
	/// AccentColorTableViewController's swatchImage falls back rather than
	/// propagating an Optional for what's normally a static, valid string).
	func uiColor(palette: HighlightPalette, isDark: Bool) -> UIColor {
		UIColor(cssHex: hex(palette: palette, isDark: isDark)) ?? .systemYellow
	}

	/// A small filled-circle swatch, for UIMenu/UIAction images -- UIKit
	/// menus can't host a SwiftUI Circle the way HighlightColorPopover and
	/// AnnotationEditorView do. Currently unused: it backed the toolbar's
	/// "Default Highlight Color" submenu that used to live in
	/// ArticleViewController's annotations UIMenu, before that button
	/// became a direct action (see
	/// ArticleViewController.showAnnotationsList's doc comment) with
	/// color selection moved to AnnotationsSettingsView's picker (SwiftUI,
	/// uses swiftUIColor(palette:isDark:) directly). Left in place as a
	/// small, self-contained UIKit-bridging helper in case a future
	/// UIMenu-based color picker needs it again -- flagging for removal if
	/// that doesn't happen.
	func swatchImage(palette: HighlightPalette, isDark: Bool) -> UIImage {
		let diameter: CGFloat = 18
		let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
		return renderer.image { context in
			uiColor(palette: palette, isDark: isDark).setFill()
			context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
		}.withRenderingMode(.alwaysOriginal)
	}
}
