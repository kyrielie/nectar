//
//  AnnotationsListView.swift
//  NetNewsWire-iOS
//
//  Reachable two ways: from the reader's annotations toolbar button
//  (ArticleViewController.showAnnotationsList(_:), the open article's
//  chapter) and from Settings (unscoped, "everything I've ever
//  highlighted"). Per the text-replacement feature's plan (Part 2, "the
//  combined viewer... needs a chapter scope back"), this is one screen
//  with a This Chapter/Entire Book tab switcher (see selectedScope/
//  showsTabSwitcher below) plus a separate "All Highlights" push for
//  the unscoped case, not two (or three) separately-launched views that
//  happen to render similar content. Either of the two tabs is
//  reachable from either entry point once the screen is open; only
//  which tab it *opens* on differs, seeded from the `scope` the caller
//  passed in. The Settings entry point has no book in context, so it
//  only ever offers the unscoped view directly (showsTabSwitcher is
//  false there, and the caller passes .everything at init). There used
//  to be a third, per-chapter scope reachable from a *pre-open* toolbar
//  menu with two choices; that menu is gone (see
//  ArticleViewController.showAnnotationsList's doc comment). This is a
//  deliberate reintroduction of a per-chapter scope, but as an
//  in-screen tab decided after the screen opens, not a menu decided
//  before -- don't restore the old menu.
//
//  "This Chapter" is defined as "annotations on the article currently
//  open behind this screen" (account.fetchAnnotations(forArticleID:)),
//  not a heading-precise slice -- chapterTitle (the heading nearest a
//  highlight's quote) doesn't always align 1:1 with articleID, since one
//  book's chapters can span more than one articleID (see the Groups
//  comment below). Flagged as a known simplification, not solved here.
//
//  Groups are keyed by (bookKey ?? articleID, chapterTitle) -- NOT by
//  articleID alone. Two reasons this matters (see docs/book-identity.md,
//  docs/annotations.md):
//   1. The same book can have more than one articleID sharing one bookKey
//      (duplicate collection feeds, resubscriptions) -- grouping by
//      articleID alone split those into separate sections that repeated
//      the same book title as both the nav bar title and a section
//      header. Falling back to bookKey collapses genuine duplicates while
//      still falling back to articleID for the rare unresolvable-bookKey
//      case (see Annotation.bookKey's doc comment).
//   2. A single book's chapters can themselves span more than one
//      articleID (confirmed against a real multi-chapter book -- chapter
//      identity here is carried by chapterTitle, not by articleID
//      boundaries), so chapterTitle has to be part of the key too, or
//      distinct chapters of the same book would incorrectly collapse into
//      one section once grouping moved to bookKey.
//
//  Tapping a row has two cases: if the row's article is the one already
//  open behind this screen, this view can't scroll the live webview
//  itself (it has no reference to WebViewController), so it hands back
//  via onNavigateToAnnotation and lets the presenter (ArticleViewController)
//  decide whether that's a same-article scrollToAnnotation call or a
//  cross-article SceneCoordinator.selectArticleDirectly navigation
//  followed by one.
//

import SwiftUI
import NaturalLanguage
import Articles
import Account

struct AnnotationsListView: View {

	enum Scope: Hashable {
		case chapter(articleID: String, bookKey: String?)
		case book(bookKey: String)
		case everything
	}

	/// The order BookSection (outer, "Title by Author") sections appear
	/// in -- see loadRows(). Per Part 11: this replaces the previous
	/// fixed recency ("which book did I highlight in most recently")
	/// ordering with an explicit person-facing choice. Chapter ordering
	/// *within* a book (AnnotationGroup, the inner tier) is unaffected by
	/// this -- see loadRows' chapterSortOrder, still reading order
	/// regardless of which SortOrder is active here.
	///
	/// Persisted via AppDefaults.Key.annotationsSortOrder (an
	/// @AppStorage-backed raw Int, same pattern as highlightPaletteRawValue
	/// below) so the person's choice survives relaunches -- there's no
	/// per-scope reason to reset it, and Part 12's A–Z index slider needs
	/// a stable active sort to key its own letter index off of.
	enum SortOrder: Int, CaseIterable, Identifiable {
		case dateCreated = 0
		case title = 1
		case author = 2

		var id: Int { rawValue }

		var label: String {
			switch self {
			case .dateCreated:
				return NSLocalizedString("Date Created", comment: "Annotations list: sort order option, most recent first")
			case .title:
				return NSLocalizedString("Title", comment: "Annotations list: sort order option, book title A-Z")
			case .author:
				return NSLocalizedString("Author", comment: "Annotations list: sort order option, author name A-Z")
			}
		}
	}

	let account: Account
	/// The book this screen was opened for, when opened from the
	/// in-context toolbar button -- kept independently of `selectedScope`
	/// (below) so "Entire Book" stays available as a tab even after the
	/// person switches to "This Chapter" and back, per Part 2: "either
	/// tab reachable from either entry point once the screen is open."
	/// nil when opened from Settings with no single book in context, in
	/// which case the tab switcher itself is hidden (see
	/// `showsTabSwitcher`) -- there is no book to scope either tab to.
	let bookKey: String?

	/// The article this screen was opened for, when opened from the
	/// in-context toolbar button -- nil when opened from Settings with no
	/// article in context. Threaded through as its own stored property
	/// (parallel to `bookKey`) rather than recovered from `selectedScope`,
	/// since the "This Chapter" Picker tag needs a concrete value up
	/// front the same way the existing `.book` tag already hardcodes
	/// `bookKey ?? ""`.
	let articleID: String?

