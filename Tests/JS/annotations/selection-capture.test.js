// Coverage for annotations.js's selection-capture path: turning a live
// window.Selection into the same selector shape stored/resolved
// annotations use, drawing the highlight immediately, and the
// selectionchange/click DOM-listener wiring that drives the native-side
// popover and note-editor entry points.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations, encodeArgs, decodeResult } = require("./setup");

function selectTextInNode(window, node, start, end) {
	const range = window.document.createRange();
	range.setStart(node, start);
	range.setEnd(node, end);
	const selection = window.getSelection();
	selection.removeAllRanges();
	selection.addRange(range);
	return range;
}

test("addHighlightFromSelection computes a selector and draws the mark immediately", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	selectTextInNode(window, textNode, 0, 4); // "Once"

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "new-id", color: "yellow" })));

	assert.ok(result, "expected a selector to be returned");
	assert.equal(result.annotationID, "new-id");
	assert.equal(result.color, "yellow");
	assert.equal(result.quoteExact, "Once");
	assert.equal(result.startOffset, 0);
	assert.equal(result.endOffset, 4);
	assert.equal(result.chapterTitle, null, "no heading in this fixture");

	const mark = document.querySelector('mark[data-annotation-id="new-id"]');
	assert.ok(mark, "the highlight should be drawn immediately, not after a round trip");
	assert.equal(mark.textContent, "Once");
});

test("addHighlightFromSelection captures prefix/suffix context around the selection", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox in the garden.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	const fullText = textNode.textContent;
	const start = fullText.indexOf("a fox");
	const end = start + "a fox".length;
	selectTextInNode(window, textNode, start, end);

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "a1", color: "blue" })));

	assert.equal(result.quoteExact, "a fox");
	assert.ok(result.quotePrefix.endsWith("was "), `expected quotePrefix to end with "was ", got ${JSON.stringify(result.quotePrefix)}`);
	assert.ok(result.quoteSuffix.startsWith(" in the"), `expected quoteSuffix to start with " in the", got ${JSON.stringify(result.quoteSuffix)}`);
});

test("addHighlightFromSelection captures up to CONTEXT_CHARS on each side, not the old 32-char window", () => {
	const long = "word ".repeat(80).trim();
	const { Annotations, document, window } = loadAnnotations(
		`<div class="articleBody"><p>${long} TARGET ${long}</p></div>`
	);
	const textNode = document.querySelector("p").firstChild;
	const fullText = textNode.textContent;
	const start = fullText.indexOf("TARGET");
	const end = start + "TARGET".length;
	selectTextInNode(window, textNode, start, end);

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "a1", color: "blue" })));

	assert.equal(result.quotePrefix.length, Annotations._internal.CONTEXT_CHARS);
	assert.equal(result.quoteSuffix.length, Annotations._internal.CONTEXT_CHARS);
});

test("addHighlightFromSelection includes chapterTitle for the nearest preceding heading", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody">'
		+ '<h2 class="heading">Chapter 1: Arrival</h2>'
		+ '<p>The fox waited by the door.</p>'
		+ '</div>'
	);
	const textNode = document.querySelector("p").firstChild;
	const fullText = textNode.textContent;
	const start = fullText.indexOf("fox");
	const end = start + "fox".length;
	selectTextInNode(window, textNode, start, end);

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "a1", color: "blue" })));

	assert.equal(result.chapterTitle, "Chapter 1: Arrival");
});

test("addHighlightFromSelection clears the selection after drawing", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	selectTextInNode(window, textNode, 0, 4);

	decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "new-id", color: "yellow" })));

	assert.equal(window.getSelection().rangeCount, 0, "the selection should be cleared after committing a highlight");
});

test("addHighlightFromSelection returns null when there is no selection", () => {
	const { Annotations, window } = loadAnnotations('<div class="articleBody"><p>Nothing selected.</p></div>');
	window.getSelection().removeAllRanges();

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "new-id", color: "yellow" })));

	assert.equal(result, null);
});

test("addHighlightFromSelection returns null for a selection outside the root selector", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>In bounds.</p></div><div id="outside"><p>Out of bounds text.</p></div>'
	);
	const outsideText = document.querySelector("#outside p").firstChild;
	selectTextInNode(window, outsideText, 0, 11); // "Out of boun"

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "new-id", color: "yellow" })));

	assert.equal(result, null);
	assert.equal(document.querySelectorAll("mark").length, 0);
});

test("addHighlightFromSelection returns null for a collapsed selection", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	selectTextInNode(window, textNode, 4, 4); // zero-length

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "new-id", color: "yellow" })));

	assert.equal(result, null);
});

test("selectorForRange resolves the same offsets renderAnnotations would independently re-derive", () => {
	// A selection-computed selector, fed straight back into
	// resolveAnnotation, must resolve unchanged -- the two directions
	// (selection -> offsets, offsets -> resolution) have to agree on the
	// same coordinate space or a freshly created highlight would
	// immediately appear to have moved on the very next render.
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>The quick fox jumped over the lazy dog.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	const fullText = textNode.textContent;
	const start = fullText.indexOf("fox jumped");
	const end = start + "fox jumped".length;
	selectTextInNode(window, textNode, start, end);

	const selector = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "a1", color: "green" })));

	const resolution = Annotations._internal.resolveAnnotation(
		{
			startOffset: selector.startOffset,
			endOffset: selector.endOffset,
			quoteExact: selector.quoteExact
		},
		fullText
	);

	assert.deepEqual(resolution, { status: "unchanged" });
});

