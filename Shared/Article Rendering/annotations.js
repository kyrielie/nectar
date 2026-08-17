// annotations.js
//
// Highlight + note anchoring for persisted annotations. Cross-platform
// (iOS and macOS both drive this via the message-handler bridge), which is
// why this is its own file rather than folded into main.js (shared) or
// main_ios.js (iOS-only).
//
// A highlight is anchored to text in a DOM that won't necessarily be
// byte-identical the next time it's rendered (re-extraction, an upstream
// edit), so a stored character offset alone can't be trusted forever. This
// file resolves each annotation's stored selector -- an exact quote plus a
// short prefix/suffix of surrounding text, and a character-offset position
// as a fast path -- against the current document on every render: try the
// stored offset first (cheap, usually still correct); if the text there no
// longer matches the stored quote, fall back to searching for the quote,
// using prefix/suffix to disambiguate if it occurs more than once; if it
// can't be found at all, mark it orphaned rather than dropping it or
// guessing at the wrong occurrence.
//
// Rendering wraps the resolved range in
// <mark class="nnw-highlight" data-annotation-id="..."> by splitting text
// nodes at the range's boundaries (Text.splitText), the same TreeWalker +
// splitText idiom applyVersalCaps (main.js) already uses for the drop-cap
// feature. This is deliberate DOM mutation, not an overlay: it survives
// scrolling/reflow for free (it's real DOM), and gives a real tappable
// element to hang a note-icon affordance off of. main_ios.js's Finder uses
// the same "root selector + cumulative text offset via SHOW_TEXT
// TreeWalker" idiom for find-in-page, but its highlightRects/overlay-<div>
// rendering technique is right only for that ephemeral, no-tap-target case
// -- persisted highlights need permanence across reflow and a real,
// taggable DOM node, so that technique isn't reused here.
//
// Scope of this file: the anchor-resolution and DOM-wrapping algorithm,
// the render/add/remove/update entry points Swift calls via
// evaluateJavaScript, and selection capture -- listening for
// selectionchange and posting textWasSelected so the native side can show
// a color-picker popover, plus computeSelectorForCurrentSelection, called
// once a color is chosen, which turns the live selection into the same
// quote/prefix/suffix/offset selector shape resolveAnnotation expects and
// draws the highlight immediately. The Swift-side message handlers that
// receive textWasSelected/annotationWasTapped, and the popover/note-editor
// UI itself, live in WebViewController and the SwiftUI views next to it.