	/// The screen's navigation title, supplied by the caller rather than
	/// derived here. For the .chapter/.book cases this is the
	/// currently-open article's own title (already in memory at the call
	/// site -- see ArticleViewController.showAnnotationsList) rather than
	/// a fixed placeholder string; nil (or empty) falls back to a generic
	/// title below, the same fallback shape TableOfContentsViewController
	/// uses for its own bookTitle parameter. Only shown for those two
	/// tabs -- the .everything screen always uses its own generic title,
	/// even if a bookKey/title pair was supplied, since "All Highlights"
	/// showing one book's title would be misleading.
	let title: String?

	/// Called when the person taps a row: navigate to (and, once there,
	/// flash) this annotation. The caller owns both the cross-article
	/// navigation and the same-article scroll -- see this file's header
	/// comment.
	var onNavigateToAnnotation: (Annotation) -> Void

	/// Called when the person swipe-deletes a row, before this view removes
	/// it from bookSections and calls account.deleteAnnotation itself (see
	/// delete(_:) below) -- gives the presenter a chance to revert a text
	/// edit's replacement text in a currently-open article's live DOM
	/// (ArticleViewController.revertAnnotationDOMIfCurrentlyOpen), the same
	/// way WebViewController.deleteAnnotation already does for the note-
	/// editor's own delete action. This view never touches a WebViewController
	/// directly (see this file's header comment), so it can only hand the
	/// annotation back and let the presenter decide whether there's
	/// anything live to revert at all. nil (the default) means "no DOM to
	/// revert from this entry point" -- correct for the two Settings entry
	/// points (AnnotationsSettingsView/TextReplacementSettingsView) as of
	/// this writing, since neither currently threads a
	/// currentArticleViewController lookup down to here the way
	/// SettingsViewController.navigateToAnnotationFromSettings does for the
	/// navigate case; a highlight-only delete or a delete whose article
	/// isn't the one currently open is unaffected either way (see
	/// revertAnnotationDOMIfCurrentlyOpen's own doc comment).
	var onDeleteAnnotation: ((Annotation) -> Void)?

	/// Explicit close handler for callers that present this view
	/// imperatively via UIKit (ArticleViewController.showAnnotationsList
	/// wraps this in a UIHostingController and pushes it directly onto its
	/// own UINavigationController, entirely outside SwiftUI's own
	/// navigation machinery) -- @Environment(\.dismiss) only gets a
	/// working handler wired up when SwiftUI itself performed the
	/// presentation/push, so it's a silent no-op there. nil (the default)
	/// falls back to dismiss(), which is correct for the Settings entry
	/// point below: that one reaches this view through a real SwiftUI
	/// NavigationLink push, so dismiss() (pop, in that context) already
	/// works.
	var onClose: (() -> Void)?

	@Environment(\.dismiss) private var dismiss

	/// scope's initial value seeds `selectedScope` (below) -- the tab the
	/// screen opens on. ArticleViewController.showAnnotationsList passes
	/// `.chapter(articleID:bookKey:)` (opens on "This Chapter"); the
	/// Settings entry point (TextReplacementSettingsView/
	/// AnnotationsSettingsView) passes `.everything` directly (no tab
	/// switcher at all, since there's no book in context -- see
	/// showsTabSwitcher). resolvedBookKey/resolvedArticleID/
	/// showsTabSwitcher's own derivations are pulled into static
	/// functions below purely so AnnotationsListViewScopeTests can
	/// exercise them without constructing a whole view (which would
	/// otherwise require a real Account -- see that test file's own
	/// header comment for why that's not available in this test target).
	init(account: Account, scope: Scope, title: String? = nil, onClose: (() -> Void)? = nil, onDeleteAnnotation: ((Annotation) -> Void)? = nil, onNavigateToAnnotation: @escaping (Annotation) -> Void) {
		self.account = account
		self.title = title
		self.onClose = onClose
		self.onDeleteAnnotation = onDeleteAnnotation
		self.onNavigateToAnnotation = onNavigateToAnnotation
		self.bookKey = Self.resolvedBookKey(for: scope)
		self.articleID = Self.resolvedArticleID(for: scope)
		_selectedScope = State(initialValue: scope)
	}

	/// The article this screen was opened for, derived from the scope the
	/// caller passed to init -- nil for `.book`/`.everything`. A static
	/// function (not inlined into init), same reasoning as
	/// `resolvedBookKey(for:)` above.
	static func resolvedArticleID(for scope: Scope) -> String? {
		switch scope {
		case .chapter(let articleID, _):
			return articleID
		case .book, .everything:
			return nil
		}
	}

	/// The book this screen was opened for, derived from the scope the
	/// caller passed to init -- nil for `.everything`. A static function
	/// (not inlined into init) so AnnotationsListViewScopeTests can
	/// assert on this mapping directly. Named distinctly from the
	/// `bookKey` stored property (rather than overloading that name) so
	/// call sites are unambiguous at a glance.
	static func resolvedBookKey(for scope: Scope) -> String? {
		switch scope {
		case .chapter(_, let bookKey):
			return bookKey
		case .book(let bookKey):
			return bookKey
		case .everything:
			return nil
		}
	}

	/// The tab currently on screen -- distinct from `bookKey` (the fixed
	/// identity of the book this screen was opened for, if any) so
	/// switching between "This Chapter" and "Entire Book" doesn't lose
	/// which book "Entire Book" refers to, and pushing "All Highlights"
	/// (a separate screen, not a tab on this one) doesn't affect this
	/// screen's own selectedScope at all.
	@State private var selectedScope: Scope
	/// The tab switcher only makes sense when both tabs have somewhere to
	/// point -- if this screen was opened from Settings with no book in
	/// context (bookKey == nil), there is no "This Chapter"/"Entire Book"
	/// to switch between, so the switcher is hidden entirely and the
	/// screen behaves exactly as the old unscoped Settings list did. A
	/// static function over the resolved bookKey (not a property reading
	/// `self.bookKey`) so AnnotationsListViewScopeTests can assert on
	/// this decision without constructing a view instance.
	static func showsTabSwitcher(bookKey: String?) -> Bool { bookKey != nil }
	private var showsTabSwitcher: Bool { Self.showsTabSwitcher(bookKey: bookKey) }

