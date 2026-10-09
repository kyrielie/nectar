// Coverage for the annotation text rule: text inside [data-nnw-ornament]
// (the chapter divider main.js inserts) is not annotation text, so the
// text index, range wrapping and selector capture are identical across
// themes whose dividers use different glyphs, or no divider at all.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations } = require("./setup");

function chapter(title, body, divider) {
	return `<div class="chapter preface group">${divider}<h2 class="heading">${title}</h2><p>${body}</p></div>`;
}

function fixture(divider) {
	return '<div class="articleBody" id="bodyContainer"><div id="workskin">'
		+ chapter("Chapter 1", "The fox ran home.", divider)
		+ chapter("Chapter 2", "The hen stayed out.", divider)
		+ "</div></div>";
}

const NONE = "";
const ZWSP = '<div class="d" aria-hidden="true" data-nnw-ornament="">&#8203;</div>';
const VISIBLE = '<div class="d" aria-hidden="true" data-nnw-ornament="">* * *</div>';

function indexText(html) {
	const { Annotations, document } = loadAnnotations(html);
	return Annotations._internal.buildTextIndex(document.querySelector(".articleBody")).text;
}

test("text index ignores ornament text: zero-width, visible and none are identical", () => {
	const none = indexText(fixture(NONE));
	assert.equal(indexText(fixture(ZWSP)), none);
	assert.equal(indexText(fixture(VISIBLE)), none);
	assert.ok(!none.includes("\u200b") && !none.includes("* * *"));
});

test("a highlight stored against the no-divider fixture resolves against divider fixtures without moving", () => {
	const quote = "home.Chapter 2";
	const base = indexText(fixture(NONE));
	const start = base.indexOf(quote);
	assert.ok(start >= 0);
	const annotation = {
		annotationID: "a1",
		startOffset: start,
		endOffset: start + quote.length,
		quoteExact: quote,
		color: "yellow"
	};
	for (const divider of [ZWSP, VISIBLE]) {
		const { Annotations } = loadAnnotations(fixture(divider));
		const report = Annotations.renderAnnotations([annotation]);
		assert.deepEqual(report, { moved: [], orphanedIDs: [] });
	}
});

test("a highlight spanning a heading never wraps divider text", () => {
	const quote = "home.Chapter 2";
	const base = indexText(fixture(NONE));
	const start = base.indexOf(quote);
	for (const divider of [ZWSP, VISIBLE]) {
		const { Annotations, document } = loadAnnotations(fixture(divider));
		Annotations.renderAnnotations([{
			annotationID: "a1",
			startOffset: start,
			endOffset: start + quote.length,
			quoteExact: quote
		}]);
		const marks = document.querySelectorAll('mark[data-annotation-id="a1"]');
		assert.ok(marks.length > 0);
		marks.forEach(function (mark) {
			assert.ok(!mark.closest("[data-nnw-ornament]"), "mark inside ornament");
			assert.ok(!mark.textContent.includes("\u200b"));
			assert.ok(!mark.textContent.includes("* * *"));
		});
		assert.equal(Array.from(marks).map(m => m.textContent).join(""), quote);
	}
});

test("selectorForRange returns null for a range ending in ornament text", () => {
	const { Annotations, document, window } = loadAnnotations(fixture(VISIBLE));
	const root = document.querySelector(".articleBody");
	const first = document.querySelector("p").firstChild;
	const ornamentText = document.querySelector("[data-nnw-ornament]").firstChild;
	const range = document.createRange();
	range.setStart(first, 0);
	range.setEnd(ornamentText, 2);
	let result;
	assert.doesNotThrow(function () {
		result = Annotations._internal.selectorForRange(range, root, ".articleBody");
	});
	assert.equal(result, null);
});
