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
	@State private var refetchInterval = AO3PrefaceRefetchPreference.current

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
				Picker(NSLocalizedString("Check for Updates", comment: "AO3 preface refetch cadence picker label"), selection: $refetchInterval) {
					ForEach(AO3PrefaceRefetchInterval.allCases, id: \.self) { interval in
						Text(interval.description).tag(interval)
					}
				}
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
				Text(NSLocalizedString("Signing in lets Nectar read works restricted to registered AO3 users. Nectar never sees your password, only the resulting session. Sign-in is for reading only -- Nectar can't post kudos, subscribe, bookmark, or comment.", comment: "AO3 account section footer"))
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

#Preview {
	NavigationStack {
		AO3AccountSettingsView()
	}
}
