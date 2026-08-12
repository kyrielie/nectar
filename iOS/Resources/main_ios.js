var activeImageViewer = null;

class ImageViewer {
	constructor(img) {
		this.img = img;
		this.loadingInterval = null;
		this.activityIndicator = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PHN2ZyB4bWxuczpzdmc9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB2ZXJzaW9uPSIxLjAiIHdpZHRoPSI2NHB4IiBoZWlnaHQ9IjY0cHgiIHZpZXdCb3g9IjAgMCAxMjggMTI4IiB4bWw6c3BhY2U9InByZXNlcnZlIj48Zz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiMwMDAwMDAiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiNjY2NjY2MiIHRyYW5zZm9ybT0icm90YXRlKDMwIDY0IDY0KSIvPjxwYXRoIGQ9Ik01OS42IDBoOHY0MGgtOFYweiIgZmlsbD0iI2NjY2NjYyIgdHJhbnNmb3JtPSJyb3RhdGUoNjAgNjQgNjQpIi8+PHBhdGggZD0iTTU5LjYgMGg4djQwaC04VjB6IiBmaWxsPSIjY2NjY2NjIiB0cmFuc2Zvcm09InJvdGF0ZSg5MCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiNjY2NjY2MiIHRyYW5zZm9ybT0icm90YXRlKDEyMCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiNiMmIyYjIiIHRyYW5zZm9ybT0icm90YXRlKDE1MCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiM5OTk5OTkiIHRyYW5zZm9ybT0icm90YXRlKDE4MCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiM3ZjdmN2YiIHRyYW5zZm9ybT0icm90YXRlKDIxMCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiM2NjY2NjYiIHRyYW5zZm9ybT0icm90YXRlKDI0MCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiM0YzRjNGMiIHRyYW5zZm9ybT0icm90YXRlKDI3MCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiMzMzMzMzMiIHRyYW5zZm9ybT0icm90YXRlKDMwMCA2NCA2NCkiLz48cGF0aCBkPSJNNTkuNiAwaDh2NDBoLThWMHoiIGZpbGw9IiMxOTE5MTkiIHRyYW5zZm9ybT0icm90YXRlKDMzMCA2NCA2NCkiLz48YW5pbWF0ZVRyYW5zZm9ybSBhdHRyaWJ1dGVOYW1lPSJ0cmFuc2Zvcm0iIHR5cGU9InJvdGF0ZSIgdmFsdWVzPSIwIDY0IDY0OzMwIDY0IDY0OzYwIDY0IDY0OzkwIDY0IDY0OzEyMCA2NCA2NDsxNTAgNjQgNjQ7MTgwIDY0IDY0OzIxMCA2NCA2NDsyNDAgNjQgNjQ7MjcwIDY0IDY0OzMwMCA2NCA2NDszMzAgNjQgNjQiIGNhbGNNb2RlPSJkaXNjcmV0ZSIgZHVyPSIxMDgwbXMiIHJlcGVhdENvdW50PSJpbmRlZmluaXRlIj48L2FuaW1hdGVUcmFuc2Zvcm0+PC9nPjwvc3ZnPg==";
	}

	isLoaded() {
		return this.img.classList.contains("nnwLoaded");
	}

	clicked() {
		this.showLoadingIndicator();
		if (this.isLoaded()) {
			this.showViewer();
		} else {
			var callback = () => {
				if (this.isLoaded()) {
					clearInterval(this.loadingInterval);
					this.showViewer();
				}
			}
			this.loadingInterval = setInterval(callback, 100);
		}
	}
	cancel() {
		clearInterval(this.loadingInterval);
		this.hideLoadingIndicator();
	}

