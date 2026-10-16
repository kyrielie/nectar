"use strict";

// Covers removeArticleIconAvatar's per-element opt-in (data-nnw-keep) and the pruning of
// kept avatars that fail to load. See docs/nnwtheme-format.md, "Avatar".

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
	const fn = new Function("window", "document", SOURCE + "\nreturn { removeArticleIconAvatar };");
	return Object.assign(fn(window, document), { document, window });
}

test("removeArticleIconAvatar removes an avatar without data-nnw-keep", () => {
	const { removeArticleIconAvatar, document } = load('<img id="a" src="nnwImageIcon:123">');
	removeArticleIconAvatar();
	assert.equal(document.getElementById("a"), null);
});

test("removeArticleIconAvatar keeps an avatar with data-nnw-keep", () => {
	const { removeArticleIconAvatar, document } = load('<img id="a" data-nnw-keep src="nnwImageIcon:123">');
	removeArticleIconAvatar();
	assert.notEqual(document.getElementById("a"), null);
});

test("removeArticleIconAvatar removes only the unmarked avatar when both exist", () => {
	const { removeArticleIconAvatar, document } = load(
		'<img id="a" src="nnwImageIcon:1"><img id="b" data-nnw-keep src="nnwImageIcon:2">'
	);
	removeArticleIconAvatar();
	assert.equal(document.getElementById("a"), null);
	assert.notEqual(document.getElementById("b"), null);
});

test("removeArticleIconAvatar matches the scheme case-insensitively and ignores other images", () => {
	const { removeArticleIconAvatar, document } = load(
		'<img id="a" src="NNWIMAGEICON:1"><img id="b" src="https://example.com/x.png">'
	);
	removeArticleIconAvatar();
	assert.equal(document.getElementById("a"), null);
	assert.notEqual(document.getElementById("b"), null);
});

test("a kept avatar is removed when it fires an error event", () => {
	const { removeArticleIconAvatar, document, window } = load('<img id="a" data-nnw-keep src="nnwImageIcon:123">');
	removeArticleIconAvatar();
	const img = document.getElementById("a");
	// jsdom does not load images, so the image is still "complete" with width 0 only when
	// it has no pending load; the error listener is what matters for the real reader.
	img.dispatchEvent(new window.Event("error"));
	assert.equal(document.getElementById("a"), null);
});
