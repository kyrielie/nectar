// Here we are making iframes responsive.  Particularly useful for inline Youtube videos.
function wrapFrames() {
	document.querySelectorAll("iframe").forEach(element => {
		if (parseInt(element.height) > 0)
			return;
		var wrapper = document.createElement("div");
		wrapper.classList.add("iframeWrap");
		element.parentNode.insertBefore(wrapper, element);
		wrapper.appendChild(element);
	});
}

// Strip out color and font styling

function stripStylesFromElement(element, propertiesToStrip) {
	for (name of propertiesToStrip) {
		element.style.removeProperty(name);
	}
}

// Strip inline styles that could harm readability.
function stripStyles() {
	document.getElementsByTagName("body")[0].querySelectorAll("style, link[rel=stylesheet]").forEach(element => element.remove());
	// Removing "background" and "font" will also remove properties that would be reflected in them, e.g., "background-color" and "font-family"
	document.getElementsByTagName("body")[0].querySelectorAll("[style]").forEach(element => stripStylesFromElement(element, ["color", "background", "font", "max-width", "max-height", "position"]));
}

// Constrain the height of iframes whose heights are defined relative to the document body to be at most
// 50% of the viewport width.
function constrainBodyRelativeIframes() {
	let iframes = document.getElementsByTagName("iframe");

	for (iframe of iframes) {
		if (iframe.offsetParent === document.body) {
			let heightAttribute = iframe.style.height;

			if (/%|vw|vh$/i.test(heightAttribute)) {
				iframe.classList.add("nnw-constrained");
			}
		}
	}
}

// Convert all Feedbin proxy images to be used as src, otherwise change image locations to be absolute if not already
function convertImgSrc() {
	document.querySelectorAll("img").forEach(element => {
		if (element.hasAttribute("data-canonical-src")) {
			element.src = element.getAttribute("data-canonical-src")
		} else if (!/^[a-z]+\:\/\//i.test(element.src)) {
			element.src = new URL(element.src, document.baseURI).href;
		}
	});
}

// Wrap tables in an overflow-x: auto; div
function wrapTables() {
	var tables = document.querySelectorAll("div.articleBody table");

	for (table of tables) {
		var wrapper = document.createElement("div");
		wrapper.className = "nnw-overflow";
		table.parentNode.insertBefore(wrapper, table);
		wrapper.appendChild(table);
	}
}

// Add the playsinline attribute to any HTML5 videos that don"t have it.
// Without this attribute videos may autoplay and take over the whole screen
// on an iphone when viewing an article.
function inlineVideos() {
	document.querySelectorAll("video").forEach(element => {
		element.setAttribute("playsinline", true);
		if (!element.classList.contains("nnwAnimatedGIF")) {
			element.setAttribute("controls", true);
			element.removeAttribute("autoplay");
		}
	});
}

// Remove some children (currently just spans) from pre elements to work around a strange clipping issue
var ElementUnwrapper = {
	unwrapSelector: "span",
	unwrapElement: function (element) {
		var parent = element.parentNode;
		var children = Array.from(element.childNodes);

		for (child of children) {
			parent.insertBefore(child, element);
		}

		parent.removeChild(element);
	},
	// `elements` can be a selector string, an element, or a list of elements
	unwrapAppropriateChildren: function (elements) {
		if (typeof elements[Symbol.iterator] !== 'function')
			elements = [elements];
		else if (typeof elements === "string")
			elements = document.querySelectorAll(elements);

		for (element of elements) {
			for (unwrap of element.querySelectorAll(this.unwrapSelector)) {
				this.unwrapElement(unwrap);
			}

			element.normalize()
		}
	}
};

function flattenPreElements() {
	ElementUnwrapper.unwrapAppropriateChildren("div.articleBody td > pre");
}

function reloadArticleImage(imageSrc) {
	var image = document.querySelector('img[src^="nnwimageicon:" i]');
	if (image) {
		image.src = imageSrc + "?" + new Date().getTime();
	}
}

function stopMediaPlayback() {
	document.querySelectorAll("iframe").forEach(element => {
		var iframeSrc = element.src;
		element.src = iframeSrc;
	});

	// We pause all videos that have controls.  Video without controls shouldn't
	// have sound and are actually converted gifs.  Basically if the user can't
	// start the video again, don't stop it.
	document.querySelectorAll("video, audio").forEach(element => {
		if (element.hasAttribute("controls")) {
			element.pause();
		}
	});
}

function error() {
	document.body.innerHTML = "error";
}

// Takes into account absoluting of URLs.
function isLocalFootnote(target) {
	return target.hash.startsWith("#fn") && target.href.indexOf(document.baseURI) === 0;
}

