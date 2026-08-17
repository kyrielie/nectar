# Annotations (highlights + notes)

Text highlighting and free-text notes attached to a highlighted range, for
HTML articles/chapters rendered through `WebViewController` /
`ArticleRenderer`. Every reading surface here is a `WKWebView` loaded with
rendered `template.html` — no EPUB, no PDF.

## Anchor model

Each `Annotation` stores a W3C Web Annotation Data Model–style selector: an
exact quote (`quoteExact`) plus a prefix/suffix of surrounding text
(`quotePrefix`/`quoteSuffix`, `CONTEXT_CHARS` = 200 chars each — wide
enough that the Swift side can usually recover the annotation's full
surrounding sentence, not just a short fragment, via `NLTokenizer`; see
"UI" below) for disambiguation, alongside a character-offset position
(`startOffset`/`endOffset`) into a `rootSelector`-scoped (default
`.articleBody`) canonicalized "whole text" of the document. Both are
stored together rather than either alone: position offsets break the
instant `contentHTML` changes at all; a quote-only search is *O(n)* on
every render and breaks silently if the same phrase appears twice.

Every annotation also carries `chapterTitle` (nullable): the nearest
preceding `<h1>`/`<h2 class="heading">`/`<h2 class="toc-heading">`
heading inside the same `rootSelector` root, at the time the selector was
last computed. See "Anchor resolution" below for how it's derived and why
it's scoped to `rootSelector` rather than the whole document.

## Database

`AnnotationsTable.swift` (`Modules/ArticlesDatabase`) is a new table inside
`ArticlesDatabase` — same file-per-account scoping as `articles`/
`statuses`/`bookState` (see `database.md`), created via
`runCreateStatements`, indexed on `articleID` and `bookKey`. `articleID` is
the anchor scope (a highlight only means something against the specific
rendered text it was drawn against); `bookKey` is resolved at write time
(`ArticlesTable.saveAnnotationAsync`, via `bookKeysForArticleIDs` — the
same helper the read/starred/loved propagation path uses) and carried
alongside purely so a cross-chapter "all highlights in this book" listing
can group without a join through `articles` on every query. A `nil`
`bookKey` (unresolvable, same rare case `book-identity.md` describes)
still leaves the annotation fully functional; it just won't appear in
book-level grouping.

`chapterTitle` (schema version 3) was added later via a
`containsColumn`-guarded `ALTER TABLE annotations add column chapterTitle
TEXT;`, the same backward-compatible pattern `bookKey` itself established
— not baked into the original `CREATE TABLE`. Existing annotations get
`chapterTitle = nil` until the next time they're opened/re-anchored,
self-healing the same way an upgraded `quotePrefix`/`quoteSuffix` capture
window does (see "Anchor resolution").

`orphanedAt`/`lastReanchoredAt` track anchor-resolution health — an
annotation whose quote can't be relocated is marked orphaned, never
dropped.

Public surface: `ArticlesDatabase.swift`'s `saveAnnotation`,
`deleteAnnotation`, `updateAnnotationNote`, `updateAnnotationColor`,
`markAnnotationOrphaned`, `reanchorAnnotation`, and three fetch variants
(`fetchAnnotations(articleID:)`, `fetchAnnotations(bookKey:)`,
`fetchAllAnnotations()`), mirrored on `Account.swift` with the same
async/`@MainActor` shape as `saveScrollPosition`/`fetchScrollPosition`.

`Annotation` itself (the `Codable`, `Sendable` value type) lives in
`Modules/Articles`, not `ArticlesDatabase` — same reasoning as `Article`
itself: it's consumed directly by UI code that shouldn't need to link the
database module.

## Anchor resolution (`annotations.js`)

Cross-platform logic in `Shared/Article Rendering/annotations.js`, loaded
as a `WKUserScript` alongside `main.js`/`main_ios.js`/`newsfoot.js`
(`WebViewConfiguration.installArticleScripts`) — its own file rather than
folded into either, since it's a large, independent, cross-platform
concern.

1. `buildTextIndex` walks `document.querySelector(rootSelector)` with a
   single `TreeWalker` (`NodeFilter.SHOW_TEXT`) pass, building the root's
   full inner text plus a parallel `{node, start, end}` table — the same
   walker idiom `main.js`'s `applyVersalCaps` and `main_ios.js`'s `Finder`
   already use.
