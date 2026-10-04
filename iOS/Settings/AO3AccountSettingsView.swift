import AO3Kit
//
//  AO3AccountSettingsView.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login").
//
//  Pushed from SettingsViewController's new "Archive of Our Own" row,
//  following the same UIHostingController-push pattern as AboutView and
//  AccountStatsView elsewhere in this file's section.
//

import SwiftUI
import UIKit
import Account

struct AO3AccountSettingsView: View {

	@State private var model = AO3SettingsModel()
	@State private var isShowingLogin = false
	@State private var isShowingSignOutConfirmation = false
	@State private var isShowingChallengeSolver = false
	@State private var refetchInterval = AO3PrefaceRefetchPreference.current
	@State private var isKudosOnLikeEnabled = AO3KudosOnLikePreference.isEnabled
	@State private var isAmbrosiaUpdatesEnabled = AmbrosiaAO3NetworkPreference.updatesEnabled
	@State private var isPrefetchNewWorksEnabled = AO3PrefetchNewWorksPreference.isEnabled

	/// Pushes the Works Needing Attention screen. A closure, because this
	/// view is hosted in a UIHostingController pushed on Settings'
	/// UINavigationController, so the push belongs to SettingsViewController.
	var onShowWorksNeedingAttention: () -> Void = {}

