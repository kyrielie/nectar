"use strict";

const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const SOURCE_PATH = path.join(__dirname, "..", "..", "..", "Shared", "Article Rendering", "annotations.js");
const SOURCE = fs.readFileSync(SOURCE_PATH, "utf8");

// Loads the real, shipped annotations.js against a fresh jsdom document for
// one test. Returns { Annotations, document }. Each call gets its own
// isolated jsdom window/document and its own evaluation of the source, so
// tests can't leak DOM or module state into each other.
//
// NodeFilter and CSS are provided explicitly because jsdom's JSDOM.window
// exposes them on the window object but doesn't add them to Node's global
// scope automatically the way a real WKWebView's JS context would -- this
// is a harness accommodation, not something annotations.js itself needs to
// account for (it already assumes a browser-like global environment, which
// is correct for its real runtime).
function loadAnnotations(bodyHTML) {
	const dom = new JSDOM(`<!doctype html><html><body>${bodyHTML}</body></html>`);
	const window = dom.window;
	const document = window.document;

	const module = { exports: {} };
	const fn = new Function(
		"module",
		"exports",
		"window",
		"document",
		"NodeFilter",
		"CSS",
		SOURCE
	);
	fn(module, module.exports, window, document, window.NodeFilter, window.CSS);

	return { Annotations: module.exports, document, window };
}

// Mirrors annotations.js's own toBase64/fromBase64 (UTF-8-safe, not plain
// btoa/atob) so tests calling the evaluateJavaScript-shaped entry points
// (renderAnnotationsEncoded, addHighlightFromSelection) can encode
// arguments and decode results the same way WebViewController does.
function encodeArgs(value) {
	return Buffer.from(JSON.stringify(value), "utf8").toString("base64");
}

function decodeResult(base64) {
	return JSON.parse(Buffer.from(base64, "base64").toString("utf8"));
}

module.exports = { loadAnnotations, encodeArgs, decodeResult };
