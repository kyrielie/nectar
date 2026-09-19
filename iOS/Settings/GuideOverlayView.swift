//
//  GuideOverlayView.swift
//  NetNewsWire-iOS
//
//  Presented modally, .overFullScreen, from
//  SettingsViewController.tableView(_:didSelectRowAt:)'s .guide case -- not
//  pushed, unlike every other Settings row. That choice is what makes the
//  real Settings screen visible-but-inert behind this view: a
//  modally-presented view controller receives all touches by default, so
//  the screen showing through GuideTheme.scrim needs no extra hit-testing
//  work to stay untappable. See docs/guide.md for the two architectures
//  that were weighed and why this one won.
//
//  Visual spec is the approved reference mockup, translated 1:1: a plain
//  dim scrim (no spotlight/vignette cutout -- that was explicitly tried
//  and dropped), a cream dialogue box with a brown border and a flat
//  offset "3D" bottom edge, a green pill-shaped speaker tag reading
//  "Nectar" above the box's top-left corner, character-by-character
//  typewriter text reveal, page dots, and an X close button reachable at
//  any point. No mascot in this pass -- the space above the box is left
//  empty on purpose; don't fill it with placeholder art.
//

import SwiftUI

// MARK: - Theme

/// Colors lifted directly from the approved reference's CSS custom
/// properties, light and dark values both carried over unchanged. Kept
/// local to this file rather than promoted to a shared design-system type
/// -- nothing else in the app uses this palette, and speculatively
/// generalizing it isn't warranted by one screen.
private enum GuideTheme {
	static let boxCream = Color(light: "#FFF7E6", dark: "#3A2F22")
	static let boxBorder = Color(light: "#A8703F", dark: "#C99A5E")
	static let boxBorderDark = Color(light: "#7A4E28", dark: "#E3B878")
	static let textBrown = Color(light: "#4A3423", dark: "#F3E6D0")
	static let accent = Color(light: "#5E9C5E", dark: "#7FC97F")
	static let accentDark = Color(light: "#3F7A3F", dark: "#A3E0A3")
	static let dotInactive = Color(light: "#4A3423", dark: "#F3E6D0", opacity: 0.25)
	/// Matches the reference's fixed `rgba(0,0,0,0.28)` scrim -- this one
	/// value is deliberately NOT theme-varied in the reference (unlike
	/// every other token here), so it isn't here either.
	static let scrim = Color.black.opacity(0.28)
}

private extension Color {
	/// A dynamic color from paired light/dark hex strings, resolved via
	/// UIColor's trait-collection closure initializer -- this codebase
	/// has no existing light/dark color helper (confirmed via search;
	/// ArticleThemeListView.swift's Color extension only parses a single
	/// hex string, no light/dark pairing), so this is written fresh
	/// rather than reused from somewhere that doesn't fit.
	init(light: String, dark: String, opacity: Double = 1) {
		let uiColor = UIColor { traitCollection in
			let hex = traitCollection.userInterfaceStyle == .dark ? dark : light
			return guideHexColor(hex: hex)?.withAlphaComponent(opacity) ?? .clear
		}
		self.init(uiColor: uiColor)
	}
}

/// Minimal #RRGGBB parser -- this file's palette is always specified that
/// way, so no #RGB/#RRGGBBAA handling is needed. Named distinctly from a
/// plain `UIColor(hex:)` initializer to avoid any ambiguity with
/// ArticleThemeListView.swift's unrelated `Color(hex:)` parser elsewhere
/// in the app, even though both are file-private.
private func guideHexColor(hex: String) -> UIColor? {
	var sanitized = hex
	if sanitized.hasPrefix("#") { sanitized.removeFirst() }
	guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
	let r = CGFloat((value >> 16) & 0xFF) / 255
	let g = CGFloat((value >> 8) & 0xFF) / 255
	let b = CGFloat(value & 0xFF) / 255
	return UIColor(red: r, green: g, blue: b, alpha: 1)
}

// MARK: - GuideOverlayView

