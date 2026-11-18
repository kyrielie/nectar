//
//  ArticleThemeColorProbe.swift
//  ArticleTheming
//
//  Measures the colors a theme actually paints, instead of scanning its CSS.
//  The theme is rendered through the reader's real `page.html` in a hidden
//  `WKWebView`, once in light and once in dark, and read back by a user
//  script that posts to a message handler. No `evaluateJavaScript`, and
//  content JavaScript stays off (the reader's own setting), so a theme's own
//  scripts cannot influence the measurement.
//
//  Implemented here:
//  page color is `background-color` only (body over html over the legacy
//  white/black fallback), ink is `.articleBody`'s `color`, link is the first
//  `.articleBody a`, every color is normalized to opaque sRGB through a 2D
//  canvas, and a measurement that fails the sanity check is discarded.
//

import UIKit
import WebKit
import os
import RSCore

// MARK: - Probe

@MainActor public enum ArticleThemeColorProbe {

	/// Bump only when the probe's own logic changes (not for `core.css` changes,
	/// which the cache tracks through its own hash).
	public nonisolated static let version = 1

	/// Rollback switch. When false the store never measures and never serves a
	/// measurement, and the theme gate assigns synchronously with scanner colors, which
	/// restores the pre-probe behavior without touching any call site.
	public nonisolated static let isEnabled = true

	/// Seconds to wait for the read-back message from one pass.
	static let passTimeout: Duration = .seconds(5)

	/// Pre-decided fallback if the hidden window does not flip `prefers-color-scheme`
	/// (acceptance test 1): keep the window and the web view in it, but make both
	/// technically visible at near-zero alpha. Never switch to `evaluateJavaScript`.
	/// Now true: the first CI run of the probe suites (iPhone 17 simulator, iOS 26.3.1)
	/// got no read-back at all from the hidden-window host (every measurement nil, 84
	/// matrix pages without the requested appearance).
	static let useVisibleHostFallback = true

	static let messageHandlerName = "themeColorProbe"

	private static let log = Logger(subsystem: "com.nectar.ArticleTheming", category: "ThemeColorProbe")

	/// Layout size of the probe web view. A realistic phone width keeps
	/// width-dependent media queries on the reader's side of any breakpoint.
	static let webViewFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
	private static var passRunners: [Bool: PassRunner]?
	private static var passRunnerReleaseTask: Task<Void, Never>?

	/// WebKit is shared by the color probe and the simulator theme-render checks. Keep
	/// their WebViews serialized even when Swift Testing runs different suites in parallel;
	/// otherwise the simulator launches and tears down many WebContent processes at once.
	private static var webViewPermitHeld = false
	private static var webViewPermitWaiters = [CheckedContinuation<Void, Never>]()

	/// Acquires the process-wide permit for simulator theme rendering. Test-only renderers
	/// use the same permit via `@testable import ArticleTheming`.
	static func acquireWebViewPermit() async {
		await withCheckedContinuation { continuation in
			if webViewPermitHeld {
				webViewPermitWaiters.append(continuation)
			} else {
				webViewPermitHeld = true
				continuation.resume()
			}
		}
	}

	static func releaseWebViewPermit() {
		if webViewPermitWaiters.isEmpty {
			webViewPermitHeld = false
		} else {
			webViewPermitWaiters.removeFirst().resume()
		}
	}

	/// Renders `theme` in light and dark and returns what it painted, or nil if
	/// anything was unreadable or implausible (see `ThemeColorProbeLogic.isSane`).
	/// Calls are serialized: one measurement at a time.
	public static func measure(_ theme: ArticleTheme,
	                           environment: ArticleThemeProbeEnvironment) async -> ArticleThemeColorMeasurement? {
		await acquireWebViewPermit()
		defer { releaseWebViewPermit() }
		defer { schedulePassRunnerRelease() }
		return await performMeasurement(theme, environment: environment)
	}

	/// Keep the two probe views warm across a burst of theme measurements, then release their
	/// WebKit processes after idle time so an occasional measurement does not pin them for the whole session.
	private static func schedulePassRunnerRelease() {
		passRunnerReleaseTask?.cancel()
		passRunnerReleaseTask = Task { @MainActor in
			try? await Task.sleep(for: .seconds(30))
			guard !Task.isCancelled else {
				return
			}
			passRunners = nil
			passRunnerReleaseTask = nil
		}
	}

	// MARK: Internals

