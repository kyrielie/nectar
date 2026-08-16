// Coverage for annotations.js's anchor-resolution algorithm: confirms the
// stored-position fast path, the quote-search fallback, prefix/suffix
// disambiguation of multiple matches, the orphan cases (no match;
// ambiguous below the similarity floor), and that DOM wrapping preserves
// inline markup for ranges spanning multiple text nodes, mirroring the
// fixture-HTML style of ArticleRendererStripFakeParagraphIndentsTests.swift
// (small, single-concern fragments, not full rendered documents).

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations } = require("./setup");

test("stored offset still matches: resolves without a quote search", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 0,
		endOffset: 4,
		quoteExact: "Once",
		color: "yellow"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	assert.ok(mark, "expected a <mark> to be drawn");
	assert.equal(mark.textContent, "Once");
	assert.equal(mark.getAttribute("data-annotation-color"), "yellow");
});

test("stale offset, unique quote: reanchors and reports the move", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999, // stale -- content shifted
		endOffset: 1010,
		quoteExact: "a fox",
		quotePrefix: "was ",
		quoteSuffix: "."
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.equal(report.orphanedIDs.length, 0);
	assert.equal(report.moved.length, 1);
	assert.equal(report.moved[0].annotationID, "a1");
	assert.equal(report.moved[0].quoteExact, "a fox");

	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	assert.ok(mark);
	assert.equal(mark.textContent, "a fox");
});

test("quote appears twice: disambiguates via prefix/suffix similarity", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>The quick fox jumped. The quick fox ran away.</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999,
		endOffset: 1010,
		quoteExact: "quick fox",
		quotePrefix: "The ",
		quoteSuffix: " jumped"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.equal(report.orphanedIDs.length, 0);
	assert.equal(report.moved.length, 1);
	// First occurrence ("...The quick fox jumped...") should win: its
	// prefix/suffix match the stored selector exactly, the second
	// occurrence's suffix (" ran") does not.
	assert.equal(report.moved[0].startOffset, 4);

	const marks = document.querySelectorAll('mark[data-annotation-id="a1"]');
	assert.equal(marks.length, 1, "only the disambiguated occurrence should be wrapped");
});

test("quote appears twice with no distinguishing context: orphans rather than guessing", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>cat cat cat cat</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999,
		endOffset: 1002,
		quoteExact: "cat",
		quotePrefix: "XYZ", // matches nothing nearby
		quoteSuffix: "XYZ"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.deepEqual(report.moved, []);
	assert.deepEqual(report.orphanedIDs, ["a1"]);
	assert.equal(document.querySelectorAll("mark").length, 0, "an orphaned annotation must not be drawn");
});

test("quote not found at all: orphans", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Nothing to see here.</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 0,
		endOffset: 5,
		quoteExact: "This text was deleted",
		quotePrefix: "",
		quoteSuffix: ""
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.deepEqual(report.orphanedIDs, ["a1"]);
	assert.equal(document.querySelectorAll("mark").length, 0);
});

test("range spanning multiple text nodes wraps each node, preserving inline markup", () => {
	// Highlight spans "fox jumped over the lazy" -- crosses the <em> boundary
	// around "jumped over".
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>The quick fox <em>jumped over</em> the lazy dog.</p></div>'
	);
	const paragraph = document.querySelector("p");
	const fullText = paragraph.textContent; // "The quick fox jumped over the lazy dog."
	const start = fullText.indexOf("fox jumped");
	const end = fullText.indexOf("lazy") + "lazy".length;

	const annotation = {
		annotationID: "a1",
		startOffset: start,
		endOffset: end,
		quoteExact: fullText.slice(start, end),
		color: "green"
	};

	Annotations.renderAnnotations([annotation]);

	// The <em> element itself must still exist (inline markup preserved --
	// not collapsed into a single textContent rewrite).
	const em = document.querySelector("em");
	assert.ok(em, "the <em> element must survive wrapping");
	assert.equal(em.textContent, "jumped over");

	// Every wrapped text node shares the same data-annotation-id, including
	// the one nested inside <em>.
	const marks = document.querySelectorAll('mark[data-annotation-id="a1"]');
	assert.ok(marks.length >= 2, "expected multiple <mark> wraps, one per contained text node");
	const markInsideEm = em.querySelector("mark");
	assert.ok(markInsideEm, "the portion of the range inside <em> must also be wrapped");

	// Reconstructing the marked text (in document order) should equal the
	// original quote.
	const combined = Array.from(marks)
		.map((m) => m.textContent)
		.join("");
	assert.equal(combined, annotation.quoteExact);
});

test("renderAnnotations unwraps and redraws on repeated calls (no stale duplicate marks)", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	const annotation = { annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once" };

	Annotations.renderAnnotations([annotation]);
	Annotations.renderAnnotations([annotation]);

	const marks = document.querySelectorAll('mark[data-annotation-id="a1"]');
	assert.equal(marks.length, 1, "re-rendering the same annotation must not duplicate its mark");
});

test("addAnnotationHighlight draws immediately from live-computed offsets", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Hello there, world.</p></div>'
	);
	const fullText = document.querySelector("p").textContent;
	const start = fullText.indexOf("there");
	const end = start + "there".length;

	Annotations.addAnnotationHighlight({
		annotationID: "new-1",
		startOffset: start,
		endOffset: end,
		quoteExact: "there",
		color: "pink"
	});

	const mark = document.querySelector('mark[data-annotation-id="new-1"]');
	assert.ok(mark);
	assert.equal(mark.textContent, "there");
});

test("removeAnnotationHighlight unwraps the mark and merges surrounding text", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	Annotations.renderAnnotations([{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once" }]);
	assert.ok(document.querySelector('mark[data-annotation-id="a1"]'));

	Annotations.removeAnnotationHighlight("a1");

	assert.equal(document.querySelectorAll("mark").length, 0);
	assert.equal(document.querySelector(".articleBody p").textContent, "Once upon a time there was a fox.");
});

test("updateAnnotationColor updates the data attribute without moving the mark", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox.</p></div>'
	);
	Annotations.renderAnnotations([{ annotationID: "a1", startOffset: 0, endOffset: 4, quoteExact: "Once", color: "yellow" }]);

	Annotations.updateAnnotationColor("a1", "blue");

	const mark = document.querySelector('mark[data-annotation-id="a1"]');
	assert.equal(mark.getAttribute("data-annotation-color"), "blue");
	assert.equal(mark.textContent, "Once");
});

test("multiple annotations in one document each resolve independently", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>The fox ran. The fox jumped.</p></div>'
	);
	const annotations = [
		{ annotationID: "a1", startOffset: 4, endOffset: 7, quoteExact: "fox", quotePrefix: "The ", quoteSuffix: " ran" },
		{ annotationID: "a2", startOffset: 999, endOffset: 1002, quoteExact: "fox", quotePrefix: "The ", quoteSuffix: " jumped" }
	];

	const report = Annotations.renderAnnotations(annotations);

	assert.equal(report.orphanedIDs.length, 0);
	// a1's stored offset is already correct (unchanged, not in `moved`);
	// a2 is stale and must be reanchored to the second "fox".
	assert.equal(report.moved.length, 1);
	assert.equal(report.moved[0].annotationID, "a2");

	assert.ok(document.querySelector('mark[data-annotation-id="a1"]'));
	assert.ok(document.querySelector('mark[data-annotation-id="a2"]'));
});