	showViewer() {
		this.hideLoadingIndicator();
		
		const rect = this.img.getBoundingClientRect();
		
		// Instead of trying to convert to canvas (which fails with CORS),
		// send the original image src URL
		const message = {
			x: rect.x,
			y: rect.y,
			width: rect.width,
			height: rect.height,
			imageTitle: this.img.title,
			imageURL: this.img.src,
		};

		var jsonMessage = JSON.stringify(message);
		window.webkit.messageHandlers.imageWasClicked.postMessage(jsonMessage);
	}

	hideImage() {
		this.img.style.opacity = 0;
	}

	showImage() {
		this.img.style.opacity = 1
	}

	showLoadingIndicator() {
		var wrapper = document.createElement("div");
		wrapper.classList.add("activityIndicatorWrap");
		this.img.parentNode.insertBefore(wrapper, this.img);
		wrapper.appendChild(this.img);

		var activityIndicatorImg = document.createElement("img");
		activityIndicatorImg.classList.add("activityIndicator");
		activityIndicatorImg.style.opacity = 0;
		activityIndicatorImg.src = this.activityIndicator;
		wrapper.appendChild(activityIndicatorImg);

		activityIndicatorImg.style.opacity = 1;
	}

	hideLoadingIndicator() {
		var wrapper = this.img.parentNode;
		if (wrapper.classList.contains("activityIndicatorWrap")) {
			var wrapperParent = wrapper.parentNode;
			wrapperParent.insertBefore(this.img, wrapper);
			wrapperParent.removeChild(wrapper);
		}
	}

	static init() {
		cancelImageLoad();

		// keep track of when an image has finished downloading for ImageViewer
		document.querySelectorAll("img").forEach(element => {
			element.onload = function() {
				this.classList.add("nnwLoaded");
			}
		});

		// Add the click listener for images
		window.onclick = function(event) {
			if (event.target.matches("img") && !event.target.classList.contains("nnw-nozoom")) {
				if (activeImageViewer && activeImageViewer.img === event.target) {
					cancelImageLoad();
				} else {
					cancelImageLoad();
					activeImageViewer = new ImageViewer(event.target);
					activeImageViewer.clicked();
				}
			}
		}
	}
}

function cancelImageLoad() {
	if (activeImageViewer) {
		activeImageViewer.cancel();
		activeImageViewer = null;
	}
}

function hideClickedImage() {
	if (activeImageViewer) {
		activeImageViewer.hideImage();
	}
}

// Used to animate the transition from a fullscreen image
function showClickedImage() {
	if (activeImageViewer) {
		activeImageViewer.showImage();
	}
	window.webkit.messageHandlers.imageWasShown.postMessage("");
}

function postRenderProcessing() {
	ImageViewer.init();
}

function onResize() {
	const meta = document.querySelector("meta[name=viewport]");
	
	if (!meta) return;
	
	const originalContent = meta.content;
	meta.setAttribute("content", originalContent + ", maximum-scale=1.0");
	meta.setAttribute("content", originalContent);
}
window.addEventListener("resize", onResize);


function makeHighlightRect({left, top, width, height}, offsetTop=0, offsetLeft=0) {
	const overlay = document.createElement('a');

	Object.assign(overlay.style, {
		position: 'absolute',
		left: `${Math.floor(left + offsetLeft)}px`,
		top: `${Math.floor(top + offsetTop)}px`,
		width: `${Math.ceil(width)}px`,
		height: `${Math.ceil(height)}px`,
		backgroundColor: 'rgba(200, 220, 10, 0.4)',
		pointerEvents: 'none'
	});

	return overlay;
}

function clearHighlightRects() {
	let container = document.getElementById('nnw:highlightContainer')
	if (container) container.remove();
}

function highlightRects(rects, clearOldRects=true, makeHighlightRect=makeHighlightRect) {
	const article = document.querySelector('article');
	let container = document.getElementById('nnw:highlightContainer');

	article.style.position = 'relative';

	if (container && clearOldRects)
		container.remove();

	container = document.createElement('div');
	container.id = 'nnw:highlightContainer';
	article.appendChild(container);

	const {top, left} = article.getBoundingClientRect();
	return Array.from(rects, rect => 
		container.appendChild(makeHighlightRect(rect, -top, -left))
	);
}