	/// The probe page for `theme`: the reader's `page.html` with the theme's CSS,
	/// its `@import` block and its own template rendered with the shared sample
	/// article. No color-scheme meta, CSP, margin, wrapper or extra stylesheet,
	/// and no override block.
	static func composeHTML(for theme: ArticleTheme,
	                        environment: ArticleThemeProbeEnvironment) throws -> String {
		let template = theme.template ?? ArticleThemeSampleContent.fallbackTemplate
		let body = try MacroProcessor.renderedText(withTemplate: template,
												   substitutions: ArticleThemeSampleContent.substitutions())
		let style = try MacroProcessor.renderedText(withTemplate: theme.css ?? "",
													substitutions: environment.styleSubstitutions)
		return try ArticlePageComposer.compose(pageHTML: environment.pageHTML,
											   title: "Probe",
											   importStyle: ArticlePageComposer.importStyle(importCSS: theme.importCSS),
											   style: style,
											   baseURL: ArticleThemeSampleContent.baseURLString,
											   body: body,
											   lang: environment.lang)
	}

	private static func performMeasurement(_ theme: ArticleTheme,
	                                       environment: ArticleThemeProbeEnvironment) async -> ArticleThemeColorMeasurement? {
		guard let html = try? composeHTML(for: theme, environment: environment) else {
			log.error("could not compose probe HTML for theme \(theme.name, privacy: .public)")
			return nil
		}
		guard let rawLight = await runPass(html: html, dark: false, environment: environment) else {
			log.error("light pass failed for theme \(theme.name, privacy: .public)")
			return nil
		}
		guard let rawDark = await runPass(html: html, dark: true, environment: environment) else {
			log.error("dark pass failed for theme \(theme.name, privacy: .public)")
			return nil
		}
		guard let light = ThemeColorProbeLogic.resolve(rawLight, requestedDark: false) else {
			log.error("light pass was invalid for theme \(theme.name, privacy: .public): dark=\(rawLight.dark.map { String($0) } ?? "nil", privacy: .public) error=\(rawLight.error ?? "nil", privacy: .public)")
			return nil
		}
		guard let dark = ThemeColorProbeLogic.resolve(rawDark, requestedDark: true) else {
			log.error("dark pass was invalid for theme \(theme.name, privacy: .public): dark=\(rawDark.dark.map { String($0) } ?? "nil", privacy: .public) error=\(rawDark.error ?? "nil", privacy: .public)")
			return nil
		}
		guard ThemeColorProbeLogic.isSane(light) else {
			log.error("light colors failed sanity for theme \(theme.name, privacy: .public): page=\(light.page.hex, privacy: .public) ink=\(light.ink.hex, privacy: .public) link=\(light.accent.hex, privacy: .public)")
			return nil
		}
		guard ThemeColorProbeLogic.isSane(dark) else {
			log.error("dark colors failed sanity for theme \(theme.name, privacy: .public): page=\(dark.page.hex, privacy: .public) ink=\(dark.ink.hex, privacy: .public) link=\(dark.accent.hex, privacy: .public)")
			return nil
		}
		return ThemeColorProbeLogic.assemble(light: light, dark: dark)
	}

	/// Attempts per pass. A cold web content process (the first load of a run, or one that
	/// lands while the host is busy) can miss the 5 second window with no read-back at all,
	/// while the same page reads fine a moment later. One retry covers that without changing
	/// what is measured, so `version` is not bumped. A pass that fails twice is still nil.
	static let passAttempts = 2

	/// One load in one appearance, retried once if no read-back arrived. Returns the decoded
	/// read-back, or nil on timeout, navigation failure, or an undecodable message.
	static func runPass(html: String,
	                    dark: Bool,
	                    environment: ArticleThemeProbeEnvironment) async -> ThemeColorProbeLogic.RawPass? {
		for attempt in 1...passAttempts {
			if let pass = await runPassOnce(html: html, dark: dark, environment: environment) {
				return pass
			}
			if attempt < passAttempts {
				log.notice("\(dark ? "dark" : "light", privacy: .public) pass: no read-back, retrying")
			}
		}
		return nil
	}

