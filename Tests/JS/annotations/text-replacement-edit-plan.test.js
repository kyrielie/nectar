// Coverage for annotations.js's non-mutating edit-planning entry points:
// computeTextEditPlan (the pre-flight AnnotationEditorView's Save button
// runs before persisting anything) and getArticleText (the read-only
// text accessor the Swift-side rule-table engine uses). See
// docs/annotations.md, "Applying edits". Every expected value below was
// captured by actually running the code against a live jsdom document,
// not hand-computed.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations, decodeResult } = require("./setup");

test("getArticleText returns the root's canonicalized inner text", () => {
	const { Annotations } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox in the garden.</p></div>'
	);
	assert.equal(
		Annotations.getArticleText(".articleBody"),
		"Once upon a time there was a fox in the garden."
	);
});

test("getArticleText returns an empty string when rootSelector matches nothing", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Hi.</p></div>');
	assert.equal(Annotations.getArticleText(".nope"), "");
});

test("computeTextEditPlan returns delta 0 and no shifted rows for a same-length edit", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Once upon a time.</p></div>');
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 0,
		endOffset: 4,
		replacementLength: 4,
		otherAnnotations: [{ annotationID: "a", startOffset: 5, endOffset: 9 }]
	});
	assert.deepEqual(plan, { status: "ok", delta: 0, shifted: [] });
});

test("computeTextEditPlan reports overlap and stops before computing any shift", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Once upon a time there was a fox.</p></div>');
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 5,
		endOffset: 9,
		replacementLength: 4,
		otherAnnotations: [{ annotationID: "blocker", startOffset: 0, endOffset: 8 }]
	});
	assert.deepEqual(plan, { status: "overlap", conflictingAnnotationID: "blocker" });
});

test("computeTextEditPlan shifts a later row's offsets and re-slices its quote/prefix/suffix for a lengthening edit", () => {
	const { Annotations } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox in the garden.</p></div>'
	);
	// "Once" (0-4, 4 chars) becomes a 12-char replacement: delta +8.
	// "garden" sits at [40, 46) in the original text (verified via
	// String.indexOf against the exact source string above, not
	// estimated), so its shifted offsets are [48, 54).
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 0,
		endOffset: 4,
		replacementLength: 12,
		otherAnnotations: [{ annotationID: "highlight-1", startOffset: 40, endOffset: 46 }]
	});

	assert.equal(plan.status, "ok");
	assert.equal(plan.delta, 8);
	assert.equal(plan.shifted.length, 1);
	assert.equal(plan.shifted[0].annotationID, "highlight-1");
	assert.equal(plan.shifted[0].startOffset, 48);
	assert.equal(plan.shifted[0].endOffset, 54);
	// quoteExact is re-sliced against the *simulated* post-edit text at
	// the new offsets -- "garden" itself is untouched by an edit
	// upstream of it, so it comes through unchanged.
	assert.equal(plan.shifted[0].quoteExact, "garden");
	// quoteSuffix is genuinely just the trailing "." -- nothing else
	// follows "garden" in this fixture's text.
	assert.equal(plan.shifted[0].quoteSuffix, ".");
	assert.equal(plan.shifted[0].chapterTitle, null);
});

test("computeTextEditPlan shifts a later row backward for a shortening edit", () => {
	const { Annotations } = loadAnnotations(
		'<div class="articleBody"><p>Once upon a time there was a fox in the garden.</p></div>'
	);
	// [0,12) ("Once upon a ", 12 chars) becomes a 4-char replacement:
	// delta -8. "garden" at [40,46) shifts to [32,38).
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 0,
		endOffset: 12,
		replacementLength: 4,
		otherAnnotations: [{ annotationID: "highlight-1", startOffset: 40, endOffset: 46 }]
	});

	assert.equal(plan.delta, -8);
	assert.equal(plan.shifted[0].startOffset, 32);
	assert.equal(plan.shifted[0].endOffset, 38);
	assert.equal(plan.shifted[0].quoteExact, "garden");
});

test("computeTextEditPlan includes a row that starts exactly at the edit's endOffset", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Once upon a time.</p></div>');
	// A row touching the boundary (its own startOffset equals the
	// edit's endOffset) is not an overlap -- see firstOverlap's own
	// touching-boundary rule on the Swift side -- and is shifted like
	// any other downstream row.
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 0,
		endOffset: 4,
		replacementLength: 6,
		otherAnnotations: [{ annotationID: "touch", startOffset: 4, endOffset: 8 }]
	});

	assert.equal(plan.status, "ok");
	assert.equal(plan.shifted.length, 1);
	assert.equal(plan.shifted[0].startOffset, 6);
	assert.equal(plan.shifted[0].endOffset, 10);
});

test("computeTextEditPlan does not shift a row that lies entirely before the edit", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Once upon a time.</p></div>');
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 10,
		endOffset: 14,
		replacementLength: 6,
		otherAnnotations: [{ annotationID: "before", startOffset: 0, endOffset: 4 }]
	});

	assert.equal(plan.status, "ok");
	assert.equal(plan.delta, 2);
	assert.deepEqual(plan.shifted, []);
});

test("computeTextEditPlan defaults rootSelector to .articleBody when omitted", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Hi there.</p></div>');
	const plan = Annotations._internal.computeTextEditPlan({
		startOffset: 0,
		endOffset: 2,
		replacementLength: 2,
		otherAnnotations: []
	});
	assert.deepEqual(plan, { status: "ok", delta: 0, shifted: [] });
});

test("computeTextEditPlanEncoded returns a no-op plan for malformed base64/JSON input", () => {
	const { Annotations } = loadAnnotations('<div class="articleBody"><p>Hi.</p></div>');
	const result = decodeResult(Annotations.computeTextEditPlanEncoded("not valid base64 json!!"));
	assert.deepEqual(result, { status: "ok", delta: 0, shifted: [] });
});
