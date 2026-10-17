"use strict";

// Covers setNectarState: live star/love updates to the hidden #nectarState marker.
// See docs/nnwtheme-format.md, "Nectar state hooks".

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const SOURCE = fs.readFileSync(
	path.join(__dirname, "..", "..", "..", "Shared", "Article Rendering", "main.js"),
	"utf8"
);

function load(bodyHTML) {
	const dom = new JSDOM(`<!doctype html><html><body>${bodyHTML}</body></html>`);
	const { window } = dom;
	const { document } = window;
	document.addEventListener = function () {};
	const fn = new Function("window", "document", SOURCE + "\nreturn { setNectarState };");
	return Object.assign(fn(window, document), { document, window });
}

test("setNectarState sets data attributes from booleans", () => {
	const { setNectarState, document } = load('<span id="nectarState" data-starred="false" data-loved="false" hidden></span>');
	setNectarState({ starred: true, loved: false });
	const marker = document.getElementById("nectarState");
	assert.equal(marker.getAttribute("data-starred"), "true");
	assert.equal(marker.getAttribute("data-loved"), "false");
});

test("setNectarState leaves keys it was not given, including data-restricted", () => {
	const { setNectarState, document } = load('<span id="nectarState" data-starred="false" data-restricted="true" hidden></span>');
	setNectarState({ starred: true });
	const marker = document.getElementById("nectarState");
	assert.equal(marker.getAttribute("data-restricted"), "true");
	assert.equal(marker.getAttribute("data-starred"), "true");
});

test("setNectarState ignores a page with no marker", () => {
	const { setNectarState, document } = load("<p>no marker</p>");
	assert.doesNotThrow(() => setNectarState({ starred: true }));
	assert.equal(document.getElementById("nectarState"), null);
});
