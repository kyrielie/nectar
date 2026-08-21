//
//  AO3SearchResultsFetchCoordinator.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 search-results refresh-cadence work: WKWebView HTML-harvest
//  fallback -- see docs/ao3-integration.md.
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
		case imported(newWorkCount: Int, hasNextPage: Bool, pageTitle: String?)
		case noResults(pageTitle: String?)
		case registrationRequired
		case rateLimited
		/// Headless fetch was Cloudflare-challenged. Caller should show an
		/// opt-in prompt ("AO3 needs verification -- tap to continue");
		/// if the person accepts, call `presentSolverAndRetry`.
		case needsVerification(challengedURL: URL)
		case cancelled          // person dismissed the WKWebView screen
		case failed(String)
		/// See `AO3SearchResultsFetchOutcome.notSignedIn`'s own doc
		/// comment -- reachable here only if this coordinator is ever
		/// pointed at an always-authenticated listing feed
		/// (subscriptions, marked-for-later); today it's only used for
		/// the Cloudflare-challenge retry path, which every listing type
		/// can hit, so this case must still be handled even though the
		/// headless `fetch(url:feedURL:)` this wraps doesn't do the
		/// sign-in retry itself.
		case notSignedIn
	}

	/// Tries the headless path only -- does not present anything. On a
	/// Cloudflare challenge, returns `.needsVerification` so the caller
	/// can decide how to prompt, rather than presenting automatically.
	func fetch(url: URL, feedURL: String) async -> Outcome {
		do {
			switch try await AO3SearchResultsFetcher.fetch(url: url, feedURL: feedURL) {
			case .success(let parsedItems, let hasNextPage, let pageTitle, _):
				return .imported(newWorkCount: parsedItems.count, hasNextPage: hasNextPage, pageTitle: pageTitle)
			case .noResults(let pageTitle, _):
				return .noResults(pageTitle: pageTitle)
			case .registrationRequired:
				return .registrationRequired
			case .rateLimited:
				return .rateLimited
			case .cloudflareChallenge(let challengedURL):
				return .needsVerification(challengedURL: challengedURL)
			case .notSignedIn:
				return .notSignedIn
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
	///
	/// `updatesFeedName` controls whether a successful import is allowed to
	/// (re)name the feed off the harvested page's `<title>` -- automatic
	/// naming happens once, at add time, only; a person's own rename
	/// always wins after that. `AddFeedViewController` (create-time
	/// challenge) passes `true`; every later retry -- `advancePageTo == 1`
	/// or not -- passes `false`. This is a separate, explicit parameter
	/// rather than inferred from `advancePageTo == 1`, since the
	/// inspector's arbitrary-fetch action can deliberately refetch page 1
	/// itself (a real, expected case under the "additive" rule), so
	/// `advancePageTo == 1` no longer reliably means "this is the initial
	/// add-time fetch."
	func presentSolverAndRetry(challengedURL: URL, feedURL: String, feed: Feed, account: Account, advancePageTo: Int?, updatesFeedName: Bool, presentingViewController: UIViewController) async -> Outcome {
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
		case .imported(let newWorkCount, let hasNextPage, let pageTitle):
			// feed.name only, never editedName -- editedName is
			// exclusively written by an explicit user rename
			// (Account.renameFeed/LocalAccountDelegate.renameFeed), so
			// this can never clobber a hand-typed name. Gated on
			// updatesFeedName (see this method's own doc comment) --
			// only the create-time challenge retry renames; a later
			// "load more" or inspector arbitrary-fetch retry must not,
			// since the feed is already named.
			if updatesFeedName, let pageTitle {
				feed.name = pageTitle
			}
			return .imported(newWorkCount: newWorkCount, hasNextPage: hasNextPage, pageTitle: pageTitle)
		case .noResults(let pageTitle):
			if updatesFeedName, let pageTitle {
				feed.name = pageTitle
			}
			return .noResults(pageTitle: pageTitle)
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
