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

// ---- chapterTitle derivation (buildHeadingIndex / nearestChapterTitle) ----

test("nearestChapterTitle returns null before any heading (front matter, or a book with no headings at all)", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody"><p>No headings in this fixture.</p></div>'
	);
	const root = document.querySelector(".articleBody");
	const index = Annotations._internal.buildTextIndex(root);
	const headingIndex = Annotations._internal.buildHeadingIndex(root, index.entries);

	assert.deepEqual(headingIndex, []);
	assert.equal(Annotations._internal.nearestChapterTitle(headingIndex, 0), null);
});

test("nearestChapterTitle picks the nearest preceding h1/h2.heading/h2.toc-heading, matching main_ios.js's tocNodes selector", () => {
	const { Annotations, document } = loadAnnotations(
		'<div class="articleBody">'
		+ '<h1>Ambrosia Anthology</h1>'
		+ '<p>Front matter before any chapter heading.</p>'
		+ '<h2 class="heading">Chapter 1: Arrival</h2>'
		+ '<p>Text in chapter one.</p>'
		+ '<h2 class="toc-heading">Chapter 2: Departure</h2>'
		+ '<p>Text in chapter two.</p>'
		+ '</div>'
	);
	const root = document.querySelector(".articleBody");
	const index = Annotations._internal.buildTextIndex(root);
	const headingIndex = Annotations._internal.buildHeadingIndex(root, index.entries);

	assert.equal(headingIndex.length, 3, "all three headings (h1, h2.heading, h2.toc-heading) should be indexed");
	assert.deepEqual(
		headingIndex.map((h) => h.title),
		["Ambrosia Anthology", "Chapter 1: Arrival", "Chapter 2: Departure"]
	);

	const fullText = index.text;
	const beforeAnyHeading = 0; // offset 0 is the h1's own text -- see next test for the "strictly before" case
	const inFrontMatter = fullText.indexOf("Front matter");
	const inChapterOne = fullText.indexOf("chapter one");
	const inChapterTwo = fullText.indexOf("chapter two");

	assert.equal(Annotations._internal.nearestChapterTitle(headingIndex, beforeAnyHeading), "Ambrosia Anthology");
	assert.equal(Annotations._internal.nearestChapterTitle(headingIndex, inFrontMatter), "Ambrosia Anthology");
	assert.equal(Annotations._internal.nearestChapterTitle(headingIndex, inChapterOne), "Chapter 1: Arrival");
	assert.equal(Annotations._internal.nearestChapterTitle(headingIndex, inChapterTwo), "Chapter 2: Departure");
});

test("buildHeadingIndex is scoped to root, not document -- a heading outside .articleBody (e.g. template chrome) is not indexed", () => {
	// Mirrors template.html's chrome-level `.articleTitle h1`, which lives
	// outside .articleBody and must never be treated as a "chapter".
	const { Annotations, document } = loadAnnotations(
		'<div class="articleTitle"><h1>Chrome-level book title link</h1></div>'
		+ '<div class="articleBody"><h2 class="heading">Chapter 1</h2><p>Body text.</p></div>'
	);
	const root = document.querySelector(".articleBody");
	const index = Annotations._internal.buildTextIndex(root);
	const headingIndex = Annotations._internal.buildHeadingIndex(root, index.entries);

	assert.equal(headingIndex.length, 1, "only the in-root heading should be indexed");
	assert.equal(headingIndex[0].title, "Chapter 1");
});

test("renderAnnotations includes chapterTitle in a reanchored annotation's report entry", () => {
	const { Annotations } = loadAnnotations(
		'<div class="articleBody">'
		+ '<h2 class="heading">Chapter 1: Arrival</h2>'
		+ '<p>The fox waited by the door.</p>'
		+ '<h2 class="heading">Chapter 2: Departure</h2>'
		+ '<p>The fox left at dawn.</p>'
		+ '</div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999, // stale, forces the reanchor branch
		endOffset: 1010,
		quoteExact: "left at dawn",
		quotePrefix: "fox ",
		quoteSuffix: "."
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.equal(report.moved.length, 1);
	assert.equal(report.moved[0].chapterTitle, "Chapter 2: Departure");
});

test("renderAnnotations reports chapterTitle: null for a reanchored annotation with no preceding heading", () => {
	const { Annotations } = loadAnnotations(
		'<div class="articleBody"><p>No headings, just a plain paragraph about a fox.</p></div>'
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999,
		endOffset: 1010,
		quoteExact: "a fox",
		quotePrefix: "about ",
		quoteSuffix: "."
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.equal(report.moved.length, 1);
	assert.equal(report.moved[0].chapterTitle, null);
});

// ---- CONTEXT_CHARS widening / self-healing ----

test("reanchor always recaptures prefix/suffix at the current CONTEXT_CHARS width, not the annotation's stored (possibly narrower) length", () => {
	// A long paragraph so there's room for a window wider than the old
	// hardcoded 32 chars on both sides of the quote.
	const long = "word ".repeat(80).trim(); // 80 words, ~400 chars
	const { Annotations } = loadAnnotations(
		`<div class="articleBody"><p>${long} TARGET ${long}</p></div>`
	);
	const annotation = {
		annotationID: "a1",
		startOffset: 999, // stale, forces the reanchor branch
		endOffset: 1010,
		quoteExact: "TARGET",
		// Simulate an annotation captured before CONTEXT_CHARS was widened:
		// a narrow, 4-char stored prefix/suffix. The old behavior derived
		// the recapture window from this stored length (`.length || 32`),
		// which meant it could never widen past whatever was already
		// stored. The fix recomputes at the current CONTEXT_CHARS
		// regardless of what's stored here.
		quotePrefix: "rd ",
		quoteSuffix: " wo"
	};

	const report = Annotations.renderAnnotations([annotation]);

	assert.equal(report.moved.length, 1);
	const { quotePrefix, quoteSuffix } = report.moved[0];
	assert.equal(quotePrefix.length, Annotations._internal.CONTEXT_CHARS);
	assert.equal(quoteSuffix.length, Annotations._internal.CONTEXT_CHARS);
});
