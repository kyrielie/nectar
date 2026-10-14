import AO3Kit
//
//  ArticleThemePreviewWebView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme → Font & Color Overrides.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import WebKit
import RSCore
import ArticleTheming

/// Renders a small, scrollable sample article styled with real theme CSS, so the
/// override screen's preview reflects the actual current theme (default or an imported
/// .nnwtheme) as a baseline, with the in-progress override CSS layered on top -- the
/// same layering ArticleRenderer.styleString() does for real articles. A SwiftUI-only
/// preview (as used before this theme was wired up) can't do this: it has no way to
/// know an arbitrary theme's colors or fonts, since those live in that theme's own
/// stylesheet.css, not in anything Swift can introspect.
struct ArticleThemePreviewWebView: UIViewRepresentable {

	let importCSS: String?
	let css: String

	/// The current theme's own `template.html`, with its `[[placeholder]]` tokens still
	/// in place. Bundled themes don't share one header layout -- the default theme wraps
	/// its byline/feedlink in a `.headerContainer` table, Reversi has no header at all
	/// and puts the byline under the title, Kennerley uses `.headerBar`/`.barContent` -- so a single
	/// hand-written sample body would only match the default theme's markup and
	/// render every other theme's header unstyled. Running the
	/// theme's real template through the same `MacroProcessor` `ArticleRenderer` uses
	/// for actual articles (see `ArticleRenderer.renderedHTML()`) means the preview is
	/// structurally identical to what a real article gets, for any theme.
	let template: String?

	/// Mirrors `AppDefaults.shared.showFeedNameInReaderView`: when off, `feed_link_title`
	/// is substituted with an empty string and the (now textless) feed-name link is
	/// stripped, exactly matching what `ArticleRenderer.articleSubstitutions()` and
	/// `main.js`'s `removeFeedNameLink()` do for real articles.
	let showFeedName: Bool

	/// Forces the preview to a specific appearance regardless of the system setting, via
	/// `WKWebView.overrideUserInterfaceStyle`, so a "Light"/"Dark" preview slider can show
	/// both variants of a light+dark theme without the person needing to actually change
	/// their device's appearance. Has no visible effect on a single-palette theme, since
	/// those themes' CSS doesn't branch on `prefers-color-scheme` in the first place.
	let colorScheme: ColorScheme

	/// In-progress, unsaved override background hex values from
	/// ArticleThemeListView's own @State -- not AppDefaults.shared.articleThemeOverrides,
	/// which only reflects the last *saved* override. nil when the corresponding
	/// "Custom Color" toggle is off, same "nil means don't override" contract
	/// ArticleThemeOverrides itself uses.
	let overrideBackgroundColorHex: String?
	let overrideBackgroundColorDarkHex: String?

	/// Ported directly from `removeFeedNameLink()` in `Shared/Article Rendering/main.js`:
	/// finds the anchor with a real `href` but empty text (exactly what an empty
	/// `feed_link_title` substitution produces above) and removes it, plus a trailing
	/// `<br>` and any now-empty wrapper dedicated to it. The rest of `main.js` isn't
	/// included here, since its other functions (image handling, table wrapping, video
	/// playback) assume a real article document and WKScriptMessage handlers this preview
	/// doesn't set up; only the feed-name behavior this screen's override actually affects
	/// is reproduced.
	/// Also removes the feed icon (`#nnwImageIcon`, always rendered by every bundled
	/// and third-party theme's `template.html`), matching how a real article's
	/// icon and feed name are governed by the same `showFeedNameInReaderView`
	/// setting from the reader's point of view -- see `removeArticleIconAvatar()`
	/// in `main.js`, which removes it unconditionally there since real articles
	/// never show a per-feed icon in the reader at all.
	private static let removeFeedNameLinkScript = """
	<script>
	function removeArticleIconAvatar() {
		var icon = document.getElementById("nnwImageIcon");
		if (icon) { icon.remove(); }
	}
	function removeFeedNameLink() {
		var links = document.querySelectorAll("a[href]");
		for (var i = 0; i < links.length; i++) {
			var link = links[i];
			var href = link.getAttribute("href");
			if (!href || href.trim() === "") { continue; }
			if (link.textContent.trim() !== "") { continue; }
			var parent = link.parentNode;
			var nextSibling = link.nextSibling;
			link.remove();
			if (nextSibling && nextSibling.nodeName === "BR") { nextSibling.remove(); }
			if (parent && parent.children.length === 0 && parent.textContent.trim() === ""
				&& parent.tagName !== "TD" && parent.tagName !== "TR" && parent.tagName !== "TABLE"
				&& parent.tagName !== "HEADER" && parent.tagName !== "ARTICLE" && parent.tagName !== "BODY") {
				parent.remove();
			}
		}
	}
	document.addEventListener("DOMContentLoaded", removeArticleIconAvatar);
	document.addEventListener("DOMContentLoaded", removeFeedNameLink);
	</script>
	"""