	/// Outer (book) tier -- see BookSection's own doc comment. Replaces
	/// the old flat `[AnnotationGroup]` per Part 11's two-tier
	/// restructure; AnnotationGroup itself is unchanged conceptually and
	/// now nests inside each BookSection as the inner (chapter) tier.
	@State private var bookSections: [BookSection] = []
	@State private var isLoading = true
	/// Section headers are collapsible (see `list`/`sectionHeader(for:)`
	/// below) -- a group's key present here means its rows are hidden.
	/// Collapsing stays per-*chapter* (inner tier) even after Part 11's
	/// restructure -- GroupKey is unchanged, so a chapter collapsed
	/// before switching sort order or reloading stays collapsed after,
	/// since GroupKey doesn't encode sort order or book-section
	/// position. Starts empty so every section opens expanded by
	/// default; not persisted across screen presentations, same as the
	/// rest of this view's transient @State.
	@State private var collapsedGroupKeys: Set<GroupKey> = []
	/// Backing state for `.searchable(text:)` on `list`. Filtering
	/// (`filteredBookSections`) is purely client-side against the
	/// already-loaded `bookSections` -- no new fetch.
	@State private var searchText = ""
	/// Which book-level ordering is active -- see SortOrder's own doc
	/// comment. @AppStorage-backed, same persistence pattern as
	/// highlightPaletteRawValue below (a raw Int rather than the enum
	/// itself, since @AppStorage requires a directly storable type).
	@AppStorage(AppDefaults.Key.annotationsSortOrder) private var sortOrderRawValue = AnnotationsListView.SortOrder.dateCreated.rawValue
	private var sortOrder: SortOrder {
		SortOrder(rawValue: sortOrderRawValue) ?? .dateCreated
	}

	/// Not private: AnnotationGroup.rows (below) is internal now that
	/// AnnotationGroup itself had to widen to internal (see that type's
	/// doc comment), and a stored property can't be less visible than
	/// its declaring type.
	struct Row: Identifiable {
		let annotation: Annotation
		/// Comma-joined, sorted Author.name list for this row's article;
		/// nil when the article has no authors with a name. Row-level
		/// (not group-level) since a (bookKey, chapterTitle) group can, in
		/// the .everything scope's cross-book case, span articles that
		/// don't necessarily share authors -- see loadRows'
		/// authorsByArticleID.
		let articleAuthors: String?
		/// This row's own article title, independent of the group's
		/// `heading` -- `heading` is chapter-title-first (see
		/// AnnotationGroup's doc comment) and won't reliably contain the
		/// book/article title, so search (filteredBookSections) needs this
		/// separately. Sourced from loadRows' titlesByArticleID.
		let articleTitle: String
		/// This row's article's preferred link (Article.preferredLink),
		/// for the long-press "Copy Highlight" action below. nil when the
		/// article has no resolvable link. Sourced from loadRows'
		/// linksByArticleID.
		let articleLink: String?

		var id: String { annotation.annotationID }
	}

	/// Grouping key: bookKey when the owning article resolves one, else
	/// articleID (Annotation.bookKey's own fallback shape), paired with
	/// chapterTitle so a book's distinct chapters don't collapse into one
	/// section just because they share a bookKey -- see this file's header
	/// comment. Not private, for the same reason AnnotationGroup below
	/// isn't: AnnotationGroup.id returns GroupKey, and Identifiable's id
	/// requirement can't be less visible than AnnotationGroup itself.
	struct GroupKey: Hashable {
		let bookOrArticleID: String
		let chapterTitle: String?
	}

	/// Inner (chapter) tier -- one per (book, chapter), unchanged
	/// conceptually from before Part 11. `heading` is the text to show
	/// in the *inner* section header when there's more than one chapter
	/// group inside the same BookSection: chapterTitle when this group
	/// has one (the real-anthology case -- see mockup discussed with the
	/// person), otherwise the group's own book/article title (the
	/// cross-book case in the .everything scope, where different books
	/// need their own headers even though none of them has chapters).
	/// Not private: BookSection.chapterGroups (below) is internal, since
	/// AlphabetIndexView (a separate file in this target) takes
	/// [BookSection] directly -- a stored property can't be less visible
	/// than the type it's declared on, so this has to be at least
	/// internal too even though nothing outside this file constructs or
	/// reads into an AnnotationGroup directly today.
	struct AnnotationGroup: Identifiable {
		let key: GroupKey
		let heading: String
		let rows: [Row]

		var id: GroupKey { key }
	}

	/// Outer (book) tier -- Part 11's "Title by Author" restructure.
	/// One section per book (bookOrArticleID), containing every chapter
	/// group (AnnotationGroup, the inner tier) belonging to that book,
	/// already ordered per chapterSortOrder inside loadRows(). `heading`
	/// is always "Title by Author" text (titleAuthorHeading below), not
	/// conditional on group count the way AnnotationGroup.heading is --
	/// the outer tier's whole purpose is to name which book this is, so
	/// it always renders even when a book has only one chapter group.
	struct BookSection: Identifiable {
		let bookOrArticleID: String
		let title: String
		/// Comma-joined author names for this book, or nil when no
		/// article in the book resolves any author names. Same shape as
		/// Row.articleAuthors/authorsByArticleID -- see loadRows.
		let authors: String?
		let chapterGroups: [AnnotationGroup]

		var id: String { bookOrArticleID }

		/// "Title by Author" (or just "Title" when there's no resolvable
		/// author) -- the outer section header text, and the sort key
		/// for SortOrder.title. Author-sort's own key is `authors`
		/// directly, not this combined string, since "Title by Author"
		/// alphabetizes by title even when the person asked to sort by
		/// author.
		var titleAuthorHeading: String {
			guard let authors, !authors.isEmpty else { return title }
			return String(format: NSLocalizedString("%@ by %@", comment: "Annotations list: book section header, title by author"), title, authors)
		}
	}

