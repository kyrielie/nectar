# Nectar Architecture

Nectar is a private iOS fork of NetNewsWire, repointed at "Ambrosia" — a JSON
Feed–based backend that extends the JSON Feed 1.1 spec with an `_ambrosia`
object carrying fic-reader/book metadata (word count, chapters, fandom,
rating/warnings, series, and book identity). Ambrosia also offers a second,
higher-throughput sync route for large collections: a paginated SQLite
transfer format, fetched and imported directly rather than parsed as JSON.
Confirmed against the current source tree.

## Module layout

SPM packages live under `Modules/`. The ones with app-specific relevance:

- **Modules/RSParser** — feed/OPML/HTML parsing, no app dependencies.
  `JSONFeedParser` reads the standard JSON Feed fields (`summary`,
  `content_html`/`content_text`) and separately reads the `_ambrosia`
  extension object, producing a `ParsedItem` with both the standard fields
  and the Ambrosia-specific ones: `wordCount`, `chapterCurrent/Total`,
  `isComplete`, `fandoms`, `relationships`, `characters`, `ratings`,
  `warnings`, `categories`, `series`, plus the book-identity fields
  `ao3WorkID`, `isAnthology`, `ao3SeriesID`, and `seriesName` (the
  Calibre-derived fallback name for an anthology with no AO3 series id).
  `ParsedItem` also carries `isAmbrosiaItem` (true whenever an `_ambrosia`
  object is present at all, regardless of which fields inside it are
  populated) and a computed `bookKey`, used for identifying "the same book"
  across feeds/re-subscriptions/re-imports — see Book identity below.
  `ParsedItem` also carries a `markdown` field: when present, RSParser
  renders it to HTML via `Tidemark.markdownToHTML` and uses that as
  `contentHTML` (falling back to any provided `contentHTML` if the
  rendered result is empty).
- **Modules/Articles** — the persisted domain model. `Article` mirrors
  `ParsedItem` 1:1, including the Ambrosia fields, `markdown`, and
  `bookKey` (always resolves to at least `uniqueID`, so it's
  non-optional), and a `summary: String?` distinct from
  `contentHTML`/`contentText`. `ArticleStatus` holds per-article mutable
  state — `read`, `starred`, `loved`, and `readingProgress: Double?`
  (local UI state, not synced, same tier as scroll position).
- **Modules/ArticlesDatabase** — SQLite-backed persistence for articles,
  status, and search (`ArticlesTable`, `StatusesTable`, `SearchTable`).
  `articles.contentHTML` is stored LZFSE-compressed and base64-encoded
  (`ContentHTMLCompression`), reusing the same compression Foundation API
  the CloudKit sync path already relies on; a row that fails to
  decode/decompress falls back to returning the stored string as-is rather
  than throwing. `BookStateTable` holds book-level state, one row per
  `bookKey` — see Book identity below. `AmbrosiaSQLiteImportTable` /
  `ArticlesDatabase.importAmbrosiaSQLiteTransfer` handle the SQLite
  transfer import route via `ATTACH DATABASE` + `INSERT OR REPLACE ...
  SELECT`, computing `bookKey` per row with a SQL `CASE` expression that
  mirrors `ParsedItem.bookKey`'s precedence.
- **Modules/Account** — account management and sync services (Feedbin,
  Feedly, Reader API, NewsBlur, CloudKit, local/Ambrosia), built on top of
  `ArticlesDatabase`. `LocalAccountRefresher` (LocalAccount) routes each
  feed to one of two fetch paths per refresh — see SQLite transfer route
  below.
- **Modules/RSCore / RSWeb / RSDatabase / RSTree** — cross-cutting utility
  layers (AppKit/UIKit helpers, HTTP/download plumbing, SQLite wrapper,
  tree/outline data structure) carried over from NetNewsWire, largely
  unmodified by the Ambrosia work.
