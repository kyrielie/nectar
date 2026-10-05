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

	/// Pushes the ignore list manager, same reason as above.
	var onShowIgnoreList: () -> Void = {}

	var body: some View {
		List {
			if let sessionEnded = model.sessionEnded, !model.isSignedIn {
				Section {
					Text(sessionEndedText(date: sessionEnded.date))
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
			} header: {
				Text(NSLocalizedString("AO3 Account", comment: "AO3 settings: account section header"))
			} footer: {
				Text(NSLocalizedString("Lets Nectar read works restricted to registered AO3 users. Nectar never sees your password.", comment: "AO3 account section footer"))
			}

			Section {
				Toggle(NSLocalizedString("Fetch AO3 Updates for Library Works", comment: "Ambrosia AO3 updates toggle label"), isOn: $isAmbrosiaUpdatesEnabled)
					.onChange(of: isAmbrosiaUpdatesEnabled) { _, newValue in
						AmbrosiaAO3NetworkPreference.updatesEnabled = newValue
					}
				Picker(NSLocalizedString("Check for Updates", comment: "AO3 preface refetch cadence picker label"), selection: $refetchInterval) {
					ForEach(AO3PrefaceRefetchInterval.allCases, id: \.self) { interval in
						Text(interval.description).tag(interval)
					}
				}
				.onChange(of: refetchInterval) { _, newValue in
					AO3PrefaceRefetchPreference.current = newValue
				}
				Toggle(NSLocalizedString("Fetch New Works Immediately", comment: "AO3 prefetch-on-arrival toggle label"), isOn: $isPrefetchNewWorksEnabled)
					.onChange(of: isPrefetchNewWorksEnabled) { _, newValue in
						AO3PrefetchNewWorksPreference.isEnabled = newValue
					}
			} header: {
				Text(NSLocalizedString("Updates", comment: "AO3 settings: updates section header"))
			} footer: {
				Text(NSLocalizedString("Fetch New Works Immediately downloads each work as it arrives. AO3 limits how fast apps can request pages, so Nectar paces downloads and pauses if AO3 asks it to slow down.", comment: "AO3 prefetch-on-arrival toggle footer"))
			}

			Section {
				Toggle(NSLocalizedString("Leave Kudos When You Love a Work", comment: "AO3 kudos-on-like toggle label"), isOn: $isKudosOnLikeEnabled)
					.onChange(of: isKudosOnLikeEnabled) { _, newValue in
						AO3KudosOnLikePreference.isEnabled = newValue
					}
			} header: {
				Text(NSLocalizedString("Kudos on AO3", comment: "AO3 settings: kudos section header"))
			} footer: {
				Text(model.isSignedIn
					 ? NSLocalizedString("Also leaves kudos on AO3 from your account.", comment: "AO3 kudos-on-like footer, signed in")
					 : NSLocalizedString("Also leaves kudos on AO3 as a guest. Sign in to use your account.", comment: "AO3 kudos-on-like footer, signed out"))
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
				Button {
					onShowIgnoreList()
				} label: {
					HStack {
						Text(NSLocalizedString("Ignored Works and Authors", comment: "AO3 settings: ignore list row title"))
							.foregroundStyle(.primary)
						Spacer()
						Image(systemName: "chevron.right")
							.font(.footnote.weight(.semibold))
							.foregroundStyle(.tertiary)
					}
				}
			} header: {
				Text(NSLocalizedString("Works and Authors", comment: "AO3 settings: works and authors section header"))
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
			} header: {
				Text(NSLocalizedString("Troubleshooting", comment: "AO3 settings: troubleshooting section header"))
			} footer: {
				Text(NSLocalizedString("Use this if AO3 shows a Cloudflare challenge. Not tied to your account.", comment: "AO3 Cloudflare challenge section footer"))
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