(function (global) {
	"use strict";

	var HIGHLIGHT_CLASS = "nnw-highlight";
	var DEFAULT_ROOT_SELECTOR = ".articleBody";

	// Below this prefix/suffix similarity score (0-1), a multiple-quote-match
	// is treated as ambiguous and the annotation is orphaned rather than
	// guessing at the wrong occurrence.
	var SIMILARITY_FLOOR = 0.5;

	// quotePrefix/quoteSuffix capture window, in characters, on both sides
	// of the quote. Wide enough that NLTokenizer (Swift side,
	// AnnotationsListView) can usually recover the full surrounding
	// sentence from prefix+quote+suffix, not just a fragment. Used both
	// when a selection is first captured (selectorForRange) and whenever
	// an annotation is reanchored (renderAnnotations) -- the reanchor path
	// always recomputes against this current constant rather than reusing
	// whatever length an existing annotation's stored quotePrefix happens
	// to be, so annotations captured before this was widened still
	// self-heal up to the new window the next time their chapter is
	// rendered, the same way offset drift itself self-heals.
	var CONTEXT_CHARS = 200;

	// Same selector main_ios.js's tocNodes() uses to find navigable
	// chapter/book headings (see that function's own comment for why both
	// classes are matched). Duplicated here rather than imported --
	// annotations.js is cross-platform and deliberately doesn't depend on
	// an iOS-only script having run first (see this file's own
	// toBase64/fromBase64 helpers below for the same reasoning).
	var TOC_HEADING_SELECTOR = "h1, h2.heading, h2.toc-heading";

	// ---- Text extraction -----------------------------------------------
	//
	// Builds the root's full inner text in a single TreeWalker pass
	// (NodeFilter.SHOW_TEXT), recording each text node's cumulative start
	// offset into that combined string. Returns both the text and a
	// parallel array of {node, start, end} entries so resolved
	// [startOffset, endOffset) pairs can be mapped back to real DOM
	// node/offset pairs in wrapRange below.
	function buildTextIndex(root) {
		var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
		var text = "";
		var entries = [];
		var node;
		while ((node = walker.nextNode())) {
			var start = text.length;
			var content = node.textContent;
			text += content;
			entries.push({ node: node, start: start, end: start + content.length });
		}
		return { text: text, entries: entries };
	}

	// ---- Chapter heading lookup (chapterTitle derivation) ------------------
	//
	// Finds every TOC_HEADING_SELECTOR match inside `root` (the same root
	// buildTextIndex was just walked against for this annotation) and maps
	// each heading element to its cumulative text offset within that same
	// `entries` table, by locating the first text-index entry contained
	// within the heading element. Deliberately scoped to `root`
	// (annotation.rootSelector, default .articleBody), not `document` --
	// tocNodes() in main_ios.js queries document-wide, which also matches
	// the template's own chrome-level `.articleTitle h1` (the book's own
	// title, rendered outside .articleBody); scoping to root here means
	// that chrome heading is never considered a "chapter" for this
	// purpose, and more importantly keeps heading offsets in the exact
	// same coordinate space as the annotation's own startOffset/endOffset
	// (both measured against the same buildTextIndex(root) call) rather
	// than needing to translate between a document-wide index and a
	// root-scoped one.
	function buildHeadingIndex(root, entries) {
		var headings = Array.from(root.querySelectorAll(TOC_HEADING_SELECTOR));
		var index = [];
		for (var i = 0; i < headings.length; i++) {
			var heading = headings[i];
			var offset = null;
			for (var j = 0; j < entries.length; j++) {
				if (heading.contains(entries[j].node)) {
					offset = entries[j].start;
					break;
				}
			}
			if (offset !== null) {
				index.push({ offset: offset, title: heading.textContent.trim() });
			}
		}
		return index;
	}

	// The nearest preceding heading's title for a given text offset, or
	// null if there's no heading before it at all (front matter, or an
	// ordinary single-heading book whose one heading lives outside
	// .articleBody and was therefore never indexed -- see
	// buildHeadingIndex). headingIndex is assumed sorted in document
	// order, which querySelectorAll already guarantees.
	function nearestChapterTitle(headingIndex, offset) {
		var best = null;
		for (var i = 0; i < headingIndex.length; i++) {
			if (headingIndex[i].offset <= offset) {
				best = headingIndex[i];
			} else {
				break;
			}
		}
		return best ? best.title : null;
	}

	// ---- Similarity scoring (for disambiguating multiple quote matches) --
	//
	// A simple, dependency-free similarity: proportion of matching
	// characters at corresponding positions from the end of the candidate
	// prefix / start of the candidate suffix, compared against the stored
	// prefix/suffix. This doesn't need to be a general string-distance
	// algorithm -- prefix/suffix strings are short (tens of characters) and
	// only need to rank candidates relative to each other.
	function similarity(a, b) {
		if (!a && !b) return 1;
		if (!a || !b) return 0;
		var len = Math.min(a.length, b.length);
		if (len === 0) return 0;
		var matches = 0;
		for (var i = 0; i < len; i++) {
			if (a[i] === b[i]) matches++;
		}
		return matches / Math.max(a.length, b.length);
	}

	// Score a candidate match's surrounding context against the stored
	// prefix/suffix selector. Prefix is compared right-aligned (characters
	// immediately before the match matter most), suffix left-aligned
	// (characters immediately after matter most).
	function scoreCandidate(text, matchStart, matchEnd, quotePrefix, quoteSuffix) {
		var prefixLen = quotePrefix ? quotePrefix.length : 0;
		var suffixLen = quoteSuffix ? quoteSuffix.length : 0;

		var candidatePrefix = text.slice(Math.max(0, matchStart - prefixLen), matchStart);
		var candidateSuffix = text.slice(matchEnd, matchEnd + suffixLen);

		var prefixScore = similarity(candidatePrefix, quotePrefix || "");
		var suffixScore = similarity(candidateSuffix, quoteSuffix || "");

		// Weight equally; either side matching well is meaningful signal.
		return (prefixScore + suffixScore) / 2;
	}

	// Finds every non-overlapping occurrence of `quote` in `text`.
	function findAllOccurrences(text, quote) {
		var occurrences = [];
		if (!quote) return occurrences;
		var fromIndex = 0;
		while (true) {
			var index = text.indexOf(quote, fromIndex);
			if (index === -1) break;
			occurrences.push({ start: index, end: index + quote.length });
			fromIndex = index + 1; // allow overlapping matches to be considered
		}
		return occurrences;
	}

	// ---- Core resolution --------------------------------------------------
	//
	// Attempts to resolve one annotation's stored selector against the
	// current `text`. Returns:
	//   { status: "unchanged" }                              -- stored offsets still valid
	//   { status: "reanchored", startOffset, endOffset }      -- moved, found unambiguously
	//   { status: "orphaned" }                                -- not found, or ambiguous below the similarity floor
	function resolveAnnotation(annotation, text) {
		var start = annotation.startOffset;
		var end = annotation.endOffset;
		var quoteExact = annotation.quoteExact;

		// Step 2: try the stored position first.
		if (
			typeof start === "number" &&
			typeof end === "number" &&
			start >= 0 &&
			end <= text.length &&
			start < end &&
			text.slice(start, end) === quoteExact
		) {
			return { status: "unchanged" };
		}

		// Step 3: stored position didn't match (or wasn't set/valid) -- fall
		// back to a full quote search, disambiguated by prefix/suffix when
		// there's more than one occurrence.
		var occurrences = findAllOccurrences(text, quoteExact);

		if (occurrences.length === 0) {
			return { status: "orphaned" };
		}

		if (occurrences.length === 1) {
			var only = occurrences[0];
			return { status: "reanchored", startOffset: only.start, endOffset: only.end };
		}

		// Multiple matches: score each by prefix/suffix similarity and take
		// the best above the floor. Below the floor, orphan rather than
		// guess wrong silently.
		var best = null;
		var bestScore = -1;
		for (var i = 0; i < occurrences.length; i++) {
			var occurrence = occurrences[i];
			var score = scoreCandidate(text, occurrence.start, occurrence.end, annotation.quotePrefix, annotation.quoteSuffix);
			if (score > bestScore) {
				bestScore = score;
				best = occurrence;
			}
		}

		if (best && bestScore >= SIMILARITY_FLOOR) {
			return { status: "reanchored", startOffset: best.start, endOffset: best.end };
		}

		return { status: "orphaned" };
	}

	// ---- DOM mapping + wrapping --------------------------------------------
	//
	// Maps a resolved [startOffset, endOffset) pair in the combined-text
	// coordinate space back to a Range against real DOM nodes, using the
	// same `entries` table buildTextIndex produced, then splits text nodes
	// at both boundaries (Text.splitText, applyVersalCaps' technique) and
	// wraps every text node fully contained within the range in a <mark>.
	// A range spanning multiple text nodes (crosses an inline element or
	// paragraph boundary) wraps each contained text node individually with
	// the same data-annotation-id, rather than collapsing to textContent --
	// same "don't discard inline markup" requirement applyVersalCaps'
	// header comment already states.
	function wrapRange(entries, startOffset, endOffset, annotationID, colorName) {
		var wrapped = [];

		for (var i = 0; i < entries.length; i++) {
			var entry = entries[i];

			// Entry lies entirely outside the range.
			if (entry.end <= startOffset || entry.start >= endOffset) continue;

			var node = entry.node;
			var nodeStart = entry.start;

			// Trim the trailing portion first (higher offset), so the earlier
			// splitText call below doesn't invalidate this one's offset.
			var localEnd = Math.min(endOffset, entry.end) - nodeStart;
			if (localEnd < node.textContent.length) {
				node.splitText(localEnd);
			}

			// Trim the leading portion, if this entry starts before the range.
			var localStart = Math.max(startOffset, entry.start) - nodeStart;
			var middleNode = node;
			if (localStart > 0) {
				middleNode = node.splitText(localStart);
			}

			var mark = document.createElement("mark");
			mark.className = HIGHLIGHT_CLASS;
			mark.setAttribute("data-annotation-id", annotationID);
			if (colorName) {
				mark.setAttribute("data-annotation-color", colorName);
			}

			middleNode.parentNode.insertBefore(mark, middleNode);
			mark.appendChild(middleNode);
			wrapped.push(mark);
		}

		return wrapped;
	}

	// Removes any existing <mark> wraps for annotationID, unwrapping their
	// text content back into the surrounding DOM (used by
	// removeAnnotationHighlight and before re-rendering during
	// re-anchoring, so a moved highlight doesn't leave a stale duplicate
	// mark behind at its old position).
	function unwrapAnnotation(root, annotationID) {
		var marks = root.querySelectorAll('mark.' + HIGHLIGHT_CLASS + '[data-annotation-id="' + cssEscape(annotationID) + '"]');
		marks.forEach(function (mark) {
			var parent = mark.parentNode;
			if (!parent) return;
			while (mark.firstChild) {
				parent.insertBefore(mark.firstChild, mark);
			}
			parent.removeChild(mark);
			parent.normalize();
		});
	}

	function cssEscape(value) {
		if (global.CSS && typeof global.CSS.escape === "function") {
			return global.CSS.escape(value);
		}
		// Minimal fallback for environments without CSS.escape (older
		// WebKit, or the headless test environment) -- annotationIDs are
		// client-generated UUIDs, so this only needs to be safe for that
		// character set, not general-purpose.
		return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
	}

	// ---- Public entry points ------------------------------------------------

	// Resolves and draws every annotation's highlight against the current
	// document. Called after DOMContentLoaded with the full set for this
	// article. Returns a single reanchor report ({ moved: [...], orphanedIDs: [...] })
	// rather than posting per-annotation, to keep the bridge chatty-message
	// count bounded on chapters with many highlights -- the actual postMessage
	// call is Swift-bridge wiring (later step); this function just computes
	// and returns the report so that call site can send it.
	function renderAnnotations(annotations, options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector);

		var report = { moved: [], orphanedIDs: [] };
		if (!root || !annotations || !annotations.length) {
			return report;
		}

		annotations.forEach(function (annotation) {
			unwrapAnnotation(root, annotation.annotationID);
		});

		annotations.forEach(function (annotation) {
			var effectiveRoot = document.querySelector(annotation.rootSelector || rootSelector) || root;
			var index = buildTextIndex(effectiveRoot);
			var resolution = resolveAnnotation(annotation, index.text);

			if (resolution.status === "orphaned") {
				report.orphanedIDs.push(annotation.annotationID);
				return;
			}

			var startOffset = resolution.status === "reanchored" ? resolution.startOffset : annotation.startOffset;
			var endOffset = resolution.status === "reanchored" ? resolution.endOffset : annotation.endOffset;

			wrapRange(index.entries, startOffset, endOffset, annotation.annotationID, annotation.color);

			if (resolution.status === "reanchored") {
				var resolvedText = index.text.slice(startOffset, endOffset);
				var headingIndex = buildHeadingIndex(effectiveRoot, index.entries);
				report.moved.push({
					annotationID: annotation.annotationID,
					startOffset: startOffset,
					endOffset: endOffset,
					quoteExact: resolvedText,
					quotePrefix: index.text.slice(Math.max(0, startOffset - CONTEXT_CHARS), startOffset),
					quoteSuffix: index.text.slice(endOffset, endOffset + CONTEXT_CHARS),
					chapterTitle: nearestChapterTitle(headingIndex, startOffset)
				});
			}
		});

		return report;
	}

	// Draws a single new highlight immediately (the "no round trip needed
	// before the person sees it highlighted" path). Unlike
	// renderAnnotations, this trusts the passed-in offsets as-is --
	// they were just computed against the live selection, not stored data
	// that might be stale.
	function addAnnotationHighlight(annotation, options) {
		options = options || {};
		var rootSelector = annotation.rootSelector || options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector);
		if (!root) return [];

		var index = buildTextIndex(root);
		return wrapRange(index.entries, annotation.startOffset, annotation.endOffset, annotation.annotationID, annotation.color);
	}

	function removeAnnotationHighlight(annotationID, options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector) || document;
		unwrapAnnotation(root, annotationID);
	}

	// ---- Base64 helpers (for the evaluateJavaScript call/response convention) --
	//
	// Self-contained rather than reused from main_ios.js's toBase64, since
	// this file is cross-platform and can't assume an iOS-only script ran
	// first (or at all, on macOS). Plain btoa()/atob() only handle Latin-1
	// (code points 0-255) and throw on anything outside that range, which
	// real article/quote text hits constantly -- curly quotes, em dashes,
	// accented characters, emoji -- so both directions go through the
	// encodeURIComponent/decodeURIComponent round trip below.
	function toBase64(str) {
		return global.btoa(unescape(encodeURIComponent(str)));
	}

	function fromBase64(str) {
		return decodeURIComponent(escape(global.atob(str)));
	}

	function updateAnnotationColor(annotationID, colorName, options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector) || document;
		var marks = root.querySelectorAll('mark.' + HIGHLIGHT_CLASS + '[data-annotation-id="' + cssEscape(annotationID) + '"]');
		marks.forEach(function (mark) {
			mark.setAttribute("data-annotation-color", colorName);
		});
	}

	// Scrolls the first <mark> for annotationID into view and adds a
	// brief flash class (nnw-highlight-flash, styled in core.css) so the
	// destination is obvious even against a highlight color the person
	// might not immediately spot on a long page -- same "land in a
	// specific spot, not just the general area" goal scrollToHeading
	// serves for table-of-contents navigation, but keyed on an annotation
	// ID against a real DOM node rather than a heading index. A range
	// spanning multiple text nodes produces multiple <mark> elements (see
	// wrapRange); scrolling to the first is sufficient since they're
	// always visually contiguous.
	function scrollToAnnotation(annotationID, options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector) || document;
		var mark = root.querySelector('mark.' + HIGHLIGHT_CLASS + '[data-annotation-id="' + cssEscape(annotationID) + '"]');
		if (!mark) return false;

		mark.scrollIntoView({ block: "center" });
		mark.classList.add("nnw-highlight-flash");
		setTimeout(function () {
			mark.classList.remove("nnw-highlight-flash");
		}, 1500);
		return true;
	}

	// ---- Selection capture ----------------------------------------------
	//
	// Turns a live Range (the person's current selection, or a
	// programmatically constructed one) into the same
	// {quoteExact, quotePrefix, quoteSuffix, startOffset, endOffset,
	// rootSelector} selector shape stored annotations use, by locating the
	// range's boundaries within the same cumulative text index
	// buildTextIndex produces elsewhere in this file. This is the
	// selection-time counterpart to resolveAnnotation's render-time lookup
	// -- same coordinate space, opposite direction.
	function selectorForRange(range, root, rootSelector) {
		var index = buildTextIndex(root);

		var startOffset = null;
		var endOffset = null;
		var runningOffset = 0;

		for (var i = 0; i < index.entries.length; i++) {
			var entry = index.entries[i];
			if (startOffset === null && entry.node === range.startContainer) {
				startOffset = entry.start + range.startOffset;
			}
			if (entry.node === range.endContainer) {
				endOffset = entry.start + range.endOffset;
			}
			runningOffset = entry.end;
		}

		if (startOffset === null || endOffset === null || endOffset <= startOffset) {
			return null;
		}

		var quoteExact = index.text.slice(startOffset, endOffset);
		var headingIndex = buildHeadingIndex(root, index.entries);

		return {
			quoteExact: quoteExact,
			quotePrefix: index.text.slice(Math.max(0, startOffset - CONTEXT_CHARS), startOffset),
			quoteSuffix: index.text.slice(endOffset, Math.min(index.text.length, endOffset + CONTEXT_CHARS)),
			rootSelector: rootSelector,
			startOffset: startOffset,
			endOffset: endOffset,
			chapterTitle: nearestChapterTitle(headingIndex, startOffset)
		};
	}

	// Called via evaluateJavaScript right after the person taps a color
	// swatch: evaluateJavaScript("addHighlightFromSelection(\"<base64 JSON
	// {annotationID, color, rootSelector?}>\")"). Computes the selector
	// against the current selection, draws the highlight immediately so
	// there's no visible delay before the person sees it highlighted,
	// clears the selection, and returns the selector as a base64-encoded
	// JSON string -- the same call/response shape getTableOfContents and
	// updateFind already use -- so the native side can persist it. Returns
	// the base64 encoding of the literal string "null" if there's no
	// usable selection (e.g. the person dismissed the popover without a
	// selection surviving), which the Swift side decodes and checks for
	// same as any other JSON null.
	function addHighlightFromSelection(encodedArgs) {
		var args;
		try {
			args = JSON.parse(fromBase64(encodedArgs));
		} catch (e) {
			return toBase64("null");
		}

		var rootSelector = args.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector);
		var selection = global.getSelection ? global.getSelection() : null;

		if (!root || !selection || selection.rangeCount === 0 || selection.isCollapsed) {
			return toBase64("null");
		}

		var range = selection.getRangeAt(0);
		if (!root.contains(range.commonAncestorContainer)) {
			return toBase64("null");
		}

		var selector = selectorForRange(range, root, rootSelector);
		if (!selector) {
			return toBase64("null");
		}

		selection.removeAllRanges();

		var index = buildTextIndex(root);
		wrapRange(index.entries, selector.startOffset, selector.endOffset, args.annotationID, args.color);

		return toBase64(
			JSON.stringify({
				annotationID: args.annotationID,
				color: args.color,
				quoteExact: selector.quoteExact,
				quotePrefix: selector.quotePrefix,
				quoteSuffix: selector.quoteSuffix,
				rootSelector: selector.rootSelector,
				startOffset: selector.startOffset,
				endOffset: selector.endOffset,
				chapterTitle: selector.chapterTitle
			})
		);
	}

	// ---- Bridge wiring: selectionchange -> textWasSelected, tap -> annotationWasTapped
	//
	// Debounced the same way find-in-page-adjacent interaction handling in
	// this codebase already coalesces bursty events, just with a plain
	// setTimeout here rather than a queue that needs to survive
	// backgrounding -- this only needs to survive the handful of
	// selectionchange events a single drag emits.
	var SELECTION_DEBOUNCE_MS = 150;
	var selectionDebounceTimer = null;

	function postMessage(name, payload) {
		try {
			if (global.webkit && global.webkit.messageHandlers && global.webkit.messageHandlers[name]) {
				global.webkit.messageHandlers[name].postMessage(payload);
			}
		} catch (e) {
			// messageHandler not installed (e.g. Settings theme preview, which
			// renders article HTML without the full WebViewController bridge)
			// -- selection capture simply does nothing there, same fail-quiet
			// shape as processPage's runStep wrapper in main.js.
		}
	}

	function handleSelectionChange(options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;

		if (selectionDebounceTimer) {
			clearTimeout(selectionDebounceTimer);
		}

		selectionDebounceTimer = setTimeout(function () {
			var root = document.querySelector(rootSelector);
			var selection = global.getSelection ? global.getSelection() : null;

			// Posting {cleared: true} here (rather than just returning
			// silently, as before) lets the native side reset its cached
			// "is there currently a highlightable selection" flag --
			// needed by PreloadedWebView.buildMenu(with:) in native-menu
			// mode, which has no other way to know a selection was
			// dismissed/collapsed since its last build. The popup path
			// (WebViewController.textWasSelected) simply ignores
			// {cleared: true} payloads, since it has nothing to dismiss
			// that wasn't already dismissed when a swatch was tapped.
			if (!root || !selection || selection.rangeCount === 0 || selection.isCollapsed) {
				postMessage("textWasSelected", { cleared: true });
				return;
			}

			var range = selection.getRangeAt(0);
			if (!root.contains(range.commonAncestorContainer)) {
				postMessage("textWasSelected", { cleared: true });
				return;
			}

			var text = range.toString();
			if (!text || !text.trim().length) {
				postMessage("textWasSelected", { cleared: true });
				return;
			}

			var rect = range.getBoundingClientRect();
			postMessage("textWasSelected", {
				x: rect.x,
				y: rect.y,
				width: rect.width,
				height: rect.height
			});
		}, SELECTION_DEBOUNCE_MS);
	}

	function handleAnnotationTap(event) {
		var mark = event.target && event.target.closest ? event.target.closest("mark." + HIGHLIGHT_CLASS) : null;
		if (!mark) return;

		var annotationID = mark.getAttribute("data-annotation-id");
		if (!annotationID) return;

		event.preventDefault();
		postMessage("annotationWasTapped", { annotationID: annotationID });
	}

	// Wires the two DOM listeners above. Safe to call more than once per
	// document (e.g. if a future caller re-inits after a partial content
	// swap) -- document-level listeners aren't duplicated meaningfully
	// enough to matter here, but init is still named/idempotent-in-intent
	// rather than folded into top-level script execution, so a future
	// caller has an explicit, single place to hook re-initialization into.
	function initAnnotations(options) {
		options = options || {};
		// mode "off" means selecting text shouldn't offer to create a
		// highlight at all -- skip wiring selectionchange entirely rather
		// than wiring it and having the native side ignore its messages,
		// so there's no background work (or stray textWasSelected
		// traffic) for a mode the person has turned off. The click
		// listener below is unaffected by mode: tapping an *existing*
		// highlight to view/edit it must always work regardless of how
		// (or whether) new highlights can currently be created.
		if (options.mode !== "off") {
			document.addEventListener("selectionchange", function () {
				handleSelectionChange(options);
			});
		}
		document.addEventListener("click", handleAnnotationTap);
	}

	// evaluateJavaScript-callable wrapper around renderAnnotations: takes a
	// base64-encoded JSON array of annotations, returns the base64-encoded
	// JSON {moved, orphanedIDs} report. Called by WebViewController once,
	// after DOMContentLoaded, with the full annotation set fetched for the
	// current article.
	function renderAnnotationsEncoded(encodedArgs) {
		var annotations;
		try {
			annotations = JSON.parse(fromBase64(encodedArgs));
		} catch (e) {
			return toBase64(JSON.stringify({ moved: [], orphanedIDs: [] }));
		}
		var report = renderAnnotations(annotations);
		return toBase64(JSON.stringify(report));
	}

	var Annotations = {
		// Exposed for the Swift-callable entry points.
		renderAnnotations: renderAnnotations,
		renderAnnotationsEncoded: renderAnnotationsEncoded,
		addAnnotationHighlight: addAnnotationHighlight,
		removeAnnotationHighlight: removeAnnotationHighlight,
		updateAnnotationColor: updateAnnotationColor,
		addHighlightFromSelection: addHighlightFromSelection,
		initAnnotations: initAnnotations,
		scrollToAnnotation: scrollToAnnotation,

		// Exposed for headless unit testing (annotations.test.js) of the
		// pure algorithm pieces without needing to drive the whole
		// render/wrap pipeline through a real document.
		_internal: {
			buildTextIndex: buildTextIndex,
			resolveAnnotation: resolveAnnotation,
			findAllOccurrences: findAllOccurrences,
			scoreCandidate: scoreCandidate,
			similarity: similarity,
			wrapRange: wrapRange,
			unwrapAnnotation: unwrapAnnotation,
			selectorForRange: selectorForRange,
			buildHeadingIndex: buildHeadingIndex,
			nearestChapterTitle: nearestChapterTitle,
			HIGHLIGHT_CLASS: HIGHLIGHT_CLASS,
			SIMILARITY_FLOOR: SIMILARITY_FLOOR,
			CONTEXT_CHARS: CONTEXT_CHARS
		}
	};

	global.Annotations = Annotations;

	if (typeof module !== "undefined" && module.exports) {
		module.exports = Annotations;
	}
})(typeof window !== "undefined" ? window : globalThis);
