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

### Storage shape: highlights and text edits share one row

Starting at schema version 5, `annotations` also carries `hasHighlight`
(`BOOL NOT NULL DEFAULT 1`), `originalText` (nullable `TEXT`), and
`replacementText` (nullable `TEXT`) — the local diff/override layer a
manual text edit (and, eventually, rule-driven replacement) is built on
top of. These live in the same table as highlights, not a sibling table:
the required capability set (exportable, browsable, notable, reversible)
is exactly what `annotations`/`AnnotationsListView`/
`AnnotationCSVExporter` already provide.

`hasHighlight` and `originalText`/`replacementText` are independent
facts about a row, not an exclusive `kind` choice — a single row can be
a highlight, a text edit, or both at once. `Annotation` has no `Kind`
enum; it's three plain fields (`hasHighlight: Bool`, `originalText:
String?`, `replacementText: String?`), matching the schema directly.
**Validity rule:** a row must have `hasHighlight == true` OR
`originalText != nil`. A row with neither has no visual or functional
meaning and is never persisted — unchecking "keep highlight" on a row
with no edited text simply deletes the row via the existing
delete-highlight flow (`AnnotationEditorView`'s destructive action),
rather than writing an empty one.

The canonical stored article text never changes for an edit row, the
same way it never changes for a highlight — `originalText`/
`replacementText` describe a *replacement* applied at render time, not a
rewrite of `contentHTML`. An edit row's `quoteExact`/`quotePrefix`/
`quoteSuffix`/`startOffset`/`endOffset` describe the *replaced span*'s
location in the original-stored-text coordinate space, resolved by the
exact same anchor-resolution machinery described below.

**Applying edits.** `renderAnnotations` (`annotations.js`) applies every
row with `originalText`/`replacementText` set via `applyTextEdit` —
extracted, along with `wrapRange`'s node-walking/splitting logic, into a
shared `resolveDOMRange(entries, startOffset, endOffset)` helper that
both `wrapRange`/`wrapDOMRange` (highlighting) and `applyTextEdit`
(editing) build on, rather than duplicating the boundary math. A row that
is both a highlight and an edit (`hasHighlight == true` and
`originalText` set) runs `applyTextEdit` first, then immediately wraps
the *same returned Range* in `<mark>` via `wrapDOMRange` — not
re-resolved against the post-edit DOM a second time, since the range
`applyTextEdit` already located points exactly at the new text.

An edit-only row (`hasHighlight == false`, `originalText` set) gets the
same treatment but wraps in a plain, unhighlighted
`<span class="nnw-edit-only" data-annotation-id="...">` instead of
`<mark class="nnw-highlight">` — `wrapEditOnlyDOMRange`, sharing the same
node-collection step (`collectRangeTextNodes`) `wrapDOMRange` uses.
Without this wrapper the corrected text would render as a bare `Text`
node once its highlight is turned off: nothing for `handleAnnotationTap`
or `scrollToAnnotation` to find, so the row would be untappable from the
article itself (only reachable via the annotations list). Every
lookup-by-`annotationID` in this file — `unwrapAnnotation` (before a
re-render), the click handler, `scrollToAnnotation` — goes through
`annotationWrapperSelector(annotationID)`, a combined
`mark.nnw-highlight[...], span.nnw-edit-only[...]` selector, so it finds
whichever wrapper kind a given row currently has without needing to know
its `hasHighlight` in advance. `core.css`'s `span.nnw-edit-only` rule sets
`cursor: pointer` and includes the same `nnw-highlight-flash` animation
as `mark.nnw-highlight`, but deliberately no background-color or other
highlight-like styling — a visual highlight there would make turning
"keep highlight" off indistinguishable from leaving it on.

Saving an edit from `AnnotationEditorView` (see "Manual edit UI" below)
first calls `Annotations.computeTextEditPlanEncoded` — a non-mutating,
JS-side pre-flight over the live, already-rendered DOM that either
reports an overlap (`{status: "overlap", conflictingAnnotationID}`) or
computes every other annotation row's shifted anchor
(`{status: "ok", delta, shifted: [...]}`) for rows whose span lies at or
after the edit's end offset, in the original coordinate space. Any row
whose range *overlaps* the edited span blocks the edit at creation time
("can't edit text that's part of an existing highlight or another edit
— remove or resize it first") rather than silently orphaning it — a
manual edit's own span never conflicts with itself, since that's the
highlight's own span it was created against; only *other* rows are
checked. `WebViewController.saveTextEdit(annotation:replacementText:
keepHighlight:account:)` persists the result:
`account.setAnnotationEditFields` for the edited row's own
`hasHighlight`/`originalText`/`replacementText`, then
`account.reanchorAnnotation` for every shifted row, in descending-offset
order (rightmost/latest first) so an earlier row's write is never
computed relative to a not-yet-applied later shift —
`TextReplacementOffsetShift.descendingApplicationOrder` exists in
`Modules/Articles` for exactly this ordering requirement, pure and
independently testable, alongside `shiftedAnchors`/
`shiftedAnchorsForRevert`/`firstOverlap`, the Swift-side counterparts to
the same arithmetic `computeTextEditPlan` performs in JS. Each shifted
row's `quoteExact`/`quotePrefix`/`quoteSuffix`/`chapterTitle` are
re-sliced against the simulated post-edit text by
`computeTextEditPlan` itself (reusing `buildHeadingIndex`/
`nearestChapterTitle` for the `chapterTitle` recompute, the same
functions the ordinary re-anchor path uses) — not recomputed a second
time on the Swift side. Once every write lands,
`loadAndRenderAnnotations()` re-renders: the actual DOM mutation
(`applyTextEdit`) happens there, not in `saveTextEdit` itself.

Unchecking then re-checking "keep highlight" on the same row does not
lose the row's color — `hasHighlight` toggles independently of `color`,
which is only ever cleared by deleting the row entirely.

### Rule-driven replacement (categories 1 and 3)

`TextReplacementRuleTable`/`TextReplacementRuleEngine`
(`Modules/Articles/Sources/Articles/TextReplacementRuleTable.swift`) are
the shared matching engine behind two of the four edit categories the
feature's own plan defines: automatic safe fixes (a shipped,
person-editable typo table — `TextReplacementRuleTable.defaultTypoTable`)
and reader-insert/word replacement (`Y/N`/`F/N`-style placeholders —
`.defaultReaderInsertTable`). Both are plain `[TextReplacementRule]`
lists (`input`: comma-separated tokens; `output`: the replacement),
matched word-boundary (`\btoken\b`) and case-insensitively against a
plain `String` — pure and storage-agnostic, no `ArticlesDatabase`/JS
dependency, the same reasoning `TextReplacementOffsetShift` lives in this
module for.

**A rule whose `output` is empty never matches at all** —
`defaultReaderInsertTable` ships with empty `output`s deliberately (there
is no sensible global default for a reader's own name), so an unfilled
row is inert by construction rather than merely a no-op replacement.

**Cross-rule overlap**: if two rules' tokens would match overlapping
spans, the earlier rule in the table's `rules` array wins for that span
and the later rule's candidate is dropped — table order decides the
winner, not text order or span width (see
`TextReplacementRuleTableTests.overlapWinnerIsDeterminedByTableOrderNotSpanWidth`).

**A parenthesized token never matches.** `\b` is a transition between a
word and a non-word character; `(`/`)` are themselves non-word, so `\b`
can't anchor between a preceding space and an opening paren (both
non-word) — a configured rule like `(Y/N)` therefore matches nothing,
silently, regardless of escaping. `defaultReaderInsertTable`'s
parenthesized token variants (`(Y/N)`, `(F/N)`, `(G/N)`, `(Y/L/N)`,
`(L/N)`) are consequently dead weight in the shipped table; only the
bare forms (`Y/N`, `F/N`, `G/N`, `Y/L/N`, `L/N`) ever match anything.
Confirmed via
`TextReplacementRuleTableTests.parenthesizedTokenNeverMatchesBecauseWordBoundaryFailsOnPunctuation`
— flagged here as a known, currently-shipped gap rather than silently
worked around, since fixing it (stripping the parens from the defaults,
or loosening the boundary rule) is a product decision, not just a code
fix.

### Quote conversion (category 2)

`TextReplacementQuoteConversion`
(`Modules/Articles/Sources/Articles/TextReplacementQuoteConversion.swift`)
converts British-style single-quote dialogue (`'like this'`) to American
double-quote dialogue (`"like this"`). Deliberately **not** built on
`TextReplacementRuleTable`/`TextReplacementRuleEngine` — the `'` glyph is
identical between a dialogue quote mark and an apostrophe (`don't`,
`Sarah's`), so a token find/replace would corrupt every contraction and
possessive in the document. Instead this does real balanced-pair
detection: a candidate *opening* `'` is one at the start of the text or
preceded by whitespace, opening punctuation (`(`, `"`, `"`, `—`, `-`), or
a paragraph boundary; a candidate *closing* `'` is one followed by
whitespace, terminal punctuation, closing punctuation, or the end of the
text. A `'` that's neither (e.g. the one in `it's`, followed by `s`) is
never treated as a pair boundary, so contractions/possessives are never
matched — not filtered out afterward, never proposed as a candidate in
the first place. Pairing is greedy, left to right, nearest-subsequent-
closer, non-overlapping; a nested `'She said "hello" to me'` converts
only the outer `'...'` pair, since the inner content is already `"..."`
and untouched. Produces the same `TextReplacementMatch` shape
`TextReplacementRuleEngine` does, so a caller treats both categories'
output identically once matches are found — only the *finding* differs.
See `TextReplacementQuoteConversionTests.swift` for the dedicated corpus
(nested quotes, adjacent contraction/quote boundaries, an unpaired `'`).

