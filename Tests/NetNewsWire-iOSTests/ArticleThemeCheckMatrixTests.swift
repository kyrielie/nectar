//
//  ArticleThemeCheckMatrixTests.swift
//  NetNewsWire-iOSTests
//
//  The theme check matrix. Renders every theme in `Themes/` and
//  `gallery-themes/` through `ArticlePageComposer` in the reader's configuration
//  (content JavaScript off, read back by a `WKUserScript` that posts to a message
//  handler, the same mechanism as `ArticleThemeColorProbe`) with the upstream
//  `nnw-theme` fixtures plus the AO3 preface sample, light and dark, at the default
//  and the largest accessibility Dynamic Type size.
//
//  Asserted: no horizontal document overflow (`scrollWidth <= clientWidth`) and no
//  article image that failed to load or renders at zero size. Footnote legibility
//  (a port of the numeral checks in `nnw-theme`'s `assets/footnotes.js`) runs for the
//  themes whose own stylesheet styles footnotes. A third test writes a render-diff
//  report against the pinned upstream `core.css`; it is a report, not a gate.
//
//  There is no "scripts on" column: the reader never runs theme scripts.
//
//  Written without being run in Xcode. `UIFont.preferredFont(forTextStyle:compatibleWith:)`
//  and `UITraitCollection(preferredContentSizeCategory:)` are used for the large-text
//  size; confirm they behave as expected on first run.
//
//  Cost: `Themes/` gets the full 12-column matrix (3 fixtures x 2 sizes x 2 appearances).
//  `gallery-themes/` gets the largest size only, light only, plus a dark page for a bundle
//  whose own stylesheet declares a dark variant (see `ThemeCheckColumns`). The timing line
//  printed at the end of each run says what it cost. The heavy suites in this file are skipped
//  by default in CI (docs/theme-testing.md, "CI scope").
//

import Testing
import Foundation
import UIKit
import WebKit
import CryptoKit
import RSCore
@testable import Nectar
@testable import ArticleTheming

// MARK: - Fixtures

/// The article fixtures the matrix renders. `article` and `kitchenSink` are converted
/// verbatim from `nnw-theme`'s `assets/fixtures/*.toml` (see
/// `Fixtures/ThemeCheck/`); `ao3Preface` is the app's own sample so the AO3 preface
/// markup stays covered.
enum ThemeCheckFixture: String, CaseIterable, Sendable {
	case article
	case kitchenSink = "kitchen-sink"
	case ao3Preface = "ao3-preface"

	/// Macro values for `template.html`. The upstream fixtures hold what
	/// `nnwdump` captures from `ArticleRenderer.articleSubstitutions()` minus
	/// `dateline_style`, which the reader adds itself; add it here.
	func substitutions() throws -> [String: String] {
		switch self {
		case .ao3Preface:
			return ArticleThemeSampleContent.substitutions()
		case .article, .kitchenSink:
			let url = try ThemeCheckPaths.repoURL("Tests/NetNewsWire-iOSTests/Fixtures/ThemeCheck/\(rawValue).json")
			let data = try Data(contentsOf: url)
			var values = try JSONDecoder().decode([String: String].self, from: data)
			values["dateline_style"] = "articleDatelineTitle"
			return values
		}
	}
}

enum ThemeCheckPaths {
	static func repoURL(_ relativePath: String) throws -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent(relativePath)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	static func bundles(in folder: String) throws -> [URL] {
		let directory = try repoURL(folder)
		return try FileManager.default.contentsOfDirectory(atPath: directory.path)
			.filter { $0.hasSuffix(".nnwtheme") }
			.sorted()
			.map { directory.appendingPathComponent($0) }
	}
}

// MARK: - Page metrics

/// What the in-page script reports. Everything is optional so a script failure
/// decodes to `error` instead of throwing.
struct ThemePageMetrics: Decodable, Sendable {
	var dark: Bool?
	var scrollWidth: Double?
	var clientWidth: Double?
	var bodyScrollWidth: Double?
	var badImages: [String]?
	var imageSizes: [String]?
	var footnoteFailures: [String]?
	var error: String?

	var overflows: Bool {
		guard let client = clientWidth else {
			return false
		}
		return max(scrollWidth ?? 0, bodyScrollWidth ?? 0) > client
	}
}

// MARK: - Columns and circuit breaker

/// Which size and appearance columns a bundle gets in the overflow matrix.
enum ThemeCheckColumns {

	struct Column: Sendable {
		var sizeName: String
		var dark: Bool
	}