	private static func runPassOnce(html: String,
	                                dark: Bool,
	                                environment: ArticleThemeProbeEnvironment) async -> ThemeColorProbeLogic.RawPass? {
		let runner: PassRunner
		if let existing = passRunners?[dark] {
			runner = existing
		} else {
			let blocker = await remoteLoadBlocker()
			runner = PassRunner(dark: dark, environment: environment, blocker: blocker)
			if passRunners == nil {
				passRunners = [:]
			}
			passRunners?[dark] = runner
		}
		let message = await runner.load(html: html)

		guard let message, let data = message.data(using: .utf8) else {
			// A WebContent process can exit during a simulator run. Do not keep a dead WebView
			// for the retry or the next theme; the next pass gets a fresh runner.
			passRunners?[dark] = nil
			log.error("\(dark ? "dark" : "light", privacy: .public) pass: no read-back (timeout, navigation failure or process exit)")
			return nil
		}
		do {
			let raw = try JSONDecoder().decode(ThemeColorProbeLogic.RawPass.self, from: data)
			if let error = raw.error {
				log.error("\(dark ? "dark" : "light", privacy: .public) pass: page script reported \(error, privacy: .public)")
			}
			return raw
		} catch {
			passRunners?[dark] = nil
			log.error("\(dark ? "dark" : "light", privacy: .public) pass: undecodable read-back \(String(message.prefix(300)), privacy: .public)")
			return nil
		}
	}

	/// Reuses one WebView for each appearance. Theme probes may measure hundreds of bundles
	/// during cache refresh or the smoke suite; constructing a fresh view for every pass makes
	/// WebKit launch and tear down a WebContent process each time.
	@MainActor private final class PassRunner {
		private let run = ProbeRun()
		private let webView: WKWebView
		private let host: UIWindow?

		init(dark: Bool, environment: ArticleThemeProbeEnvironment, blocker: WKContentRuleList?) {
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = .nonPersistent()
			configuration.defaultWebpagePreferences = environment.makePagePreferences()
			let controller = WKUserContentController()
			controller.addUserScript(WKUserScript(source: ThemeColorProbeLogic.readbackScript,
											  injectionTime: .atDocumentEnd,
											  forMainFrameOnly: true))
			controller.add(run, name: messageHandlerName)
			if let blocker {
				controller.add(blocker)
			}
			configuration.userContentController = controller
			webView = WKWebView(frame: webViewFrame, configuration: configuration)
			webView.navigationDelegate = run
			host = attachToHiddenWindow(webView)
			webView.overrideUserInterfaceStyle = dark ? .dark : .light
		}

		func load(html: String) async -> String? {
			let message = await run.load(html: html, in: webView, timeout: passTimeout)
			webView.stopLoading()
			return message
		}
	}

