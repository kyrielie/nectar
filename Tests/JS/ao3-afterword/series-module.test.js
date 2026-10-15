// Coverage for main.js removeAO3SeriesModule: AO3's own series module is removed
// only when Nectar's #ao3SeriesFooter exists, and an emptied .afterword goes with it.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadMain } = require("./setup");

const SERIES = '<div id="series" class="series module"><h3 class="heading">Series this work belongs to:</h3>'
	+ '<ul><li><span class="series"><a class="previous" href="/works/1">Previous Work</a>'
	+ '<span class="divider"> </span><span class="position">Part 2 of <a href="/series/9">S</a></span></span></li></ul></div>';
const ENDNOTES = '<div id="work_endnotes" class="end notes module"><h3 class="heading">Notes:</h3></div>';
const FOOTER = "<div id='ao3SeriesFooter'>footer</div>";

function page(afterwordInner, footer) {
	return '<div id="workskin"><div class="afterword preface group">' + afterwordInner + "</div></div>" + (footer || "");
}

test("removes the module when the footer is present", () => {
	const { removeAO3SeriesModule, document } = loadMain(page(ENDNOTES + SERIES, FOOTER));
	removeAO3SeriesModule();
	assert.equal(document.getElementById("series"), null);
	assert.ok(document.getElementById("work_endnotes"));
	assert.ok(document.querySelector(".afterword"));
});

test("keeps the module when the footer is absent", () => {
	const { removeAO3SeriesModule, document } = loadMain(page(ENDNOTES + SERIES));
	removeAO3SeriesModule();
	assert.ok(document.getElementById("series"));
});

test("removes an afterword left empty", () => {
	const { removeAO3SeriesModule, document } = loadMain(page(SERIES, FOOTER));
	removeAO3SeriesModule();
	assert.equal(document.getElementById("series"), null);
	assert.equal(document.querySelector(".afterword"), null);
});

test("keeps an afterword that still has end notes", () => {
	const { removeAO3SeriesModule, document } = loadMain(page(SERIES + ENDNOTES, FOOTER));
	removeAO3SeriesModule();
	assert.ok(document.querySelector(".afterword"));
	assert.ok(document.getElementById("work_endnotes"));
});

test("keeps an afterword that still has works inspired by this one", () => {
	const children = '<div id="children" class="children module"><h3 class="heading">Works inspired by this one:</h3><ul></ul></div>';
	const { removeAO3SeriesModule, document } = loadMain(page(SERIES + children, FOOTER));
	removeAO3SeriesModule();
	assert.ok(document.getElementById("children"));
	assert.ok(document.querySelector(".afterword"));
});

test("only touches a module inside #workskin", () => {
	const { removeAO3SeriesModule, document } = loadMain(SERIES + FOOTER);
	removeAO3SeriesModule();
	assert.ok(document.getElementById("series"));
});