FinderResult = class {
	constructor(result) {
		Object.assign(this, result);
	}

	range() {
		const range = document.createRange();
		range.setStart(this.node, this.offset);
		range.setEnd(this.node, this.offsetEnd);
		return range;
	}

	bounds() {
		return this.range().getBoundingClientRect();
	}

	rects() {
		return this.range().getClientRects();
	}

	highlight({clearOldRects=true, fn=makeHighlightRect} = {}) {
		highlightRects(this.rects(), clearOldRects, fn);
	}

	scrollTo() {
		scrollToRect(this.bounds(), this.node);
	}

	toJSON() {
		return {
			rects: Array.from(this.rects()),
			bounds: this.bounds(),
			index: this.index,
			matchGroups: this.match
		};
	}

	toJSONString() {
		return JSON.stringify(this.toJSON());
	}
}

Finder = class {
	constructor(pattern, options) {
		if (!pattern.global) {
			pattern = new RegExp(pattern, 'g');
		}

		this.pattern = pattern;
		this.lastResult = null;
		this._nodeMatches = [];
		this.options = {
			rootSelector: '.articleBody',
			startNode: null,
			startOffset: null,
		}

		this.resultIndex = -1

		Object.assign(this.options, options);

		this.walker = document.createTreeWalker(this.root, NodeFilter.SHOW_TEXT);
	}

	get root() {
		return document.querySelector(this.options.rootSelector)
	}

	get count() {
		const node = this.walker.currentNode;
		const index = this.resultIndex;
		this.reset();

		let result, count = 0;
		while ((result = this.next())) ++count;

		this.resultIndex = index;
		this.walker.currentNode = node;

		return count;
	}

	reset() {
		this.walker.currentNode = this.options.startNode || this.root;
		this.resultIndex = -1;
	}

	[Symbol.iterator]() {
		return this;
	}

	next({wrap = false} = {}) {
		const { startNode } = this.options;
		const { pattern, walker } = this;

		let { node, matchIndex = -1 } = this.lastResult || { node: startNode };

		while (true) {
			if (!node)
				node = walker.nextNode();

			if (!node) {
				if (!wrap || this.resultIndex < 0) break;

				this.reset();

				continue;
			}

			let nextIndex = matchIndex + 1;
			let matches = this._nodeMatches;

			if (!matches.length) {
				matches = Array.from(node.textContent.matchAll(pattern));
				nextIndex = 0;
			}
 
			if (matches[nextIndex]) {
				this._nodeMatches = matches;
				const m = matches[nextIndex];

				this.lastResult = new FinderResult({
					node,
					offset: m.index,
					offsetEnd: m.index + m[0].length,
					text: m[0],
					match: m,
					matchIndex: nextIndex,
					index: ++this.resultIndex,
				});

				return { value: this.lastResult, done: false };
			}

			this._nodeMatches = [];
			node = null;
		}

		return { value: undefined, done: true };
	}

	/// TODO Call when the search text changes
	retry() {
		if (this.lastResult) {
			this.lastResult.offsetEnd = this.lastResult.offset;
		}
		
	}

	toJSON() {
		const results = Array.from(this);
	}
}

function scrollParent(node) {
	let elt = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;

	while (elt) {
		if (elt.scrollHeight > elt.clientHeight)
			return elt;
		elt = elt.parentElement;
	}
}
 
function scrollToRect({top, height}, node, pad=20, padBottom=60) {
	const scrollToTop = top - pad;

	let scrollBy = scrollToTop;

	if (scrollToTop >= 0) {
		const visible = window.visualViewport;
		const scrollToBottom = top + height + padBottom - visible.height;
		// The top of the rect is already in the viewport
		if (scrollToBottom <= 0 || scrollToTop === 0)
			// Don't need to scroll up--or can't
			return;

		scrollBy = Math.min(scrollToBottom, scrollBy);
	} 

	scrollParent(node).scrollBy({ top: scrollBy });
}

