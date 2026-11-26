//
//  AppDefaults+ArticleDisplay.swift
//  Nectar
//

import Foundation

extension AppDefaults {

	/// Whether the notch/Dynamic Island area is masked (solid black) while in
	/// fullscreen reading mode, instead of showing through as normal. Exposed
	/// as its own toggle -- independent of the page counter below -- for
	/// people who want the notch hidden but don't care about the counter.
	/// The page counter turning on also hides the notch (see
	/// WebViewController.updateNotchAndPageCounterVisibility()) without
	/// requiring this setting to also be switched on: showing a page counter
	/// in a space that still displays the notch would look broken.
	var hideNotchInFullScreen: Bool {
		get {
			return AppDefaults.bool(for: Key.hideNotchInFullScreen)
		}
		set {
			AppDefaults.setBool(for: Key.hideNotchInFullScreen, newValue)
		}
	}

	/// Page counter shown in the notch's leading side space while in
	/// fullscreen reading mode. Off by default; when on, implies hiding the
	/// notch regardless of hideNotchInFullScreen's own value (see above).
	var pageCounterDisplayMode: PageCounterDisplayMode {
		get {
			guard let rawValue = AppDefaults.string(for: Key.pageCounterDisplayMode),
				  let mode = PageCounterDisplayMode(rawValue: rawValue) else {
				return .off
			}
			return mode
		}
		set {
			AppDefaults.setString(for: Key.pageCounterDisplayMode, newValue.rawValue)
		}
	}

	/// When on, tapping any link in the article body (including target=_blank
	/// links) is suppressed entirely rather than navigating anywhere. Off by
	/// default, since it changes existing behavior.
	var disableArticleLinks: Bool {
		get {
			return AppDefaults.bool(for: Key.disableArticleLinks)
		}
		set {
			AppDefaults.setBool(for: Key.disableArticleLinks, newValue)
		}
	}

	/// When the article web view shows its native vertical scroll
	/// indicator. .whenNotFullScreen by default (via registerDefaults),
	/// preserving the system's normal scrollbar behavior outside of
	/// fullscreen reading, where the app's own chrome is already hidden.
	/// Read fresh (not cached) wherever it's consulted -- same
	/// "reasserted on every dequeue" convention this file already uses
	/// for pinchGestureRecognizer.isEnabled on the pooled
	/// PreloadedWebView -- so a Settings change takes effect the next
	/// time an article (re)loads, and
	/// WebViewController.updateScrollbarVisibility() can also re-derive
	/// visibility live as fullscreen is entered/exited without a reload.
	var articleScrollbarVisibility: ArticleScrollbarVisibility {
		get {
			guard let raw = AppDefaults.string(for: Key.showArticleScrollbar),
				  let value = ArticleScrollbarVisibility(rawValue: raw) else {
				return .whenNotFullScreen
			}
			return value
		}
		set {
			AppDefaults.setString(for: Key.showArticleScrollbar, newValue.rawValue)
		}
	}

	/// The "Updated X ago" / "Updated Just Now" label shown under the feed
	/// list while idle. On by default, preserving current behavior.
	var showLastUpdatedLabel: Bool {
		get {
			return AppDefaults.bool(for: Key.showLastUpdatedLabel)
		}
		set {
			AppDefaults.setBool(for: Key.showLastUpdatedLabel, newValue)
		}
	}
}