	private var navigationTitleText: String {
		switch selectedScope {
		case .chapter:
			if let title, !title.isEmpty {
				return title
			}
			return NSLocalizedString("This Chapter", comment: "Annotations list navigation title: single chapter, title unavailable")
		case .book:
			if let title, !title.isEmpty {
				return title
			}
			return NSLocalizedString("This Work", comment: "Annotations list navigation title: whole book, title unavailable")
		case .everything:
			return NSLocalizedString("All Highlights", comment: "Annotations list navigation title: everything")
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			if showsTabSwitcher {
				// "This Chapter" / "Entire Book", per Part 2 of the plan --
				// .everything is no longer a tab here; it's reached via the
				// "All Highlights" toolbar button below, which pushes a
				// second AnnotationsListView instance (same pattern
				// TextReplacementSettingsView's Edit History row uses).
				// Hidden entirely when there's no book in context to make
				// either tab meaningful (see showsTabSwitcher).
				Picker(selection: $selectedScope) {
					Text("This Chapter", comment: "Annotations list tab: current chapter/article only")
						.tag(Scope.chapter(articleID: articleID ?? "", bookKey: bookKey))
					Text("This Work", comment: "Annotations list tab: current book, every chapter")
						.tag(Scope.book(bookKey: bookKey ?? ""))
				} label: {
					Text("Scope", comment: "Annotations list: tab picker accessibility label")
				}
				.pickerStyle(.segmented)
				.padding(.horizontal)
				.padding(.vertical, 8)
			}

			Group {
				if isLoading {
					ProgressView()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
				} else if bookSections.isEmpty {
					emptyState
				} else {
					list
				}
			}
		}
		.navigationTitle(Text(navigationTitleText))
		.navigationBarTitleDisplayMode(.inline)
		// Default .automatic placement renders under the nav bar and
		// scrolls with the list -- same scroll-to-reveal behavior as
		// MainTimelineModernViewController's UISearchController, no extra
		// configuration needed to match it.
		.searchable(text: $searchText, prompt: Text("Search Highlights", comment: "Annotations list: search field prompt"))
		.toolbar {
			// From the toolbar-button entry point this screen is presented
			// modally, full-screen, with no system back chevron (see
			// ArticleViewController.showAnnotationsList) -- same close
			// affordance TableOfContentsViewController uses for the same
			// reason (system .close item, trailing placement: an "×"
			// glyph, not text -- xmark here matches that rather than
			// spelling out "Close"), and from Settings' NavigationLink
			// entry point a back chevron is already present, but showing
			// this too is harmless and keeps one behavior for both entry
			// points.
			ToolbarItem(placement: .confirmationAction) {
				Button {
					if let onClose {
						onClose()
					} else {
						dismiss()
					}
				} label: {
					Image(systemName: "xmark")
				}
				.accessibilityLabel(Text("Close", comment: "Annotations list: close button accessibility label"))
			}
			// "All Highlights" -- only offered when there's a book in
			// context to switch *out* of (showsTabSwitcher) and the
			// screen isn't already showing .everything (pushing a second
			// .everything screen on top of the first would be pointless).
			// A plain NavigationLink, same pattern
			// TextReplacementSettingsView's Edit History row already uses
			// -- this view is never wrapped in its own NavigationStack
			// (see this file's header comment), so the link pushes onto
			// whichever real UINavigationController is hosting this
			// screen, UIKit's own or a SwiftUI one, without needing a
			// manual UIHostingController push here. Not a scope change on
			// this screen, so "This Chapter"/"Entire Book" stay exactly
			// where the person left them if they come back.
			if showsTabSwitcher && selectedScope != .everything {
				ToolbarItem(placement: .topBarLeading) {
					NavigationLink {
						AnnotationsListView(account: account, scope: .everything, onClose: onClose, onDeleteAnnotation: onDeleteAnnotation, onNavigateToAnnotation: onNavigateToAnnotation)
					} label: {
						Text("All Highlights", comment: "Annotations list toolbar: push the unscoped everything view")
					}
				}
			}
			// Part 11's sort-order control -- a Menu (not a segmented
			// Picker, unlike the scope switcher above) since it's a
			// toolbar-hosted, three-way, infrequently-changed choice,
			// matching how this app surfaces other toolbar sort/filter
			// menus elsewhere rather than spending permanent screen
			// width on a segmented control for it.
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Picker(selection: $sortOrderRawValue) {
						ForEach(SortOrder.allCases) { order in
							Text(order.label).tag(order.rawValue)
						}
					} label: {
						Text("Sort By", comment: "Annotations list: sort order menu label")
					}
				} label: {
					Image(systemName: "arrow.up.arrow.down")
				}
				.accessibilityLabel(Text("Sort By", comment: "Annotations list: sort order menu label"))
			}
		}
		.task {
			await loadRows()
		}
		.onChange(of: selectedScope) {
			Task {
				await loadRows()
			}
		}
		// Re-sorting doesn't need a new fetch -- resort(sections:by:) is a
		// pure reordering of the already-loaded bookSections/chapterGroups,
		// same annotations, same grouping, only the two tiers' order
		// changes. A full loadRows() round-trip here would be wasted work
		// (and would flash the ProgressView for no reason) for what's
		// purely a display-order preference change.
		.onChange(of: sortOrderRawValue) {
			bookSections = Self.resort(sections: bookSections, by: sortOrder)
		}
	}

	private var emptyState: some View {
		ContentUnavailableView(
			NSLocalizedString("No Highlights", comment: "Annotations list empty state title"),
			systemImage: "highlighter",
			description: Text("Select text in a work to highlight it.", comment: "Annotations list empty state message")
		)
	}

	private var list: some View {
		ScrollViewReader { proxy in
			List {
				ForEach(filteredBookSections) { section in
					// The outer (book) tier always gets its own SwiftUI
					// Section per book, regardless of chapter-group count --
					// unlike the inner tier's single-group omission below,
					// "Title by Author" is the header this whole restructure
					// exists to show, so it renders even for a one-chapter
					// book. Only the *inner* per-chapter header is
					// conditionally omitted, same reasoning as before Part
					// 11 (a lone chapter's header would just repeat
					// something already visible).
					Section {
						ForEach(section.chapterGroups) { group in
							if section.chapterGroups.count > 1 {
								// Collapse is suppressed (not cleared) while a
								// search is active: a collapsed group whose only
								// remaining rows are the search match would
								// otherwise stay hidden, and filtering would look
								// broken. Leaving collapsedGroupKeys itself
								// untouched means clearing the search goes
								// straight back to whatever was collapsed before,
								// with nothing to reconcile.
								DisclosureGroup(isExpanded: chapterExpandedBinding(for: group.key)) {
									rows(for: group)
								} label: {
									sectionHeader(for: group)
								}
							} else {
								rows(for: group)
							}
						}
					} header: {
						Text(section.titleAuthorHeading)
					}
					// Part 12's scroll target -- BookSection.id (not
					// AnnotationGroup.id) is what the A-Z index scrolls
					// to, since the index letters are computed from the
					// outer (book) tier's own sort key (title or author),
					// not the inner chapter tier -- see
					// AlphabetIndexView.indexLetters.
					.id(section.id)
				}
			}
			// The index strip is only meaningful for title/author sort --
			// there's no natural A-Z axis on a date-ordered list (see
			// Part 12's own "Only meaningful for..." note). Gated on
			// sortOrder rather than always mounted-but-hidden, so a
			// date-sorted screen doesn't reserve trailing-edge width for
			// a control that can never do anything there.
			.overlay(alignment: .trailing) {
				if sortOrder != .dateCreated {
					AlphabetIndexView(sections: filteredBookSections, sortOrder: sortOrder) { section in
						withAnimation(.default) {
							proxy.scrollTo(section.id, anchor: .top)
						}
					}
				}
			}
		}
	}

	/// Two-way binding SwiftUI's DisclosureGroup needs, backed by
	/// collapsedGroupKeys (inverted -- collapsedGroupKeys stores what's
	/// *hidden*, DisclosureGroup wants what's *expanded*). Kept as
	/// collapsedGroupKeys, not rewritten to an "expanded" set, since
	/// starting empty already gives the desired "every section open by
	/// default" behavior for free (an "expanded" set would need
	/// pre-seeding with every key on each load instead).
	private func chapterExpandedBinding(for key: GroupKey) -> Binding<Bool> {
		Binding(
			get: { searchText.isEmpty ? !collapsedGroupKeys.contains(key) : true },
			set: { isExpanded in
				if isExpanded {
					collapsedGroupKeys.remove(key)
				} else {
					collapsedGroupKeys.insert(key)
				}
			}
		)
	}

	/// `bookSections` filtered against `searchText`, matching a row's
	/// quote, note, or article title (case-insensitive). A chapter group
	/// left with zero matching rows is dropped; a book section left with
	/// zero remaining chapter groups is dropped entirely rather than
	/// shown empty. Purely client-side against the already-loaded
	/// `bookSections` -- no new fetch.
	private var filteredBookSections: [BookSection] {
		guard !searchText.isEmpty else { return bookSections }
		return bookSections.compactMap { section -> BookSection? in
			let chapterGroups = section.chapterGroups.compactMap { group -> AnnotationGroup? in
				let rows = group.rows.filter { row in
					row.annotation.quoteExact.localizedStandardContains(searchText)
					|| (row.annotation.note?.localizedStandardContains(searchText) ?? false)
					|| row.articleTitle.localizedStandardContains(searchText)
				}
				guard !rows.isEmpty else { return nil }
				return AnnotationGroup(key: group.key, heading: group.heading, rows: rows)
			}
			guard !chapterGroups.isEmpty else { return nil }
			return BookSection(bookOrArticleID: section.bookOrArticleID, title: section.title, authors: section.authors, chapterGroups: chapterGroups)
		}
	}

	/// The inner (chapter) tier's header label, used as a DisclosureGroup
	/// label above -- DisclosureGroup supplies its own chevron/expand-
	/// collapse affordance and accessibility value now (see
	/// chapterExpandedBinding), so this no longer needs the Button/manual
	/// chevron/accessibility wiring the pre-Part-11 version had.
	private func sectionHeader(for group: AnnotationGroup) -> some View {
		Text(group.heading)
	}

	@ViewBuilder
	private func rows(for group: AnnotationGroup) -> some View {
		ForEach(group.rows) { row in
			Button {
				onNavigateToAnnotation(row.annotation)
			} label: {
				AnnotationRow(annotation: row.annotation, articleAuthors: row.articleAuthors, articleLink: row.articleLink)
			}
			.buttonStyle(.plain)
			.contextMenu {
				Button {
					UIPasteboard.general.string = copyText(annotation: row.annotation, articleAuthors: row.articleAuthors, link: row.articleLink)
				} label: {
					Label(NSLocalizedString("Copy Highlight", comment: "Annotations list: copy highlight context menu action"), systemImage: "doc.on.doc")
				}
			}
			.swipeActions(edge: .trailing, allowsFullSwipe: true) {
				Button(role: .destructive) {
					delete(row.annotation)
				} label: {
					Label(NSLocalizedString("Delete", comment: "Delete button"), systemImage: "trash")
				}
			}
		}
	}

	private func loadRows() async {
		isLoading = true

		let annotations: [Annotation]
		switch selectedScope {
		case .chapter(let articleID, _):
			annotations = await account.fetchAnnotations(forArticleID: articleID)
		case .book(let bookKey):
			annotations = await account.fetchAnnotations(forBookKey: bookKey)
		case .everything:
			annotations = await account.fetchAllAnnotations()
		}

		guard !annotations.isEmpty else {
			bookSections = []
			isLoading = false
			return
		}

		// Titles are looked up once per unique articleID, not once per
		// annotation -- a chapter with several highlights would otherwise
		// fetch the same Article repeatedly.
		let articleIDs = Set(annotations.map(\.articleID))
		let articles = await account.fetchArticlesAsync(.articleIDs(articleIDs))
		let titlesByArticleID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0.title ?? NSLocalizedString("Untitled", comment: "Fallback article title")) })
		// Set<Author> iteration order isn't guaranteed stable between
		// renders -- sort names before joining so a row's byline doesn't
		// visually reorder itself across reloads.
		let authorsByArticleID = Dictionary(uniqueKeysWithValues: articles.map { article -> (String, String?) in
			let names = (article.authors ?? []).compactMap(\.name).sorted()
			return (article.articleID, names.isEmpty ? nil : names.joined(separator: ", "))
		})
		// For the long-press "Copy Highlight" action below -- same shape
		// as authorsByArticleID, one lookup per unique articleID.
		let linksByArticleID = Dictionary(uniqueKeysWithValues: articles.map { ($0.articleID, $0.preferredLink) })

		// Grouped by (bookKey ?? articleID, chapterTitle) -- see this file's
		// header comment.
		func normalizedChapterTitle(_ chapterTitle: String?) -> String? {
			guard let trimmed = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
				return nil
			}
			return trimmed
		}

		// Chapters *within* one book are always reading order, never
		// recency and never affected by SortOrder (SortOrder governs only
		// the outer/book tier -- see SortOrder's own doc comment).
		// annotations table has no stored chapter-position column (see
		// docs/annotations.md), so this falls back to the leading integer
		// in chapterTitle itself ("Chapter 9" -> 9), which is what
		// annotations.js's nearestChapterTitle actually captures for a
		// Calibre-style TOC heading. A chapterTitle with no leading number
		// sorts after every group that has one, rather than falling back
		// to some other order; a nil chapterTitle (no heading before this
		// annotation at all -- front matter, or the single-heading
		// non-anthology case) sorts first, ahead of Chapter 1, matching
		// where that content actually sits in the book.
		func leadingInteger(in string: String) -> Int? {
			var digits = ""
			for character in string {
				if character.isNumber {
					digits.append(character)
				} else if !digits.isEmpty {
					break
				}
			}
			return digits.isEmpty ? nil : Int(digits)
		}

		func chapterSortOrder(_ chapterTitle: String?) -> Int {
			guard let chapterTitle else { return Int.min }
			return leadingInteger(in: chapterTitle) ?? Int.max
		}

		let rowsByGroupKey = Dictionary(grouping: annotations) { annotation in
			GroupKey(
				bookOrArticleID: annotation.bookKey ?? annotation.articleID,
				chapterTitle: normalizedChapterTitle(annotation.chapterTitle)
			)
		}
		let chapterGroups = rowsByGroupKey
			.map { key, groupAnnotations -> AnnotationGroup in
				let sortedAnnotations = groupAnnotations.sorted { $0.updatedAt > $1.updatedAt }
				// Fallback heading when this group has no chapterTitle of
				// its own: the owning article's title (the cross-book case
				// in .everything, or a plain non-chaptered book). Any
				// article's title in the group works here -- every
				// annotation sharing a bookKey is understood to be the
				// same book (see book-identity.md), so their titles should
				// already agree.
				let fallbackTitle = sortedAnnotations
					.lazy
					.compactMap { titlesByArticleID[$0.articleID] }
					.first ?? NSLocalizedString("Untitled", comment: "Fallback article title")
				let heading = key.chapterTitle ?? fallbackTitle
				let rows = sortedAnnotations.map {
					Row(
						annotation: $0,
						articleAuthors: authorsByArticleID[$0.articleID] ?? nil,
						articleTitle: titlesByArticleID[$0.articleID] ?? NSLocalizedString("Untitled", comment: "Fallback article title"),
						articleLink: linksByArticleID[$0.articleID] ?? nil
					)
				}
				return AnnotationGroup(key: key, heading: heading, rows: rows)
			}

		// Part 11's outer (book) tier: cluster the (already-built) inner
		// chapter groups by bookOrArticleID, order each book's chapters
		// by reading order (chapterSortOrder, never by sortOrder -- see
		// above), and title/authors come from any chapter group's rows in
		// that book (every annotation sharing a bookKey is the same book,
		// same reasoning fallbackTitle above already relies on).
		let chapterGroupsByBook = Dictionary(grouping: chapterGroups, by: \.key.bookOrArticleID)
		let sections = chapterGroupsByBook.map { bookOrArticleID, groupsForBook -> BookSection in
			let orderedGroups = groupsForBook.sorted { lhs, rhs in
				let lhsOrder = chapterSortOrder(lhs.key.chapterTitle)
				let rhsOrder = chapterSortOrder(rhs.key.chapterTitle)
				if lhsOrder != rhsOrder {
					return lhsOrder < rhsOrder
				}
				// Same (unparseable-or-absent) chapter order -- stable
				// tiebreaker so groups don't reshuffle from one loadRows()
				// call to the next.
				return lhs.heading < rhs.heading
			}
			let anyRow = orderedGroups.lazy.flatMap(\.rows).first
			let title = anyRow.map { titlesByArticleID[$0.annotation.articleID] ?? NSLocalizedString("Untitled", comment: "Fallback article title") }
				?? NSLocalizedString("Untitled", comment: "Fallback article title")
			let authors = anyRow.flatMap { authorsByArticleID[$0.annotation.articleID] ?? nil }
			return BookSection(bookOrArticleID: bookOrArticleID, title: title, authors: authors, chapterGroups: orderedGroups)
		}

		bookSections = Self.resort(sections: sections, by: sortOrder)
		isLoading = false
	}

	/// The outer (book) tier's ordering -- the one axis SortOrder
	/// actually controls (chapter order within a book is always reading
	/// order; see loadRows' chapterSortOrder). A static, pure function
	/// over already-built sections (not folded into loadRows) so
	/// switching SortOrder can re-sort the already-loaded bookSections
	/// in place (see the .onChange(of: sortOrderRawValue) handler in
	/// body) without a new account fetch, and so it's directly testable
	/// without constructing a view -- same reasoning
	/// AnnotationsListViewScopeTests gives for testing other static
	/// functions on this type directly.
	static func resort(sections: [BookSection], by sortOrder: SortOrder) -> [BookSection] {
		switch sortOrder {
		case .dateCreated:
			// Most-recently-annotated book first -- the max updatedAt
			// across every row in every chapter group belonging to that
			// book. This is the same "which book did I highlight in most
			// recently" ordering the pre-Part-11 fixed behavior gave,
			// now reachable as one SortOrder choice among three rather
			// than the only option.
			return sections.sorted { lhs, rhs in
				let lhsRecency = lhs.chapterGroups.lazy.flatMap(\.rows).map(\.annotation.updatedAt).max() ?? .distantPast
				let rhsRecency = rhs.chapterGroups.lazy.flatMap(\.rows).map(\.annotation.updatedAt).max() ?? .distantPast
				if lhsRecency != rhsRecency {
					return lhsRecency > rhsRecency
				}
				// Stable tiebreaker, same reasoning as the other two
				// cases below.
				return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
			}
		case .title:
			return sections.sorted { lhs, rhs in
				let comparison = lhs.title.localizedStandardCompare(rhs.title)
				if comparison != .orderedSame {
					return comparison == .orderedAscending
				}
				return lhs.bookOrArticleID < rhs.bookOrArticleID
			}
		case .author:
			// A section with no resolvable author name sorts after every
			// section that has one, rather than crashing to the front of
			// an alphabetical list on an empty string -- an unattributed
			// book isn't "before A", it just has nothing to sort by.
			return sections.sorted { lhs, rhs in
				switch (lhs.authors, rhs.authors) {
				case (nil, nil):
					return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
				case (nil, _):
					return false
				case (_, nil):
					return true
				case (let lhsAuthors?, let rhsAuthors?):
					let comparison = lhsAuthors.localizedStandardCompare(rhsAuthors)
					if comparison != .orderedSame {
						return comparison == .orderedAscending
					}
					return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
				}
			}
		}
	}

	/// Swipe-to-delete from the list. Mirrors WebViewController.deleteAnnotation's
	/// fix (docs/annotations.md, "Storage shape" -> "Applying edits"): a row
	/// carrying a text edit (originalText != nil) needs its replacement text
	/// reverted in the live DOM before the row disappears, or the edited
	/// wording stays stuck in the article even though the annotation is
	/// gone. This view has no reference to the open WebViewController (see
	/// this file's header comment -- navigation is always handed back to the
	/// presenter), so it hands the annotation to onDeleteAnnotation before
	/// removing the row and deleting the DB record, the same way
	/// onNavigateToAnnotation already threads a presenter callback through
	/// for the navigate case. The presenter (ArticleViewController.
	/// revertAnnotationDOMIfCurrentlyOpen) decides whether there's a live
	/// DOM to revert at all; the two Settings entry points that pass no
	/// onDeleteAnnotation are unaffected either way, since neither can have
	/// a WebViewController open behind them.
	private func delete(_ annotation: Annotation) {
		onDeleteAnnotation?(annotation)
		for sectionIndex in bookSections.indices {
			let updatedChapterGroups = bookSections[sectionIndex].chapterGroups.map { group in
				AnnotationGroup(
					key: group.key,
					heading: group.heading,
					rows: group.rows.filter { $0.annotation.annotationID != annotation.annotationID }
				)
			}.filter { !$0.rows.isEmpty }
			bookSections[sectionIndex] = BookSection(
				bookOrArticleID: bookSections[sectionIndex].bookOrArticleID,
				title: bookSections[sectionIndex].title,
				authors: bookSections[sectionIndex].authors,
				chapterGroups: updatedChapterGroups
			)
		}
		bookSections.removeAll { $0.chapterGroups.isEmpty }
		Task {
			await account.deleteAnnotation(annotationID: annotation.annotationID)
		}
	}
}

