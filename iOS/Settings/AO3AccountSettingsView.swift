//
//  AO3AccountSettingsView.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login")
//  -- see docs/ao3-merged-plan-nectar.md.
//
//  Pushed from SettingsViewController's new "Archive of Our Own" row,
//  following the same UIHostingController-push pattern as AboutView and
//  AccountStatsView elsewhere in this file's section.
//

import SwiftUI
import UIKit
import Account

struct AO3AccountSettingsView: View {

	@State private var isSignedIn = AO3SessionStore.isSignedIn
	@State private var isShowingLogin = false
	@State private var isShowingSignOutConfirmation = false
	@State private var challengeCapturedAt = AO3ChallengeSessionStore.capturedAt
	@State private var isShowingChallengeSolver = false
	@State private var refetchInterval = AO3PrefaceRefetchPreference.current
	@State private var isKudosOnLikeEnabled = AO3KudosOnLikePreference.isEnabled
	@State private var isAmbrosiaContentUpdatesEnabled = AmbrosiaAO3NetworkPreference.contentUpdatesEnabled
	@State private var isAmbrosiaStatsUpdatesEnabled = AmbrosiaAO3NetworkPreference.statsUpdatesEnabled

	var body: some View {
		List {
			Section {
				HStack {
					Text(NSLocalizedString("Status", comment: "AO3 sign-in status row label"))
					Spacer()
					Text(isSignedIn
						 ? NSLocalizedString("Signed In", comment: "AO3 signed-in status")
						 : NSLocalizedString("Not Signed In", comment: "AO3 signed-out status"))
						.foregroundStyle(.secondary)
				}
			}

			Section {
				Toggle(NSLocalizedString("Pull Chapter Updates for Library Works", comment: "Ambrosia AO3 content-updates toggle label"), isOn: $isAmbrosiaContentUpdatesEnabled)
					.onChange(of: isAmbrosiaContentUpdatesEnabled) { _, newValue in
						AmbrosiaAO3NetworkPreference.contentUpdatesEnabled = newValue
					}
				Toggle(NSLocalizedString("Fetch AO3 Stats for Library Works", comment: "Ambrosia AO3 stats-updates toggle label"), isOn: $isAmbrosiaStatsUpdatesEnabled)
					.onChange(of: isAmbrosiaStatsUpdatesEnabled) { _, newValue in
						AmbrosiaAO3NetworkPreference.statsUpdatesEnabled = newValue
					}
			} footer: {
				Text(NSLocalizedString("Only affects works added to your library from Ambrosia/Calibre. Both are off by default so Nectar makes no AO3 requests for a purely local archive unless you turn one on. Works imported directly from an AO3 RSS feed always fetch live content -- there's no other way for them to get it.", comment: "Ambrosia AO3 network toggles footer"))
			}

			Section {
				Picker(NSLocalizedString("Check for Updates", comment: "AO3 preface refetch cadence picker label"), selection: $refetchInterval) {
					ForEach(AO3PrefaceRefetchInterval.allCases, id: \.self) { interval in
						Text(interval.description).tag(interval)
					}
				}
				.disabled(!isAmbrosiaContentUpdatesEnabled)
				.onChange(of: refetchInterval) { _, newValue in
					AO3PrefaceRefetchPreference.current = newValue
				}
			} footer: {
				Text(NSLocalizedString("How often Nectar rechecks an already-read-up-to-date AO3 work for new comments, kudos, hits, or formatting changes.", comment: "AO3 preface refetch cadence footer"))
			}

			Section {
				if isSignedIn {
					Button(role: .destructive) {
						isShowingSignOutConfirmation = true
					} label: {
						Text(NSLocalizedString("Sign Out", comment: "AO3 sign out button"))
							.frame(maxWidth: .infinity)
					}
				} else {
					Button {
						isShowingLogin = true
					} label: {
						Text(NSLocalizedString("Sign In to AO3", comment: "AO3 sign in button"))
							.frame(maxWidth: .infinity)
					}
				}
			} footer: {
				Text(NSLocalizedString("Signing in lets Nectar read works restricted to registered AO3 users. Nectar never sees your password, only the resulting session. Nectar can leave kudos on your behalf if you turn that on below -- it still can't subscribe, bookmark, or comment.", comment: "AO3 account section footer"))
			}

			Section {
				Toggle(NSLocalizedString("Leave Kudos When You Love a Work", comment: "AO3 kudos-on-like toggle label"), isOn: $isKudosOnLikeEnabled)
					.onChange(of: isKudosOnLikeEnabled) { _, newValue in
						AO3KudosOnLikePreference.isEnabled = newValue
					}
			} footer: {
				Text(isSignedIn
					 ? NSLocalizedString("When you love a work in Nectar, it also leaves a kudos on that work on AO3, using your signed-in AO3 account.", comment: "AO3 kudos-on-like footer, signed in")
					 : NSLocalizedString("When you love a work in Nectar, it also leaves a kudos on that work on AO3. You're not signed in, so it's left as a guest kudos -- sign in above to leave it as yourself instead.", comment: "AO3 kudos-on-like footer, signed out"))
			}

			Section {
				Text(NSLocalizedString("About Tag & User Feeds", comment: "AO3 RSS limitations info row title"))
					.font(.headline)
				Text(NSLocalizedString("AO3's tag and user RSS feeds only cover canonical tags -- a feed for a synonym or an uncommonly-spelled tag will come back empty even if the tag itself has works. Feeds can't combine multiple tags the way AO3's own filtered search results can.", comment: "AO3 RSS limitations: canonical tags and combining"))
					.foregroundStyle(.secondary)
				Text(NSLocalizedString("Works an author has archive-locked to registered users never appear in RSS at all, signed in or not -- RSS has no concept of an authenticated request. Nectar's AO3 sign-in above only helps once a locked work's link reaches Nectar some other way.", comment: "AO3 RSS limitations: archive-locked works"))
					.foregroundStyle(.secondary)
			} footer: {
				Text(NSLocalizedString("These are limits of AO3's existing RSS mechanism itself, not of Nectar.", comment: "AO3 RSS limitations section footer"))
			}

			Section {
				HStack {
					Text(NSLocalizedString("Browser Verification", comment: "AO3 Cloudflare challenge status row label"))
					Spacer()
					Text(challengeStatusText)
						.foregroundStyle(.secondary)
				}
				Button {
					isShowingChallengeSolver = true
				} label: {
					Text(NSLocalizedString("Verify Browser Access", comment: "AO3 Cloudflare challenge button"))
						.frame(maxWidth: .infinity)
				}
			} footer: {
				Text(NSLocalizedString("If an AO3 search-results feed reports a Cloudflare challenge, use this to prove to Cloudflare that Nectar is being used by a real person -- the same check AO3 shows in a regular browser sometimes. This isn't tied to your AO3 account and doesn't require being signed in; it usually needs re-doing periodically.", comment: "AO3 Cloudflare challenge section footer"))
			}
		}
		.navigationTitle(Text(verbatim: "Archive of Our Own"))
		.sheet(isPresented: $isShowingLogin, onDismiss: {
			// Covers both outcomes of the login sheet (signed in, or
			// cancelled) -- re-reading the store rather than trusting a
			// flag threaded back through the sheet keeps this in sync even
			// if AO3SessionStore changed for some other reason while the
			// sheet was up.
			isSignedIn = AO3SessionStore.isSignedIn
		}) {
			AO3LoginRepresentable()
		}
		.confirmationDialog(
			NSLocalizedString("Sign out of AO3?", comment: "AO3 sign out confirmation title"),
			isPresented: $isShowingSignOutConfirmation,
			titleVisibility: .visible
		) {
			Button(NSLocalizedString("Sign Out", comment: "AO3 sign out button"), role: .destructive) {
				AO3SessionStore.clearSession()
				isSignedIn = false
			}
			Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
		}
		.sheet(isPresented: $isShowingChallengeSolver, onDismiss: {
			// Covers both outcomes (cleared, or cancelled), same reasoning
			// as the login sheet's onDismiss above.
			challengeCapturedAt = AO3ChallengeSessionStore.capturedAt
		}) {
			AO3ChallengeSolverRepresentable()
		}
	}