test("renderAnnotationsEncoded round-trips through base64 JSON like the evaluateJavaScript call site does", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const annotations = [{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once", color: "yellow" }];

	const report = decodeResult(Annotations.renderAnnotationsEncoded(encodeArgs(annotations)));

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	assert.ok(document.querySelector('mark[data-annotation-id="a1"]'));
});

test("renderAnnotationsEncoded round-trips non-Latin-1 text (curly quotes, accents, emoji) without breaking", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>She said “café” with a smile 🎉 today.</p></div>'
	);
	const fullText = document.querySelector("p").textContent;
	const quote = "“café”";
	const start = fullText.indexOf(quote);
	const annotations = [
		{ annotationID: "a1", startOffset: start, endOffset: start + quote.length, quoteExact: quote, color: "purple" }
	];

	const report = decodeResult(Annotations.renderAnnotationsEncoded(encodeArgs(annotations)));

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	assert.ok(mark);
	assert.equal(mark.textContent, quote);
});

test("renderAnnotationsEncoded returns an empty report for malformed input rather than throwing", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Text.</p></div>');

	const report = decodeResult(Annotations.renderAnnotationsEncoded("not valid base64 json!!"));

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
});

test("addHighlightFromSelection round-trips non-Latin-1 text in the returned selector", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>She said “café” with a smile.</p></div>'
	);
	const textNode = document.querySelector("p").firstChild;
	const fullText = textNode.textContent;
	const start = fullText.indexOf("“café”");
	const end = start + "“café”".length;
	const range = window.document.createRange();
	range.setStart(textNode, start);
	range.setEnd(textNode, end);
	const selection = window.getSelection();
	selection.removeAllRanges();
	selection.addRange(range);

	const result = decodeResult(Annotations.addHighlightFromSelection(encodeArgs({ annotationID: "a1", color: "purple" })));

	assert.equal(result.quoteExact, "“café”");
});

test("scrollToAnnotation scrolls to and flashes an existing highlight, returning true", async () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	Annotations.renderAnnotations([{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once" }]);

	const found = Annotations.scrollToAnnotation("a1");

	assert.equal(found, true);
	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	assert.ok(mark.classList.contains("nnw-highlight-flash"), "expected the flash class to be added immediately");

	await new Promise((resolve) => setTimeout(resolve, 1600));
	assert.ok(!mark.classList.contains("nnw-highlight-flash"), "expected the flash class to be removed after the timeout");
});

test("scrollToAnnotation returns false for an annotation with no rendered mark", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Nothing highlighted here.</p></div>');

	const found = Annotations.scrollToAnnotation("does-not-exist");

	assert.equal(found, false);
});

test("initAnnotations wires a tap on an existing mark to post annotationWasTapped", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	Annotations.renderAnnotations([{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once" }]);

	const posted = [];
	window.webkit = {
		messageHandlers: {
			annotationWasTapped: { postMessage: (payload) => posted.push(payload) }
		}
	};

	Annotations.initAnnotations();

	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	mark.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

	assert.equal(posted.length, 1);
	assert.equal(posted[0].annotationID, "a1");
});

test("initAnnotations does not post annotationWasTapped for a click outside any mark", () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	Annotations.renderAnnotations([{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once" }]);

	const posted = [];
	window.webkit = {
		messageHandlers: {
			annotationWasTapped: { postMessage: (payload) => posted.push(payload) }
		}
	};

	Annotations.initAnnotations();

	document.querySelector("p").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

	assert.equal(posted.length, 0);
});

test("selectionchange posts textWasSelected (debounced) with the selection's bounding rect, only for in-bounds non-empty selections", async () => {
	const { Annotations, document, window } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);

	const posted = [];
	window.webkit = {
		messageHandlers: {
			textWasSelected: { postMessage: (payload) => posted.push(payload) }
		}
	};

	// jsdom has no layout engine, so Range.getBoundingClientRect doesn't
	// exist at all there (real WebKit always provides it) -- stub it for
	// this test only. Assigning to the prototype (rather than the instance)
	// so the same createRange() used inside annotations.js's own
	// handleSelectionChange also gets it.
	window.Range.prototype.getBoundingClientRect = function () {
		return { x: 0, y: 0, width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0 };
	};

	Annotations.initAnnotations();

	const textNode = document.querySelector("p").firstChild;
	selectTextInNode(window, textNode, 0, 4);
	document.dispatchEvent(new window.Event("selectionchange"));

	// The debounce is a real setTimeout; wait past it.
	await new Promise((resolve) => setTimeout(resolve, 200));

	assert.equal(posted.length, 1);
	assert.ok("x" in posted[0] && "y" in posted[0] && "width" in posted[0] && "height" in posted[0]);
});