2. `resolveAnnotation` tries the stored `[startOffset, endOffset)` first;
   if `text.slice(start, end) === quoteExact`, resolution is done. If not,
   it searches the full text for every occurrence of `quoteExact`
   (`findAllOccurrences`). Zero matches → orphaned. One match → use it,
   offsets corrected. Multiple matches → `scoreCandidate` ranks each by
   prefix/suffix similarity against the stored selector; the best match
   above `SIMILARITY_FLOOR` (0.5) wins, otherwise the annotation is
   orphaned rather than guessing wrong.
3. `wrapRange` maps a resolved offset range back to real DOM node/offset
   pairs via the same cumulative-offset table, splits text nodes at both
   boundaries (`Text.splitText`, `applyVersalCaps`'s technique), and wraps
   each contained text node in `<mark class="nnw-highlight"
   data-annotation-id="...">` — a range crossing an inline element or
   paragraph boundary wraps each contained node individually rather than
   collapsing to `textContent`. This is DOM mutation, not an overlay: it
   survives reflow for free and gives a real tappable element for the
   note-icon affordance. `main_ios.js`'s `Finder`
   (`highlightRects`/`FinderResult`) uses a different, overlay-`<div>`
   technique for find-in-page — right for that ephemeral, no-tap-target
   case, not reused here.
4. `renderAnnotations` runs this for every annotation on a render,
   unwrapping-then-rewrapping each (so a moved highlight never leaves a
   stale duplicate `<mark>` at its old position), and returns a single
   `{moved, orphanedIDs}` report per call rather than posting per-annotation
   — keeps the bridge chatty-message count bounded on chapters with many
   highlights.
5. `chapterTitle` is derived by `buildHeadingIndex`/`nearestChapterTitle`
   at the same two points `quotePrefix`/`quoteSuffix` are computed:
   initial capture (`selectorForRange`) and every re-anchor
   (`renderAnnotations`'s reanchor branch — a reanchored offset can cross
   a chapter boundary in a heavily-edited chapter, so this is recomputed
   on reanchor, not just on first save). `buildHeadingIndex` matches
   `h1, h2.heading, h2.toc-heading` — the same selector `main_ios.js`'s
   `tocNodes()` uses for the table-of-contents feature, duplicated locally
   rather than imported (this file is cross-platform and doesn't assume an
   iOS-only script ran first; see the `toBase64`/`fromBase64` note below)
   — then maps each matched heading to a text offset within the *same*
   `rootSelector`-scoped index the rest of the selector was resolved
   against, and `nearestChapterTitle` picks the last heading at or before
   a given offset.

   This is deliberately scoped to `rootSelector` (default `.articleBody`),
   not `document`: `template.html` renders a separate, chrome-level
   `<h1>` inside `.articleTitle` (the feed-item title link), *outside*
   `.articleBody` — `tocNodes()`'s document-wide query also matches that
   `<h1>`, but scoping `buildHeadingIndex` to `rootSelector` naturally
   excludes it, so an ordinary single-heading book (its own in-body title,
   per Calibre's export shape — see `tocNodes()`'s own comment) yields
   `chapterTitle` equal to that one in-body heading, not `null` and not
   the chrome title. It also keeps heading offsets and annotation
   offsets in the same coordinate space, since both come from one
   `buildTextIndex(root)` call rather than two differently-scoped ones.

Re-anchoring has no separate scheduled job or explicit database-side hook
into the `pendingUpdateContentHTML`/ordinary-`changesFrom` content-mutation
paths (`database.md`, "Migrations of note"): it's a side effect of normal
rendering. `WebViewController.loadAndRenderAnnotations()` calls
`Annotations.renderAnnotationsEncoded` on every render (after
`DOMContentLoaded`), decodes the returned report, and persists corrected
offsets and `chapterTitle` via `account.reanchorAnnotation` for anything
reported `moved`, or `account.markAnnotationOrphaned` for anything in
`orphanedIDs`. Since this runs unconditionally on every render, both the
AO3 pending-update-apply path and ordinary feed-refresh content changes
are covered by the same call site without needing to hook either
explicitly.

## Message bridge

`WebViewController`'s `MessageName` struct has two new cases (registered/
removed in the same paired `add`/`removeScriptMessageHandler` blocks as
the other five): `textWasSelected` (fired on debounced `selectionchange`
when the selection is non-empty and inside `.articleBody`; payload is the
selection's bounding rect, used to anchor `HighlightColorPopover`) and
`annotationWasTapped` (fired when a `<mark class="nnw-highlight">` is
tapped; payload is `data-annotation-id`, opens the note editor). There is
no separate `annotationsDidReanchor` message case — the re-anchor report
is returned synchronously from the `evaluateJavaScript` call to
`renderAnnotationsEncoded` instead, avoiding a third message-handler case
for something that already has a natural call/response shape.

`addHighlightFromSelection` (called right after a color is picked) and
`renderAnnotationsEncoded` both use the existing
base64-encode-the-JSON-argument convention (`getTableOfContents`/
`updateFind`), through `Annotations`' own `toBase64`/`fromBase64` helpers
— self-contained rather than reused from `main_ios.js`, since this file is
cross-platform and can't assume an iOS-only script ran first.

## UI

- **Selection → highlight**: `annotations.js` posts `textWasSelected`;
  `WebViewController` presents `HighlightColorPopover` (SwiftUI, hosted via
  `UIPopoverPresentationController`) with five color swatches plus a note
  icon. Tapping a swatch calls `Annotations.addHighlightFromSelection`,
  which draws the `<mark>` immediately and returns the computed selector
  for `WebViewController` to persist via `account.saveAnnotation` — no
  round trip before the highlight is visible. Tapping the note icon does
  the same, then opens the note editor immediately.
- **Note editor**: `AnnotationEditorView` (SwiftUI, half-sheet via
  `UIHostingController`), reachable both from the note-icon path (fresh
  annotation) and from tapping an existing `<mark>`
  (`annotationWasTapped`). Shows the read-only quote, a note field, the
  five color swatches, and a destructive delete (with confirmation).
  Delete calls `Annotations.removeAnnotationHighlight` (unwraps the
  `<mark>`, `normalize()`s the affected text nodes) before
  `account.deleteAnnotation`.
- **Color palette**: five fixed colors (`Annotation.Color`: yellow, red,
  green, blue, purple), stored as a palette key, not a hex value. Resolved
  at render time via CSS custom properties in `core.css`
  (`mark.nnw-highlight[data-color="..."]`) so each theme can supply its
  own hex set; `HighlightColorPopover.swiftUIColor` mirrors the same five
  hex values in SwiftUI, kept in sync manually since there's no shared
  source of truth between CSS custom properties and SwiftUI `Color`.
- **Toolbar button**: `ArticleToolbarToggle` (`iOS/AppDefaults.swift`)
  has an `.annotations` case, backed by
  `AppDefaults.shared.articleToolbarShowAnnotations` (default `false`,
  opt-in). `ArticleViewController.annotationsBarButtonItem` calls
  `showAnnotationsList(_:)` directly, pushing `AnnotationsListView`
  scoped to the current article's book (`.book(bookKey:)`) — there is no
  toolbar menu with multiple scope choices; that was an earlier design
  this doc previously (incorrectly) described.
- **Annotations list**: `AnnotationsListView` (SwiftUI), one implementation
  for all three scopes (`.article`, `.book`, `.everything`) — only the
  underlying `Account` fetch method differs. Groups are keyed by
  `articleID`; for a non-anthology book (one Ambrosia JSON Feed item per
  work, per `ambrosia-feed.md`) that's always exactly one group, so the
  section header is suppressed and the nav bar's `article.title` is the
  only place the book title appears. Rows show a color dot; the full
  sentence surrounding the highlight (reconstructed from
  `quotePrefix`/`quoteExact`/`quoteSuffix` via `NLTokenizer(unit:
  .sentence)`, with just the `quoteExact` portion given a
  `annotation.color`-tinted background wash — not the raw, potentially
  mid-sentence `quoteExact` slice on its own); the note preview; a
  `chapterTitle` caption, shown only when it's non-empty and differs from
  the group's own book title (suppresses the common case where a
  single-heading book's one heading just repeats the title already shown
  in the nav bar/section header — see "Anchor resolution" for why that's
  usually `nil` or equal rather than something else). No per-row
  timestamp or repeated book title — both were dropped as redundant with
  the nav bar/section header. Orphaned annotations (`orphanedAt != nil`)
  appear dimmed with a "couldn't relocate this highlight" caption rather
  than being hidden.
  Tapping a row hands the chosen `Annotation` back via
  `onNavigateToAnnotation` — the caller (either
  `ArticleViewController.navigateToAnnotation` or
  `SettingsViewController.navigateToAnnotationFromSettings`) decides
  whether that's a same-article `scrollToAnnotation` call or a
  cross-article `SceneCoordinator.selectArticleDirectly` navigation
  followed by one. `SceneCoordinator.currentArticleViewController` exposes
  the currently-pushed `ArticleViewController` read-only, specifically so
  the Settings entry point (which has no `ArticleViewController` of its
  own) can delegate to `navigateToAnnotation(_:account:)` rather than
  re-deriving the same `awaitNextPageLoad`-then-scroll sequence.