function styleLocalFootnotes() {
	for (elem of document.querySelectorAll("sup > a[href*='#fn'], sup > div > a[href*='#fn']")) {
		if (isLocalFootnote(elem)) {
			elem.classList.add("footnote");
		}
	}
}

// convert <img alt="📰" src="[...]" class="wp-smiley"> to a text node containing 📰
function removeWpSmiley() {
	for (const img of document.querySelectorAll("img.wp-smiley[alt]")) {
		 img.parentNode.replaceChild(document.createTextNode(img.alt), img);
	}
}

// The feed icon/avatar (#nnwImageIcon) is just the generic fallback icon rendered
// as a raster image via the nnwImageIcon:// URL scheme (see ArticleRenderer.swift
// and ArticleIconSchemeHandler.swift) — it never shows a real per-feed icon.
// Every bundled and third-party theme's template.html renders this element, so it
// is removed here in the shared rendering pipeline rather than in each template,
// which lets user-installed NetNewsWire themes keep working unmodified.
function removeArticleIconAvatar() {
	document.querySelectorAll('img[src^="nnwimageicon:" i]').forEach(img => img.remove());
}

// The feed-name link (populated from ArticleRenderer's feed_link /
// feed_link_title template keys -- see template.html's headerTable markup)
// is rendered by every bundled and third-party theme, with different wrapper
// markup per theme (a bare <a>, one wrapped in its own <div>, one sharing a
// <td> with the byline, etc.) and no consistent id or class across all of
// them. Rather than requiring every theme to adopt a specific id (which
// third-party themes predating that convention wouldn't have) or hardcoding
// per-theme handling, this piggybacks on how ArticleRenderer already governs
// visibility: when AppDefaults.shared.showFeedNameInReaderView is off,
// ArticleRenderer sets feed_link_title to an empty string, so the rendered
// anchor has a real href (the feed's home page URL) but empty text --
// whatever theme is active. That combination (non-empty href, empty text)
// is what identifies the link here, so it can be found and removed the same
// way regardless of theme markup, matching the removeArticleIconAvatar
// approach above.
//
// When the toggle is on, ArticleRenderer instead fills feed_link_title with
// a real name (single feed, or several comma-separated feeds if the article
// was deduplicated across feeds by a smart feed -- see ArticleFeedNaming),
// so the anchor's text is never empty in that case and this function is a
// no-op, leaving the theme's own markup exactly as it renders it.
function removeFeedNameLink() {
	var links = document.querySelectorAll("a[href]");
	for (var i = 0; i < links.length; i++) {
		var link = links[i];
		var href = link.getAttribute("href");
		if (!href || href.trim() === "") {
			continue;
		}
		if (link.textContent.trim() !== "") {
			continue;
		}

		var parent = link.parentNode;

		// Themes that put the byline right after the feed name in the same
		// container (e.g. "<a>...</a><br />[[byline]]") would otherwise be
		// left with a stray blank line above the byline.
		var nextSibling = link.nextSibling;
		link.remove();
		if (nextSibling && nextSibling.nodeName === "BR") {
			nextSibling.remove();
		}

		// If removing the link emptied out a wrapper dedicated to it (some
		// themes give the feed name its own <div>/<span>), remove that
		// wrapper too rather than leaving an empty element that could still
		// affect layout. Never remove structural containers, and never
		// remove a table cell -- doing so would misalign the surrounding
		// header table rather than just leaving a harmless empty cell.
		if (parent && parent.textContent.trim() === "" &&
			!parent.querySelector("img") &&
			!["HEADER", "ARTICLE", "BODY", "TABLE", "TR", "TD"].includes(parent.tagName)) {
			parent.remove();
		}

		// There's only ever one feed-name link per rendered page.
		return;
	}
}

