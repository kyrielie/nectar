//
//  AnnotationEditorView.swift
//  NetNewsWire-iOS
//
//  The note-editor sheet for a single highlight. Two entry points converge
//  here (both via WebViewController.openNoteEditor(for:)): tapping the
//  note icon in HighlightColorPopover right after creating a fresh
//  highlight (empty note field, pre-focused), and tapping an existing
//  <mark> in the article (populated with its stored note/color). Saving
//  calls Account.saveAnnotation; Delete calls Account.deleteAnnotation and
//  also has to tell the webview to unwrap the corresponding <mark>
//  (annotations.js's removeAnnotationHighlight) -- WebViewController owns
//  that JS call, not this view, since this view has no reference to the
//  webview at all. This view only edits the value and reports back what
//  the person chose via the onSave/onDelete closures; it never talks to
//  Account or the webview directly, so it stays testable/previewable on
//  its own.
//
//  This is also the only surface for manual one-off text edits (see
//  docs/annotations.md, "Manual edit UI") -- there is no selection-time
//  "Correct this" entry point. Below the color swatches and above the
//  destructive delete action, an "Edit text" field (pre-filled with the
//  exact quote) and a "Keep highlight on the corrected text" checkbox let
//  a person correct a highlighted span in place. Unchanged from the
//  original quote -> no edit row. Changed -> onSave reports the new text
//  and the checkbox state alongside the existing note/color, and
//  WebViewController runs it through the offset-shift pipeline. The
//  checkbox is independently persisted even when the text field is left
//  unchanged (toggling it alone on an already-edited row), via a
//  separate, cheaper WebViewController path that skips the offset-shift
//  pipeline entirely since nothing moved.
//
//  The checkbox's own default also reacts live while typing: for a row
//  with no edit yet, it flips to off the moment the field starts
//  diverging from the original quote (see isFirstTimeEdit), rather than
//  always starting from the row's pre-edit hasHighlight (always true for
//  a plain highlight). A row that already carries an edit keeps
//  defaulting from its current hasHighlight regardless of further edits,
//  the same way color already does.
//

import SwiftUI
import Articles

struct AnnotationEditorView: View {

	let annotation: Annotation

	/// Called when the person taps Save, with the (possibly unchanged)
	/// note text, color, and edit-text state. Note is passed as `nil` when
	/// the field is empty -- an empty note is "highlight only," per
	/// Annotation.note's nullable-means-no-note contract, not an empty
	/// string stored as a note.
	///
	/// `editedText` is `nil` when the edit-text field is unchanged from
	/// the original quote (no edit row should be created/modified) and
	/// the new value otherwise. `keepHighlight` is the checkbox's current
	/// state and must be persisted whenever it differs from
	/// `annotation.hasHighlight`, independently of whether `editedText`
	/// is nil -- toggling it on an already-edited row without touching
	/// the text is a valid, common save. See docs/annotations.md's
	/// "Manual edit UI" for the full save-behavior contract this maps
	/// onto.
	var onSave: (_ note: String?, _ color: Annotation.Color, _ editedText: String?, _ keepHighlight: Bool) -> Void

	/// Called after the person confirms deletion (the confirmation dialog
	/// itself lives in this view; by the time this fires, it's already
	/// been confirmed).
	var onDelete: () -> Void

	@Environment(\.dismiss) private var dismiss
	@Environment(\.colorScheme) private var colorScheme
	@AppStorage(AppDefaults.Key.highlightPalette) private var highlightPaletteRawValue = HighlightPalette.default.rawValue
	@State private var noteText: String
	@State private var selectedColor: Annotation.Color
	/// Pre-filled with the exact quote -- see docs/annotations.md's
	/// "Manual edit UI": shows the bare quote only, not the surrounding
	/// sentence (sentenceContext is reserved for the consolidated
	/// viewer's row rendering, not this field). If this row already
	/// carries an edit (originalText/replacementText set), the field
	/// shows the *current* replacement text, not the original -- editing
	/// an already-edited row further corrects the already-corrected text,
	/// it doesn't reopen the original typo.
	@State private var editText: String
	@State private var keepHighlight: Bool