	/// "Not yet verified" / "Verified just now" / "Verified 12 minutes ago"
	/// -- doesn't distinguish a stale (past AO3ChallengeSessionStore's
	/// freshness window) cookie from no cookie at all, since both need the
	/// same action from the person here; the freshness window itself is an
	/// internal implementation detail, not something worth surfacing as a
	/// countdown.
	private var challengeStatusText: String {
		guard let challengeCapturedAt else {
			return NSLocalizedString("Not Verified", comment: "AO3 Cloudflare challenge status: never verified")
		}
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		let relative = formatter.localizedString(for: challengeCapturedAt, relativeTo: Date())
		let format = NSLocalizedString("Verified %@", comment: "AO3 Cloudflare challenge status: verified some time ago")
		return String(format: format, relative)
	}
}

/// Bridges AO3LoginViewController (UIKit, WKWebView-based) into the sheet
/// above. Wrapped in its own UINavigationController here so the login
/// screen's title and Cancel button have somewhere to render -- the
/// presented sheet has no navigation chrome of its own otherwise.
private struct AO3LoginRepresentable: UIViewControllerRepresentable {

	@Environment(\.dismiss) private var dismiss

	func makeUIViewController(context: Context) -> UINavigationController {
		let loginViewController = AO3LoginViewController()
		loginViewController.delegate = context.coordinator
		return UINavigationController(rootViewController: loginViewController)
	}

