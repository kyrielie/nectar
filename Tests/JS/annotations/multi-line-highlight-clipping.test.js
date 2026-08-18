"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("fs");
const path = require("path");

// core.css has no build step and no CSS-in-JS abstraction to unit test
// directly (see Tests/JS/package.json's own scope note: this directory
// covers Shared/Article Rendering/*.js logic that has no other way to be
// exercised outside a real WKWebView -- CSS itself has no such gap, jsdom
// has no layout engine so it can't measure real clipping either way). This
// is a narrow regression test against the stylesheet's *text*, not its
// rendered effect: it exists only to catch a future edit to
// mark.nnw-highlight silently dropping the properties that fix multi-line
// highlight clipping (see docs/annotations.md, "Multi-line highlight
// clipping"), not to validate CSS correctness generally.
const CSS_PATH = path.join(__dirname, "..", "..", "..", "Shared", "Article Rendering", "core.css");
const CSS = fs.readFileSync(CSS_PATH, "utf8");

function ruleBodyFor(selector) {
	const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	const match = CSS.match(new RegExp(escaped.replace(/\\ /g, "\\s+") + "\\s*\\{([^}]*)\\}"));
	assert.ok(match, `expected to find a ${selector} rule in core.css`);
	return match[1];
}

test("mark.nnw-highlight sets -webkit-box-decoration-break: clone", () => {
	const body = ruleBodyFor("mark.nnw-highlight");
	// Without box-decoration-break: clone, a <mark> that wraps across
	// multiple lines paints one background box across its whole bounding
	// rect rather than one box per visual line, so on a tight line-height
	// that box clips into the ascenders/descenders of the line above or
	// below. WKWebView only supports the -webkit- prefixed form.
	assert.match(body, /-webkit-box-decoration-break:\s*clone\s*;/);
});

test("mark.nnw-highlight sets vertical padding, not just horizontal", () => {
	const body = ruleBodyFor("mark.nnw-highlight");
	const paddingMatch = body.match(/padding:\s*([^;]+);/);
	assert.ok(paddingMatch, "expected a padding declaration on mark.nnw-highlight");
	const parts = paddingMatch[1].trim().split(/\s+/);
	// A single value (e.g. "0.05em") or a "0 0.05em" shorthand both mean
	// zero vertical padding, which is what originally let a wrapped
	// highlight's per-line box sit flush against the line above/below
	// with no breathing room even after adding box-decoration-break.
	assert.ok(parts.length >= 2, `expected explicit vertical and horizontal padding, got "${paddingMatch[1]}"`);
	assert.notEqual(parts[0], "0", `expected non-zero vertical padding, got "${paddingMatch[1]}"`);
});