	private var highlightPalette: HighlightPalette {
		HighlightPalette(rawValue: highlightPaletteRawValue) ?? .default
	}
	@State private var isDeleteConfirmationPresented = false
	@FocusState private var isNoteFieldFocused: Bool

	/// True for the "just created via the note-icon path" entry point,
	/// where there's nothing to lose yet -- lets the initial focus and
	/// placeholder copy differ slightly from editing an existing note,
	/// without needing a second init parameter thread through call sites.
	private var isNewAnnotation: Bool {
		annotation.note == nil && annotation.updatedAt == annotation.createdAt
	}

	init(
		annotation: Annotation,
		onSave: @escaping (String?, Annotation.Color, String?, Bool) -> Void,
		onDelete: @escaping () -> Void
	) {
		self.annotation = annotation
		self.onSave = onSave
		self.onDelete = onDelete
		_noteText = State(initialValue: annotation.note ?? "")
		_selectedColor = State(initialValue: annotation.color)
		// The field's starting value is the row's current text: the
		// replacement if this row already has one, otherwise the exact
		// quote -- see editText's own doc comment above.
		_editText = State(initialValue: annotation.replacementText ?? annotation.quoteExact)
		_keepHighlight = State(initialValue: annotation.hasHighlight)
	}

	/// True for a row that has never carried a text edit before this
	/// sheet was opened -- as opposed to a row that already has one and
	/// is merely being edited further. Only in this first-time case does
	/// starting to type a correction flip `keepHighlight`'s default; a
	/// row that already has an edit keeps honoring whatever `hasHighlight`
	/// was last explicitly set to, per "Manual edit UI"'s existing
	/// "re-checking it on a later visit restores the original color"
	/// precedent for the analogous color case.
	private var isFirstTimeEdit: Bool {
		annotation.originalText == nil
	}

	/// The value editText is compared against to decide whether a Save
	/// counts as "the field changed" -- the row's current text, same
	/// logic as editText's initial value above.
	private var originalEditableText: String {
		annotation.replacementText ?? annotation.quoteExact
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					// Read-only context, not editable -- the quote is the
					// anchor annotations.js resolves against; changing it
					// here would desync the note from what's actually
					// highlighted in the article.
					Text(truncatedQuote)
						.font(.callout)
						.foregroundStyle(.secondary)
						.italic()
				}

				Section {
					noteEditor
				} header: {
					Text("Note", comment: "Annotation editor: note field section header")
				}

				Section {
					colorSwatches
				} header: {
					Text("Highlight Color", comment: "Annotation editor: color section header")
				}

				Section {
					editTextField
					Toggle(isOn: $keepHighlight) {
						Text("Keep highlight on the corrected text", comment: "Annotation editor: keep-highlight-after-edit checkbox")
					}
				} header: {
					Text("Edit Text", comment: "Annotation editor: edit-text section header")
				}
				.onChange(of: editText) { _, newValue in
					// Only a first-time edit's default reacts live -- see
					// isFirstTimeEdit's doc comment. The moment the field
					// starts diverging from the original quote, default
					// to off; reverting it back to the original falls
					// back to the row's actual current hasHighlight
					// (always true here, since a never-edited row is
					// always a plain highlight).
					guard isFirstTimeEdit else { return }
					keepHighlight = (newValue == originalEditableText) ? annotation.hasHighlight : false
				}

