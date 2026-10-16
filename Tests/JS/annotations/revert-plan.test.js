// Coverage for annotations.js's computeRevertPlan, the inverse of
// computeTextEditPlan used when a text-edit row is deleted (see
// docs/annotations.md, "Reverting an edit"). The round-trip tests apply an
// edit through computeTextEditPlan, revert it through computeRevertPlan,
// and assert every other row ends up exactly where it started.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadAnnotations, decodeResult } = require("./setup");

const BASE = "Once upon a time there was a fox in the garden, and the fox was happy.";

function html(text) {
	return '<div class="articleBody"><p>' + text + "</p></div>";
}

function rowFor(text, id, quote, occurrence) {
	let from = 0;
	let start = -1;
	for (let i = 0; i <= (occurrence || 0); i++) {
		start = text.indexOf(quote, from);
		from = start + 1;
	}
	assert.notEqual(start, -1, "quote not found: " + quote);
	return { annotationID: id, startOffset: start, endOffset: start + quote.length };
}

// Applies an edit of [start, end) -> replacement to `text`, persisting shifted rows
// the way saveTextEdit does. Returns the new text, the edit row and the shifted rows.
function applyEdit(text, edit, rows) {
	const { Annotations } = loadAnnotations(html(text));
	const plan = Annotations._internal.computeTextEditPlan({
		annotationToEditID: edit.annotationID,
		startOffset: edit.startOffset,
		endOffset: edit.endOffset,
		replacementLength: edit.replacementText.length,
		otherAnnotations: rows
	});
	assert.equal(plan.status, "ok");
	const byID = new Map(plan.shifted.map((s) => [s.annotationID, s]));
	const newRows = rows.map((r) => {
		const s = byID.get(r.annotationID);
		return s ? { annotationID: r.annotationID, startOffset: s.startOffset, endOffset: s.endOffset } : r;
	});
	const newText = text.slice(0, edit.startOffset) + edit.replacementText + text.slice(edit.endOffset);
	return { text: newText, rows: newRows };
}

function revertEdit(text, edit, rows) {
	const { Annotations } = loadAnnotations(html(text));
	const plan = Annotations._internal.computeRevertPlan({
		annotationID: edit.annotationID,
		startOffset: edit.startOffset,
		originalText: edit.originalText,
		replacementText: edit.replacementText,
		otherAnnotations: rows
	});
	assert.equal(plan.status, "ok");
	const byID = new Map(plan.shifted.map((s) => [s.annotationID, s]));
	const newRows = rows.map((r) => {
		const s = byID.get(r.annotationID);
		return s ? { annotationID: r.annotationID, startOffset: s.startOffset, endOffset: s.endOffset } : r;
	});
	const newText = text.slice(0, edit.startOffset) + edit.originalText + text.slice(edit.startOffset + edit.replacementText.length);
	return { text: newText, rows: newRows, plan };
}

function makeEdit(text, id, quote, replacementText) {
	const row = rowFor(text, id, quote);
	return Object.assign(row, { originalText: quote, replacementText });
}

test("computeRevertPlan round trips a lengthening edit", () => {
	const later = rowFor(BASE, "later", "garden");
	const earlier = rowFor(BASE, "earlier", "time");
	const edit = makeEdit(BASE, "edit", "Once", "A very long time ago");
	const applied = applyEdit(BASE, edit, [later, earlier]);
	assert.notDeepEqual(applied.rows[0], later);
	const reverted = revertEdit(applied.text, edit, applied.rows);
	assert.equal(reverted.text, BASE);
	assert.deepEqual(reverted.rows, [later, earlier]);
});

test("computeRevertPlan round trips a shortening edit", () => {
	const later = rowFor(BASE, "later", "garden");
	const edit = makeEdit(BASE, "edit", "Once upon a ", "X");
	const applied = applyEdit(BASE, edit, [later]);
	assert.equal(applied.rows[0].startOffset, later.startOffset - 11);
	const reverted = revertEdit(applied.text, edit, applied.rows);
	assert.equal(reverted.text, BASE);
	assert.deepEqual(reverted.rows, [later]);
});

test("computeRevertPlan re-slices quote, prefix and suffix against the reverted text", () => {
	const later = rowFor(BASE, "later", "garden");
	const edit = makeEdit(BASE, "edit", "Once", "Long long ago");
	const applied = applyEdit(BASE, edit, [later]);
	const { Annotations } = loadAnnotations(html(applied.text));
	const plan = Annotations._internal.computeRevertPlan({
		annotationID: "edit",
		startOffset: edit.startOffset,
		originalText: edit.originalText,
		replacementText: edit.replacementText,
		otherAnnotations: applied.rows
	});
	assert.equal(plan.delta, -9);
	assert.equal(plan.shifted[0].quoteExact, "garden");
	assert.equal(plan.shifted[0].quoteSuffix, BASE.slice(later.endOffset, later.endOffset + Annotations._internal.CONTEXT_CHARS));
	assert.equal(plan.shifted[0].quotePrefix, BASE.slice(Math.max(0, later.startOffset - Annotations._internal.CONTEXT_CHARS), later.startOffset));
});

