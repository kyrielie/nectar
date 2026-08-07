//
//  AO3SearchResultsFetchCoordinator.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 search-results refresh-cadence work, Workstream C
//  (WKWebView HTML-harvest fallback) -- see
//  nectar-ao3-search-refresh-plan.md.
//
//  Presented as an opt-in prompt, not automatically: callers invoke
//  `fetch(...)`, and on `.needsVerification` show their own "AO3 needs
//  verification" banner/prompt; only if the person taps through does the
//  caller call `presentSolverAndRetry(...)` to actually show the
//  WKWebView. This coordinator itself never presents anything the person
//  didn't opt into.
//
//  Named/located under iOS/Settings/ alongside AO3ChallengeSolverViewController
//  and AO3AccountSettingsView, which already own the manual "Verify Browser
//  Access" flow this reuses -- not moved to a new iOS/AO3/ grouping this
//  pass; revisit if/when enough AO3-specific iOS code accumulates to
//  justify one.
//

import UIKit
import Account

@MainActor final class AO3SearchResultsFetchCoordinator {

	enum Outcome {
		case imported(newWorkCount: Int, hasNextPage: Bool)
		case noResults
		case registrationRequired
		case rateLimited
		/// Headless fetch was Cloudflare-challenged. Caller should show an
		/// opt-in prompt ("AO3 needs verification -- tap to continue");
		/// if the person accepts, call `presentSolverAndRetry`.
		case needsVerification(challengedURL: URL)
		case cancelled          // person dismissed the WKWebView screen
		case failed(String)
	}

	/// Tries the headless path only -- does not present anything. On a
	/// Cloudflare challenge, returns `.needsVerification` so the caller
	/// can decide how to prompt, rather than presenting automatically.
	func fetch(url: URL, feedURL: String) async -> Outcome {
		do {
			switch try await AO3SearchResultsFetcher.fetch(url: url, feedURL: feedURL) {
			case .success(let parsedItems, let hasNextPage):
				return .imported(newWorkCount: parsedItems.count, hasNextPage: hasNextPage)
			case .noResults:
				return .noResults
			case .registrationRequired:
				return .registrationRequired
			case .rateLimited:
				return .rateLimited
			case .cloudflareChallenge(let challengedURL):
				return .needsVerification(challengedURL: challengedURL)
			}
		} catch {
			return .failed(error.localizedDescription)
		}
	}

	/// Presents the WKWebView challenge-solver against `challengedURL`
	/// from `presentingViewController`; once the challenge clears,
	/// harvests the rendered HTML and imports it via
	/// `AO3SearchResultsImporter` instead of retrying headlessly (see this
	/// file's own header comment on why: no second request, no UA/cookie-
	/// binding question -- the page parsed is the exact page a real
	/// browser rendered).
	///
	/// Only called after the caller's own opt-in prompt
	/// (`.needsVerification` above) -- this method itself always presents
	/// immediately.
	func presentSolverAndRetry(challengedURL: URL, feedURL: String, feed: Feed, account: Account, advancePageTo: Int?, presentingViewController: UIViewController) async -> Outcome {
		let delegate = SolverDelegate()

		let solverViewController = AO3ChallengeSolverViewController(challengeURL: challengedURL) { html in
			delegate.harvestedHTML = html
		}
		solverViewController.delegate = delegate

		let navigationController = UINavigationController(rootViewController: solverViewController)
		presentingViewController.present(navigationController, animated: true)

		// AO3ChallengeSolverViewControllerDidFinish fires once, covering
		// both "challenge cleared" (onHTMLHarvested already ran first,
		// same-turn, since captureSessionAndFinish calls it right before
		// the delegate callback) and "person tapped Cancel" (never ran).
		await withCheckedContinuation { continuation in
			delegate.onFinish = { continuation.resume() }
		}
		navigationController.presentingViewController?.dismiss(animated: true)

		guard let html = delegate.harvestedHTML else {
			return .cancelled
		}

		let importOutcome = await AO3SearchResultsImporter.importFetchedPage(html: html, feedURL: feedURL, feed: feed, account: account, advancePageTo: advancePageTo)
		switch importOutcome {
		case .imported(let newWorkCount, let hasNextPage):
			return .imported(newWorkCount: newWorkCount, hasNextPage: hasNextPage)
		case .noResults:
			return .noResults
		case .registrationRequired:
			return .registrationRequired
		}
	}
}

/// Bridges `AO3ChallengeSolverViewControllerDelegate`'s single callback to
/// something this coordinator can read synchronously once it fires --
/// `harvestedHTML` is set (by the `onHTMLHarvested` closure, which fires
/// before this delegate callback per
/// `AO3ChallengeSolverViewController.captureSessionAndFinish`) only on the
/// success path, so its presence after `onFinish` is exactly the signal
/// `presentSolverAndRetry` needs to distinguish "harvested" from
/// "cancelled".
@MainActor private final class SolverDelegate: NSObject, AO3ChallengeSolverViewControllerDelegate {
	var harvestedHTML: String?
	var onFinish: (() -> Void)?

	func ao3ChallengeSolverViewControllerDidFinish(_ viewController: AO3ChallengeSolverViewController) {
		onFinish?()
	}
}