	/// Substrings that mark a stylesheet as having a dark variant worth a dark page. Same style of
	/// rule as the footnote test's `footnote` match.
	static let darkMarkers = ["prefers-color-scheme", "color-scheme", "light-dark("]

	static func declaresDarkVariant(_ ownStylesheet: String?) -> Bool {
		guard let ownStylesheet else {
			return false
		}
		return darkMarkers.contains { ownStylesheet.localizedCaseInsensitiveContains($0) }
	}

	/// `Themes/` (shipped bundles): every size, light and dark. Anything else (`gallery-themes/`):
	/// largest size, light, plus dark only when the bundle's own stylesheet declares a dark variant.
	static func columns(folder: String, ownStylesheet: String?) -> [Column] {
		if folder == "Themes" {
			return [false, true].flatMap { dark in
				["default", "largest"].map { Column(sizeName: $0, dark: dark) }
			}
		}
		var columns = [Column(sizeName: "largest", dark: false)]
		if declaresDarkVariant(ownStylesheet) {
			columns.append(Column(sizeName: "largest", dark: true))
		}
		return columns
	}
}

/// Aborts a loop after `limit` consecutive pages that did not report back, so a systemic failure
/// (every load timing out) costs a handful of timeouts instead of one per page.
struct ConsecutiveNilBreaker {
	let limit: Int
	private(set) var streak = 0

	init(limit: Int = 5) {
		self.limit = limit
	}

	var isTripped: Bool { streak >= limit }

	mutating func record(isNil: Bool) {
		streak = isNil ? streak + 1 : 0
	}
}

// MARK: - Runner

@MainActor private final class MatrixRun: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

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
			// baseURL nil: the page's own `<base href>` carries the fixed base, as in the probe.
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

@MainActor private enum MatrixRenderer {

	static let handlerName = "themeCheckMatrix"
	static let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
	static let timeout: Duration = .seconds(10)