struct GuideOverlayView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var pageIndex = 0
	@State private var revealedCharacterCount = 0
	@State private var typewriterTask: Task<Void, Never>?

	private var pages: [GuidePage] { GuideContent.pages }
	private var currentPage: GuidePage { pages[pageIndex] }
	private var isFullyRevealed: Bool { revealedCharacterCount >= currentPage.body.count }
	private var isLastPage: Bool { pageIndex == pages.count - 1 }

	var body: some View {
		ZStack(alignment: .bottom) {
			// Plain dim scrim -- deliberately no spotlight/vignette cutout.
			// Tapping the scrim itself does nothing (only the box and its
			// own tap target advance/reveal text); the X button is the
			// only way to dismiss without finishing every page.
			GuideTheme.scrim
				.ignoresSafeArea()

			dialogueBox
				.padding(.horizontal, 14)
				.padding(.bottom, 28)
		}
		.overlay(alignment: .topTrailing) {
			closeButton
				.padding(.top, 18)
				.padding(.trailing, 18)
		}
		.onAppear { startPage() }
		.onDisappear { typewriterTask?.cancel() }
	}

	// MARK: Dialogue box

	private var dialogueBox: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(currentPage.title)
				.font(.subheadline.weight(.bold))
				.foregroundStyle(GuideTheme.textBrown)

			revealedBody
				.font(.system(size: 14.5))
				.foregroundStyle(GuideTheme.textBrown)
				.frame(minHeight: 66, alignment: .topLeading)
				.fixedSize(horizontal: false, vertical: true)

			HStack {
				pageDots
				Spacer()
				advanceHint
			}
		}
		.padding(.horizontal, 20)
		.padding(.top, 18)
		.padding(.bottom, 16)
		.background(dialogueBoxBackground)
		.overlay(alignment: .topLeading) {
			speakerTag
				.offset(x: 22, y: -16)
		}
		.contentShape(Rectangle())
		.onTapGesture { onTap() }
	}

	/// The offset "3D" bottom edge from the reference's
	/// `box-shadow: 0 8px 0 var(--box-border-dark)` -- a flat-colored
	/// rectangle behind the box, offset downward, standing in for a
	/// shadow SwiftUI's blurred `.shadow` modifier can't produce.
	private var dialogueBoxBackground: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(GuideTheme.boxBorderDark)
				.offset(y: 8)
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(GuideTheme.boxCream)
				.overlay(
					RoundedRectangle(cornerRadius: 22, style: .continuous)
						.strokeBorder(GuideTheme.boxBorder, lineWidth: 3)
				)
		}
	}

	private var speakerTag: some View {
		Text("Nectar")
			.font(.system(size: 13, weight: .heavy))
			.foregroundStyle(.white)
			.padding(.horizontal, 14)
			.padding(.vertical, 4)
			.background(
				Capsule()
					.fill(GuideTheme.accent)
					.overlay(Capsule().strokeBorder(GuideTheme.accentDark, lineWidth: 2))
			)
	}

	/// Typewriter reveal via a substring of currentPage.body, driven by
	/// revealedCharacterCount -- a trailing blinking cursor is appended
	/// only while reveal is in progress, matching the reference's
	/// cursor.hidden toggle once the pass completes.
	private var revealedBody: some View {
		let revealed = String(currentPage.body.prefix(revealedCharacterCount))
		return HStack(spacing: 2) {
			Text(revealed)
			if !isFullyRevealed {
				TypewriterCursor(color: GuideTheme.textBrown)
			}
		}
	}

	private var pageDots: some View {
		HStack(spacing: 6) {
			ForEach(pages.indices, id: \.self) { index in
				Capsule()
					.fill(index == pageIndex ? GuideTheme.accentDark : GuideTheme.dotInactive)
					.frame(width: index == pageIndex ? 16 : 6, height: 6)
					.animation(.easeOut(duration: 0.2), value: pageIndex)
			}
		}
	}

	private var advanceHint: some View {
		HStack(spacing: 4) {
			if isLastPage && isFullyRevealed {
				Text("done", comment: "Guide overlay: advance hint, last page fully revealed")
			} else {
				Text("tap", comment: "Guide overlay: advance hint, more pages remain")
			}
			Image(systemName: "chevron.right")
				.font(.system(size: 9, weight: .bold))
		}
		.font(.system(size: 12, weight: .bold))
		.foregroundStyle(GuideTheme.accentDark)
	}

	private var closeButton: some View {
		Button {
			dismiss()
		} label: {
			Image(systemName: "xmark")
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(GuideTheme.textBrown)
				.frame(width: 32, height: 32)
				.background(Circle().fill(.white.opacity(0.65)))
		}
		.accessibilityLabel(Text("Close", comment: "Guide overlay: close button accessibility label"))
	}

	// MARK: Interaction

	/// Mirrors the reference's onTap(): a tap while text is still
	/// revealing fast-forwards to the full string; a tap once fully
	/// revealed advances to the next page (or, on the last page,
	/// dismisses).
	private func onTap() {
		if !isFullyRevealed {
			typewriterTask?.cancel()
			revealedCharacterCount = currentPage.body.count
			return
		}
		if isLastPage {
			dismiss()
		} else {
			pageIndex += 1
			startPage()
		}
	}

	private func startPage() {
		typewriterTask?.cancel()
		revealedCharacterCount = 0
		let targetCount = currentPage.body.count
		typewriterTask = Task {
			// 22ms per character, matching the reference's setInterval
			// cadence exactly.
			for count in 1...max(targetCount, 1) where !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(22))
				guard !Task.isCancelled else { return }
				await MainActor.run { revealedCharacterCount = count }
			}
		}
	}
}

/// A blinking text-cursor glyph, matching the reference's
/// `@keyframes blink` (500ms visible/hidden, step timing not eased). A
/// repeating step toggle isn't directly expressible via `.animation` on a
/// single Bool the way CSS `steps(1)` is, so this drives the same visible
/// blink rate with a timer-backed `Task` instead of fighting SwiftUI's
/// implicit-animation interpolation for a hard cut.
private struct TypewriterCursor: View {
	let color: Color
	@State private var isVisible = true

	var body: some View {
		Rectangle()
			.fill(color)
			.frame(width: 2, height: 14)
			.opacity(isVisible ? 1 : 0)
			.task {
				while !Task.isCancelled {
					try? await Task.sleep(for: .milliseconds(400))
					isVisible.toggle()
				}
			}
	}
}

#Preview("Light") {
	GuideOverlayView()
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	GuideOverlayView()
		.preferredColorScheme(.dark)
}
