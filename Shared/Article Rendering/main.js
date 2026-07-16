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
	var image = document.getElementById("nnwImageIcon");
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
	var icon = document.getElementById("nnwImageIcon");
	if (icon) {
		icon.remove();
	}
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

function processPage() {
	wrapFrames();
	wrapTables();
	inlineVideos();
	stripStyles();
	constrainBodyRelativeIframes();
	convertImgSrc();
	flattenPreElements();
	styleLocalFootnotes();
	removeWpSmiley()
	removeArticleIconAvatar();
	removeFeedNameLink();
	postRenderProcessing();
}

document.addEventListener("DOMContentLoaded", function(event) {
	processPage();
})