function withEncodedArg(fn) {
	return function(encodedData, ...rest) {
		const data = encodedData && JSON.parse(atob(encodedData));
		return fn(data, ...rest);
	}
}

// btoa() only handles Latin-1 (code points 0-255) and throws InvalidCharacterError
// on anything outside that range -- which real article/book text hits constantly:
// curly quotes, em dashes, accented characters, emoji. Every Swift-bound JSON
// payload built in this file must go through this instead of raw btoa(), or a
// single non-Latin-1 character anywhere in the payload silently breaks the whole
// call (see getTableOfContents/updateFind, and WebViewController.swift's
// fetchTableOfContents, which swallows the resulting evaluateJavaScript error
// with no logging -- so this class of bug shows up as "the button does nothing").
function toBase64(str) {
	return btoa(unescape(encodeURIComponent(str)));
}

function escapeRegex(s) {
	return s.replace(/[.?*+^$\\()[\]{}]/g, '\\$&');
}

class FindState {
	constructor(options) {
		let { text, caseSensitive, regex } = options;
		
		if (!regex)
			text = escapeRegex(text);
		
		const finder = new Finder(new RegExp(text, caseSensitive ? 'g' : 'ig'));
		this.results = Array.from(finder);
		this.index = -1;
		this.options = options;
	}
	
	get selected() {
		return this.index > -1 ? this.results[this.index] : null;
	}
	
	toJSON() {
		return {
			index: this.index > -1 ? this.index : null,
			results: this.results,
			count: this.results.length
		};
	}
	
	selectNext(step=1) {
		const index = this.index + step;
		const result = this.results[index];
		if (result) {
			this.index = index;
			result.highlight();
			result.scrollTo();
		}
		return result;
	}
	
	selectPrevious() {
		return this.selectNext(-1);
	}
}

CurrentFindState = null;

const ExcludeKeys = new Set(['top', 'right', 'bottom', 'left']);
updateFind = withEncodedArg(options => {
	// TODO Start at the current result position
	// TODO Introduce slight delay, cap the number of results, and report results asynchronously
	
	let newFindState;
	if (!options || !options.text) {
		clearHighlightRects();
		return
	}
	
	try {
		newFindState = new FindState(options);
	} catch (err) {
		clearHighlightRects();
		throw err;
	}
	
	if (newFindState.results.length) {
		let selected = CurrentFindState && CurrentFindState.selected;
		let selectIndex = 0;
		if (selected) {
			let {node: currentNode, offset: currentOffset} = selected;
			selectIndex = newFindState.results.findIndex(r => {
				if (r.node === currentNode) {
					return r.offset >= currentOffset;
				}
				
				let relation = currentNode.compareDocumentPosition(r.node);
				return Boolean(relation & Node.DOCUMENT_POSITION_FOLLOWING);
			});
		}
		
		newFindState.selectNext(selectIndex+1);
	} else {
		clearHighlightRects();
	}
	
	CurrentFindState = newFindState;
	return toBase64(JSON.stringify(CurrentFindState, (k, v) => (ExcludeKeys.has(k) ? undefined : v)));
});

selectNextResult = withEncodedArg(options => {
	if (CurrentFindState)
		CurrentFindState.selectNext();
});

selectPreviousResult = withEncodedArg(options => {
	if (CurrentFindState)
		CurrentFindState.selectPrevious();
});

function endFind() {
	clearHighlightRects()
	CurrentFindState = null;
}