- **Modules/Images, HTMLMetadata, FeedFinder, ActivityLog, ErrorLog,
  CloudKitSync, SyncDatabase, NewsBlur, Secrets** — supporting services
  (icon/favicon downloading, page metadata, feed autodiscovery, activity
  and error logging, CloudKit sync plumbing, NewsBlur API client, secrets
  storage). Not touched by the Ambrosia-specific work described below.
- **Shared/** — cross-platform (iOS/Mac target scaffolding, though only iOS
  is actually built — see below) formatting and rendering:
  `ArticleStringFormatter` (title/summary truncation and caching),
  `ArticleRenderer` (HTML page assembly for the web view), `Assets.swift`
  (icon/color constants, including the fork's Loved/heart and Ambrosia
  additions), and `SmartFeeds/` (Today/Unread/Starred/Loved/Read smart
  feeds — `LovedFeedDelegate` uses a dedicated filled-heart icon, not the
  Starred bookmark icon).
- **iOS/** — the only compiled app target. Key areas for current work:
  - `iOS/MainTimeline` — the article list. `MainTimelineCellData` builds
    per-row display state from an `Article`; `MainTimelineCellLayout`
    computes rects; `MainTimelineCell` renders.
  - `iOS/Article` — `WebViewController` (article web view, scroll
    tracking, read-marking), `ArticleViewController`.
  - `iOS/Settings` — `SettingsViewController` (app settings list) and
    `TimelineCustomizerCollectionViewController` (Timeline Layout screen:
    icon size, line count, and a live `MainTimelineCell` preview).
  - `SceneCoordinator`/`SceneDelegate` — navigation, state restoration,
    Handoff.

Note: several `#if os(macOS)` branches survive from the upstream NetNewsWire
codebase but nothing macOS is currently built or shipped for Nectar.

## Book identity (`bookKey`) and `BookStateTable`

Ambrosia items can be re-imported (Calibre re-exports), re-extracted (AO3
metadata arriving later than the initial import), or appear in more than one
collection feed at once. `bookKey` is the identity used to recognize "the
same book" across all of that, distinct from `uniqueID`
(`"ambrosia-book-<calibre_id>"`, which stays stable forever) and from
`articleID` (per feed/guid pair). Precedence, mirrored exactly between
`ParsedItem.bookKey` (Swift) and the SQL `CASE` expression in
`AmbrosiaSQLiteImportTable`: an anthology's AO3 series id, else its
Calibre-derived series name, else the item's own AO3 work id, else the bare
`uniqueID` as a last resort.

`BookStateTable` (`ArticlesDatabase`) stores one row per `bookKey` — `read`,
`starred`, `loved`, `scrollPosition`, `readingProgress`, `updatedAt` — and is
now the *primary* store for read/starred/loved and scroll position:

- Marking read/starred/loved on any `articleID` looks up its `bookKey`
  (falling back to `uniqueID` for pre-migration rows with no `bookKey`
  persisted yet), writes the flag to `BookStateTable`, and also
  live-propagates the same flag to every other `articleID` sharing that
  `bookKey` via `StatusesTable`, so every open copy of the same book across
  feeds repaints immediately rather than waiting for its next
  import/refresh.
- Scroll position (`ArticlesTable.saveScrollPosition`/`fetchScrollPosition`)
  is likewise `bookKey`-keyed through `BookStateTable` when a `bookKey`
  resolves, so it survives feed deletion/re-subscription and is shared
  across every feed's copy of the same book. `StatusesTable`'s own
  `scrollPosition` column remains only as a last-resort fallback for an
  `articleID` that doesn't resolve to any key at all.
- `readingProgress`, by contrast, is still read/written only through
  `StatusesTable` per `articleID` — it is not yet part of the
  `BookStateTable` write-through despite `BookState` carrying a
  `readingProgress` field, and is not shared across duplicate copies of a
  book the way read/starred/loved/scrollPosition are.

`StatusesTable`'s parallel read/starred/loved/scrollPosition columns remain
as the fallback path for the rare row with no resolvable `bookKey`; these
fallback rows are ordinary `statuses` rows and are cleaned up automatically
whenever a feed's articles/statuses are deleted.

## SQLite transfer route (large-collection sync)

Alongside HTTP JSON Feed fetching, `LocalAccountRefresher` supports a second
route for feeds whose URL ends in `.sqlite`: rather than downloading and
parsing JSON, it fetches a paginated SQLite "transfer walk"
(`AmbrosiaSQLiteTransferFetcher`) and imports each page directly into
`ArticlesTable`/`StatusesTable` via `ATTACH DATABASE`. This exists because
`DownloadSession`'s default 15s request timeout would kill a multi-minute
whole-database transfer outright; `AmbrosiaSQLiteTransferFetcher` uses its
own dedicated `URLSession` with a 300s timeout instead. Feeds are split into
`sqliteFeeds`/`downloadFeeds` by URL path extension before a refresh starts;
`.sqlite` feeds are routed directly to the SQLite fetcher and never enter
`DownloadSession`.

Each downloaded page carries a `transfer_manifest` table (`walk_id`,
`page_number`, `has_more`, `page_row_count`, `expected_total_row_count`),
which is read and validated before the page is attached/imported — a
`page_row_count` mismatch against the page's actual `items` row count, or a
`walk_id` mismatch mid-walk (stale/restarted walk), is treated as a hard
error rather than silently importing a partial or wrong-walk page. A
resumed walk that stalls partway reports `.incomplete` (pages/rows imported
so far, expected total, last page attempted) rather than throwing, and
retries from where it left off on the next refresh.

Known gaps, called out in code rather than fixed: the SQLite import path
writes straight into the article tables without producing `Article`/
`ArticleChanges` values, so `.AccountDidDownloadArticles` (the notification
the timeline observes for new-article insertion) does not fire for it — the
comment notes this needs a closer look at the timeline's data source before
deciding whether it matters. A `.incomplete` transfer is currently only
surfaced via the Activity Log, not (yet) as distinct per-feed UI state in
the feed list.

## Data flow: feed to card

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
   back to the per-article `StatusesTable` column otherwise (see Book
   identity above) — and separately checks the existing 99%-of-height
   threshold to mark the article read.
3. `setArticle` restores position for the article being opened via
   `account.fetchScrollPosition(forArticleID:)`, resolved through the same
   `bookKey`-first/`StatusesTable`-fallback lookup.
   `isAwaitingInitialScrollFetch` suppresses `viewDidLoad`'s unconditional
   render-at-0 while this fetch is in flight, and `pendingLoadResets`
   (a count, not a single boolean) suppresses the corresponding N
   post-load scroll-reset events for overlapping loads.
4. `SceneCoordinator.restoreWindowState` / Handoff resume instead read the
   single global `AppDefaults.shared.articleWindowScrollY`. `windowScrollY`'s
   `didSet` still writes that global on every scroll update, alongside the
   per-book/per-article write in (2) — deliberately left in place (see the
   comment in `WebViewController`) because relaunch/Handoff restore still
   depends on it. This remains a known source of restore inaccuracy across
   relaunch/Handoff specifically (every open article's scroll updates
   overwrite the one global slot), distinct from the same-session
   reopen race that has since been fixed via `isAwaitingInitialScrollFetch`
   and `pendingLoadResets` above.
5. `readingProgress` is a separate, still per-`articleID`-only value (not
   `bookKey`-shared like scroll position/read/starred/loved) — see Book
   identity above.

## Settings screen structure

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list: icon size (0), number of lines
(1), no-icon preview (2), icon preview (3). Sections 2/3 render a live
`MainTimelineCell` built from a hardcoded `previewArticle` and reload on
`UserDefaults.didChangeNotification` for the two sliders currently wired up.

## Planning notes

`docs/` (gitignored, not present in this source tree) holds working notes
for in-progress and completed fork work (`nectar-plan-v3.md`,
`nectar-fixes-plan.md`, `nectar-loved-icon-heart-plan.md`,
`netnewswire-fork-plan.md`, `feed-api.md`). These are design/debugging
scratch documents, not guaranteed to reflect the shipped state — this file
is the source of truth for current architecture.
