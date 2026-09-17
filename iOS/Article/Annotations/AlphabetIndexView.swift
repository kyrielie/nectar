//
//  AlphabetIndexView.swift
//  NetNewsWire-iOS
//
//  Part 12 of the highlights/text-replacement plan: a Contacts-style A-Z
//  index strip pinned to the trailing edge of AnnotationsListView's list,
//  letting the person jump straight to a book section by its first
//  letter rather than scrolling. Only meaningful when the list is
//  ordered by title or author (AnnotationsListView.SortOrder) -- there's
//  no natural A-Z axis on a date-ordered list, so this view's caller
//  (AnnotationsListView.list) only mounts it for those two sort orders.
//
//  Deliberately a SwiftUI overlay on the existing List, not a
//  UITableView-backed sectionIndexTitles(for:) rewrite -- see the plan's
//  own "Recommendation" note for why re-hosting every row as a
//  UIHostingConfiguration cell just to get the native index-title
//  affordance isn't worth it for one screen's one control.
//

import Foundation
import SwiftUI

/// One letter (or the "#" catch-all bucket) in the index strip, plus
/// which book section it should scroll to.
struct AlphabetIndexLetter: Identifiable, Equatable {
	let character: Character
	let sectionID: String

	var id: Character { character }
}

struct AlphabetIndexView: View {

	/// The book sections currently on screen (post-search-filter, same
	/// list the caller's List/ForEach is already rendering) -- letters
	/// are computed from these, so the index strip only ever offers
	/// letters that actually have a matching, currently-visible section,
	/// consistent with the plan's "letters with no matching group render
	/// dimmed" wording read literally: every rendered letter here has a
	/// match by construction.
	let sections: [AnnotationsListView.BookSection]
	let sortOrder: AnnotationsListView.SortOrder
	/// Called with the section to scroll to, once per drag-position
	/// change and once per tap -- see body's DragGesture, matching the
	/// plan's "continuous drag, not one scrollTo per discrete tap".
	let onSelectSection: (AnnotationsListView.BookSection) -> Void

	@State private var draggedLetter: Character?

	private var letters: [AlphabetIndexLetter] {
		Self.indexLetters(sections: sections, sortOrder: sortOrder)
	}

