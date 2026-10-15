// Coverage for main.js localizeSplitFileLinks: Calibre/EPUB split-file links
// ("book_split_003.xhtml#endnotes") become plain same-document links only when
// the target id exists in this document.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadMain } = require("./setup");

function hrefOf(document, id) {
	return document.getElementById(id).getAttribute("href");
}

test("rewrites a bare .xhtml#id link when the id exists", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="l" href="nudes_split_003.xhtml#endnotes">notes</a><div id="endnotes"></div>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "l"), "#endnotes");
});

test("leaves the link alone when the id is missing", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="l" href="nudes_split_003.xhtml#endnotes">notes</a>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "l"), "nudes_split_003.xhtml#endnotes");
});

test("ignores .html#id links", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="l" href="book_split_003.html#endnotes">notes</a><div id="endnotes"></div>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "l"), "book_split_003.html#endnotes");
});

test("ignores absolute URLs and paths containing a slash", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="a" href="https://example.com/book.xhtml#endnotes">a</a>'
		+ '<a id="b" href="dir/book.xhtml#endnotes">b</a>'
		+ '<a id="c" href="/book.xhtml#endnotes">c</a>'
		+ '<div id="endnotes"></div>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "a"), "https://example.com/book.xhtml#endnotes");
	assert.equal(hrefOf(document, "b"), "dir/book.xhtml#endnotes");
	assert.equal(hrefOf(document, "c"), "/book.xhtml#endnotes");
});

test("handles percent-encoded ids", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="l" href="book_split_003.xhtml#end%20notes">notes</a><div id="end notes"></div>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "l"), "#end%20notes");
});

test("a malformed percent sequence is skipped without throwing", () => {
	const { localizeSplitFileLinks, document } = loadMain(
		'<a id="l" href="book_split_003.xhtml#%E0%A4%A">notes</a><div id="x"></div>'
	);
	localizeSplitFileLinks();
	assert.equal(hrefOf(document, "l"), "book_split_003.xhtml#%E0%A4%A");
});
