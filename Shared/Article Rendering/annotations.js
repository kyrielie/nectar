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
// Scope of this file as of this step: the pure anchor-resolution and
// DOM-wrapping algorithm, plus the render/add/remove/update entry points
// Swift will call, implemented against plain DOM APIs so they're testable
// headlessly (see Tests/JS/annotations/). Selection capture, the
// WKScriptMessageHandler postMessage calls themselves, and the Swift-side
// message handlers come later -- this file exposes the functions Swift
// will call, but nothing here reaches into window.webkit.messageHandlers
// yet.

(function (global) {
	"use strict";

	var HIGHLIGHT_CLASS = "nnw-highlight";
	var DEFAULT_ROOT_SELECTOR = ".articleBody";

	// Below this prefix/suffix similarity score (0-1), a multiple-quote-match
	// is treated as ambiguous and the annotation is orphaned rather than
	// guessing at the wrong occurrence.
	var SIMILARITY_FLOOR = 0.5;

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
				var prefixLen = (annotation.quotePrefix || "").length || 32;
				var suffixLen = (annotation.quoteSuffix || "").length || 32;
				report.moved.push({
					annotationID: annotation.annotationID,
					startOffset: startOffset,
					endOffset: endOffset,
					quoteExact: resolvedText,
					quotePrefix: index.text.slice(Math.max(0, startOffset - prefixLen), startOffset),
					quoteSuffix: index.text.slice(endOffset, endOffset + suffixLen)
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

	function updateAnnotationColor(annotationID, colorName, options) {
		options = options || {};
		var rootSelector = options.rootSelector || DEFAULT_ROOT_SELECTOR;
		var root = document.querySelector(rootSelector) || document;
		var marks = root.querySelectorAll('mark.' + HIGHLIGHT_CLASS + '[data-annotation-id="' + cssEscape(annotationID) + '"]');
		marks.forEach(function (mark) {
			mark.setAttribute("data-annotation-color", colorName);
		});
	}

	var Annotations = {
		// Exposed for the Swift-callable entry points.
		renderAnnotations: renderAnnotations,
		addAnnotationHighlight: addAnnotationHighlight,
		removeAnnotationHighlight: removeAnnotationHighlight,
		updateAnnotationColor: updateAnnotationColor,

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
			HIGHLIGHT_CLASS: HIGHLIGHT_CLASS,
			SIMILARITY_FLOOR: SIMILARITY_FLOOR
		}
	};

	global.Annotations = Annotations;

	if (typeof module !== "undefined" && module.exports) {
		module.exports = Annotations;
	}
})(typeof window !== "undefined" ? window : globalThis);