				Section {
					Button(role: .destructive) {
						isDeleteConfirmationPresented = true
					} label: {
						Text("Delete Highlight", comment: "Annotation editor: delete button")
					}
				}
			}
			.navigationTitle(Text("Highlight", comment: "Annotation editor navigation title"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						dismiss()
					} label: {
						Text("Cancel", comment: "Cancel button")
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button {
						let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
						// Unchanged from the row's current text -> no edit
						// row created/modified, per "Manual edit UI"'s save
						// behavior contract.
						let editedText = editText == originalEditableText ? nil : editText
						onSave(trimmedNote.isEmpty ? nil : trimmedNote, selectedColor, editedText, keepHighlight)
						dismiss()
					} label: {
						Text("Save", comment: "Save button")
					}
				}
			}
			.onAppear {
				if isNewAnnotation {
					isNoteFieldFocused = true
				}
			}
			.confirmationDialog(
				NSLocalizedString("Delete this highlight?", comment: "Annotation editor: delete confirmation title"),
				isPresented: $isDeleteConfirmationPresented,
				titleVisibility: .visible
			) {
				Button(NSLocalizedString("Delete Highlight", comment: "Annotation editor: confirm delete button"), role: .destructive) {
					onDelete()
					dismiss()
				}
				Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
			} message: {
				if annotation.note?.isEmpty == false {
					Text("The highlight and its note will be removed.", comment: "Annotation editor: delete confirmation message, with note")
				} else {
					Text("The highlight will be removed.", comment: "Annotation editor: delete confirmation message, no note")
				}
			}
		}
	}

	// Same 120-character truncate-with-ellipsis treatment used for
	// selected-text previews elsewhere in this feature's design --
	// long enough for context, short enough to stay a one-line-ish
	// caption rather than reproducing the whole highlighted passage.
	private var truncatedQuote: String {
		let quote = annotation.quoteExact
		guard quote.count > 120 else { return quote }
		return String(quote.prefix(120)) + "…"
	}

	private var noteEditor: some View {
		ZStack(alignment: .topLeading) {
			if noteText.isEmpty {
				Text("Add a note…", comment: "Annotation editor: note field placeholder")
					.foregroundStyle(.tertiary)
					.padding(.top, 8)
					.padding(.leading, 5)
					.allowsHitTesting(false)
			}
			TextEditor(text: $noteText)
				.frame(minHeight: 100)
				.focused($isNoteFieldFocused)
		}
	}

	private var editTextField: some View {
		TextField(
			NSLocalizedString("Edit text", comment: "Annotation editor: edit-text field placeholder"),
			text: $editText,
			axis: .vertical
		)
	}

	private var colorSwatches: some View {
		HStack(spacing: 16) {
			ForEach(Annotation.Color.allCases, id: \.self) { color in
				Button {
					selectedColor = color
				} label: {
					Circle()
						.fill(color.swiftUIColor(palette: highlightPalette, isDark: colorScheme == .dark))
						.frame(width: 32, height: 32)
						.overlay {
							if color == selectedColor {
								Circle()
									.strokeBorder(Color.primary, lineWidth: 2)
									.padding(-3)
							}
						}
				}
				.buttonStyle(.plain)
				.accessibilityLabel(color.accessibilityLabel)
				.accessibilityAddTraits(color == selectedColor ? .isSelected : [])
			}
			Spacer()
		}
		.padding(.vertical, 4)
	}
}

#Preview("New highlight") {
	AnnotationEditorView(
		annotation: Annotation(
			annotationID: UUID().uuidString,
			articleID: "preview-article",
			bookKey: nil,
			quoteExact: "It was the best of times, it was the worst of times.",
			quotePrefix: "",
			quoteSuffix: "",
			startOffset: 0,
			endOffset: 54,
			color: .yellow,
			note: nil,
			createdAt: Date(),
			updatedAt: Date()
		),
		onSave: { _, _, _, _ in },
		onDelete: {}
	)
}

#Preview("Existing highlight with note") {
	AnnotationEditorView(
		annotation: Annotation(
			annotationID: UUID().uuidString,
			articleID: "preview-article",
			bookKey: nil,
			quoteExact: "It was the best of times, it was the worst of times.",
			quotePrefix: "",
			quoteSuffix: "",
			startOffset: 0,
			endOffset: 54,
			color: .purple,
			note: "This is a great opening line -- come back to this for the essay.",
			createdAt: Date().addingTimeInterval(-86400),
			updatedAt: Date().addingTimeInterval(-3600)
		),
		onSave: { _, _, _, _ in },
		onDelete: {}
	)
}
