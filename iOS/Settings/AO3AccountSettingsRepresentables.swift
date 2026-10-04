//
//  AO3AccountSettingsRepresentables.swift
//  NetNewsWire-iOS
//
//  UIKit bridges for AO3AccountSettingsView's two sheets: the WKWebView
//  login and the Cloudflare challenge solver. Split out of
//  AO3AccountSettingsView.swift; behavior unchanged.
//

import SwiftUI
import UIKit
import AO3Kit

/// Bridges AO3LoginViewController (UIKit, WKWebView-based) into the sheet
/// above. Wrapped in its own UINavigationController here so the login
/// screen's title and Cancel button have somewhere to render -- the
/// presented sheet has no navigation chrome of its own otherwise.
struct AO3LoginRepresentable: UIViewControllerRepresentable {

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
/// Defaults to `AO3ChallengeSessionStore.lastChallengedURL` -- the actual
/// URL a feed most recently got challenged on -- falling back to AO3's
/// general works listing only if no challenge has been recorded yet (e.g.
/// the very first time someone opens this screen before ever seeing the
/// error). Confirmed necessary, not just theoretical: the generic listing
/// loaded fine with no challenge at all in testing, while the specific
/// `work_search[...]` query for the same account kept getting one -- so a
/// fixed generic URL here could report "cleared" without ever having
/// exercised the gate that actually matters.
struct AO3ChallengeSolverRepresentable: UIViewControllerRepresentable {

	@Environment(\.dismiss) private var dismiss

	func makeUIViewController(context: Context) -> UINavigationController {
		let challengeURL = AO3ChallengeSessionStore.lastChallengedURL ?? AO3Link.worksURL
		let solverViewController = AO3ChallengeSolverViewController(challengeURL: challengeURL)
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
