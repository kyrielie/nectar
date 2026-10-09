"use strict";

const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const SOURCE_PATH = path.join(__dirname, "..", "..", "..", "Shared", "Article Rendering", "main.js");
const SOURCE = fs.readFileSync(SOURCE_PATH, "utf8");

// Evaluates the real main.js against a fresh jsdom document and returns
// { applyChapterDividers, document }. document.addEventListener is stubbed
// first so main.js's DOMContentLoaded hook does not run processPage.
function loadMain(bodyHTML) {
	const dom = new JSDOM(`<!doctype html><html><body>${bodyHTML}</body></html>`);
	const window = dom.window;
	const document = window.document;
	document.addEventListener = function () {};
	const fn = new Function(
		"window",
		"document",
		SOURCE + "\nreturn { applyChapterDividers };"
	);
	const exported = fn(window, document);
	return { applyChapterDividers: exported.applyChapterDividers, document, window };
}

module.exports = { loadMain };