	var body: some View {
		List {
			if let sessionEnded = model.sessionEnded, !model.isSignedIn {
				Section {
					Text(sessionEndedText(date: sessionEnded.date))
					Button {
						isShowingLogin = true
					} label: {
						Text(NSLocalizedString("Sign In to AO3", comment: "AO3 sign in button"))
							.frame(maxWidth: .infinity)
					}
				}
			}

			if let resumeDate = model.rateLimitResumeDate {
				Section {
					Text(rateLimitText(resumeDate: resumeDate))
				}
			}

			Section {
				HStack {
					Text(NSLocalizedString("Status", comment: "AO3 sign-in status row label"))
					Spacer()
					Text(model.isSignedIn
						 ? NSLocalizedString("Signed In", comment: "AO3 signed-in status")
						 : NSLocalizedString("Not Signed In", comment: "AO3 signed-out status"))
						.foregroundStyle(.secondary)
				}
			}

			Section {
				Toggle(NSLocalizedString("Fetch AO3 Updates for Library Works", comment: "Ambrosia AO3 updates toggle label"), isOn: $isAmbrosiaUpdatesEnabled)
					.onChange(of: isAmbrosiaUpdatesEnabled) { _, newValue in
						AmbrosiaAO3NetworkPreference.updatesEnabled = newValue
					}
			} footer: {
				Text(NSLocalizedString("Only affects works added to your library from Ambrosia/Calibre. Off by default so Nectar makes no AO3 requests for a purely local archive unless you turn this on. When on, both chapter text and stats (kudos/comments/hits) stay in sync with the live AO3 version; a fetch that looks like it removed chapters or lost a large amount of text is held back for review instead of applied automatically. Works imported directly from an AO3 RSS feed always fetch live content -- there's no other way for them to get it.", comment: "Ambrosia AO3 network toggle footer"))
			}

			Section {
				Picker(NSLocalizedString("Check for Updates", comment: "AO3 preface refetch cadence picker label"), selection: $refetchInterval) {
					ForEach(AO3PrefaceRefetchInterval.allCases, id: \.self) { interval in
						Text(interval.description).tag(interval)
					}
				}
				.onChange(of: refetchInterval) { _, newValue in
					AO3PrefaceRefetchPreference.current = newValue
				}
			} footer: {
				Text(NSLocalizedString("How often Nectar rechecks an already-read-up-to-date AO3 work for new comments, kudos, hits, or formatting changes. Works from AO3 feeds always follow this. Works in your library follow it only when Fetch AO3 Updates for Library Works is turned on above.", comment: "AO3 preface refetch cadence footer"))
			}

			Section {
				Toggle(NSLocalizedString("Fetch New Works Immediately", comment: "AO3 prefetch-on-arrival toggle label"), isOn: $isPrefetchNewWorksEnabled)
					.onChange(of: isPrefetchNewWorksEnabled) { _, newValue in
						AO3PrefetchNewWorksPreference.isEnabled = newValue
					}
			} footer: {
				Text(NSLocalizedString("Downloads a work's text as soon as it appears in your tag and user shelves, instead of waiting until you open it. Uses more AO3 requests, but protects against a work being deleted or locked before you get to it. Off by default. Doesn't apply to AO3 search results, which never fetch content automatically.", comment: "AO3 prefetch-on-arrival toggle footer"))
			}

			Section {
				if model.isSignedIn {
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
				Text(NSLocalizedString("Signing in lets Nectar read works restricted to registered AO3 users. Nectar never sees your password, only the resulting session. Nectar can leave kudos on your behalf if you turn that on below -- it still can't subscribe, bookmark, or comment. Signing out also signs you out of Nectar's in-app AO3 browser.", comment: "AO3 account section footer"))
			}

			Section {
				Toggle(NSLocalizedString("Leave Kudos When You Love a Work", comment: "AO3 kudos-on-like toggle label"), isOn: $isKudosOnLikeEnabled)
					.onChange(of: isKudosOnLikeEnabled) { _, newValue in
						AO3KudosOnLikePreference.isEnabled = newValue
					}
			} footer: {
				Text(model.isSignedIn
					 ? NSLocalizedString("When you love a work in Nectar, it also leaves a kudos on that work on AO3, using your signed-in AO3 account.", comment: "AO3 kudos-on-like footer, signed in")
					 : NSLocalizedString("When you love a work in Nectar, it also leaves a kudos on that work on AO3. You're not signed in, so it's left as a guest kudos -- sign in above to leave it as yourself instead.", comment: "AO3 kudos-on-like footer, signed out"))
			}

			Section {
				Button {
					onShowWorksNeedingAttention()
				} label: {
					HStack {
						Text(NSLocalizedString("Works Needing Attention", comment: "AO3 settings: works needing attention row title"))
							.foregroundStyle(.primary)
						Spacer()
						Image(systemName: "chevron.right")
							.font(.footnote.weight(.semibold))
							.foregroundStyle(.tertiary)
					}
				}
			} footer: {
				Text(NSLocalizedString("Works with an update waiting for your review, and works Nectar could not refresh from AO3.", comment: "AO3 settings: works needing attention row footer"))
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
				Text(NSLocalizedString("If an AO3 search-results shelf reports a Cloudflare challenge, use this to prove to Cloudflare that Nectar is being used by a real person -- the same check AO3 shows in a regular browser sometimes. This isn't tied to your AO3 account and doesn't require being signed in; it usually needs re-doing periodically.", comment: "AO3 Cloudflare challenge section footer"))
			}
		}
		.navigationTitle(Text(verbatim: "Archive of Our Own"))
		.sheet(isPresented: $isShowingLogin, onDismiss: {
			// Covers both outcomes of the login sheet (signed in, or
			// cancelled) -- re-reading the store rather than trusting a
			// flag threaded back through the sheet keeps this in sync even
			// if AO3SessionStore changed for some other reason while the
			// sheet was up.
			model.refresh()
		}, content: {
			AO3LoginRepresentable()
		})
		.confirmationDialog(
			NSLocalizedString("Sign out of AO3?", comment: "AO3 sign out confirmation title"),
			isPresented: $isShowingSignOutConfirmation,
			titleVisibility: .visible
		) {
			Button(NSLocalizedString("Sign Out", comment: "AO3 sign out button"), role: .destructive) {
				AO3SessionStore.clearSession()
				model.refresh()
				Task {
					await AO3AuthenticatedWebViewController.clearBrowserData()
				}
			}
			Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
		}
		.sheet(isPresented: $isShowingChallengeSolver, onDismiss: {
			// Covers both outcomes (cleared, or cancelled), same reasoning
			// as the login sheet's onDismiss above.
			model.refresh()
		}, content: {
			AO3ChallengeSolverRepresentable()
		})
		.onAppear {
			model.refresh()
		}
		.onDisappear {
			model.stop()
		}
	}

	private func sessionEndedText(date: Date) -> String {
		let format = NSLocalizedString("Your AO3 session ended on %@. Sign in again to read restricted works.", comment: "AO3 settings: session ended notice; %@ is a date")
		return String(format: format, date.formatted(date: .abbreviated, time: .omitted))
	}

	private func rateLimitText(resumeDate: Date) -> String {
		let format = NSLocalizedString("AO3 asked Nectar to slow down. Requests resume at %@.", comment: "AO3 settings: rate limit notice; %@ is a time")
		return String(format: format, resumeDate.formatted(date: .omitted, time: .shortened))
	}

	/// "Not yet verified" / "Verified just now" / "Verified 12 minutes ago"
	/// -- doesn't distinguish a stale (past AO3ChallengeSessionStore's
	/// freshness window) cookie from no cookie at all, since both need the
	/// same action from the person here; the freshness window itself is an
	/// internal implementation detail, not something worth surfacing as a
	/// countdown.
	private var challengeStatusText: String {
		guard let challengeCapturedAt = model.challengeCapturedAt else {
			return NSLocalizedString("Not Verified", comment: "AO3 Cloudflare challenge status: never verified")
		}
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		let relative = formatter.localizedString(for: challengeCapturedAt, relativeTo: Date())
		let format = NSLocalizedString("Verified %@", comment: "AO3 Cloudflare challenge status: verified some time ago")
		return String(format: format, relative)
	}
}

#Preview {
	NavigationStack {
		AO3AccountSettingsView()
	}
}