	/// Computes the index letters from whichever field is driving the
	/// active sort (book title for .title, author name for .author):
	/// first character of each section's sort key, uppercased, anything
	/// non-alphabetic collapsed to a single "#" bucket, deduped, sorted
	/// with "#" first (matching where Contacts itself places its own "#"
	/// bucket, ahead of A). A pure function over `sections` (not folded
	/// into the view body) so it's directly unit-testable without
	/// constructing a view -- same reasoning
	/// AnnotationsListViewScopeTests's own header comment gives for
	/// testing static functions on AnnotationsListView directly.
	///
	/// `sortOrder` is expected to be `.title` or `.author` -- passing
	/// `.dateCreated` isn't a caller error (there's no invalid input
	/// here, sections always have both a title and possibly authors),
	/// it just isn't something AnnotationsListView.list ever does, since
	/// it doesn't mount this view for that sort order at all.
	///
	/// nonisolated: AlphabetIndexView conforms to View, so its static
	/// members inherit main-actor isolation by default under this
	/// project's concurrency settings -- fine for the view itself, but
	/// this function's own doc comment above states the whole point of
	/// pulling it out as a static function is to be "directly
	/// unit-testable without constructing a view", and
	/// AlphabetIndexViewLetterExtractionTests is a plain (non-@MainActor)
	/// Swift Testing @Suite, so a synchronous call from its test bodies
	/// into an inherited-@MainActor static method is a Swift 6
	/// concurrency error, not a false positive. This function only reads
	/// its value-type parameters (BookSection, SortOrder, both plain
	/// structs/enums with no actor affinity of their own) and returns a
	/// new value array -- no actor-isolated state anywhere in it -- so
	/// nonisolated is correct, not just expedient.
	nonisolated static func indexLetters(sections: [AnnotationsListView.BookSection], sortOrder: AnnotationsListView.SortOrder) -> [AlphabetIndexLetter] {
		func sortKey(for section: AnnotationsListView.BookSection) -> String {
			switch sortOrder {
			case .title, .dateCreated:
				return section.title
			case .author:
				// A section with no resolvable author has no author-axis
				// letter to contribute -- same "sorts after everything
				// with an author" reasoning AnnotationsListView.resort
				// already applies for .author, just expressed here as
				// "doesn't produce an index letter" rather than a sort
				// comparator. Falling back to title would misrepresent
				// where an unattributed book actually sits in an
				// author-sorted list.
				return section.authors ?? ""
			}
		}

		func bucketCharacter(for key: String) -> Character? {
			guard let firstScalar = key.unicodeScalars.first(where: { CharacterSet.alphanumerics.contains($0) }) else {
				return key.isEmpty ? nil : "#"
			}
			let firstCharacter = Character(firstScalar)
			guard firstCharacter.isLetter else { return "#" }
			return Character(firstCharacter.uppercased())
		}

		// First matching section per letter wins -- sections is already
		// in the active sort order by the time this runs (built from
		// AnnotationsListView.resort's output), so "first" here means
		// "first in that order", giving a stable, deterministic
		// sectionID per letter across calls rather than depending on
		// dictionary-iteration order.
		var sectionIDByLetter: [Character: String] = [:]
		for section in sections {
			let key = sortKey(for: section)
			guard let letter = bucketCharacter(for: key) else { continue }
			if sectionIDByLetter[letter] == nil {
				sectionIDByLetter[letter] = section.id
			}
		}

		return sectionIDByLetter
			.map { AlphabetIndexLetter(character: $0.key, sectionID: $0.value) }
			.sorted { lhs, rhs in
				// "#" sorts first, ahead of "A" -- matches where
				// Contacts places its own catch-all bucket.
				if lhs.character == "#" { return rhs.character != "#" }
				if rhs.character == "#" { return false }
				return lhs.character < rhs.character
			}
	}

	var body: some View {
		if !letters.isEmpty {
			GeometryReader { geometry in
				VStack(spacing: 0) {
					ForEach(letters) { letter in
						Text(String(letter.character))
							.font(.caption2.weight(.semibold))
							.foregroundStyle(draggedLetter == letter.character ? Color.accentColor : .secondary)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
					}
				}
				.contentShape(Rectangle())
				.gesture(
					// A single DragGesture over the whole strip, not
					// per-letter tap targets only -- computes which
					// letter row the touch's y falls into from the
					// strip's own geometry (this GeometryReader's
					// frame), and fires onSelectSection on every
					// position change plus the final release, which is
					// what makes this feel like the Contacts slider
					// (continuous drag) rather than a row of small
					// buttons. minimumDistance: 0 so a plain tap (no
					// drag) still registers immediately, without waiting
					// for movement first.
					DragGesture(minimumDistance: 0)
						.onChanged { value in
							select(at: value.location.y, in: geometry.size, letters: letters)
						}
						.onEnded { value in
							select(at: value.location.y, in: geometry.size, letters: letters)
							draggedLetter = nil
						}
				)
			}
			.frame(width: 20)
			.padding(.trailing, 4)
		}
	}

	private func select(at y: CGFloat, in size: CGSize, letters: [AlphabetIndexLetter]) {
		guard !letters.isEmpty, size.height > 0 else { return }
		let rowHeight = size.height / CGFloat(letters.count)
		let index = min(letters.count - 1, max(0, Int(y / rowHeight)))
		let letter = letters[index]
		guard draggedLetter != letter.character else { return }
		draggedLetter = letter.character
		if let section = sections.first(where: { $0.id == letter.sectionID }) {
			onSelectSection(section)
		}
	}
}