private struct AnnotationRow: View {

	let annotation: Annotation
	/// Comma-joined, sorted Author.name list for this row's article; nil
	/// when the article has no authors with a name. See
	/// AnnotationsListView.loadRows' authorsByArticleID.
	let articleAuthors: String?
	/// This row's article's preferred link. Only used by the containing
	/// view's "Copy Highlight" context menu action, not by this view's own
	/// body -- carried here so AnnotationsListView.rows(for:) has one row
	/// value to build both the display and the copy action from.
	let articleLink: String?

	@AppStorage(AppDefaults.Key.highlightPalette) private var highlightPaletteRawValue = HighlightPalette.default.rawValue
	@Environment(\.colorScheme) private var colorScheme

	private var highlightPalette: HighlightPalette {
		HighlightPalette(rawValue: highlightPaletteRawValue) ?? .default
	}

	/// Field-driven rendering, per the text-replacement feature's
	/// "Consolidated viewer" section: originalText/replacementText
	/// presence picks the row *style* (edit's compact one-liner vs. a
	/// highlight's full sentence context); hasHighlight overlays the
	/// color dot on whichever style that produced, so a row that's both
	/// a highlight and an edit still visibly carries its color; note
	/// presence adds the same note-preview line either way. No `kind`
	/// switch -- these three checks are independent, matching Annotation's
	/// own three-plain-fields storage shape (docs/annotations.md,
	/// "Storage shape").
	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			if annotation.hasHighlight {
				Circle()
					.fill(annotation.color.swiftUIColor(palette: highlightPalette, isDark: colorScheme == .dark))
					.frame(width: 12, height: 12)
					.padding(.top, 4)
			}