- **Settings entry point**: `ArticlesRow.annotations` in
  `SettingsViewController` pushes `AnnotationsSettingsView` (SwiftUI),
  containing the unscoped `AnnotationsListView` (using the first account —
  Nectar's usual shape is one local account, per `ambrosia-feed.md`), the
  toolbar-button toggle, the default color picker, and the two export
  rows below.

## Export

- **CSV**: `AnnotationCSVExporter.swift` (`Shared/Exporters`), same shape
  as `ArticleCSVExporter.swift` — a `columnHeaders` array (`book`,
  `chapter`, `quote`, `note`, `color`, `created`, `link`) and a
  `CSVString(with:)` static function taking `[(Annotation, Article?)]`
  (paired with the owning `Article` for book title and link, which live
  on `Article`, not `Annotation`). The `chapter` column prefers
  `annotation.chapterTitle` (real per-annotation data as of schema
  version 3) and falls back to the book title (`article?.title`) only
  when `chapterTitle` is `nil` — an annotation made before `chapterTitle`
  existed and not yet re-anchored, or a genuinely single-heading book
  with no distinct chapter to report. Before `chapterTitle` existed this
  column was always `article?.title` — i.e., the book title, mislabeled
  as chapter. Both `ArticleCSVExporter` and `AnnotationCSVExporter` call
  the shared `CSVFormatting.rowString`/`.escapedField`
  (`Shared/Exporters/CSVFormatting.swift`), pulled out so the same
  escaping rules aren't hand-rolled twice.
  `SettingsViewController.exportAnnotationsCSVDocumentPicker` fetches
  every annotation via `account.fetchAllAnnotations()`, resolves each
  one's owning `Article` by `articleID`, and writes through the same
  temp-file → `UIDocumentPickerViewController` tail end as
  `exportArticlesCSVDocumentPicker`.
- **SQLite**: `ArticleSQLiteExportTable.copyItems` (`Modules/ArticlesDatabase`)
  has a third `CREATE TABLE ... AS SELECT`, joined against the just-created
  `articles` export the same way `statuses` already is — an annotation
  only exports if its owning article does, so a feed-scoped export never
  leaks annotations outside that scope. This means the existing
  `exportArticlesSQLite` path picks up annotations automatically,
  `chapterTitle` included (`SELECT an.*` — a new annotations column
  requires no export-side change to be included); there is no separate
  annotations-only SQLite export UI.

## Ambrosia integration

Local-only, matching every other piece of local article state (starred,
scroll position) — annotations work fully offline. Ambrosia today is a
read-only pull source (`ambrosia-feed.md`); there is no push channel from
Nectar back to Ambrosia for anything, annotations included, and none was
added as part of this feature. A future push-sync phase (keyed by
`bookKey` + the stored quote/prefix/suffix selector, since raw offsets are
meaningless against a different device's independently-fetched copy of
the same chapter's HTML) would need a new Ambrosia-side route and is not
in scope here — that's a change to a server not in this repository.

## Tests

- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/AnnotationsTableTests.swift`:
  save/fetch round-trip (including `chapterTitle`, both a set value and
  `nil`), scoping by articleID/bookKey/unscoped, note/color partial
  updates, delete, orphan/reanchor lifecycle (`reanchor` writing
  `chapterTitle` alongside corrected offsets, including clearing it back
  to `nil`).
- `Tests/JS/annotations/anchor-resolution.test.js`,
  `selection-capture.test.js`: headless coverage of the pure
  text/DOM-offset algorithm pieces exposed via `Annotations._internal`,
  including `buildHeadingIndex`/`nearestChapterTitle` (root-scoping vs.
  chrome-level headings outside `.articleBody`, nearest-preceding-heading
  selection, `null` before any heading), `chapterTitle` appearing in both
  `selectorForRange`'s/`addHighlightFromSelection`'s selector and
  `renderAnnotations`'s `moved` report entries, and `CONTEXT_CHARS`
  self-healing (a reanchor always recaptures at the current width, never
  reusing whatever narrower length an existing annotation's stored
  `quotePrefix` happens to be).
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ArticleSQLiteExportTableTests.swift`
  covers the annotations-export join scoping alongside the pre-existing
  feedID/statuses-join/destination-exists cases.