test("computeRevertPlan shifts a row that starts exactly at the replacement's end", () => {
	const touching = rowFor(BASE, "touch", " upon");
	const edit = makeEdit(BASE, "edit", "Once", "Twice upon");
	const applied = applyEdit(BASE, edit, [touching]);
	const reverted = revertEdit(applied.text, edit, applied.rows);
	assert.deepEqual(reverted.rows, [touching]);
});

test("computeRevertPlan does not move rows before the edit", () => {
	const before = rowFor(BASE, "before", "Once");
	const edit = makeEdit(BASE, "edit", "garden", "yard");
	const applied = applyEdit(BASE, edit, [before]);
	const reverted = revertEdit(applied.text, edit, applied.rows);
	assert.equal(reverted.plan.shifted.length, 0);
	assert.deepEqual(reverted.rows, [before]);
});

test("computeRevertPlan returns an empty plan for a same-length edit", () => {
	const later = rowFor(BASE, "later", "garden");
	const edit = makeEdit(BASE, "edit", "Once", "Twas");
	const applied = applyEdit(BASE, edit, [later]);
	const reverted = revertEdit(applied.text, edit, applied.rows);
	assert.deepEqual(reverted.plan, { status: "ok", delta: 0, shifted: [] });
});

test("computeRevertPlan reports a mismatch and shifts nothing when the live text differs", () => {
	const { Annotations } = loadAnnotations(html(BASE));
	const plan = Annotations._internal.computeRevertPlan({
		annotationID: "edit",
		startOffset: 0,
		originalText: "Once",
		replacementText: "NOPE",
		otherAnnotations: [{ annotationID: "x", startOffset: 40, endOffset: 46 }]
	});
	assert.deepEqual(plan, { status: "mismatch", delta: 0, shifted: [] });
});

for (const order of ["latest first", "earliest first"]) {
	test("computeRevertPlan round trips two stacked edits reverted " + order, () => {
		const tail = rowFor(BASE, "tail", "happy");
		const mid = rowFor(BASE, "mid", "fox", 1);
		const editA = makeEdit(BASE, "A", "Once", "A very long time ago");
		const afterA = applyEdit(BASE, editA, [tail, mid]);
		// Created against the live (post-A) text, like a person would.
		const editB = makeEdit(afterA.text, "B", "garden", "yard");
		const afterB = applyEdit(afterA.text, editB, afterA.rows);

		let state = { text: afterB.text, rows: afterB.rows };
		const asRow = (edit) => ({ annotationID: edit.annotationID, startOffset: edit.startOffset, endOffset: edit.endOffset });
		// Reverts `edit` against the live text; `carried` is the other edit's row, which
		// is shifted like any other row and returned with its new offsets.
		const revert = (edit, carried) => {
			const result = revertEdit(state.text, edit, state.rows.concat([asRow(carried)]));
			state = { text: result.text, rows: result.rows.slice(0, state.rows.length) };
			const moved = result.rows[result.rows.length - 1];
			return Object.assign({}, carried, { startOffset: moved.startOffset, endOffset: moved.endOffset });
		};
		if (order === "latest first") {
			// B follows A, so reverting B never moves A's row.
			revert(editB, editA);
			revert(editA, editB);
		} else {
			const movedB = revert(editA, editB);
			revert(movedB, editA);
		}
		assert.equal(state.text, BASE);
		assert.deepEqual(state.rows, [tail, mid]);
	});
}

test("computeRevertPlanEncoded round trips through the base64 bridge", () => {
	const later = rowFor(BASE, "later", "garden");
	const edit = makeEdit(BASE, "edit", "Once", "Long long ago");
	const applied = applyEdit(BASE, edit, [later]);
	const { Annotations, window } = loadAnnotations(html(applied.text));
	const args = {
		annotationID: "edit",
		startOffset: edit.startOffset,
		originalText: edit.originalText,
		replacementText: edit.replacementText,
		otherAnnotations: applied.rows
	};
	const encoded = Buffer.from(JSON.stringify(args)).toString("base64");
	const result = decodeResult(Annotations.computeRevertPlanEncoded(encoded));
	assert.equal(result.status, "ok");
	assert.equal(result.shifted[0].startOffset, later.startOffset);
	assert.ok(window);
});