	func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

	func makeCoordinator() -> Coordinator {
		Coordinator(dismiss: dismiss)
	}

	final class Coordinator: AO3LoginViewControllerDelegate {
		private let dismiss: DismissAction

		init(dismiss: DismissAction) {
			self.dismiss = dismiss
		}

		func ao3LoginViewControllerDidFinish(_ viewController: AO3LoginViewController) {
			dismiss()
		}
	}
}

/// Bridges AO3ChallengeSolverViewController into the sheet above, same
/// wrapping-in-a-UINavigationController reasoning as AO3LoginRepresentable.
///
/// Uses AO3's general works listing rather than any one specific
/// search-results URL: this screen is reached from Settings, not from a
/// particular feed's error, so there's no single URL to verify against
/// here. If it turns out Cloudflare gates specific query shapes
/// differently from the general listing, this default may need
/// revisiting -- unconfirmed either way from the available logs, which
/// only show the challenge on one search-results query.
private struct AO3ChallengeSolverRepresentable: UIViewControllerRepresentable {

	@Environment(\.dismiss) private var dismiss

	private static let defaultChallengeURL = URL(string: "https://archiveofourown.org/works")!

	func makeUIViewController(context: Context) -> UINavigationController {
		let solverViewController = AO3ChallengeSolverViewController(challengeURL: Self.defaultChallengeURL)
		solverViewController.delegate = context.coordinator
		return UINavigationController(rootViewController: solverViewController)
	}

	func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

	func makeCoordinator() -> Coordinator {
		Coordinator(dismiss: dismiss)
	}

	final class Coordinator: AO3ChallengeSolverViewControllerDelegate {
		private let dismiss: DismissAction

		init(dismiss: DismissAction) {
			self.dismiss = dismiss
		}

		func ao3ChallengeSolverViewControllerDidFinish(_ viewController: AO3ChallengeSolverViewController) {
			dismiss()
		}
	}
}

#Preview {
	NavigationStack {
		AO3AccountSettingsView()
	}
}
