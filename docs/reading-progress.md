# Reading-progress and feed-to-card data flow

How a parsed feed item becomes a timeline card, and separately, how scroll
position / read-progress is tracked and restored for an open article. Both
pipelines route through `WebViewController`, which also owns the article
scrollbar-visibility setting (`AppDefaults.shared.showArticleScrollbar`) —
unrelated to this doc's scroll-position tracking, but the same file, worth
knowing before assuming a scroll-related bug here also affects that
setting or vice versa. See `book-identity.md` for the `bookKey`-sharing
mechanism referenced throughout the reading-progress section below.

1. `JSONFeedParser` parses an Ambrosia JSON Feed response into `ParsedItem`s,
   reading `summary` and `_ambrosia.*` as sibling fields to `content_html`
   (or rendering `markdown` to HTML when present).
2. Account sync code (or, for `.sqlite` feeds, `AmbrosiaSQLiteImportTable`)
   persists these into `ArticlesDatabase`, producing `Article` values with
   `summary`, `bookKey`, and the Ambrosia fields populated, and
   `contentHTML` stored LZFSE-compressed.
3. `MainTimelineCellData.init(article:...)` calls
   `ArticleStringFormatter.shared.truncatedSummary(article)` for the card's
   body preview, and reads `article.wordCount`/`fandoms`/`isComplete`/
   `ratings`/`warnings` directly for the metadata line.
4. `ArticleStringFormatter.truncatedSummary` prefers `article.summary` when
   present and non-empty, falling back to `article.body`
   (`contentHTML ?? contentText ?? summary`, decompressing `contentHTML` as
   needed) otherwise, then truncates to 300 characters and caches the
   result keyed by `(articleID, accountID)`.

## Reading-progress data flow

1. `WebViewController` tracks `windowScrollY` via a JS bridge and coalesces
   scroll updates through a 0.3s `CoalescingQueue`.
2. On each coalesced update it evaluates JS to read `scrollY`/`scrollHeight`/
   `innerHeight`, writes the raw offset via
   `account.saveScrollPosition(_:forArticleID:)` — resolved to the
   article's `bookKey` and written to `BookStateTable` when a `bookKey` is
   available (shared across every feed's copy of the same book), falling
   back to the per-article `StatusesTable` column otherwise (see
   `book-identity.md`) — and separately checks the existing 99%-of-height
   threshold to mark the article read.
3. `setArticle` restores position for the article being opened via
   `account.fetchScrollPosition(forArticleID:)`, resolved through the same
   `bookKey`-first/`StatusesTable`-fallback lookup.
   `isAwaitingInitialScrollFetch` suppresses `viewDidLoad`'s unconditional
   render-at-0 while this fetch is in flight. Separately,
   `isRestoringScrollPosition` (a single `Bool`, not a count) suppresses
   `scrollPositionDidChange` samples during the restore script's own
   multi-point settle (`DOMContentLoaded`/`load`/`fonts.ready`/
   `ResizeObserver`-driven reflows), so a reset/attempt sampled before the
   document reaches final height doesn't get treated as a real scroll and
   overwrite the just-restored position. It's cleared either by the
   `scrollRestoreComplete` JS confirmation message or, if that message
   never arrives, a 5s failsafe timer (`scrollRestoreFailsafeWorkItem`).
4. Relaunch and Handoff restoration now go through the same per-book/
   per-article path as (2)/(3)
   (`SceneCoordinator.restoreSelectedSidebarItemAndArticle`/`selectArticle`),
   not a separate global. An earlier version threaded a single
   `AppDefaults.shared.articleWindowScrollY` value (shared across every
   open article) through this path instead; that property and the
   `didSet` write that fed it have both been removed (see the comments on
   `WebViewController.windowScrollY`'s `didSet` and
   `SceneCoordinator.restoreSelectedSidebarItemAndArticle`) now that
   relaunch/Handoff restore no longer needs it. If you find a stray
   reference to `articleWindowScrollY` elsewhere, it's describing this
   removed mechanism historically, not a live property -- update or
   remove it rather than assuming it still exists.
5. `readingProgress` is `bookKey`-shared the same way scroll
   position/read/starred/loved are — see `book-identity.md`.

## In-article jump history (scrollBack)

`WebViewController.scrollJumpHistory` (`iOS/Article/WebViewController.swift`)
is a separate, session-only mechanism from the scroll-position tracking
above -- it does not persist, is not read/written through `Account`, and
has no `bookKey` sharing. It is a plain `[Double]` stack of pre-jump
`windowScrollY` values.

- **Scope (deliberately narrow):** only explicit programmatic "jump to X"
  calls push onto this stack -- `scrollToHeading(tocIndex:)` (Table of
  Contents) and `scrollToAnnotation(annotationID:)` (tapping an annotation
  reference), each pushing `windowScrollY` immediately before issuing their
  own `evaluateJavaScript` call. Large manual scroll deltas (e.g. a fast
  fling, or scrolling back up by hand to reread something) are **not**
  detected as jumps and do not push anything. This was a deliberate choice,
  not an oversight: detecting manual scrolls as jumps would need a
  heuristic (e.g. flagging a delta between consecutive coalesced samples
  that exceeds some multiple of `innerHeight`) with real false-positive
  risk -- a fast fling scroll isn't "jumping back to check something," it's
  just fast reading -- and that heuristic would need its own tuning pass
  against real reading sessions before shipping. If manual-scroll jump
  detection gets built later, it's a genuinely separate mechanism layered
  on top of this stack, not an extension of it.
- **`scrollBack()`** pops the most recent entry and calls the JS-side
  `scrollToWindowY` (added in `main_ios.js` alongside `scrollToHeading`,
  using the same `withEncodedArg` convention) to jump back to it. No-op if
  the stack is empty.
- **`isScrollBackAvailable`** exposes `!scrollJumpHistory.isEmpty` for UI
  binding. `ArticleViewController` uses it to enable/disable the
  `.scrollBack` `ToolbarFunction`'s bar button and overflow-menu action,
  following the same per-article/session-live-state pattern already used
  for `.checkForUpdates`'s eligibility and `.prevNext`'s next/prev
  availability (see `ArticleViewController.overflowActions(for:)`'s own doc
  comment).
- **`scrollToTop()`/`scrollToBottom()`** are unrelated to the jump stack --
  they don't push or pop anything, since "go to the top/bottom" isn't a
  position a person would want to jump back from the way a Table-of-Contents
  or annotation jump is.