	/// Mirrors `applyVersalCaps()`/`applyChapterDividers()` from
	/// `Shared/Article Rendering/main.js`, so this preview -- which loads with
	/// content JS enabled and doesn't install `main.js` as a `WKUserScript` the
	/// way the real reader does -- still demonstrates a theme's drop-cap/versal
	/// and chapter-divider treatment rather than silently showing neither.
	/// Deliberately not just embedding the whole of `main.js` here: that file's
	/// `processPage()` unconditionally strips `#nnwImageIcon`
	/// (`removeArticleIconAvatar()`), which would fight this preview's own,
	/// intentionally different, icon-visibility behavior above (kept when
	/// `showFeedName` is true, to demonstrate a theme's icon styling -- the real
	/// reader never shows a per-feed icon at all, preview does on purpose).
	/// Keep this in sync with `applyVersalCaps`/`applyChapterDividers` in
	/// `main.js` if either changes -- see docs/nnwtheme-format.md.
	private static let versalAndDividerScript = """
	<script>
	function applyVersalCaps() {
		var container = document.getElementById("bodyContainer");
		if (!container || !container.hasAttribute("data-versal-target")) return;
		var sentenceEnd = /[.!?]["'\\u201d\\u2019)\\]]*(\\s|$)/;
		function isApparatus(paragraph) {
			return !!paragraph.closest(".summary, .notes, .preface, #ao3SyntheticPreface, #ao3Preface");
		}
		function firstRealParagraph(scope) {
			var paragraphs = scope.querySelectorAll("p");
			for (var i = 0; i < paragraphs.length; i++) {
				if (!isApparatus(paragraphs[i])) { return paragraphs[i]; }
			}
			return null;
		}
		function firstRealParagraphAfter(heading) {
			var walker = document.createTreeWalker(container, NodeFilter.SHOW_ELEMENT, null);
			walker.currentNode = heading;
			var node;
			while ((node = walker.nextNode())) {
				if (node.tagName === "H2" && node.classList.contains("heading")) return null;
				if (node.tagName === "H3" && node.classList.contains("title")) return null;
				if (node.tagName === "P" && !isApparatus(node)) return node;
			}
			return null;
		}
		function applyVersal(paragraph) {
			if (!paragraph || paragraph.querySelector(".versalCap")) return;
			var walker = document.createTreeWalker(paragraph, NodeFilter.SHOW_TEXT, null);
			var endNode = null;
			var node;
			while ((node = walker.nextNode())) {
				var match = sentenceEnd.exec(node.textContent);
				if (match) {
					node.splitText(match.index + match[0].length);
					endNode = node;
					break;
				}
			}
			if (!endNode) return;
			var span = document.createElement("span");
			span.className = "versalCap";
			var child = paragraph.firstChild;
			while (child) {
				var next = child.nextSibling;
				span.appendChild(child);
				if (child === endNode) break;
				child = next;
			}
			paragraph.insertBefore(span, paragraph.firstChild);
		}
		applyVersal(firstRealParagraph(container));
		container.querySelectorAll("h2.heading, h3.title").forEach(function (heading) {
			applyVersal(firstRealParagraphAfter(heading));
		});
	}
	function applyChapterDividers() {
		var container = document.getElementById("bodyContainer");
		if (!container || !container.hasAttribute("data-chapter-divider")) return;
		var dividerChar = container.getAttribute("data-chapter-divider-char");
		var dividerClass = container.getAttribute("data-chapter-divider-class");
		if (!dividerChar || !dividerClass) return;
		container.querySelectorAll("h2.heading, h3.title").forEach(function (heading) {
			var divider = document.createElement("div");
			divider.className = dividerClass;
			divider.setAttribute("aria-hidden", "true");
			divider.setAttribute("data-nnw-ornament", "");
			divider.textContent = dividerChar;
			heading.parentNode.insertBefore(divider, heading);
		});
	}
	document.addEventListener("DOMContentLoaded", applyVersalCaps);
	document.addEventListener("DOMContentLoaded", applyChapterDividers);
	</script>
	"""

	func makeUIView(context: Context) -> WKWebView {
		let configuration = WKWebViewConfiguration()
		configuration.userContentController = WKUserContentController()
		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.isScrollEnabled = true
		webView.scrollView.bounces = true
		// Interaction is needed for the scroll gesture, but this preview still isn't
		// meant to be a real reader: the sample's links all point at "#" and there's
		// no navigation delegate to intercept a tap, so there's nothing else here to
		// interact with.
		webView.isUserInteractionEnabled = true
		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

		let isDark = colorScheme == .dark
		let resolved = ArticleResolvedColors.resolved(
			theme: ArticleThemesManager.shared.currentTheme,
			isDark: isDark,
			overrideBackgroundColorHex: overrideBackgroundColorHex,
			overrideBackgroundColorDarkHex: overrideBackgroundColorDarkHex
		)
		webView.backgroundColor = resolved.background
		webView.underPageBackgroundColor = resolved.background

		let templateText = template ?? ArticleThemeSampleContent.fallbackTemplate
		let renderedBody = (try? MacroProcessor.renderedText(withTemplate: templateText, substitutions: ArticleThemeSampleContent.substitutions(showFeedName: showFeedName)))
			?? templateText
		let body = renderedBody + (showFeedName ? "" : Self.removeFeedNameLinkScript) + Self.versalAndDividerScript

		// Same page skeleton and style macro pass the reader uses (`page.html`), so
		// canvas, viewport and margin behavior match a real article.
		let style = (try? MacroProcessor.renderedText(withTemplate: css, substitutions: ArticleRenderer.styleSubstitutions())) ?? css
		let html = (try? ArticlePageComposer.compose(
			pageHTML: ArticleRenderer.page.html,
			title: "Preview",
			importStyle: ArticlePageComposer.importStyle(importCSS: importCSS),
			style: style,
			baseURL: ArticleThemeSampleContent.baseURLString,
			body: body,
			lang: ArticlePageComposer.defaultLang
		)) ?? body
		webView.loadHTMLString(html, baseURL: URL(string: ArticleThemeSampleContent.baseURLString))
	}
}
