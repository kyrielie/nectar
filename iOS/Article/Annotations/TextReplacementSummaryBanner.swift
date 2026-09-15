//
//  TextReplacementSummaryBanner.swift
//  NetNewsWire-iOS
//
//  The plan's "Confirmation policy" section calls for a lightweight,
//  non-blocking one-time summary after an automatic replacement pass --
//  "12 replacements made -- review in Edit History" -- rather than a
//  blocking per-match confirmation or fully silent application.
//  docs/annotations.md's "Auto-apply on open" previously noted that no
//  toast/banner mechanism existed anywhere in this codebase to hook this
//  into (confirmed by search); this is that primitive, purpose-built for
//  this one call site rather than a general-purpose toast system, since
//  no second use case exists yet to justify one.
//
//  Presentation shape: a small, rounded, tappable capsule pinned below the
//  navigation bar, auto-dismissing after a few seconds or immediately on
//  tap -- tapping it opens Edit History (the same destination the
//  Settings screen's Edit History row and this feature's own footer copy
//  both point to), same "notification, not a gate" framing the plan
//  describes: it never blocks reading, and dismissing it (by tap or
//  timeout) loses nothing, since every match it's summarizing is already
//  a real, persisted, individually reviewable/reversible annotation row.
//

import SwiftUI

/// The banner's own content view -- a plain, small, capsule-shaped label.
/// Kept deliberately simple (no icon, no swipe-to-dismiss gesture) since
/// this is a one-off, low-frequency notification, not a recurring UI
/// element worth a richer interaction model.
struct TextReplacementSummaryBannerView: View {

	let replacementCount: Int
	var onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			Text(bannerText)
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.white)
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
				.background(Capsule().fill(Color.accentColor))
				.shadow(color: .black.opacity(0.2), radius: 6, y: 2)
		}
		.buttonStyle(.plain)
		.accessibilityHint(Text("Opens Edit History.", comment: "Text replacement summary banner: accessibility hint"))
	}

	// "%d replacement(s)" -- the same pragmatic (rather than stringsdict-
	// pluralized) count formatting BackupRestoreCoordinator's own restore
	// summary strings already use elsewhere in this app.
	private var bannerText: String {
		String(format: NSLocalizedString("%d replacement(s) made -- review in Edit History", comment: "Text replacement summary banner"), replacementCount)
	}
}

/// Presents/dismisses a TextReplacementSummaryBannerView as a floating
/// overlay above `hostView`, pinned to its top-safe-area edge. A thin
/// UIKit shim (rather than a SwiftUI-only solution) since the call site
/// (WebViewController.applyTextReplacementRulesIfNeeded, by way of
/// ArticleViewController -- see that method's own doc comment on why the
/// hook is a closure rather than a shared presenter singleton) lives in
/// plain UIKit view controllers, not inside an existing SwiftUI tree.
@MainActor final class TextReplacementSummaryBannerPresenter {

	private weak var hostingController: UIHostingController<TextReplacementSummaryBannerView>?
	private var dismissTask: Task<Void, Never>?

	/// Shows the banner above `hostView`'s top safe area, replacing any
	/// currently-shown banner from this same presenter instance (there is
	/// at most one auto-apply pass per article per load -- see
	/// applyTextReplacementRulesIfNeeded's own "one-time pass" guard -- so
	/// this only matters if the person pages to a second article with its
	/// own fresh matches before the first banner's timeout fires).
	/// `onTap` fires once, immediately dismissing the banner first so a
	/// slow presentation on the other end doesn't leave a stale banner
	/// behind.
	func show(replacementCount: Int, in hostView: UIView, onTap: @escaping () -> Void) {
		dismiss(animated: false)

		let bannerView = TextReplacementSummaryBannerView(replacementCount: replacementCount) { [weak self] in
			self?.dismiss(animated: true)
			onTap()
		}
		let hostingController = UIHostingController(rootView: bannerView)
		hostingController.view.backgroundColor = .clear
		hostingController.view.translatesAutoresizingMaskIntoConstraints = false
		hostView.addSubview(hostingController.view)
		NSLayoutConstraint.activate([
			hostingController.view.topAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.topAnchor, constant: 8),
			hostingController.view.centerXAnchor.constraint(equalTo: hostView.centerXAnchor)
		])
		hostingController.view.alpha = 0
		UIView.animate(withDuration: 0.25) {
			hostingController.view.alpha = 1
		}
		self.hostingController = hostingController

		dismissTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(4))
			guard !Task.isCancelled else { return }
			self?.dismiss(animated: true)
		}
	}

	func dismiss(animated: Bool) {
		dismissTask?.cancel()
		dismissTask = nil
		guard let view = hostingController?.view else { return }
		hostingController = nil
		if animated {
			UIView.animate(withDuration: 0.2, animations: {
				view.alpha = 0
			}, completion: { _ in
				view.removeFromSuperview()
			})
		} else {
			view.removeFromSuperview()
		}
	}
}