	/// Blocks every remote subresource (`http(s)` stylesheets, fonts, images, scripts, media). Theme
	/// stylesheets begin with `@import url(https://fonts.googleapis.com/...)`; unblocked, that fetch
	/// delays the load past the pass timeout when the network is slow or absent, and the probe and the
	/// theme check matrix report no read-back for themes that are fine. Colors never depend on a
	/// remote resource, and the pages carry their images as `data:` URIs. Compiled once per process;
	/// nil if compilation fails, in which case the page loads unblocked as before.
	static let remoteLoadBlockerRules = #"""
	[{"trigger": {"url-filter": "^https?://", "resource-type": ["image", "style-sheet", "script", "font", "raw", "svg-document", "media"]}, "action": {"type": "block"}}]
	"""#

	private static var remoteLoadBlockerList: WKContentRuleList?
	private static var remoteLoadBlockerCompiled = false

	static func remoteLoadBlocker() async -> WKContentRuleList? {
		if remoteLoadBlockerCompiled {
			return remoteLoadBlockerList
		}
		do {
			remoteLoadBlockerList = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ThemeProbeBlockRemoteLoads", encodedContentRuleList: remoteLoadBlockerRules)
			remoteLoadBlockerCompiled = true
		} catch {
			log.error("could not compile the remote load blocker: \(error.localizedDescription, privacy: .public)")
		}
		return remoteLoadBlockerList
	}

	/// A 1x1 window in the first foreground-active scene, so the web view has
	/// a real trait environment. With no such scene the web view stays unattached
	/// and the `matchMedia` assertion guards the result.
	private static func attachToHiddenWindow(_ webView: WKWebView) -> UIWindow? {
		// Prefer the active scene, but tests (and a cold launch) can run before it becomes active, and an
		// unattached web view never flips `prefers-color-scheme`, so fall back to any connected scene.
		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		let scene = scenes.first { $0.activationState == .foregroundActive }
			?? scenes.first { $0.activationState == .foregroundInactive }
			?? scenes.first
		guard let scene else {
			return nil
		}
		let window = UIWindow(windowScene: scene)
		window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
		window.isUserInteractionEnabled = false
		let root = UIViewController()
		window.rootViewController = root
		root.view.addSubview(webView)
		if useVisibleHostFallback {
			window.alpha = 0.01
			webView.alpha = 0.01
			window.isHidden = false
		} else {
			window.isHidden = true
		}
		return window
	}
}

// MARK: - One pass

/// Owns the continuation for one load: resumed by the first of the posted
/// message, a navigation failure, a content-process crash, or the timeout.
@MainActor private final class ProbeRun: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

	private var continuation: CheckedContinuation<String?, Never>?
	private var timeoutTask: Task<Void, Never>?

	func load(html: String, in webView: WKWebView, timeout: Duration) async -> String? {
		await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
			self.continuation = continuation
			self.timeoutTask = Task { [weak self] in
				try? await Task.sleep(for: timeout)
				guard !Task.isCancelled else {
					return
				}
				self?.finish(nil)
			}
			// baseURL is nil; the page's own `<base href>` carries the fixed base.
			webView.loadHTMLString(html, baseURL: nil)
		}
	}

	private func finish(_ value: String?) {
		guard let continuation else {
			return
		}
		self.continuation = nil
		timeoutTask?.cancel()
		timeoutTask = nil
		continuation.resume(returning: value)
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		finish(message.body as? String)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		finish(nil)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		finish(nil)
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		finish(nil)
	}
}

// MARK: - Pure logic

/// Everything about a measurement that does not need a web view: the read-back
/// script, decoding, alpha compositing, the sanity check and hex formatting.
/// Nonisolated so the package's own tests can exercise it.
enum ThemeColorProbeLogic {

	struct RGBA: Decodable, Equatable, Sendable {
		var r: Int
		var g: Int
		var b: Int
		var a: Int
	}

	struct RGB: Equatable, Sendable {
		var r: Int
		var g: Int
		var b: Int

		var hex: String {
			String(format: "#%02X%02X%02X", r, g, b)
		}
	}

	/// The JSON the read-back script posts. `error` is set when a computed value
	/// could not be parsed; `link` is nil when the page has no `<a>` at all.
	struct RawPass: Decodable, Equatable, Sendable {
		var html: RGBA?
		var body: RGBA?
		var ink: RGBA?
		var link: RGBA?
		var dark: Bool?
		var error: String?
		/// The first link's own `background-color`. Themes that draw links as highlighter chips set
		/// one, and the link color is then meant to contrast with the chip, not with the page.
		var linkBackground: RGBA?
	}

	struct PassResult: Equatable, Sendable {
		var page: RGB
		var ink: RGB
		var link: RGB
		var pageWasPainted: Bool
		/// The link's own background composited over the page, nil when the link paints none.
		var linkGround: RGB?

		/// The color to report as the link color: the link's own background when it is drawn as a chip
		/// (its text color is chosen to sit on the chip, so it can be invisible on the page), else the text color.
		var accent: RGB { linkGround ?? link }
	}

	/// Minimum WCAG contrast of ink and of link against the page.
	static let minimumContrast = 1.5

	/// The color a page has when nothing paints one: what the legacy scanner uses.
	static func legacyFallback(isDark: Bool) -> RGB {
		isDark ? RGB(r: 0, g: 0, b: 0) : RGB(r: 255, g: 255, b: 255)
	}

	static func composite(_ top: RGBA, over bottom: RGB) -> RGB {
		func mix(_ source: Int, _ destination: Int) -> Int {
			Int((Double(source * top.a + destination * (255 - top.a)) / 255.0).rounded())
		}
		return RGB(r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b))
	}

	private static func isValid(_ c: RGBA) -> Bool {
		[c.r, c.g, c.b, c.a].allSatisfy { (0...255).contains($0) }
	}

	/// Requires the appearance to match what was requested, then resolves page
	/// compositing and opaque ink and link. Nil when the pass cannot be trusted.
	static func resolve(_ raw: RawPass, requestedDark: Bool) -> PassResult? {
		guard raw.error == nil,
			  raw.dark == requestedDark,
			  let html = raw.html, let body = raw.body, let ink = raw.ink,
			  isValid(html), isValid(body), isValid(ink),
			  raw.link.map(isValid) ?? true,
			  raw.linkBackground.map(isValid) ?? true else {
			return nil
		}
		let fallback = legacyFallback(isDark: requestedDark)
		let pageWasPainted = html.a > 0 || body.a > 0
		let page: RGB
		if pageWasPainted {
			page = composite(body, over: composite(html, over: fallback))
		} else {
			page = fallback
		}
		// Text is composited onto the page so every stored value is opaque.
		let inkRGB = composite(ink, over: page)
		let linkGround = raw.linkBackground.flatMap { $0.a > 0 ? composite($0, over: page) : nil }
		let linkRGB = raw.link.map { composite($0, over: linkGround ?? page) } ?? inkRGB
		return PassResult(page: page, ink: inkRGB, link: linkRGB, pageWasPainted: pageWasPainted, linkGround: linkGround)
	}

	static func relativeLuminance(_ c: RGB) -> Double {
		func channel(_ v: Int) -> Double {
			let s = Double(v) / 255.0
			return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
	}

	static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
		let la = relativeLuminance(a)
		let lb = relativeLuminance(b)
		return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
	}

	/// Ink and page differ, ink reaches the contrast floor against the page, and the link reaches it
	/// against what it is drawn on: its own background when it paints one (a link chip), else the page.
	static func isSane(_ pass: PassResult) -> Bool {
		pass.ink != pass.page
			&& contrastRatio(pass.ink, pass.page) >= minimumContrast
			&& contrastRatio(pass.link, pass.linkGround ?? pass.page) >= minimumContrast
	}

	static func assemble(light: PassResult, dark: PassResult) -> ArticleThemeColorMeasurement {
		ArticleThemeColorMeasurement(
			pageLight: light.page.hex, pageDark: dark.page.hex,
			inkLight: light.ink.hex, inkDark: dark.ink.hex,
			linkLight: light.accent.hex, linkDark: dark.accent.hex,
			pageWasPaintedLight: light.pageWasPainted,
			pageWasPaintedDark: dark.pageWasPainted,
			hasDarkModeVariant: light.page != dark.page || light.ink != dark.ink || light.accent != dark.accent)
	}

	/// Runs at document end in the page world, reads computed colors,
	/// normalizes each through a 2D canvas (so `oklch()`, `light-dark()` and
	/// space-separated `rgb()` all come out as sRGB bytes) and posts one JSON
	/// string. A color the canvas cannot parse is detected by assigning it after
	/// two different sentinel colors: a rejected assignment leaves the sentinel
	/// in place, so the two readbacks differ. Never touches the network.
	static let readbackScript = #"""
	(function () {
	  function post(o) {
	    window.webkit.messageHandlers.themeColorProbe.postMessage(JSON.stringify(o));
	  }
	  try {
	    var ctx = null;
	    function canvas2d() {
	      if (!ctx) {
	        var canvas = document.createElement('canvas');
	        canvas.width = 1;
	        canvas.height = 1;
	        ctx = canvas.getContext('2d', { willReadFrequently: true });
	        if (!ctx) { throw new Error('2d canvas unavailable'); }
	      }
	      return ctx;
	    }
	    function clamp255(x) { return Math.max(0, Math.min(255, Math.round(x))); }
	    // Computed sRGB colors serialize as rgb()/rgba() with plain numbers; read those directly so the
	    // common case does not depend on canvas. Anything else (oklch, color(), lab, ...) goes through canvas.
	    function parseLegacy(v) {
	      var m = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:\s*[,\/]\s*([\d.]+%?))?\s*\)$/.exec(v.trim());
	      if (!m) { return null; }
	      var alpha = 1;
	      if (m[4] !== undefined) {
	        alpha = m[4].slice(-1) === '%' ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
	      }
	      return { r: clamp255(parseFloat(m[1])), g: clamp255(parseFloat(m[2])), b: clamp255(parseFloat(m[3])), a: clamp255(alpha * 255) };
	    }
	    function parse(v) {
	      var legacy = parseLegacy(v);
	      if (legacy) { return legacy; }
	      var c = canvas2d();
	      c.fillStyle = '#010203';
	      c.fillStyle = v;
	      var first = c.fillStyle;
	      c.fillStyle = '#fdfcfb';
	      c.fillStyle = v;
	      var second = c.fillStyle;
	      if (first !== second) { throw new Error('unparsable color: ' + v); }
	      c.clearRect(0, 0, 1, 1);
	      c.fillStyle = v;
	      c.fillRect(0, 0, 1, 1);
	      var d = c.getImageData(0, 0, 1, 1).data;
	      return { r: d[0], g: d[1], b: d[2], a: d[3] };
	    }
	    function computed(el, prop) { return parse(getComputedStyle(el)[prop]); }
	    var inkEl = document.querySelector('.articleBody') || document.body;
	    var linkEl = document.querySelector('.articleBody a') || document.querySelector('a');
	    post({
	      html: computed(document.documentElement, 'backgroundColor'),
	      body: computed(document.body, 'backgroundColor'),
	      ink: computed(inkEl, 'color'),
	      link: linkEl ? computed(linkEl, 'color') : null,
	      linkBackground: linkEl ? computed(linkEl, 'backgroundColor') : null,
	      dark: window.matchMedia('(prefers-color-scheme: dark)').matches
	    });
	  } catch (e) {
	    post({ error: String(e) });
	  }
	})();
	"""#
}