			VStack(alignment: .leading, spacing: 4) {
				switch annotation.rowStyle {
				case .edit(let originalText, let replacementText):
					editSummary(originalText: originalText, replacementText: replacementText)
				case .highlight:
					// No lineLimit here -- chapterTitle is now the section
					// header (AnnotationsListView.list), not a per-row
					// caption, so there's nothing else competing for
					// space in this row; truncating the one thing being
					// shown just hides context the row exists to
					// provide.
					Text(sentenceContext)
						.font(.callout)
						.foregroundStyle(.primary)
				}

				if let note = annotation.note, !note.isEmpty {
					// No lineLimit -- same reasoning as sentenceContext
					// above: a note is real user content, and a real
					// paragraph break the person typed shouldn't get
					// silently clipped to one visual line.
					Text(note)
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				if let articleAuthors {
					Text(articleAuthors)
						.font(.caption2)
						.foregroundStyle(.tertiary)
				}

				if annotation.orphanedAt != nil {
					Label(
						NSLocalizedString("Couldn't relocate this highlight", comment: "Annotation row: orphaned highlight caption"),
						systemImage: "exclamationmark.triangle"
					)
					.font(.caption2)
					.foregroundStyle(.orange)
				}
			}
		}
		.padding(.vertical, 4)
		// Dimmed, not hidden -- an orphaned annotation's note is still
		// real, saved user data (see markAnnotationOrphaned's doc comment
		// in WebViewController), so it stays visible and tappable (the
		// caller can still show the editor/article even if scrollToAnnotation
		// itself finds nothing to scroll to there).
		.opacity(annotation.orphanedAt != nil ? 0.5 : 1.0)
	}

	/// The compact one-line style for an edit row (originalText/
	/// replacementText both set): struck-through original text, then the
	/// inserted replacement. Deliberately not the full sentence-context
	/// style a highlight's own row shows -- per the plan's "Consolidated
	/// viewer" section, this is a scanning list, not a detail view; full
	/// context for an edit is available by tapping into it (opens
	/// AnnotationEditorView, same as tapping an existing highlight does
	/// today).
	private func editSummary(originalText: String, replacementText: String) -> some View {
		(
			Text(SentenceContext.normalizedForDisplay(originalText))
				.strikethrough()
				.foregroundStyle(.secondary)
			+ Text(" \u{2192} ")
				.foregroundStyle(.tertiary)
			+ Text(SentenceContext.normalizedForDisplay(replacementText))
				.foregroundStyle(.primary)
		)
		.font(.callout)
	}

	/// Wraps SentenceContext.sentence(quotePrefix:quoteExact:quoteSuffix:)
	/// (Modules/Articles -- see that type's own header comment for why the
	/// pure text/range math lives there, not here) in an AttributedString
	/// with this row's own palette/color-scheme-aware backgroundColor
	/// applied to the quote's range. Only used for the highlight-style row
	/// (see AnnotationRow.body's field-driven branch) -- an edit-only row
	/// uses the compact struck-through-original -> inserted-replacement
	/// style instead, which has no sentence context of its own.
	private var sentenceContext: AttributedString {
		let result = SentenceContext.sentence(quotePrefix: annotation.quotePrefix, quoteExact: annotation.quoteExact, quoteSuffix: annotation.quoteSuffix)
		var attributed = AttributedString(result.text)
		guard
			let quoteRange = result.quoteRange,
			let attrStart = AttributedString.Index(quoteRange.lowerBound, within: attributed),
			let attrEnd = AttributedString.Index(quoteRange.upperBound, within: attributed)
		else {
			return attributed
		}
		attributed[attrStart..<attrEnd].backgroundColor = annotation.color.swiftUIColor(palette: highlightPalette, isDark: colorScheme == .dark).opacity(0.3)
		return attributed
	}
}

