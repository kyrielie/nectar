// Coverage for main.js applyChapterDividers: every inserted divider is
// marked as an ornament (excluded from annotation text) and hidden from
// assistive technology.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadMain } = require("./setup");

const BODY = '<div id="bodyContainer" class="articleBody" data-chapter-divider'
	+ ' data-chapter-divider-char="\u200b" data-chapter-divider-class="div">'
	+ '<div class="chapter preface group"><h2 class="heading">One</h2><p>a</p></div>'
	+ '<div class="chapter preface group"><h2 class="heading">Two</h2><p>b</p></div>'
	+ "</div>";

test("every chapter divider carries data-nnw-ornament and aria-hidden", () => {
	const { applyChapterDividers, document } = loadMain(BODY);
	applyChapterDividers();
	const dividers = document.querySelectorAll("div.div");
	assert.equal(dividers.length, 2);
	dividers.forEach(function (divider) {
		assert.ok(divider.hasAttribute("data-nnw-ornament"));
		assert.equal(divider.getAttribute("aria-hidden"), "true");
		assert.equal(divider.textContent, "\u200b");
	});
});

test("no dividers are inserted without the container opt-in", () => {
	const { applyChapterDividers, document } = loadMain(BODY.replace(" data-chapter-divider ", " "));
	applyChapterDividers();
	assert.equal(document.querySelectorAll("div.div").length, 0);
});