// Table of contents.
//
// Ambrosia book content can be a single book (in which case top-level
// <h1> markup is the book's own title, not a TOC entry) or several books
// concatenated together (Calibre-derived anthology export), in which case
// each book's own <h1> begins a run of that book's <h2> chapter headings,
// up to the next <h1>. Calibre emits two distinct classes on those <h2>s:
// ordinary chapters get class="heading"; a book's closing "Afterword" (and,
// for one-shots, a repeated title heading) gets class="toc-heading". Both
// are real, navigable TOC entries -- selecting only "toc-heading" silently
// drops every ordinary chapter, so both classes are matched here.
//
// Source content reuses the same id (e.g. "calibre_toc_3") across separate
// books in an anthology, so ids are not unique within the document and
// document.getElementById() is not a reliable way to jump to a specific
// entry. Instead, entries are addressed by their position in document
// order among all <h1>/<h2> heading elements combined ("tocIndex"); id is
// still reported for display/debugging but must not be used for lookup.
function tocNodes() {
	return Array.from(document.querySelectorAll('h1, h2.heading, h2.toc-heading'));
}

getTableOfContents = withEncodedArg(options => {
	const entries = tocNodes().map((h, tocIndex) => ({
		tocIndex,
		id: h.id,
		text: h.textContent.trim(),
		tagName: h.tagName.toLowerCase(),
		isTocHeading: h.classList.contains('toc-heading')
	}));
	return toBase64(JSON.stringify(entries));
});

scrollToHeading = withEncodedArg(options => {
	const nodes = tocNodes();
	const el = nodes[options.tocIndex];
	if (el) {
		el.scrollIntoView({ behavior: 'instant', block: 'start' });
	}
});

// Inline series navigation (nectar-inline-series-nav-implementation-
// plan.md, Phase 4e). Repaints the tapped link's own text/disabled state
// in place, without a full page reload/scroll-position loss. `seriesKey`
// matches the `data-nectar-series-key="<ao3ID>|<direction>"` attribute
// AO3PrefaceRenderer stamps onto every tappable First/Previous/Next link
// (WebViewController's SeriesNavKey, `"\(ao3SeriesID)|\(direction)"`
// there). Deliberately `querySelectorAll`-shaped, not a single-id
// lookup: the same series' link appears twice on the page (the preface's
// top row and the "This work is part of" footer), and a work can belong
// to more than one series row, so every match for this key must repaint
// together.
updateNectarSeriesLink = withEncodedArg(options => {
	const { seriesKey, label, disabled } = options;
	document.querySelectorAll('[data-nectar-series-key="' + seriesKey + '"]').forEach(el => {
		el.textContent = label;
		if (disabled) {
			el.setAttribute('aria-disabled', 'true');
			el.classList.add('nectarSeriesLinkLoading');
		} else {
			el.removeAttribute('aria-disabled');
			el.classList.remove('nectarSeriesLinkLoading');
		}
	});
});

// Preface-flash fix: swaps #bodyContainer's content in place instead of a
// full loadHTMLString reload, for the two cases where the page needs to be
// re-rendered after the initial synthetic-preface render but the document
// itself hasn't changed (AO3ChapterFetcher finishing, successfully or not --
// see WebViewController's ao3ChapterFetchDidComplete(_:)/ao3ChapterFetchDidFail(_:)).
// template.html funnels preface + article content + series footer through one
// [[body]] substitution into #bodyContainer, so one swap covers all three.
//
// processPage() (main.js) re-runs after the swap since DOMContentLoaded --
// which is what triggers it originally -- doesn't fire again for an
// innerHTML mutation. This is safe to call a second time here: every step it
// runs (wrapFrames, stripStyles, flattenPreElements, applyVersalCaps, etc.)
// operates only on elements currently in the document, addressed fresh by
// selector each call, and none of them stash cross-call state at the
// document/window level -- the old #bodyContainer subtree (and anything
// those steps previously did to it) is simply gone, replaced by nodes that
// have not been processed yet, same as a first pass on initial load.
updateArticleBody = withEncodedArg(options => {
	const container = document.getElementById("bodyContainer");
	if (!container) return;
	container.innerHTML = options.html;
	processPage();
});