	/// Same host window as the probe: a 1x1 hidden window in the first
	/// foreground-active scene, so `prefers-color-scheme` follows the override.
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
		// Same host as the probe: a hidden window never flipped `prefers-color-scheme` on the CI
		// simulator, so follow the probe's switch and keep the window technically visible.
		if ArticleThemeColorProbe.useVisibleHostFallback {
			window.alpha = 0.01
			webView.alpha = 0.01
			window.isHidden = false
		} else {
			window.isHidden = true
		}
		return window
	}

	static func measure(html: String, dark: Bool, environment: ArticleThemeProbeEnvironment) async -> ThemePageMetrics? {
		let run = MatrixRun()
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		configuration.defaultWebpagePreferences = environment.makePagePreferences()
		let controller = WKUserContentController()
		controller.addUserScript(WKUserScript(source: script,
											  injectionTime: .atDocumentEnd,
											  forMainFrameOnly: true))
		controller.add(run, name: handlerName)
		// Same blocker as the probe: a theme's remote `@import` font stylesheet must not stall the load.
		if let blocker = await ArticleThemeColorProbe.remoteLoadBlocker() {
			controller.add(blocker)
		}
		configuration.userContentController = controller

		let webView = WKWebView(frame: frame, configuration: configuration)
		webView.navigationDelegate = run
		let host = attachToHiddenWindow(webView)
		webView.overrideUserInterfaceStyle = dark ? .dark : .light

		let message = await run.load(html: html, in: webView, timeout: timeout)

		controller.removeScriptMessageHandler(forName: handlerName)
		controller.removeAllUserScripts()
		webView.navigationDelegate = nil
		webView.stopLoading()
		webView.removeFromSuperview()
		host?.isHidden = true

		guard let message, let data = message.data(using: .utf8) else {
			return nil
		}
		return try? JSONDecoder().decode(ThemePageMetrics.self, from: data)
	}

	/// Composes the page for `theme` and `fixture` the way the reader does, with an optional
	/// replacement for the composed CSS (the render-diff report swaps `core.css`).
	static func composeHTML(theme: ArticleTheme,
	                        fixture: ThemeCheckFixture,
	                        fontSize: String,
	                        css cssOverride: String? = nil,
	                        environment: ArticleThemeProbeEnvironment) throws -> String {
		let template = theme.template ?? ArticleThemeSampleContent.fallbackTemplate
		let body = try MacroProcessor.renderedText(withTemplate: template, substitutions: try fixture.substitutions())
		var styleValues = environment.styleSubstitutions
		styleValues["font-size"] = fontSize
		let style = try MacroProcessor.renderedText(withTemplate: cssOverride ?? theme.css ?? "", substitutions: styleValues)
		return try ArticlePageComposer.compose(pageHTML: environment.pageHTML,
											   title: "Check",
											   importStyle: ArticlePageComposer.importStyle(importCSS: theme.importCSS),
											   style: style,
											   baseURL: ArticleThemeSampleContent.baseURLString,
											   body: body,
											   lang: environment.lang)
	}

	/// Body font size the reader would use at the default and the largest accessibility size.
	static var defaultFontSize: String {
		ArticleRenderer.styleSubstitutions()["font-size"] ?? "17.0"
	}

	static var largestFontSize: String {
		let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
		let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
		return String(describing: font.pointSize)
	}

	/// Posted once, after the load event. The footnote section is a port of the numeral checks in
	/// `nnw-theme`'s `assets/footnotes.js`: markers resolve to a note, the numeral stands out from its
	/// flattened backdrop (summed channel distance above 60, white when nothing is painted), it does not
	/// spill out of its marker, and all markers present alike. Not ported: the popover click (newsfoot is
	/// an app script and does not run here) and `keep_with_word` (opt-in upstream). The marker selector
	/// adds `sup > a[href*="#fn"]` because `main.js` adds the `footnote` class at runtime in the app.
	static let script = #"""
	(function () {
		function post(value) {
			window.webkit.messageHandlers.themeCheckMatrix.postMessage(JSON.stringify(value));
		}
		// Content JavaScript is off here, so the app's `main.js` `processPage()` never runs. Mirror the steps
		// that change layout or selector matches, or the checks measure a page the reader never shows:
		// `wrapFrames`, `wrapTables` (the `.nnw-overflow` scroller) and `styleLocalFootnotes` (the `footnote`
		// class that theme rules such as `body a.footnote { background: ... }` key off).
		// Transitions are switched off first: `a.footnote` themes declare `transition: background-color`, and
		// without this a read right after the class is added sees the transition's transparent start value.
		function applyReaderSteps() {
			var style = document.createElement("style");
			style.textContent = "*, *::before, *::after { transition: none !important; }";
			document.head.appendChild(style);
			Array.prototype.forEach.call(document.querySelectorAll("iframe"), function (frame) {
				if (parseInt(frame.height) > 0) { return; }
				var wrapper = document.createElement("div");
				wrapper.classList.add("iframeWrap");
				frame.parentNode.insertBefore(wrapper, frame);
				wrapper.appendChild(frame);
			});
			Array.prototype.forEach.call(document.querySelectorAll("div.articleBody table"), function (table) {
				var wrapper = document.createElement("div");
				wrapper.className = "nnw-overflow";
				table.parentNode.insertBefore(wrapper, table);
				wrapper.appendChild(table);
			});
			Array.prototype.forEach.call(document.querySelectorAll("sup > a[href*='#fn'], sup > div > a[href*='#fn']"), function (link) {
				if (link.hash.indexOf("#fn") === 0 && link.href.indexOf(document.baseURI) === 0) { link.classList.add("footnote"); }
			});
		}
		function footnoteFailures() {
			var failures = [];
			var article = document.querySelector(".articleBody");
			if (!article) { return failures; }
			function text(element) { return element.textContent.replace(/\s+/g, " ").trim(); }
			var markers = Array.prototype.slice.call(article.querySelectorAll('a.footnote, sup > a[href*="#fn"]'))
				.filter(function (marker) { return marker.getClientRects().length; });
			function label(marker) { return text(marker) || marker.getAttribute("href"); }
			markers.forEach(function (marker) {
				var id = marker.hash ? decodeURIComponent(marker.hash.slice(1)) : "";
				var target = id && document.getElementById(id);
				if (!target) { failures.push("footnote " + label(marker) + ": " + marker.getAttribute("href") + " names no note"); }
				else if (!text(target)) { failures.push("footnote " + label(marker) + ": note is empty"); }
			});
			function rgba(value) {
				var n = (value.match(/[\d.]+/g) || []).map(Number);
				return n.length ? [n[0], n[1], n[2], n.length > 3 ? n[3] : 1] : [0, 0, 0, 0];
			}
			function backdrop(element) {
				var layers = [];
				for (var node = element; node; node = node.parentElement) {
					var layer = rgba(getComputedStyle(node).backgroundColor);
					if (!layer[3]) { continue; }
					layers.push(layer);
					if (layer[3] === 1) { break; }
				}
				var base = layers.pop() || [255, 255, 255, 1];
				while (layers.length) {
					var top = layers.pop();
					base = [0, 1, 2].map(function (i) { return top[i] * top[3] + base[i] * (1 - top[3]); });
				}
				return base.slice(0, 3);
			}
			function distance(a, b) { return [0, 1, 2].reduce(function (sum, i) { return sum + Math.abs(a[i] - b[i]); }, 0); }
			markers.forEach(function (marker) {
				var inner = Array.prototype.slice.call(marker.querySelectorAll("*")).filter(function (e) { return text(e); });
				var glyph = inner.length ? inner[inner.length - 1] : marker;
				var color = rgba(getComputedStyle(glyph).color);
				var ground = backdrop(marker);
				if (distance(color, ground) <= 60) {
					failures.push("footnote " + label(marker) + ": numeral " + color.slice(0, 3) + " is illegible on " + ground);
				}
				var box = marker.getBoundingClientRect();
				var glyphBox = glyph.getBoundingClientRect();
				if (glyphBox.top < box.top - 1 || glyphBox.bottom > box.bottom + 1) {
					failures.push("footnote " + label(marker) + ": numeral spills out of its marker");
				}
			});
			var geometry = markers.map(function (marker) {
				var probe = document.createElement("span");
				probe.textContent = "\u2060";
				marker.after(probe);
				var box = marker.getBoundingClientRect();
				var seat = box.bottom - probe.getBoundingClientRect().bottom;
				probe.remove();
				return { marker: marker, height: box.height, seat: seat, size: parseFloat(getComputedStyle(marker).fontSize) };
			});
			geometry.slice(1).forEach(function (g) {
				var first = geometry[0];
				var name = "footnote " + label(g.marker);
				if (Math.abs(g.height - first.height) >= 0.5) { failures.push(name + ": height differs from the first marker"); }
				if (Math.abs(g.seat - first.seat) >= 0.5) { failures.push(name + ": baseline seat differs from the first marker"); }
				if (Math.abs(g.size - first.size) >= 0.1) { failures.push(name + ": font-size differs from the first marker"); }
			});
			return failures;
		}
		function run() {
			try {
				applyReaderSteps();
				var root = document.documentElement;
				var out = {};
				out.dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
				out.scrollWidth = root.scrollWidth;
				out.clientWidth = root.clientWidth;
				out.bodyScrollWidth = document.body ? document.body.scrollWidth : 0;
				out.badImages = [];
				out.imageSizes = [];
				Array.prototype.forEach.call(document.querySelectorAll(".articleBody img"), function (img) {
					var src = img.getAttribute("src") || "";
					if (!src || getComputedStyle(img).display === "none") { return; }
					var rect = img.getBoundingClientRect();
					out.imageSizes.push(Math.round(rect.width) + "x" + Math.round(rect.height));
					var shortSrc = src.length > 40 ? src.slice(0, 40) + "..." : src;
					if (!img.complete || img.naturalWidth === 0) { out.badImages.push("failed to load: " + shortSrc); }
					else if (rect.width < 1 || rect.height < 1) { out.badImages.push("zero rendered size: " + shortSrc); }
				});
				out.footnoteFailures = footnoteFailures();
				post(out);
			} catch (error) {
				post({ error: String(error) });
			}
		}
		if (document.readyState === "complete") { run(); }
		else { window.addEventListener("load", run); }
	})();
	"""#
}

// MARK: - Tests

@MainActor @Suite(.serialized) struct ArticleThemeCheckMatrixTests {

	private static func environment() -> ArticleThemeProbeEnvironment {
		ArticleThemeProbeEnvironment.reader()
	}

	private static func displayName(_ url: URL) -> String {
		url.deletingPathExtension().lastPathComponent
	}

	@Test(.timeLimit(.minutes(15)), arguments: ["Themes", "gallery-themes"])
	func noOverflowAndNoBrokenImagesAcrossMatrix(folder: String) async throws {
		let environment = Self.environment()
		let sizes: [String: String] = ["default": MatrixRenderer.defaultFontSize,
									   "largest": MatrixRenderer.largestFontSize]
		var failures = [String]()
		var appearanceMismatches = 0
		var pages = 0
		var breaker = ConsecutiveNilBreaker()
		var aborted = false
		let started = ContinuousClock.now

		bundleLoop: for bundle in try ThemeCheckPaths.bundles(in: folder) {
			let theme = try ArticleTheme(url: bundle, isAppTheme: false)
			let columns = ThemeCheckColumns.columns(folder: folder, ownStylesheet: theme.ownStylesheet)
			for fixture in ThemeCheckFixture.allCases {
				for column in columns {
					let size = try #require(sizes[column.sizeName])
					let html = try MatrixRenderer.composeHTML(theme: theme, fixture: fixture,
															  fontSize: size, environment: environment)
					let dark = column.dark
					let label = "\(Self.displayName(bundle)) / \(fixture.rawValue) / \(dark ? "dark" : "light") / \(column.sizeName)"
					pages += 1
					let measured = await MatrixRenderer.measure(html: html, dark: dark, environment: environment)
					guard let metrics = measured, metrics.error == nil else {
						failures.append("\(label): page did not report back")
						breaker.record(isNil: true)
						if breaker.isTripped {
							aborted = true
							break bundleLoop
						}
						continue
					}
					breaker.record(isNil: false)
					if metrics.dark != dark {
						appearanceMismatches += 1
					}
					if metrics.overflows {
						failures.append("\(label): horizontal overflow, scrollWidth \(metrics.scrollWidth ?? 0), body \(metrics.bodyScrollWidth ?? 0), clientWidth \(metrics.clientWidth ?? 0)")
					}
					for image in metrics.badImages ?? [] {
						failures.append("\(label): \(image)")
					}
				}
			}
		}

		print("ThemeCheckMatrix \(folder): \(pages) pages in \(ContinuousClock.now - started)\(aborted ? " (aborted by circuit breaker)" : "")")
		#expect(!aborted, "\(breaker.limit) consecutive pages did not report back in \(folder); the run was aborted. This points at the harness (hidden window, WebKit), not at one theme.")
		#expect(appearanceMismatches == 0, "\(appearanceMismatches) page(s) did not get the requested prefers-color-scheme; the hidden window did not flip it (see ArticleThemeColorProbe.useVisibleHostFallback)")
		#expect(failures.isEmpty, "\(failures.count) failure(s):\n\(failures.prefix(60).joined(separator: "\n"))")
	}

	/// Only themes whose own stylesheet mentions footnotes are held to the numeral checks; a theme
	/// that does not style them inherits `core.css`, which this checks nothing about.
	@Test(.timeLimit(.minutes(10))) func footnoteMarkersAreLegibleForThemesThatStyleThem() async throws {
		let environment = Self.environment()
		var failures = [String]()
		var checked = 0
		for folder in ["Themes", "gallery-themes"] {
			for bundle in try ThemeCheckPaths.bundles(in: folder) {
				let theme = try ArticleTheme(url: bundle, isAppTheme: false)
				guard (theme.ownStylesheet ?? "").localizedCaseInsensitiveContains("footnote") else {
					continue
				}
				checked += 1
				let html = try MatrixRenderer.composeHTML(theme: theme, fixture: .kitchenSink,
														  fontSize: MatrixRenderer.defaultFontSize, environment: environment)
				for dark in [false, true] {
					let label = "\(Self.displayName(bundle)) / \(dark ? "dark" : "light")"
					guard let metrics = await MatrixRenderer.measure(html: html, dark: dark, environment: environment),
						  metrics.error == nil else {
						failures.append("\(label): page did not report back")
						continue
					}
					for message in metrics.footnoteFailures ?? [] {
						failures.append("\(label): \(message)")
					}
				}
			}
		}
		print("ThemeCheckMatrix footnotes: \(checked) themes style footnotes")
		#expect(checked > 0, "no theme styles footnotes; the selection rule found nothing")
		#expect(failures.isEmpty, "\(failures.count) failure(s):\n\(failures.prefix(60).joined(separator: "\n"))")
	}
}

// MARK: - Cheap fixture check (always runs)

@MainActor @Suite struct ArticleThemeCheckFixtureTests {

	/// The fixtures decode, hold exactly the reader's macro keys, and match the keys the app's own
	/// sample uses, so a change on either side is noticed.
	@Test func upstreamFixturesCarryTheReaderMacroKeys() throws {
		let sampleKeys = Set(ArticleThemeSampleContent.substitutions().keys).subtracting(["dateline_style"])
		for fixture in [ThemeCheckFixture.article, .kitchenSink] {
			let values = try fixture.substitutions()
			#expect(Set(values.keys).subtracting(["dateline_style"]) == sampleKeys, "\(fixture.rawValue) macro keys")
			#expect(values["dateline_style"] == "articleDatelineTitle")
			#expect(values["body"]?.contains("<p") == true)
		}
	}
}

// MARK: - Render-diff report (heavy, skipped by default in CI)

@MainActor @Suite(.serialized) struct ArticleThemeRenderDiffTests {

	private static func environment() -> ArticleThemeProbeEnvironment {
		ArticleThemeProbeEnvironment.reader()
	}

	private static func displayName(_ url: URL) -> String {
		url.deletingPathExtension().lastPathComponent
	}

	/// Report, not a gate: how Nectar's `core.css` and the pinned upstream one differ in overflow and
	/// image sizes for the starter-style fixture and the bundles that pass the upstream validator.
	/// The only assertions are that the upstream copy is the pinned file and that every page rendered.
	@Test(.timeLimit(.minutes(5))) func renderDiffAgainstUpstreamCoreCSS() async throws {
		let upstreamURL = try ThemeCheckPaths.repoURL("Tests/NetNewsWire-iOSTests/Fixtures/ThemeCheck/upstream-core.css")
		let upstreamData = try Data(contentsOf: upstreamURL)
		let hash = SHA256.hash(data: upstreamData).map { String(format: "%02x", $0) }.joined()
		#expect(hash == "d67552259cb45261e1aacf0c1af6bc39b560b084c7b9e3943191907e0977cd4d",
				"upstream-core.css is not the file pinned at NetNewsWire mac-7.2b4 (b7f4d8c7)")
		let upstreamCore = try #require(String(data: upstreamData, encoding: .utf8))

		let environment = Self.environment()
		let starter = try ThemeCheckPaths.repoURL("Tests/NetNewsWire-iOSTests/Fixtures/ThemeColorProbe/StarterStyle.nnwtheme")
		// The six bundles that pass `nnw-theme`'s validator today (plan decision D19).
		let compatible = ["Biblioteca", "NewsFax", "Promenade", "Sepia", "Tiqoe Dark", "Verdana Revival"]
		// These six are gallery-only now; look in both folders so a later promotion still works.
		let folders = [try ThemeCheckPaths.repoURL("Themes"), try ThemeCheckPaths.repoURL("gallery-themes")]
		let bundles = try [starter] + compatible.map { name in
			let found = folders.map { $0.appendingPathComponent("\(name).nnwtheme") }
				.first { FileManager.default.fileExists(atPath: $0.path) }
			return try #require(found, "\(name).nnwtheme is in neither Themes/ nor gallery-themes/")
		}

		var rendered = 0
		var differences = 0
		for bundle in bundles {
			let theme = try ArticleTheme(url: bundle, isAppTheme: false)
			let upstreamCSS = upstreamCore + "\n" + (theme.ownStylesheet ?? "")
			for fixture in [ThemeCheckFixture.article, .kitchenSink] {
				let size = MatrixRenderer.defaultFontSize
				let nectarHTML = try MatrixRenderer.composeHTML(theme: theme, fixture: fixture, fontSize: size, environment: environment)
				let upstreamHTML = try MatrixRenderer.composeHTML(theme: theme, fixture: fixture, fontSize: size, css: upstreamCSS, environment: environment)
				let nectar = await MatrixRenderer.measure(html: nectarHTML, dark: false, environment: environment)
				let upstream = await MatrixRenderer.measure(html: upstreamHTML, dark: false, environment: environment)
				#expect(nectar?.error == nil && nectar != nil, "\(Self.displayName(bundle)) did not render with Nectar core.css")
				#expect(upstream?.error == nil && upstream != nil, "\(Self.displayName(bundle)) did not render with upstream core.css")
				guard let nectar, let upstream else {
					continue
				}
				rendered += 1
				var notes = [String]()
				if nectar.overflows != upstream.overflows {
					notes.append("overflow Nectar \(nectar.overflows) vs upstream \(upstream.overflows)")
				}
				if nectar.imageSizes != upstream.imageSizes {
					notes.append("image sizes Nectar \(nectar.imageSizes ?? []) vs upstream \(upstream.imageSizes ?? [])")
				}
				if !notes.isEmpty {
					differences += 1
					print("RenderDiff \(Self.displayName(bundle)) / \(fixture.rawValue): \(notes.joined(separator: "; "))")
				}
			}
		}
		print("RenderDiff: \(rendered) page pair(s) rendered, \(differences) differ in overflow or image size")
		#expect(rendered == bundles.count * 2)
	}
}