// Wraps the opening sentence of a paragraph in a marker span so a theme's CSS
// can style a real drop cap/versal off it (e.g. `::first-letter` on
// `p:has(> .versalCap:first-child)`). This used to live as a per-theme inline
// <script> in template.html (Kelmscott's own DOMContentLoaded handler), which
// worked in the Settings theme preview (a plain WKWebView with content JS
// enabled) but silently never ran in the real article reader, since
// WebViewConfiguration disables allowsContentJavaScript there and only
// WKUserScripts (like this file) are exempt from that restriction. Moving the
// logic here fixes that for every theme, not just Kelmscott: any theme opts
// in by adding `data-versal-target` to its `#bodyContainer` element (see
// Technotes/Themes.md) instead of shipping its own copy of this script.
//
// Operates on actual DOM nodes (via TreeWalker + Text.splitText) rather than
// rewriting textContent, so any inline markup already in that first sentence
// (an <em>, a link) is moved into the wrapper intact instead of discarded.
// If no sentence-ending punctuation is found (very short paragraph), that
// paragraph is left untouched -- a theme's ::first-letter rule still applies
// to its first character either way, just without the versal-caps span
// around the rest of the sentence.
function applyVersalCaps() {
	var container = document.getElementById("bodyContainer");
	if (!container || !container.hasAttribute("data-versal-target")) return;

	var sentenceEnd = /[.!?]["'\u201d\u2019)\]]*(\s|$)/;

	// Paragraphs inside .summary/.notes/.preface (and the AO3 preface divs)
	// are book apparatus, not the work's own prose, but they DO contain real
	// <p> elements (e.g. .summary.module > blockquote.userstuff > p) that sit
	// earlier in document order than the work's actual opening paragraph.
	// container.querySelector("p") alone -- the original version of this
	// function -- would silently pick the summary's <p> instead. Real AO3
	// chapter prose is also always nested inside a wrapping
	// div.userstuff.module[role="article"] (multi-chapter) or
	// div#chapters[role="article"] (single-chapter) -- see
	// AO3ChapterHTMLExtractor.swift -- which the flat sample body used by
	// the Settings preview doesn't reproduce, which is why a naive selector
	// can look correct there and still be wrong for real content.
	function isApparatus(paragraph) {
		return !!paragraph.closest(".summary, .notes, .preface, #ao3SyntheticPreface, #ao3Preface");
	}

	function firstRealParagraph(scope) {
		var paragraphs = scope.querySelectorAll("p");
		for (var i = 0; i < paragraphs.length; i++) {
			if (!isApparatus(paragraphs[i])) {
				return paragraphs[i];
			}
		}
		return null;
	}

	function firstRealParagraphAfter(heading) {
		// Walk forward through the DOM in document order (not just direct
		// siblings -- a chapter's own opening paragraph is typically nested
		// inside a userstuff wrapper div alongside the heading, not a direct
		// sibling of it) until a real, non-apparatus <p> turns up or we run
		// past the end of this heading's chapter section.
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

	// Fires on the work's own opening paragraph, then again on the first
	// real paragraph following each chapter boundary -- h2.heading is what
	// AO3ChapterHTMLExtractor rewrites a fetched chapter's h3.title into;
	// h3.title is kept as a fallback for Ambrosia-embedded HTML.
	applyVersal(firstRealParagraph(container));

	container.querySelectorAll("h2.heading, h3.title").forEach(function (heading) {
		applyVersal(firstRealParagraphAfter(heading));
	});
}

// Inserts a decorative divider element before every chapter heading, so a
// multi-chapter work can read as e.g. a new dated letter page each time
// rather than one continuous sheet. Opt in via `data-chapter-divider` on
// #bodyContainer, with the divider's text taken from
// `data-chapter-divider-char` and its class from
// `data-chapter-divider-class` (both required -- the function no-ops if
// either is missing, same fail-safe pattern as applyVersalCaps' marker
// attribute). This used to be Vintage Letter Green's own inline <script>,
// which had the same allowsContentJavaScript problem applyVersalCaps did:
// it worked in the Settings preview and silently never ran in the real
// article reader. See Technotes/Themes.md.
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
		divider.textContent = dividerChar;
		heading.parentNode.insertBefore(divider, heading);
	});
}

function runStep(name, fn) {
	try {
		fn();
	} catch (e) {
		if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.debugLog) {
			window.webkit.messageHandlers.debugLog.postMessage(name + ": " + (e && e.message ? e.message : String(e)));
		}
	}
}

function processPage() {
	removeArticleIconAvatar();
	removeFeedNameLink();
	runStep("wrapFrames", wrapFrames);
	runStep("wrapTables", wrapTables);
	runStep("inlineVideos", inlineVideos);
	runStep("stripStyles", stripStyles);
	runStep("constrainBodyRelativeIframes", constrainBodyRelativeIframes);
	runStep("convertImgSrc", convertImgSrc);
	runStep("flattenPreElements", flattenPreElements);
	runStep("styleLocalFootnotes", styleLocalFootnotes);
	runStep("removeWpSmiley", removeWpSmiley);
	runStep("applyVersalCaps", applyVersalCaps);
	runStep("applyChapterDividers", applyChapterDividers);
	runStep("postRenderProcessing", postRenderProcessing);
}

document.addEventListener("DOMContentLoaded", function(event) {
	processPage();
})
