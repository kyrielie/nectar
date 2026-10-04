"use strict";

// Tests main_ios.js's tocNodes() (the table-of-contents heading selector)
// against AO3-shaped fixtures. Loads the real, shipped iOS/Resources/main_ios.js
// into a fresh jsdom window per test, same approach as annotations/setup.js.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const SOURCE = fs.readFileSync(path.join(__dirname, "..", "..", "..", "iOS", "Resources", "main_ios.js"), "utf8");

function tocEntries(bodyHTML) {
	const dom = new JSDOM(`<!doctype html><html><body>${bodyHTML}</body></html>`, { runScripts: "outside-only" });
	dom.window.eval(SOURCE + "\n;window.__tocNodes = tocNodes;");
	return {
		dom,
		// Array.from copies into this realm's Array: tocNodes() returns a
		// jsdom-realm array, which strict deepEqual rejects on prototype.
		entries: Array.from(dom.window.__tocNodes(), (h) => ({ tag: h.tagName.toLowerCase(), text: h.textContent.trim() })),
	};
}

// Mirrors what AO3ChapterHTMLExtractor leaves behind for a multi-chapter work:
// the work title's class stripped to "title", each chapter's h3.title rewritten
// to h2.heading inside div.chapter.preface.group, all under #workskin, with
// template.html's own h1 outside it.
function ao3Chapter(id, title, bodyHTML, prefaceExtra = "") {
	return `<div class="chapter" id="chapter-${id}">`
		+ `<div class="chapter preface group"><h2 class="heading"><a href="#">Chapter ${id}</a>: ${title}</h2>${prefaceExtra}</div>`
		+ `<div class="userstuff module" role="article">${bodyHTML}</div>`
		+ `</div>`;
}

function ao3Page(chaptersHTML) {
	return '<div class="articleTitle"><h1>The Long Journey Home</h1></div>'
		+ '<div class="articleBody"><div id="workskin">'
		+ '<div class="preface group"><h2 class="title">The Long Journey Home</h2></div>'
		+ `<div id="chapters">${chaptersHTML}</div>`
		+ '</div></div>';
}

test("author-written h1/h2.heading inside #workskin are not TOC entries (reported bug: in-story headlines flooded the TOC)", () => {
	const { entries } = tocEntries(ao3Page(
		ao3Chapter(1, "Detection", "<h1>BREAKING: Probe Found</h1><p>text</p>")
		+ ao3Chapter(2, "Acquisition", '<h2 class="heading">Author section</h2><h1 align="justify">Another headline</h1><p>text</p>')
	));
	assert.deepEqual(entries.map((e) => e.text), [
		"The Long Journey Home",
		"Chapter 1: Detection",
		"Chapter 2: Acquisition",
	]);
});

test("author h1s no longer make a single work look like an anthology (bookEntries.count must stay 1)", () => {
	const { entries } = tocEntries(ao3Page(
		ao3Chapter(1, "A", "<h1>One</h1><h1>Two</h1><h1>Three</h1>")
	));
	assert.equal(entries.filter((e) => e.tag === "h1").length, 1);
});

test("author headings stay in the DOM, unmodified, so the work skin's own rules keep applying", () => {
	const { dom } = tocEntries(ao3Page(ao3Chapter(1, "A", '<h1 class="tw" align="justify">Headline</h1>')));
	const h1 = dom.window.document.querySelector("#workskin h1.tw");
	assert.ok(h1, "author h1 must not be removed or retagged");
	assert.equal(h1.getAttribute("align"), "justify");
});

test("a heading inside a chapter's own notes/summary blockquote is author content, not a chapter", () => {
	const notes = '<div class="notes module"><blockquote class="userstuff"><h2 class="heading">Notes heading</h2></blockquote></div>';
	const { entries } = tocEntries(ao3Page(ao3Chapter(1, "A", "<p>x</p>", notes)));
	assert.deepEqual(entries.map((e) => e.text), ["The Long Journey Home", "Chapter 1: A"]);
});

test("single-chapter AO3 work: only the template's h1 remains, author headings excluded", () => {
	const { entries } = tocEntries(
		'<div class="articleTitle"><h1>One Shot</h1></div>'
		+ '<div class="articleBody"><div id="workskin"><div id="chapters" role="article"><h1>Headline</h1><p>x</p></div></div></div>'
	);
	assert.deepEqual(entries.map((e) => e.text), ["One Shot"]);
});

test("non-AO3 (Calibre/Ambrosia) content, which has no #workskin, is unaffected", () => {
	const { entries } = tocEntries(
		'<div class="articleBody">'
		+ "<h1>Book One</h1><h2 class=\"heading\">Chapter 1</h2><h2 class=\"toc-heading\">Afterword</h2>"
		+ "<h1>Book Two</h1><h2 class=\"heading\">Chapter 1</h2>"
		+ "</div>"
	);
	assert.deepEqual(entries.map((e) => `${e.tag}:${e.text}`), [
		"h1:Book One", "h2:Chapter 1", "h2:Afterword", "h1:Book Two", "h2:Chapter 1",
	]);
});
