//
//  AO3ChallengeSolverViewController.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 direct-reading support -- Cloudflare-challenge pass-through.
//
//  In-app WKWebView against a real, live AO3 search-results URL (the same
//  kind of URL AO3SearchResultsFetcher fetches headlessly). Mirrors
//  AO3LoginViewController's shape closely -- see that file's header
//  comment -- but captures a Cloudflare clearance cookie instead of a
//  login session, and detects success by content (no more challenge-page
//  markers in the rendered HTML) rather than by URL, since Cloudflare's
//  challenge resolves in place at the same URL rather than redirecting
//  elsewhere the way a successful AO3 login does.
//
//  This exists because a Cloudflare challenge is, by design, something
//  only a real browser executing real JS (and, for an interactive
//  Turnstile-style challenge, real touch input) can satisfy -- there's no
//  way to pass it from AO3SearchResultsFetcher's headless request, and
//  trying to fake one would defeat the point of showing this screen at
//  all. This screen doesn't do anything Cloudflare doesn't already expect
//  a browser to do; it just gives the person's own real browser session a
//  place to run inside the app, and hands the resulting cookie back to
//  the exact one-shot fetcher that needed it.
//

import UIKit
import WebKit
import Account

@MainActor protocol AO3ChallengeSolverViewControllerDelegate: AnyObject {
	/// Called once, either after the challenge clears (AO3ChallengeSessionStore
	/// already has the new cookie by the time this fires) or after the person
	/// taps Cancel. Callers should re-check AO3ChallengeSessionStore rather
	/// than assume success -- this single callback covers both outcomes,
	/// same as AO3LoginViewControllerDelegate.
	func ao3ChallengeSolverViewControllerDidFinish(_ viewController: AO3ChallengeSolverViewController)
}

final class AO3ChallengeSolverViewController: UIViewController {

	weak var delegate: AO3ChallengeSolverViewControllerDelegate?

	private var webView: WKWebView!
	private var didCaptureSession = false

	/// The AO3 URL to load -- normally the exact search-results URL that
	/// came back challenged, so the person is verifying against the actual
	/// page AO3SearchResultsFetcher needs, not just AO3's home page (which
	/// Cloudflare may gate independently, or not gate at all).
	private let challengeURL: URL

	init(challengeURL: URL) {
		self.challengeURL = challengeURL
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Verify Browser Access", comment: "AO3 Cloudflare challenge screen title")
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

		// Non-persistent, matching AO3LoginViewController: this screen
		// always starts clean, so success here always reflects this
		// attempt's own challenge, not a stale Cloudflare cookie left over
		// from a previous run of this same screen.
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(webView)
		self.webView = webView

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		])

		webView.load(URLRequest(url: challengeURL))
	}

	@objc private func cancelTapped() {
		delegate?.ao3ChallengeSolverViewControllerDidFinish(self)
	}
}

// MARK: - WKNavigationDelegate

extension AO3ChallengeSolverViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard !didCaptureSession else {
			return
		}

		// A navigation finishing doesn't by itself mean the challenge
		// cleared -- the interstitial page itself "finishes loading" too,
		// before its own JS resolves and (for an automatic, non-interactive
		// challenge) silently reloads the same URL, or (for an interactive
		// one) waits on the person. Check the rendered document itself for
		// the same markers AO3SearchResultsFetcher's headless fetch checks
		// for -- only their absence means this is the real results page.
		webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
			guard let self, let html = result as? String, !html.isEmpty else {
				return
			}
			guard !AO3CloudflareChallenge.isChallengePage(html) else {
				// Still on (or back on) the challenge page -- nothing to
				// capture yet. Leave the screen up; either Cloudflare's own
				// JS will navigate again (triggering another didFinish) or
				// the person is still working through an interactive
				// challenge on screen.
				return
			}
			self.didCaptureSession = true
			self.captureSessionAndFinish()
		}
	}

	private func captureSessionAndFinish() {
		webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
			guard let self else {
				return
			}

			let ao3Cookies = cookies.filter { $0.domain.contains("archiveofourown.org") }
			guard !ao3Cookies.isEmpty else {
				// Landed on a non-challenge page but got no cookies at all
				// -- treat as not actually cleared rather than storing an
				// empty session. Let the person try again.
				self.didCaptureSession = false
				return
			}

			let cookieHeaderValue = ao3Cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
			AO3ChallengeSessionStore.saveSession(cookieHeaderValue: cookieHeaderValue)
			self.delegate?.ao3ChallengeSolverViewControllerDidFinish(self)
		}
	}
}
