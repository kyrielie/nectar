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

import SwiftUI
import Articles

struct AnnotationEditorView: View {

	let annotation: Annotation

	/// Called when the person taps Save, with the (possibly unchanged)
	/// note text and color. Note is passed as `nil` when the field is
	/// empty -- an empty note is "highlight only," per Annotation.note's
	/// nullable-means-no-note contract, not an empty string stored as a note.
	var onSave: (_ note: String?, _ color: Annotation.Color) -> Void

	/// Called after the person confirms deletion (the confirmation dialog
	/// itself lives in this view; by the time this fires, it's already
	/// been confirmed).
	var onDelete: () -> Void

	@Environment(\.dismiss) private var dismiss
	@State private var noteText: String
	@State private var selectedColor: Annotation.Color
	@State private var isDeleteConfirmationPresented = false
	@FocusState private var isNoteFieldFocused: Bool

	/// True for the "just created via the note-icon path" entry point,
	/// where there's nothing to lose yet -- lets the initial focus and
	/// placeholder copy differ slightly from editing an existing note,
	/// without needing a second init parameter thread through call sites.
	private var isNewAnnotation: Bool {
		annotation.note == nil && annotation.updatedAt == annotation.createdAt
	}

	init(annotation: Annotation, onSave: @escaping (String?, Annotation.Color) -> Void, onDelete: @escaping () -> Void) {
		self.annotation = annotation
		self.onSave = onSave
		self.onDelete = onDelete
		_noteText = State(initialValue: annotation.note ?? "")
		_selectedColor = State(initialValue: annotation.color)
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
						onSave(trimmedNote.isEmpty ? nil : trimmedNote, selectedColor)
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

	private var colorSwatches: some View {
		HStack(spacing: 16) {
			ForEach(Annotation.Color.allCases, id: \.self) { color in
				Button {
					selectedColor = color
				} label: {
					Circle()
						.fill(color.swiftUIColor)
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
		onSave: { _, _ in },
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
		onSave: { _, _ in },
		onDelete: {}
	)
}
