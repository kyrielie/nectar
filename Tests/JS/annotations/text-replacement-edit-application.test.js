// Coverage for annotations.js's manual-edit application path: an
// annotation row with originalText/replacementText set is rendered by
// replacing its span in the DOM (applyTextEdit), and a row that is both
// a highlight and an edit (hasHighlight == true, originalText set) gets
// the freshly-edited span wrapped in <mark> immediately after, without
// re-resolving offsets against the post-edit DOM a second time. See
// docs/annotations.md, "Applying edits".

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations } = require("./setup");

test("edit-only row (hasHighlight false) replaces text with no <mark>, but still wraps a tappable span", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>She sat by the wall.</p></div>'
	);
	const annotation = {
		annotationID: "edit-1",
		startOffset: 15,
		endOffset: 19, // "wall"
		quoteExact: "wall",
		color: "yellow",
		hasHighlight: false,
		originalText: "wall",
		replacementText: "door"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	const paragraph = document.querySelector("p");
	assert.equal(paragraph.textContent, "She sat by the door.");
	assert.equal(document.querySelector("mark"), null, "an edit-only row should not draw a <mark>");

	// It's not a bare Text node, though -- there must still be a real
	// node to tap back into (see wrapEditOnlyTextNode).
	const span = document.querySelector(`span.${Annotations._internal.EDIT_ONLY_CLASS}[data-annotation-id="edit-1"]`);
	assert.ok(span, "expected the corrected text to be wrapped in an edit-only span");
	assert.equal(span.textContent, "door");
	assert.equal(span.getAttribute("data-annotation-color"), null, "an edit-only span carries no color attribute");
});

test("edit + highlight row wraps the freshly-edited text in <mark>", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>She sat by the wall.</p></div>'
	);
	const annotation = {
		annotationID: "edit-2",
		startOffset: 15,
		endOffset: 19, // "wall"
		quoteExact: "wall",
		color: "blue",
		hasHighlight: true,
		originalText: "wall",
		replacementText: "door"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	const paragraph = document.querySelector("p");
	assert.equal(paragraph.textContent, "She sat by the door.");

	const mark = document.querySelector('mark[data-annotation-id="edit-2"]');
	assert.ok(mark, "expected the corrected text to be wrapped in a <mark>");
	assert.equal(mark.textContent, "door");
	assert.equal(mark.getAttribute("data-annotation-color"), "blue");
});

test("a lengthening replacement shifts a later, unrelated highlight's rendered position", () => {
	// Confirms edits and highlights coexist correctly in one render pass:
	// the edit row is applied first (mutating the DOM), then the later
	// row's own stored offsets -- already correct for the post-edit text,
	// since the caller is responsible for having shifted them via
	// TextReplacementOffsetShift/computeTextEditPlan before persisting --
	// still resolve to the right span.
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox in the garden.</p></div>'
	);
	const editAnnotation = {
		annotationID: "edit-1",
		startOffset: 0,
		endOffset: 4, // "Once"
		quoteExact: "Once",
		color: "yellow",
		hasHighlight: false,
		originalText: "Once",
		replacementText: "A long while"
	};
	// "garden" originally starts at offset 40 (verified via
	// text.indexOf in isolation, not hand-computed). "Once" (4 chars)
	// becomes "A long while" (12 chars), a delta of +8, so the
	// already-shifted stored offset for "garden" is 40 + 8 = 48.
	const laterHighlight = {
		annotationID: "highlight-1",
		startOffset: 48,
		endOffset: 54,
		quoteExact: "garden",
		color: "green"
	};

	const report = Annotations.renderAnnotations([editAnnotation, laterHighlight]);

	assert.equal(report.orphanedIDs.length, 0);
	const mark = document.querySelector('mark[data-annotation-id="highlight-1"]');
	assert.ok(mark, "expected the later highlight to still resolve correctly");
	assert.equal(mark.textContent, "garden");
});

test("applyTextEdit (internal) returns a collapsed Range around the new text", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Hello world.</p></div>'
	);
	const root = document.querySelector(".articleBody");
	const index = Annotations._internal.buildTextIndex(root);

	const range = Annotations._internal.applyTextEdit(index.entries, 0, 5, "Howdy");

	assert.ok(range, "expected a Range to be returned");
	assert.equal(range.toString(), "Howdy");
	assert.equal(document.querySelector("p").textContent, "Howdy world.");
});

test("applyTextEdit (internal) returns null when the span can't be resolved", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Short.</p></div>'
	);
	const root = document.querySelector(".articleBody");
	const index = Annotations._internal.buildTextIndex(root);

	// Way past the end of the text.
	const range = Annotations._internal.applyTextEdit(index.entries, 500, 510, "anything");

	assert.equal(range, null);
});
