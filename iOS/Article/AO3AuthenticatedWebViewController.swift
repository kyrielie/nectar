//
//  AO3AuthenticatedWebViewController.swift
//  NetNewsWire-iOS
//
//  Nectar fixes plan 3, item 3 ("Open AO3 links using the AO3 user's
//  Nectar login, if signed in"). See docs/nectar-fixes-plan-3.md.
//
//  SFSafariViewController always uses the system's shared Safari
//  cookie jar, with no API to hand it a custom cookie store -- so an
//  AO3 session can never follow an in-app link tap into it. This is a
//  small, dedicated WKWebView-based browser instead, scoped to AO3
//  links opened in-app (WebViewController routes them here instead of
//  SFSafariViewController -- see AO3LinkListImporter.isAO3Host(_:)).
//
//  Deliberately NOT wired to AO3SessionStore (the Settings > Sign In
//  to AO3 flow's captured session -- see AO3LoginViewController): that
//  store exists for AO3AuthenticatedFetcher's manual Cookie header
//  replay on plain URLSession requests, a different mechanism with a
//  different shape (a single Cookie-header string, not a cookie jar).
//  This view instead uses its own WKWebsiteDataStore, scoped to a
//  fixed identifier and persistent across launches -- WKWebView/WebKit
//  handle all Set-Cookie/session-cookie persistence for it
//  automatically, the same way any browser would, including a
//  "remember me" login performed directly inside this view. No cookie
//  reading, writing, or capturing code is needed here for that to
//  work.
//
//  The fixed identifier -- not WKWebsiteDataStore.default() -- keeps
//  this session isolated from the article-reading WKWebView elsewhere
//  in the app (WebViewController), which renders arbitrary feed/
//  article HTML+JS. That content shouldn't be able to reach a signed-
//  in AO3 session's cookies just by sharing a data store.
//

import UIKit
import WebKit
import Account

final class AO3AuthenticatedWebViewController: UIViewController {

	/// Fixed, not per-instance -- WKWebsiteDataStore(forIdentifier:) with
	/// a stable UUID is what makes this persistent across separate opens
	/// of this screen (and across app relaunches, since it's disk-backed
	/// the same way .default() is). Generating a fresh UUID per-open
	/// would create a new, empty store every time and defeat persistence
	/// entirely -- this must never become `UUID()`.
	private static let dataStoreIdentifier = UUID(uuidString: "8C6C7C7E-9A8B-4B2C-9C2E-2E6E9B7B9E4A")!

	private var webView: WKWebView!
	private var progressObservation: NSKeyValueObservation?

	private let initialURL: URL

	init(url: URL) {
		self.initialURL = url
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
		navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "safari"), style: .plain, target: self, action: #selector(openInSafariTapped))

		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(webView)
		self.webView = webView

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
		])

		// Mirrors the article reader's own titlebar behavior -- the page's
		// own <title> once known, a static fallback until then.
		title = NSLocalizedString("AO3", comment: "AO3 in-app browser fallback title")
		// KVO's observe(_:options:changeHandler:) closure is non-isolated
		// (fires synchronously off whatever thread the KVO change happens
		// on, in principle -- WKWebView's own `title` KVO only ever fires
		// on main in practice, but the closure's type doesn't know that),
		// so it can't touch either `webView.title` (WKWebView, like any
		// UIView subclass, is main-actor-isolated) or `self.title`
		// (UIViewController's own `title`) directly. DispatchQueue.main.async
		// hops back to the main actor to read and write both there --
		// deliberately not `Task { @MainActor in ... }`, which would make
		// the closure `@Sendable` and flag capturing the non-Sendable
		// `webView`/`self` in the first place; GCD's plain `() -> Void`
		// closure type predates Sendable checking and isn't held to it.
		progressObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
			DispatchQueue.main.async {
				guard let newTitle = webView.title, !newTitle.isEmpty else { return }
				self?.title = newTitle
			}
		}

		webView.load(URLRequest(url: initialURL))
	}

	@objc private func doneTapped() {
		dismiss(animated: true)
	}

	@objc private func openInSafariTapped() {
		// Escape hatch mirroring what SFSafariViewController gave for
		// free -- this hands off to the system browser, not this
		// screen's own persistent session (there's no API to carry a
		// WKWebsiteDataStore's cookies into Safari.app).
		let url = webView.url ?? initialURL
		UIApplication.shared.open(url, options: [:])
	}
}

extension AO3AuthenticatedWebViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		presentLoadError(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		presentLoadError(error)
	}

	private func presentLoadError(_ error: Error) {
		// (NSURLErrorDomain, -999) is a benign cancellation (e.g. a second
		// load starting before the first finishes) -- not worth an alert.
		let nsError = error as NSError
		guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
			return
		}
		let alert = UIAlertController(title: NSLocalizedString("Couldn't Load Page", comment: "AO3 in-app browser load error title"), message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(.init(title: NSLocalizedString("Dismiss", comment: "Dismiss"), style: .cancel, handler: nil))
		present(alert, animated: true)
	}
}