/// Builds the string for the "Copy Highlight" context menu action:
///
///   "quote"
///   -author, chapter, link
///
///   "note"
///
/// Author is never omitted -- articleAuthors is optional at the model
/// level (an article can genuinely have none), so this falls back to
/// "Unknown" rather than printing a leading comma or a bare dash. Chapter
/// and link are each dropped from the attribution line, not printed
/// empty, when the article has no chapter title or no resolvable link.
/// The note block only appears when the annotation actually has a note --
/// quote-only (highlight-only) annotations copy as just the quote and
/// attribution line, no trailing empty block.
///
/// Internal, not private -- AnnotationsListView.rows(for:) is the only
/// call site today, but this is a pure function of its arguments with no
/// dependency on view state, so it's kept directly unit-testable via
/// `@testable import Nectar` (see CopyHighlightTextTests) rather than
/// folded into a private, untestable corner of the view.
func copyText(annotation: Annotation, articleAuthors: String?, link: String?) -> String {
	var lines = ["\"\(SentenceContext.normalizedForDisplay(annotation.quoteExact))\""]

	var attribution = ["-" + (articleAuthors ?? NSLocalizedString("Unknown", comment: "Annotation copy: unknown author fallback"))]
	if let chapterTitle = annotation.chapterTitle, !chapterTitle.isEmpty {
		attribution.append(chapterTitle)
	}
	if let link {
		attribution.append(link)
	}
	lines.append(attribution.joined(separator: ", "))

	if let note = annotation.note, !note.isEmpty {
		lines.append("")
		lines.append("\"\(note)\"")
	}

	return lines.joined(separator: "\n")
}
