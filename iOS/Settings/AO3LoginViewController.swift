//
//  AO3LoginViewController.swift
//  NetNewsWire-iOS
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login")
//  -- see docs/ao3-merged-plan-nectar.md.
//
//  In-app WKWebView against AO3's real login page. Nectar never sees the
//  password, only the resulting session: on success, every archiveofourown.org
//  cookie is read back out of the WKWebView's own (non-persistent) cookie
//  store and handed to AO3SessionStore as a single Cookie header value --
//  nothing is typed into or scraped out of the page by this code.
//

import UIKit
import WebKit
import Account

/// @MainActor: this delegate only ever fires from UIKit code that's already
/// on the main actor (a view controller lifecycle callback, or a
/// WKHTTPCookieStore completion handler that calls back on the main queue),
/// and SwiftUI's Coordinator conformance in AO3AccountSettingsView.swift
/// needs to call MainActor-isolated APIs (DismissAction) synchronously from
/// inside its implementation of this method. Without this annotation, the
/// protocol requirement defaults to nonisolated, and the compiler won't let
/// a nonisolated method call DismissAction synchronously.
@MainActor protocol AO3LoginViewControllerDelegate: AnyObject {
	/// Called once, either after a successful sign-in (AO3SessionStore
	/// already has the new session by the time this fires) or after the
	/// person taps Cancel. Callers should re-check
	/// `AO3SessionStore.isSignedIn` rather than assume success -- this
	/// single callback covers both outcomes.
	func ao3LoginViewControllerDidFinish(_ viewController: AO3LoginViewController)
}

final class AO3LoginViewController: UIViewController {

	weak var delegate: AO3LoginViewControllerDelegate?

	private var webView: WKWebView!
	private var didCaptureSession = false

	private let loginURL = URL(string: "https://archiveofourown.org/users/login")!

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Sign In to AO3", comment: "AO3 login screen title")
		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

		// Non-persistent data store: this screen should always start from
		// a logged-out state in AO3's eyes, regardless of any AO3 session
		// already present in Safari or left over from a previous run of
		// this same screen -- otherwise the "did sign-in just succeed"
		// check below could be satisfied by a stale or unrelated cookie
		// instead of this actual attempt.
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

		webView.load(URLRequest(url: loginURL))
	}

	@objc private func cancelTapped() {
		delegate?.ao3LoginViewControllerDidFinish(self)
	}
}

// MARK: - WKNavigationDelegate

extension AO3LoginViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard !didCaptureSession, let url = webView.url else {
			return
		}

		// Heuristic, not a confirmed signal from AO3's own markup
		// (unverified against a real login attempt in this environment,
		// since nothing here can drive an actual browser session): Devise
		// (AO3's login framework) re-renders /users/login in place with a
		// flash error on a failed attempt, and redirects elsewhere --
		// back to whatever `return_to` pointed at, or to AO3's home page --
		// on success. If AO3 ever keeps someone on /users/login after a
		// genuinely successful sign-in (a client-side redirect, an
		// interstitial page), this check needs revisiting.
		guard url.host?.contains("archiveofourown.org") == true, url.path != "/users/login" else {
			return
		}

		didCaptureSession = true
		captureSessionAndFinish()
	}

	private func captureSessionAndFinish() {
		webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
			guard let self else {
				return
			}

			let ao3Cookies = cookies.filter { $0.domain.contains("archiveofourown.org") }
			guard !ao3Cookies.isEmpty else {
				// Reached a non-login-page URL but got no cookies at all --
				// treat as not actually signed in rather than storing an
				// empty session. Let the person try again rather than
				// silently finishing.
				self.didCaptureSession = false
				return
			}

			let cookieHeaderValue = ao3Cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
			AO3SessionStore.saveSession(cookieHeaderValue: cookieHeaderValue)
			self.delegate?.ao3LoginViewControllerDidFinish(self)
		}
	}
}