### Auto-apply on open

`WebViewController.applyTextReplacementRulesIfNeeded()` runs before
`loadAndRenderAnnotations()` on every page load, gated by
`AppDefaults.shared.textReplacementApplyAutomatically` (the Settings
screen's master toggle, default **on**). It's a one-time pass per
article, not a repeated one: it first checks whether any existing
annotation row is already a rule-driven match
(`!hasHighlight && originalText != nil`), and returns early if so — this
covers both "already applied, don't duplicate" and "a person reverted a
match, don't silently resurrect it," since both leave that same
signature behind (a still-present reviewable row, or the absence of one
after a deliberate revert either way skips re-running).

Assembles one combined `TextReplacementRuleTable` from the typo table
(only if `textReplacementTypoFixesEnabled`), the reader-insert table, and
the custom table, in that order, then finds matches via
`TextReplacementRuleEngine.findMatches`. Quote conversion (if
`textReplacementQuoteConversionEnabled`) is found independently
afterward — per the plan, it's a deliberately separate transform, not
folded into the shared engine — and any quote-conversion candidate that
overlaps a rule-table match is dropped in favor of the rule-table match:
a rule a person explicitly configured is treated as more specific/
intentional than a blanket style pass, when the two disagree on the same
span.

Matches apply in descending offset order (same reasoning as manual
edits/`TextReplacementOffsetShift.descendingApplicationOrder` — see
"Applying edits" above), each becoming its own `Annotation` row with
`hasHighlight = false`, `originalText`/`replacementText` set from the
match, and `quotePrefix`/`quoteSuffix` captured at `CONTEXT_CHARS` (200)
around the match the same way `selectorForRange` does on the JS side —
populated here in Swift against the same text the offsets were found in,
not left empty, so `resolveAnnotation`'s disambiguation has something to
work with if this quote ever needs multi-match resolution on a later
render.

**No one-time summary UI exists yet.** The plan's "12 replacements
made — review in Edit History" notification (see "Confirmation policy"
in the feature's own plan) is a `Self.logger.debug` line only — no
toast/banner mechanism was found anywhere in this codebase to hook into,
and building one is out of scope for the pass that added this trigger.
Anyone landing that UI later should replace the debug log call site,
not add a second one.

### Settings screen

`TextReplacementSettingsView` (`iOS/Article/Annotations/`), pushed from
`SettingsViewController`'s Articles section (`ArticlesRow.textReplacement`)
via `makeSurfacePaletteAwareHostingController` — see `settings-screen.md`.
Five sections, in order: the master "Apply Automatically on Open" toggle;
Reader-Insert Names (the `Y/N`-style table, `AppDefaults.shared.
textReplacementReaderInsertTable`, with a per-work override entry point
below it — see "Per-work override" below); Style Corrections (typo fixes
and British-to-American quotes toggles, the latter with footer copy
clarifying it converts dialogue marks specifically, not every
apostrophe); Custom Rules (a person's own `in`/`out` pairs,
`textReplacementCustomTable`); and Edit History (a count of rows with
`originalText != nil`, disclosure into `AnnotationsListView` with
`scope: .everything` — see "Consolidated viewer" below).

### Per-work override

`TextReplacementPerWorkOverride` (`Modules/Articles`) is a person-editable
`[bookKey: TextReplacementRuleTable]` map, layered ahead of (never
replacing) the global reader-insert table via
`mergedReaderInsertTable(forBookKey:global:)` — the override's rows are
prepended to the global table's rules, so `TextReplacementRuleEngine`'s
existing "earlier rule wins for an overlapping span" rule gives the
override precedence for free, while any token the override doesn't
mention still falls through to the global table unchanged. Pure and
storage-agnostic, same reasoning as `TextReplacementRuleTable`/
`TextReplacementOffsetShift`; persisted via `AppDefaults.shared.
textReplacementPerWorkOverride`, same Codable-in-`UserDefaults` pattern
as the other three tables. `WebViewController.applyTextReplacementRulesIfNeeded`
assembles the per-work override ahead of the global reader-insert table
when building the rule table to match against.

Scoped to the reader-insert-names category only — the typo/quote-conversion
categories have no per-work variant, since a fandom-specific naming
convention is the only category where a global default can be actively
wrong for one particular work.

`TextReplacementPerWorkOverrideView` (`iOS/Article/Annotations/`) is the
editor screen, scoped to one `bookKey`, reached via a `NavigationLink`
from `TextReplacementSettingsView`'s Reader-Insert Names section.
Surfaced whenever a "current work" is resolvable at all —
`SettingsViewController` resolves it from
`RootSplitViewController.coordinator.currentArticleViewController?.article`,
the same lookup `navigateToAnnotationFromSettings` already uses for a
different purpose — rather than any fandom/tag-matching heuristic; nil
(no article currently open behind Settings) simply hides the row.

### Consolidated viewer

`AnnotationsListView` (`iOS/Article/Annotations/`) has one `This Book`/`All`
tab switcher (a segmented `Picker` bound to `selectedScope`), not two
separate screens or a fixed scope per entry point. `scope` at `init` only
decides which tab a freshly-opened screen starts on:
`ArticleViewController.showAnnotationsList` passes `.book(bookKey:)`
(opens on `This Book`); the Settings entry points
(`TextReplacementSettingsView`'s Edit History row, `AnnotationsSettingsView`)
pass `.everything` (opens on `All`). Either tab is reachable from either
entry point once the screen is open, except when there's no book in
context at all (the Settings case) — there, `showsTabSwitcher` is `false`
and only `All` is offered, since there is no book for `This Book` to mean.
`bookKey` (the screen's own fixed book identity, when known) is retained
independently of `selectedScope` so switching to `All` and back to
`This Book` doesn't lose which book `This Book` refers to.
`resolvedBookKey(for:)`/`showsTabSwitcher(bookKey:)` are static functions
rather than instance-only logic, so `AnnotationsListViewScopeTests` can
exercise this mapping without constructing a whole view (constructing one
needs a real `Account`, which this test target has no working path to).

`AnnotationRow` renders field-driven, via `Annotation.rowStyle`
(`Modules/Articles`): `originalText`/`replacementText` both set picks the
compact struck-through-original → inserted-replacement one-liner;
otherwise the row falls back to the existing full-sentence-context style.
`hasHighlight` independently decides whether the color dot is drawn,
regardless of which style `rowStyle` picked — so a row that's both a
highlight and an edit shows the edit's compact style with the highlight's
color dot layered on top. `note` presence adds the same note-preview line
either way. These three checks are independent, matching `Annotation`'s
own three-plain-fields storage shape (see "Storage shape" above) — there
is no `Kind` switch anywhere in this rendering path.

The sentence-reconstruction logic itself — given
`quotePrefix`/`quoteExact`/`quoteSuffix`, find the surrounding sentence and
the quote's location within it — lives in `SentenceContext`
(`Modules/Articles`), extracted out of what used to be `AnnotationRow`'s
own private `sentenceContext` computed property. `SentenceContext` returns
plain `String`/`Range<String.Index>`, not `AttributedString`: this module
has no SwiftUI/UIKit dependency (see `TextReplacementRuleTable`'s own
`Package.swift` reasoning), so `AnnotationRow` itself still owns wrapping
the result in `AttributedString` and applying its own
palette/color-scheme-aware `backgroundColor`.

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
window does (see "Anchor resolution"). `hasHighlight`/`originalText`/
`replacementText` (schema version 5) followed the same pattern — see
"Storage shape" above; `hasHighlight` defaults every pre-migration row to
`true` at the SQL level, so no backfill pass was needed for it.

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

   **`wrapDOMRange`'s single-text-node fast path.** A `Range`'s
   `commonAncestorContainer` is itself a `Text` node whenever the whole
   range sits inside one text node without crossing an inline element or
   paragraph boundary — the common case for a short highlight or edit.
   `wrapDOMRange` used to root a `TreeWalker` directly at
   `commonAncestorContainer` unconditionally; a `TreeWalker` only ever
   visits *descendants* of its root, never the root itself, so when that
   root is a childless `Text` node the walker visits nothing and the call
   silently wraps zero nodes — no error, no orphan report, the highlight
   or edit's `<mark>` just never appears. Fixed by checking
   `commonAncestorContainer.nodeType === 3` (`Node.TEXT_NODE`, used as a
   raw constant rather than referencing the global `Node` object, since
   `Node` has never been one of this file's explicitly-passed-in
   environment globals the way `NodeFilter`/`CSS` are) first and wrapping
   that node directly via the shared `wrapTextNode` helper, before falling
   through to the general multi-node `TreeWalker` path. Most visible after
   `applyTextEdit` runs immediately before a composed edit-plus-highlight
   wrap (see "Applying edits" above) — the freshly-inserted replacement
   `Text` node is exactly this single-node case — but the bug applied to
   any single-text-node `wrapRange` call, edit-related or not. Regression
   coverage:
   `Tests/JS/annotations/text-replacement-edit-application.test.js`'s "a
   lengthening replacement shifts a later, unrelated highlight's rendered
   position" test, confirmed to fail without this fix and pass with it.
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

**Fullscreen safe-area fix.** `textWasSelected(body:)` converts the
selection rect JS reports into this view controller's coordinate space
via `adjustedY = y + webView.safeAreaInsets.top`, read synchronously.
While in fullscreen reading mode, `hideBars()` now calls
`updateTopSafeAreaForFullScreen()` — a top-side mirror of the pre-existing
`updateBottomSafeAreaForFullScreen()` — so this inset is correct
synchronously rather than depending on the reactive
`viewSafeAreaInsetsDidChange` path, which previously left it stale for a
beat after entering fullscreen and could shift `HighlightColorPopover`'s
`sourceRect` for a short selection entirely outside `view.bounds` (a
longer selection's taller rect usually still overlapped `view.bounds`
despite the same shift, which is why this specifically read as "single-word
selections don't highlight in fullscreen"). `showBars()` resets
`additionalSafeAreaInsets.top = 0`, symmetric with `.bottom`.
`presentHighlightColorPopover` also now defensively clamps `sourceRect`
to `view.bounds` via `CGRect.clamped(toBounds:)` (`Modules/RSCore`,
`Geometry.swift`) before presenting, independent of the fix above —
degrades to "popover anchors at the nearest valid edge" instead of
silently never presenting if this class of drift recurs elsewhere later.
Pulled into `RSCore` (rather than left as a private method on
`WebViewController`) specifically so it's directly testable without a
`UIViewController`/`UIPopoverPresentationController` in the loop — see
`CGRectClampedToBoundsTests`.

## UI

- **Selection → highlight**: `annotations.js` posts `textWasSelected`;
  which of three creation methods `WebViewController.textWasSelected`
  dispatches to depends on `AppDefaults.shared.annotationCreationMethod`
  (`AnnotationCreationMethod`: `.popup`, `.nativeMenu`, `.off` — default
  `.popup`, chosen via `AnnotationsSettingsView`'s picker, see "Settings
  entry point" below):
  - `.popup` presents `HighlightColorPopover` (SwiftUI, hosted via
    `UIPopoverPresentationController`) with two or three color swatches
    — the person's default color (`AppDefaults.shared.defaultAnnotationColor`)
    plus fixed blue and red as quick alternates, de-duplicated if the
    default is itself blue or red. Not all five `Annotation.Color`
    cases, and no note-entry affordance here at all.
  - `.nativeMenu` injects a "Highlight" item into `WKWebView`'s own
    native text-selection menu instead (`PreloadedWebView.buildMenu(with:)`,
    gated on `AnnotationMenuDelegate.isSelectionHighlightable`), using
    the default color only — no popover shown.
  - `.off` does nothing on selection; existing highlights stay fully
    viewable/editable via the annotations list and by tapping an
    existing `<mark>` (or, for an edit-only row, its `<span
    class="nnw-edit-only">` — see "Storage shape" above).
  Either creation path calls `WebViewController.saveHighlightFromSelection`,
  which calls `Annotations.addHighlightFromSelection` to resolve the
  still-live selection into a selector, draws the `<mark>` immediately,
  and persists the result via `account.saveAnnotation` — no round trip
  before the highlight is visible. Neither path has a note-entry exit
  any more: a note is always added afterward, by tapping the resulting
  mark.
- **Note editor**: `AnnotationEditorView` (SwiftUI, half-sheet via
  `UIHostingController`, `.medium()`/`.large()` detents), reachable by
  tapping any `<mark>` — freshly created or pre-existing — or, for an
  edit-only row with its highlight turned off, its `<span
  class="nnw-edit-only">` (`annotationWasTapped`; `handleAnnotationTap`
  matches either wrapper). Shows the read-only quote, a note field, the
  five color swatches, the "Edit Text" section (see "Manual edit UI"
  below), and a destructive delete (with confirmation). Delete calls
  `Annotations.removeAnnotationHighlight` (unwraps the `<mark>`,
  `normalize()`s the affected text nodes) before `account.deleteAnnotation`.
- **Manual edit UI**: below the color swatches and above the destructive
  delete action, an "Edit text" field — pre-filled with the highlight's
  current text (its `replacementText` if it already carries an edit,
  otherwise its `quoteExact`) — and a "Keep highlight on the corrected
  text" checkbox let a person correct a highlighted span in place. There
  is no selection-time entry point for this — editing a span that hasn't
  been highlighted yet isn't directly supported; it must be highlighted
  first. If the field is unchanged from the row's current text on Save,
  no edit row is created or modified — only note/color changes (if any)
  persist, exactly as before this feature. If it changed,
  `AnnotationEditorView`'s `onSave` reports the new text and the
  checkbox's state, and `WebViewController.saveTextEdit(annotation:
  replacementText:keepHighlight:account:)` runs it through the pipeline
  described under "Storage shape" above. The checkbox controls
  `hasHighlight` only — unchecking it does not clear the row's `color`,
  so re-checking it on a later visit restores the original color rather
  than defaulting to yellow.
- **Color palette**: five fixed colors (`Annotation.Color`: yellow, red,
  green, blue, purple), stored as a palette key, not a hex value. Which
  actual hex value a key resolves to is controlled by two independent
  axes:
  - **Light/dark adaptation** (bug fix): `core.css`'s
    `mark.nnw-highlight[data-annotation-color="..."]` rules read from
    `--nnw-highlight-*`/`--nnw-highlight-*-dark` CSS custom properties,
    with an `@media (prefers-color-scheme: dark)` block reading the
    `-dark`-suffixed variant. Previously there was only one, appearance-
    independent fallback hex per color (Apple's *dark*-mode system colors,
    served unconditionally in both appearances) and no live-set custom
    property at all — highlights rendered identically, and too harshly,
    in light mode. Fixed values still ship as the `@media`-branched
    fallback hex in `core.css`, but on every real render
    `WebViewController.applyHighlightPaletteColors()` sets all ten custom
    properties directly, so the fallback only matters before that first
    injection lands.
  - **`HighlightPalette`** (`iOS/AppDefaults.swift`, `AppDefaults.shared.highlightPalette`,
    `.highlightPaletteDidChange` notification) — which set of five hex
    values (one `HexSet` per light/dark appearance, same shape
    `SurfacePalette.HexSet` established) an annotation's color *key*
    resolves to. A person's saved `Annotation.color` is always one of the
    five case names, never a hex value, so switching palettes re-tints
    every existing highlight without touching a row of annotation data.
    Nine cases ship: `.default` (Apple's own system-color light/dark
    pair — unlike `SurfacePalette.default`, this is *not* nil in either
    appearance, since there's no pre-existing asset-catalog colorset for
    highlight colors to fall back to), `.muted`, `.vivid`, `.sepia`, and
    five additional "fun" palettes (`.mint`, `.flourescent`, `.refresh`,
    `.warm`, `.neutral`). Every case, including the five "fun" palettes,
    supplies its own distinct `darkHexSet` — these five originally
    reused their light-mode HexSet unchanged on the assumption that their
    lower saturation made a separate dark-mode tuning unnecessary; that
    assumption was wrong (see "Dark-mode contrast" below) and has been
    corrected, so there is no longer a case in `HighlightPalette` where
    light and dark share values.
    Picked via a fourth section (`highlightPalette`) on
    `AccentColorTableViewController`, alongside Accent Colors/Badge
    Colors/Preview — see `app-chrome-palette.md`.
  - `HighlightColorPopover`/`AnnotationEditorView`/`AnnotationsListView`'s
    color dots call `Annotation.Color.swiftUIColor(palette:isDark:)` (and
    the UIKit-facing `.uiColor(palette:isDark:)`), each reading
    `AppDefaults.shared.highlightPalette` via `@AppStorage` and
    `\.colorScheme` via `@Environment` so a live palette switch or
    light/dark change recomputes the swatch immediately — there is still
    no shared source of truth between CSS custom properties and SwiftUI
    `Color`/UIKit `UIColor`, kept in sync manually the same way as before,
    just against `HighlightPalette.HexSet` now instead of five bare
    literals.
  - No per-`.nnwtheme` highlight override exists (confirmed: no theme
    bundle in `Themes/` defines a `--nnw-highlight-*` variable) --
    `HighlightPalette` is a separate, app-level default the same way
    `SurfacePalette`/`AccentColor` are, not theme-bundle content. If a
    theme-level override is wanted later, precedence against
    `HighlightPalette` would need to be defined; not built as part of
    this feature.
  - **Dark-mode contrast** (bug fix): the reader's foreground text color
    on a `<mark>` in dark mode is near-white (`color: inherit` on
    `mark.nnw-highlight`), so a highlight background tuned for a
    light-mode-style dark-on-light presentation makes that text nearly
    unreadable. Every `HighlightPalette` case's `darkHexSet` is now
    verified (`UIColor.contrastRatio(against:)`,
    `Shared/ArticleStyles/ArticleThemeColorExtractor.swift`) to clear
    4.5:1 white-text contrast (WCAG AA for normal body text) for all five
    `Annotation.Color` slots — this previously only applied to
    `.default`/`.muted`/`.vivid`/`.sepia`'s hand-tuned dark values; the
    five "fun" palettes (`.mint`/`.flourescent`/`.refresh`/`.warm`/`.neutral`)
    originally reused their light-mode HexSet unchanged in dark mode
    (measured: several slots were under 3:1), which is what this fixes.
    Each dark value keeps its light-mode hue but is deepened and
    re-saturated until it clears the threshold — see
    `HighlightPaletteHexSetTests.everyDarkHexSetColorMeetsWCAGAAContrastForWhiteText`.
- **Multi-line highlight clipping** (bug fix, two parts): a `<mark>`
  that wraps across a line break used to paint one single
  `background-color` box sized to its whole bounding rect (from the
  start of its first line to the end of its last), rather than one box
  per visual line, so that box's top/bottom edges landed inside the
  neighboring line above/below instead of staying within its own line.
  Fixed in `core.css`'s `mark.nnw-highlight` rule with
  `-webkit-box-decoration-break: clone` (WKWebView only supports the
  prefixed form; unprefixed `box-decoration-break` is included too for
  forward-compatibility but has no effect here), so each visual line
  gets its own independently-boxed background instead of one shared
  bounding box.
  `clone` alone does not stop the rule's own vertical `padding` from
  bleeding into a neighboring line's ascenders/descenders (tall letters
  like "l"/"h", or descenders like "g"/"y") on its own: vertical padding
  on a non-replaced inline element paints without reserving extra
  line-height, so a fixed padding could still clip on a theme with a
  tight body `line-height` (several theme bundles go as low as
  1.15-1.2), `clone` or not. Rather than fix that with a fixed,
  mark-local `line-height` (which would override the person's own
  line-height setting on just the highlighted lines), `mark.nnw-highlight`
  instead sizes its padding to the headroom the *current* line-height
  actually leaves: `padding: min(0.1em, max(0em, (var(--nnw-line-height,
  1.4) - 1) * 0.5em)) 0.05em`. `--nnw-line-height` is written by
  `annotations.js`'s `updateLineHeightProperty()` (called from
  `renderAnnotations`/`addAnnotationHighlight` before any wrapping),
  which reads the article root's actual computed `line-height`/`font-size`
  ratio — whether it came from a bundled theme's own `stylesheet.css` or
  an `ArticleThemeOverrides` line-height override — and hands it to
  `core.css` as a custom property, the same layering
  `WebViewController.applyHighlightPaletteColors()` already uses for
  highlight colors. The padding this produces can never exceed the
  room that's actually there (bounded by the line box's own
  half-leading, `(line-height - 1) / 2` em), so it can't clip at any
  line-height, including the app's own floor of 1.0, and it never
  changes anything at line-heights the rule already looked correct at
  (1.2 and up, where the `min(0.1em, ...)` cap keeps the original
  cushion). Regression coverage:
  `Tests/JS/annotations/multi-line-highlight-clipping.test.js` (text-level
  assertions against `core.css`'s padding/line-height declarations, plus
  unit tests of `updateLineHeightProperty` against jsdom — not a
  rendered-layout test; jsdom has no layout engine to measure real
  clipping either way, so this doesn't replace a manual/device check of
  the actual rendered result across a few tight-line-height themes).
- **Toolbar button**: `ArticleToolbarToggle` (`iOS/AppDefaults.swift`)
  has an `.annotations` case, backed by
  `AppDefaults.shared.articleToolbarShowAnnotations` (default `false`,
  opt-in). `ArticleViewController.annotationsBarButtonItem` calls
  `showAnnotationsList(_:)` directly, pushing `AnnotationsListView`
  scoped to the current article's book (`.book(bookKey:)`) — there is no
  toolbar menu with multiple scope choices; that was an earlier design
  this doc previously (incorrectly) described.
- **Annotations list**: `AnnotationsListView` (SwiftUI), one implementation
  for both scopes (`Scope.book(bookKey:)`, `Scope.everything`) — only the
  underlying `Account` fetch method differs. There is no third,
  per-article scope; an earlier version of this doc described one, but
  that menu is gone (see "Toolbar button" above). Groups are keyed by
  `(bookKey ?? articleID, chapterTitle)`, not `articleID` alone — see the
  view's own header comment for why chapterTitle has to be part of the
  key (a single book's chapters can themselves span more than one
  articleID). `heading` (the section header text) is `chapterTitle` when
  the group has one, otherwise the group's own article title; when
  there's only one group on screen the header is suppressed entirely
  (redundant with the nav bar title) rather than shown. Rows show a color
  dot; the full sentence surrounding the highlight (reconstructed from
  `quotePrefix`/`quoteExact`/`quoteSuffix` via `NLTokenizer(unit:
  .sentence)`, with just the `quoteExact` portion given a
  `annotation.color`-tinted background wash — not the raw, potentially
  mid-sentence `quoteExact` slice on its own); the note preview
  (uncapped — a multi-paragraph note's line breaks render in full, not
  clipped to one line); the row's article author byline
  (`articleAuthors`, comma-joined sorted author names, omitted when the
  article has none) — chapterTitle is not shown per-row, it's promoted to
  the section header instead, as above. No per-row timestamp or repeated
  book title — both were dropped as redundant with the nav bar/section
  header. Orphaned annotations (`orphanedAt != nil`) appear dimmed with a
  "couldn't relocate this highlight" caption rather than being hidden.
  A `.searchable(text:)` field filters `groups` client-side against a
  row's quote, note, and article title (`localizedStandardContains`,
  case-insensitive); a group left with no matching rows is dropped, and a
  collapsed section's collapse is suppressed (not cleared) while a search
  is active so a match inside a collapsed section isn't hidden. Long-
  pressing a row opens a context menu with "Copy Highlight"
  (`copyText(annotation:articleAuthors:link:)`), which copies
  `"quote"\n-author, chapter, link\n\n"note"` to `UIPasteboard` — author
  falls back to "Unknown" rather than a blank field, chapter and link are
  each dropped from the attribution line (not printed empty) when the
  article has neither, and the note block is only included when the
  annotation has one. See `CopyHighlightTextTests.swift` for the exact
  format contract.
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
  which contains a `NavigationLink` to the unscoped `AnnotationsListView`
  (using the first account — Nectar's usual shape is one local account,
  per `ambrosia-feed.md`), the `annotationCreationMethod` picker
  (Popup/Native Menu/Off, see "Selection → highlight" above), the default
  color picker, and the two export rows below. The article-toolbar
  `.annotations` button toggle is a separate control, on a different
  settings screen (`ArticleToolbarCustomizerViewController`) — not part
  of `AnnotationsSettingsView`.

## Export

- **CSV**: `AnnotationCSVExporter.swift` (`Shared/Exporters`), same shape
  as `ArticleCSVExporter.swift` — a `columnHeaders` array (`book`,
  `chapter`, `quote`, `note`, `color`, `created`, `link`, `hasHighlight`,
  `originalText`, `replacementText` — the last three added alongside the
  schema version 5 columns, see "Storage shape" above; `originalText`/
  `replacementText` are empty strings, not omitted, for pure highlight
  rows) and a
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
  `chapterTitle` and `hasHighlight`/`originalText`/`replacementText`
  included alike (`SELECT an.*` — a new annotations column
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
- `Tests/NetNewsWire-iOSTests/HighlightPaletteHexSetTests.swift`: coverage
  for `HighlightPalette`'s `HexSet`s across all nine cases and both
  appearances — completeness/parseability, distinctness between cases,
  every case's dark/light `HexSet`s being distinct (including the five
  "fun" palettes, which originally incorrectly reused the light-mode
  values), every dark-mode color clearing 4.5:1 white-text contrast
  (`UIColor.contrastRatio(against:)`), `Annotation.Color`'s
  `.uiColor(palette:isDark:)` resolving correctly against a given
  palette/appearance pair, and the live `.highlightPaletteDidChange`
  notification contract.
- `Tests/JS/annotations/multi-line-highlight-clipping.test.js`: a narrow
  regression test against `core.css`'s text (not its rendered effect --
  jsdom has no layout engine to measure real clipping) asserting
  `mark.nnw-highlight` still declares `-webkit-box-decoration-break:
  clone` and non-zero vertical padding, so a future edit to that rule
  doesn't silently drop the fix described under "Multi-line highlight
  clipping" below.
- `Modules/Articles/Tests/ArticlesTests/TextReplacementOffsetShiftTests.swift`:
  `firstOverlap` (genuine overlap, touching boundaries, no conflict),
  `shiftedAnchors` (only rows at or after `editEndOffset` shift, positive/
  negative delta arithmetic, the zero-delta no-op fast path,
  `sliceQuote` called with the row's *new* offsets), `shiftedAnchorsForRevert`'s
  inverse-delta behavior, and `descendingApplicationOrder`'s ordering
  guarantee — pinned by a test that applies two edits in the mandated
  descending order and checks the resulting offsets are correct, not just
  that the sort itself produces the right order.
- `Modules/Articles/Tests/ArticlesTests/TextReplacementRuleTableTests.swift`:
  word-boundary/case-insensitive matching (including the false-positive
  guard — `teh` inside `tehcnically` must not match), comma-separated
  multi-token rules, regex-escaping of special characters in a token,
  cross-rule overlap resolution (table order, not text order or span
  width, decides the winner), the empty-output skip, and the
  parenthesized-token gap described above (`(Y/N)` never matches, only
  bare `Y/N` does).
- `Tests/JS/annotations/text-replacement-edit-application.test.js`:
  `renderAnnotations`' handling of edit rows — an edit-only row
  (`hasHighlight = false`) replaces text with no `<mark>` drawn, but is
  still wrapped in a tappable `<span class="nnw-edit-only">` carrying no
  color attribute; a row that's both a highlight and an edit wraps the
  freshly-edited text in `<mark>` without re-resolving against the
  post-edit DOM; a lengthening edit followed by an unrelated later
  highlight in the same render pass still resolves the later row
  correctly (the regression test for the `wrapDOMRange` single-text-node
  fix below); `applyTextEdit`'s own Range-return and
  null-on-unresolvable-span behavior via `_internal`.
- `Tests/JS/annotations/selection-capture.test.js` also covers the
  edit-only wrapper's tap/scroll parity with a highlighted `<mark>`:
  `initAnnotations` posts `annotationWasTapped` for a click on a
  `span.nnw-edit-only`, and `scrollToAnnotation` finds, scrolls to, and
  flashes one the same way it does for a `<mark>`.
- `Tests/JS/annotations/text-replacement-edit-plan.test.js`:
  `computeTextEditPlan`/`getArticleText` — same-length no-op, overlap
  detection short-circuiting before any shift is computed, lengthening
  and shortening deltas shifting and re-slicing a later row's
  quote/prefix/suffix against the simulated post-edit text, a row
  touching the edit's `endOffset` exactly still being included, a row
  entirely before the edit never being shifted, the `rootSelector`
  default, and `computeTextEditPlanEncoded`'s malformed-input fallback.
- `Modules/Articles/Tests/ArticlesTests/TextReplacementQuoteConversionTests.swift`:
  balanced-pair dialogue-quote detection and conversion, and the
  contraction/possessive cases a naive `'`-to-curly-quote pass would get
  wrong (a contraction immediately adjacent to a real quote boundary, an
  unpaired `'` with no matching close).
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/BackupSQLiteImportTableTests.swift`:
  merge-import column coverage for `hasHighlight`/`originalText`/
  `replacementText` — a new-only edit row survives a merge import
  unchanged, and a conflicting row's merge winner still carries all three
  columns, not just the pre-existing ones — written specifically to catch
  the "row merges, new columns silently drop" failure mode a
  column-by-column `UPDATE`/`INSERT` statement could otherwise have.
- `Tests/NetNewsWire-iOSTests/AnnotationCSVExporterTests.swift`: the
  `hasHighlight`/`originalText`/`replacementText` CSV columns across
  pure-highlight, edit-only, and highlight+edit rows, comma-escaping
  inside the new columns via the shared `CSVFormatting` helper, the
  pre-existing chapter-title-vs-book-title fallback (sanity-checked
  alongside the new columns, not changed by them), and row-count/empty-list
  sanity.
- `Modules/Articles/Tests/ArticlesTests/TextReplacementPerWorkOverrideTests.swift`:
  precedence (a per-work override's rule wins over the global table for a
  token it covers), no-leak-to-other-works (an override set for one
  `bookKey` never affects another), and partial-overlap (a token the
  override doesn't mention still falls through to the global table) — run
  through the real `TextReplacementRuleEngine` via
  `mergedReaderInsertTable(forBookKey:global:)`, not just asserted against
  row order.
- `Modules/Articles/Tests/ArticlesTests/SentenceContextTests.swift`:
  regression coverage for the `sentenceContext` extraction out of
  `AnnotationRow` — sentence reconstruction from
  `quotePrefix`/`quoteExact`/`quoteSuffix`, clipping to only the sentence
  containing the quote (not the whole prefix/suffix span), internal
  whitespace/newline normalization, a quote that recurs earlier in the
  prefix still resolving to the real, later occurrence, and the
  empty-quote/no-sentence-boundary edge cases — every case hand-traced
  against the exact algorithm that used to live inline in `AnnotationRow`,
  confirming the move to plain `String`/`Range<String.Index>` didn't
  change the underlying text/range math.
- `Modules/Articles/Tests/ArticlesTests/AnnotationRowStyleTests.swift`:
  `Annotation.rowStyle`'s field-driven derivation — a pure highlight
  resolves to `.highlight`; an edit-only row resolves to `.edit` with its
  text; a highlight+edit row still resolves to `.edit` (the color dot is
  a separate, independent check against `hasHighlight`, not part of
  `rowStyle` itself); the two "should not occur per the Validity rule but
  must not crash" cases where only one of `originalText`/`replacementText`
  is set.
- `Tests/NetNewsWire-iOSTests/AnnotationsListViewScopeTests.swift`: the
  tab-consolidation requirement — `scope: .book(bookKey:)` resolves to
  that `bookKey` and offers the tab switcher; `scope: .everything`
  resolves to a `nil` `bookKey` and hides it. Exercises
  `AnnotationsListView.resolvedBookKey(for:)`/`showsTabSwitcher(bookKey:)`
  as static functions rather than constructing a real
  `AnnotationsListView`, which would need a real `Account` — this test
  target has no working path to one (see that file's own header comment).
- `Modules/RSCore/Tests/RSCoreTests/CGRectClampedToBoundsTests.swift`: the
  fullscreen-popover regression coverage — `CGRect.clamped(toBounds:)`
  correctly clamps a rect off any single edge or both axes at once,
  preserves width/height throughout, and leaves an already-inside rect
  unchanged. Extracted from `WebViewController`'s own private
  `clampedToBounds(_:bounds:)` specifically so this is testable without a
  `UIViewController`/`UIPopoverPresentationController` in the loop.
