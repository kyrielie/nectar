# Nectar Architecture

Nectar is a private iOS fork of NetNewsWire, repointed at "Ambrosia" — a JSON
Feed–based backend that extends the JSON Feed 1.1 spec with an `_ambrosia`
object carrying fic-reader/book metadata (word count, chapters, fandom,
rating/warnings, series, and book identity). Ambrosia also offers a second,
higher-throughput sync route for large collections: a paginated SQLite
transfer format, fetched and imported directly rather than parsed as JSON.
Confirmed against the current source tree.

**Provenance note for whoever picks this up next:** this revision folds in
six features/behaviors that were present and wired up in the code but
missing from the previous version of this document — found via a
systematic audit (file-by-file duplication/dead-code sweep, then a
path-matched diff against an upstream NetNewsWire snapshot). All six are
marked below by name (AO3 direct feed ingestion, `JSONFeedParser`
diagnostic logging, Feed LAN-IP repointing, AO3/host refresh throttling,
background refresh budget, Last Opened smart feed). Known problems found
during the same audit — duplicated helpers, dead code, one unresolved
design question — are tracked separately in
`nectar-audit-remediation-plan.md`, not here; this file describes what the
code *does*, not what's wrong with it.

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
  rendered result is empty). `JSONFeedParser` also logs, via `os.Logger`
  (`.notice`), an item-count summary for every parse plus a reason for
  each individual dropped item (missing `uniqueID`, missing content) and
  each same-`uniqueID` collision within one feed — read this log first
  when chasing "why did this item disappear." `RSParser` also has a
  second, independent ingestion path that doesn't go through
  `JSONFeedParser` at all — see AO3 direct feed ingestion below.
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
  `ArticlesDatabase`. Only the local/Ambrosia backend is reachable —
  `AccountType` has exactly one live case, `.onMyMac`; the
  Feedbin/Feedly/NewsBlur/ReaderAPI/CloudKit delegate code, and the
  `Modules/CloudKitSync`/`Modules/NewsBlur` packages, are fully deleted
  from the tree, not merely unreachable-but-compiled (intentional: an
  unsigned IPA can't use iCloud, and the removed backends have no route to
  reach without it). `LocalAccountRefresher` (LocalAccount) routes each
  feed to one of two fetch paths per refresh — see SQLite transfer route
  below — and, separately, decides per-refresh whether a feed should be
  skipped this pass at all — see AO3/host refresh throttling below. A
  feed's fetch address (the Ambrosia server's LAN IP) can change without
  changing its `feedID` — see Feed LAN-IP repointing below.
  `Account.isLibraryReachable` (backed by `AccountSettings`, defaulting to
  `true` when never set) tracks whether the paired Ambrosia server
  responded as of the last refresh; `LocalAccountRefresher` sets it false
  on a failed refresh attempt and true again on the next successful one,
  and `MainFeedCollectionViewController`/`SceneCoordinator` read it for
  "server unreachable" UI state.
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
  additions), and `SmartFeeds/` (Today/Unread/Starred/Loved/Read/**Last
  Opened** smart feeds — `LovedFeedDelegate` uses a dedicated filled-heart
  icon, not the Starred bookmark icon; `LastOpenedFeedDelegate` is a
  Nectar-original smart feed with no upstream counterpart, described
  below).
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
- `readingProgress` is also part of `BookStateTable`'s write-through:
  `ArticlesTable.saveReadingProgress` looks up the `articleID`'s `bookKey`,
  writes through `BookStateTable.setReadingProgress`, and propagates the
  same value to every other `articleID` sharing that `bookKey` via
  `StatusesTable`, the same pattern as read/starred/loved/scrollPosition
  above. Two copies of the same book reached through different feeds are
  the same book to read -- if you're partway through one feed's copy,
  opening the other feed's copy should show the same position rather than
  resetting to 0 and risking a stale overwrite on the next scroll-position
  write.

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

`AmbrosiaSQLiteImportTable.copyItems`'s bulk `INSERT OR REPLACE ... SELECT`
moves most `items` columns straight across because their wire type already
matches the local `articles` column's storage type (TEXT-to-TEXT,
INTEGER-to-INTEGER/BOOL). `date_published`/`date_modified` are the one
column pair where that's not true: the wire format sends them as ISO 8601
TEXT (see the Wire Contract in `docs/nectar-implementation-plan.md`), but
`articles.datePublished`/`dateModified` are read/written everywhere else as
numeric `timeIntervalSince1970` doubles, via FMDB's automatic `Date`→double
binding. A straight `SELECT`-and-copy of the TEXT column skipped that
conversion — SQLite's TEXT-to-REAL coercion on read parses only the leading
digit run of an ISO 8601 string (`"2024-01-15T10:30:00Z"` → `2024.0`), so
every date imported via the `.sqlite` transfer route silently became a
~1970-01-01 timestamp, which is what a `.sqlite`-fed article's timeline date
would end up showing (via `Article.logicalDatePublished`'s
`datePublished ?? dateModified ?? status.dateArrived` fallback — a
near-1970 `datePublished` is non-nil, so the `dateArrived` fallback never
kicked in to mask it). Fixed the same way `content_html` already was: left
out of the bulk `INSERT...SELECT` and filled in afterward, one row at a
time, by `copyParsedDates` — parsed with `RSParser.DateParser` (the same
parser `JSONFeedParser` uses for these fields on the ordinary HTTP JSON Feed
path) and written via parameter binding so FMDB does the correct
Date→double conversion. Any *future* column added to this bulk copy should
be checked against this same TEXT-vs-numeric-storage question before
assuming a straight `SELECT` is safe — `content_html` and the dates are the
two columns that needed the one-row-at-a-time treatment so far, not because
they're special-cased on principle but because they're the only two whose
wire type doesn't already match the local column's storage type.

## AO3 direct feed ingestion (RSS/Atom route)

Ambrosia JSON Feed is not the only way an article reaches Nectar. Nectar
also subscribes directly to AO3's own native tag/user RSS and Atom feeds
(`https://archiveofourown.org/tags/<tag>/feed.atom`, works search feeds,
etc.) — a public site, not the user's own Ambrosia server. This route goes
through the ordinary `RSSParser`/`AtomParser` path (not `JSONFeedParser`),
with three fork-specific additions layered on at the `parsedItems`
construction site in both parsers:

- **`AO3IgnoreList.shouldExclude(_:)`** filters out items from
  blocked works/authors before they're ever turned into a `ParsedItem` —
  one choke point that covers show/fetch/save at once, so a blocked
  work never reaches the database, the timeline, or search.
- **`AO3SummaryExtractor.extract(fromSummaryHTML:)`** (`RSSItem.toParsedItem`
  only — Atom items don't carry AO3's summary HTML in the same shape) tries
  to parse AO3's machine-generated summary HTML into structured fields
  (fandoms, relationships, ratings, word count, `ao3WorkID` from the
  permalink, etc.) and, on success, builds the `ParsedItem` from that
  structured result instead of falling through to the generic
  body/summary promotion every other feed uses.
- AO3 search-results/tag-listing pages get their own pagination and
  refresh-skip handling — see AO3/host refresh throttling below.

None of this is present in `JSONFeedParser`'s article-construction path;
it only applies to feeds fetched as RSS/Atom. `RSSItem.swift`/
`RSSParser.swift`/`AtomParser.swift` are otherwise upstream NetNewsWire
code — these three additions are the only diff from upstream in any of
them. In-code comments reference this as "Task 7"/"Task 9" of a `docs/`
planning file; the planning file itself is out of scope, but the task
numbers confirm this is a deliberate, planned feature, not incidental.

## Feed LAN-IP repointing

`Feed.url` (`Modules/Account`) is `nonisolated(unsafe) public
private(set) var`, not a `let` — a feed's fetch address can change without
changing its `feedID`, via `Feed.repoint(to:)`. This exists because the
Ambrosia server is addressed by LAN IP, which can change (DHCP lease
renewal, network switch) independent of anything about the feed's
identity; repointing in place means existing articles, statuses, and
`BookStateTable` rows stay associated with the feed with no merge step,
where creating a new feed at the new URL would orphan all of that history.

`LocalAccountDelegate` drives repointing from two entry points, both
routed through one shared `collectionKeyIndex` helper (no duplicated
matching logic between the two paths):

- **OPML import** (`reconcileRepairedFeeds`/`repointAndRefresh`): after
  importing OPML, newly-created feeds are matched against existing ones by
  `AmbrosiaFeedIdentity.collectionKey(for:)` — a collection identity, not
  the URL — and a match under a different URL repoints the *existing*
  feed rather than keeping the OPML-created duplicate. This supersedes an
  earlier merge-by-`bookKey` approach (noted in-code).
- **Manual single-feed add** (`repointIfAmbrosiaRepair`, called from
  `createFeed`): the same collection-key matching, checked before falling
  through to ordinary feed creation.

A third, related piece: **`rewriteAmbrosiaJSONFeedURLs`** rewrites an
Ambrosia-exported OPML's `xmlUrl` from the RSS 2.0 route it ships (no
`_ambrosia` metadata) to the sibling `.json` route before subscribing, so
an OPML round-trip doesn't silently lose book-card data.

Repointing deliberately avoids the `bookKey`-merge path in favor of
`feedID` stability — consistent with `articleID` being `feedID`-derived
(see Book identity above): a repoint keeps the same `feedID`, so no
article identity changes at all, whereas a `bookKey` merge would try to
reconcile two different `feedID` lineages after the fact.

## AO3/host refresh throttling

`LocalAccountRefresher.feedShouldBeSkipped(_:_:)` runs once per feed per
refresh pass and decides whether that feed is skipped this time, checking
three independent reasons in order:

1. **Disallowed host** (`feedShouldBeSkippedForDisallowedHostReasons`) —
   permanently skips the `nectar-import://` pasted-AO3-link-list import
   feed (`Account.importedLinksFeedURL`; it has no real server behind it,
   articles are written directly via `updateAsync`, so refreshing it can
   never succeed) and a small `badHosts` list (`twitter.com`/`x.com`
   variants — feeds pointed at the old Twitter API, which no longer
   provides feeds). Both are inherited NetNewsWire behavior, not
   Nectar-specific.
2. **AO3 search-results feeds** (`feedShouldBeSkippedForAO3SearchResultsReasons`,
   `isAO3SearchResultsFeed`) — a normal scheduled/background/pull-to-refresh
   pass never re-fetches page 1 of an AO3 search/tag-listing feed once it's
   been added; only the one-off add-time fetch and explicit
   pagination/"load more" touch it after that. Matched on host (AO3's
   domain allowlist) + path shape (`/tags/.../works`, or `/works` with a
   `work_search[...]` query key) — deliberately not by file extension.
3. **Reddit** (`feedShouldBeSkippedForRedditReasons`) — Reddit allows one
   feed fetch per minute, so at most one Reddit feed refreshes per pass
   (the least-recently-checked one); this is also inherited NetNewsWire
   behavior, unrelated to Ambrosia/AO3.

This replaces upstream's general-purpose
`feedShouldBeSkippedForCacheControlReasons`/
`feedShouldBeSkippedForTimingReasons` (a courtesy minimum-refresh-interval
that protects small blog/podcast servers from being hammered), removed
with the comment "Nectar only ever refreshes feeds from the user's own
local Ambrosia server... never a public site the app needs to be polite
to."

**Open gap, not yet resolved:** that removal comment is incomplete. AO3
tag/user RSS/Atom feeds (see AO3 direct feed ingestion above) *are* a
public, non-Ambrosia site, and `isAO3SearchResultsFeed`'s matching only
covers AO3's HTML search/tag-listing *pages* — not AO3's native
`.atom`/RSS feed URLs, which is the actual direct-subscription route. A
regular AO3 tag/user Atom feed subscription has no proactive
skip/minimum-interval protection today; it refreshes on every
scheduled/background/pull-to-refresh pass like an Ambrosia feed, backed
only by `Downloader`'s *reactive* per-host 429/Cloudflare-challenge
handling (see AO3 preface rendering below) as a backstop. This may be
fine in practice given AO3's own aggressive rate limiting, but it's an
open design question, not a settled one — see the remediation plan.

## Background refresh budget and interrupted-feed retry

iOS background refresh runs on `BGTaskScheduler`
(`com.kyrielie.Nectar.FeedRefresh`, registered and scheduled from
`iOS/AppDelegate.swift`), which replaced upstream's in-process
`Timer`-based `AccountRefreshTimer` entirely (not a reimplementation under
a new name — a wholesale move to the standard iOS background-task API).

`AppDelegate` computes the OS-granted remaining execution time, subtracts
a safety margin, and stores the result as
`AccountManager.shared.backgroundRefreshDeadline`.
`LocalAccountRefresher` checks `Date() >= deadline` mid-pagination and, if
the deadline has passed, stops early rather than risking termination
mid-write; feeds it didn't get to are tracked as interrupted. On
completion, `LocalAccountDelegate` posts
`.refreshDidCompleteWithInterruptedFeeds` with the interrupted feed URLs,
which `AppDelegate` observes to decide whether to request another
background pass. `backgroundRefreshDeadline` is cleared (`nil`) once a
refresh pass completes normally or the app returns to the foreground, so
it never leaks a stale deadline into a later foreground-triggered refresh.

## Last Opened smart feed

`LastOpenedFeedDelegate` (`Shared/SmartFeeds/`, Nectar-original, no
upstream counterpart) is a fifth smart feed alongside
Today/Unread/Starred/Loved/Read: the 10 most recently opened articles,
mirroring `ReadFeedDelegate`/`LovedFeedDelegate`'s shape but with a fixed
`FetchType.lastOpened(10)` limit rather than an unbounded fetch — the cap
is enforced via `SQL LIMIT` in `ArticlesTable.fetchLastOpenedArticles`,
not client-side truncation. `SceneCoordinator` calls
`Account.recordBookOpened(articleID:)` (→ `BookStateTable.lastOpenedAt`)
whenever an article is opened, except when the *current* timeline feed is
itself the Last Opened feed (`SidebarItem.forcesLastOpenedSort`, `true`
only for this delegate) — opening an article from inside "Last Opened"
doesn't re-order the list out from under the user mid-browse. Unlike
Read/Loved/Read Later, there's no natural running total to show as a
badge count (the feed is always capped at 10, which says nothing about
library size), so `fetchUnreadCount` is hardcoded to `0` rather than
repurposing the badge for something misleading.

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
5. `readingProgress` is `bookKey`-shared the same way scroll
   position/read/starred/loved are — see Book identity above.

## AO3 preface rendering and on-demand chapter fetch

Two independent paths feed the same `AO3PrefaceRenderer` markup
(`<dl class='tags'>` of flat `<dt>`/`<dd>` pairs): `ArticleRenderer.
ao3SyntheticPrefaceHTML` synthesizes a preface from `Article`'s
already-parsed fields when `contentHTML == nil` (plain-text values, no AO3
links); `AO3ChapterHTMLExtractor.parseWorkHeader` parses AO3's real `<dl
class="work meta group">` off a live-fetched page into the same row/stats
shape (real tag `href`s included) once a chapter fetch has succeeded. The
synthetic path is guarded to never fire when `contentHTML` is already
non-nil — which is always true for Ambrosia items, since Ambrosia's JSON
feed sets `content_html` directly, including its own preface. So an
Ambrosia-sourced article's preface is either Ambrosia's own embedded HTML
(as imported) or, after a successful `AO3ChapterHTMLExtractor` fetch,
AO3's structure re-rendered through `AO3PrefaceRenderer` — `ArticleRenderer`
never synthesizes a preface for an Ambrosia item.

`AO3ChapterFetcher.fetchIfNeeded(for:)` is called from
`WebViewController.setArticle(_:updateView:)` (i.e. whenever an
article is opened in the reader) and, since the fixes below, also from a
throttled background sweep. It requires `article.bookKey` to have the
`ao3-work:` prefix (`AO3ChapterFetcher.ao3WorkID(fromBookKey:)` returns
`nil` otherwise):

- **Anthology/combined-series articles still can't be individually
  refetched, but this is no longer a silent no-op.** `ParsedItem.bookKey`
  resolves anthologies (`isAnthology == true`) to `ao3-series:<id>` or
  `calibre-series:<name>`, never `ao3-work:<id>`, so
  `ao3WorkID(fromBookKey:)` still returns `nil` immediately
  (`AO3ChapterFetcherTests` asserts this directly — deliberate scope, not
  an oversight, since there's no single AO3 URL a Calibre-merged
  compilation could fetch from; fetching+merging every member work was
  explicitly deferred in `ao3-merged-plan.md`). What changed:
  `fetchIfNeeded` now calls `noteAnthologyUnsupportedIfNeeded`, which logs
  an `ActivityKind.skipAO3SeriesFetch` entry and records a
  `lastFetchFailureMessage` ("Combined AO3 series can't be refreshed
  individually — showing imported content") the first time each such
  article is seen, reusing the `attemptDates` dictionary as an
  already-noted gate so reopening the same article repeatedly doesn't
  spam the Activity Log. These articles remain locked to whatever HTML
  Ambrosia supplied at import; `ArticleRenderer`'s "Full text
  unavailable" notice still only fires when `contentHTML == nil`, which
  never happens for an Ambrosia-sourced row, so the failure message
  currently surfaces only in the Activity Log, not inline in the reader.
- **Non-anthology (single-work) articles no longer depend solely on being
  opened.** `AO3ChapterFetcher.init` now observes
  `.AccountRefreshDidFinish` and runs `sweepStaleUnreadArticles(in:)` on
  each account after a refresh: it fetches the account's unread articles,
  filters to those with a resolvable `ao3WorkID` and a stale `isStale`
  result, and calls `fetchIfNeeded` for up to `maxArticlesPerSweep` (5) of
  them, sleeping `secondsBetweenSweepRequests` (5s) between each — scoped
  to unread and bounded/throttled deliberately, since this is the one
  path that can fire several AO3 requests back-to-back with no user
  action in between. `sweepingAccountIDs` guards against two
  `AccountRefreshDidFinish` notifications in quick succession starting
  overlapping sweeps for the same account. An unread single-work article
  can now pick up new formatting/content on the sync cadence rather than
  only the next time it's opened; read articles and combined-series
  articles are unaffected by the sweep.

CSS for the preface (`#ao3SyntheticPreface`/`#ao3Preface`, `dl.tags`
grid layout with `dt`/`dd` on the same row) now lives in `Shared/Article
Rendering/core.css`, not `stylesheet.css`. `ArticleTheme.init(url:
isAppTheme:)` builds a custom theme's CSS as `core.css` + that theme's own
`stylesheet.css` (from its `.nnwtheme` bundle under `Themes/`) —
`core.css` is the one file guaranteed to load for every theme, default or
custom, where `Shared/Article Rendering/stylesheet.css` only loads for the
default theme. Moving the rules fixes the same-line `dt`/`dd` grid layout
for any custom theme (confirmed none of the bundled ones, e.g. Sepia,
define their own `dl`/`dt`/`dd`/`ao3Preface` rules), which previously fell
back to the browser's default `<dl>` box model under a non-default theme.

AO3 fetch requests (`AO3ChapterFetcher.download`) go through
`Downloader.shared`, not `DownloadSession` — a deliberate choice per the
class's own doc comment (one-shot download vs. a feed-refresh session).
`Downloader`'s `URLSessionConfiguration` sends the app's real User-Agent
(`UserAgent.headers()`, from Info.plist's `UserAgent`/`UserAgentExtended`
keys — now `"Nectar (https://github.com/kyrielie/nectar; ...)"`, pointing
at the Nectar project itself rather than the upstream NetNewsWire fork it
was inherited from), forces cookies off, and caps
`httpMaximumConnectionsPerHost` at 1. `Downloader` now has its own
per-host 429/`Retry-After` handling, mirroring (not sharing code with)
`DownloadSession`'s `handle429Response`/
`requestShouldBeDroppedDueToActive429`: a 429 response is parsed into an
`HTTPResponse429` (`Retry-After` header if present and positive, else a
10-minute default — the same default `DownloadSession` uses) and recorded
per lowercased host in `retryAfterMessages`. Any subsequent `download(_:)`
call for that host before the recorded `resumeDate` short-circuits with a
synthetic 429 `HTTPURLResponse` and no network request, until the cooldown
expires. This is a genuine behavior change from `AO3ChapterFetcher`'s own
60-second `attemptDates` floor, which is still per-`articleID` and
unrelated: a rate-limit response for one AO3 article's fetch now also
pauses `Downloader`-routed fetches for *other* AO3 articles (or anything
else on the same host) opened in the same window, via the new per-host
cooldown, in addition to that article's own 60-second floor. A Cloudflare
challenge or other non-429 failure still just fails `response.statusIsOK`
and produces a generic "Could not reach AO3 (HTTP `<code>`)" message; only
the 429 case gets the distinct "AO3 rate limit hit — backing off before
retrying" message and the per-host cooldown.

## Article background/notch color pipeline

`ArticleThemeColorExtractor.colors(for:)` resolves the text/background/link
colors a theme's own stylesheet declares, so the webview background, the
notch cover, and the page-counter text can default to what the theme
actually looks like instead of a generic system color. It's a small
regex-based scanner, not a full CSS parser: it understands literal
`#hex`/`rgb()`/`rgba()` colors, a modest set of named CSS colors, and
`var(--custom-property)` resolved against that theme's own `:root`
declarations (scoped separately for light/dark so a dark-mode redefinition
of a variable doesn't leak into the light-mode result). It does not
understand CSS-4 system color keywords (`Canvas`, `CanvasText`, etc. — these
fall through to "not found" like anything else unparseable) or selector
specificity beyond exact-string matching. `@supports (...)` blocks are
excluded from consideration entirely before scanning starts
(`stripBraceBlocks`), on the basis that they carry platform-specific
overrides this scanner isn't equipped to reason about correctly — as of a
later fix, this also covers the `@supports not (...)` form, which the
original regex missed (`stylesheet.css`'s own macOS-only rules block uses
exactly that form).

Precedence, resolved once per render in
`WebViewController.renderPage()`/`applyResolvedBackgroundColors()` and
applied to the webview, scroll view, and `notchCoverView` together so all
three always agree: override background
(`ArticleThemeOverrides.backgroundColorHex`/`backgroundColorDarkHex`, if
set) → the theme's own extracted background → a black/white fallback if
neither is present.

`applyResolvedBackgroundColors()` also re-runs on its own, without a full
page reload, from a `registerForTraitChanges` handler installed in
`WebViewController.viewDidLoad` (the deployment target is iOS 17+, so this
uses the non-deprecated API rather than overriding
`traitCollectionDidChange`). This is the fix for a "notch cover / webview
background go stale on live appearance change" bug: the webview's own CSS
already updates live via `@media prefers-color-scheme` when the app's
Appearance setting changes or the system trait changes, but
`webView.backgroundColor` and the notch/page-counter colors were previously
resolved only once per `renderPage()` call, off a snapshot of
`webView.traitCollection.userInterfaceStyle` — they stayed wrong until the
next full render (theme change, article change, and so on). Upstream
NetNewsWire doesn't have this problem because it assigns the dynamic system
color `.systemBackground` via storyboard, which tracks trait changes for
free; Nectar's per-theme colors can't be expressed that way, since custom
themes need their own light/dark colors, so this pipeline needs its own
live-invalidation hook that the dynamic-color approach got automatically.

## App chrome color pipeline (Accent Color / Surface Palette)

Two independent systems tint native UIKit chrome, deliberately separate
from the article-reader theme pipeline above — a "Slate" surface palette and a
light article theme can legitimately show different chrome colors at the
same time, that's intended, not a bug to reconcile:

- **Accent Color** (`Assets.Colors.primaryAccent`/`.secondaryAccent`) tints
  icons and progress indicators.
- **Surface Palette** (`SurfacePalette`, `AppDefaults.shared.surfaceTint`)
  tints chrome surface backgrounds as a coordinated set. The Swift type is
  `SurfacePalette`; the `AppDefaults` property, `UserDefaults` key, and
  notification name are still spelled `surfaceTint`/`.surfaceTintDidChange`
  — that's a deliberate leftover from before the type was renamed from
  `SurfaceTint`, kept to avoid a defaults migration, not an inconsistency to
  "fix." `.default` falls back to the existing asset-catalog colorset value
  for each field, same contract `AccentColor.default` uses. Five cases ship
  today: `.default`, `.slate`, `.sepia`, `.forest`, `.berry`.

### SurfacePalette.HexSet: one struct, two appearances, eight fields

Each non-default `SurfacePalette` case supplies a `lightHexSet` and a
`darkHexSet` (both `nil` for `.default`), each a complete `HexSet` of eight
hex-string fields. Every field has a matching `Assets.Colors` accessor that
takes an explicit `UITraitCollection` and branches light/dark off
`traitCollection.userInterfaceStyle`, falling back to the pre-existing
asset-catalog colorset of the same base name when the resolved hex is `nil`
(the `.default` case) or fails to parse:

| `HexSet` field | `Assets.Colors` accessor | Used for |
| --- | --- | --- |
| `barBackground` | `barBackground(for:)` | `ArticleSearchBar`'s bar fill |
| `vibrantText` | `vibrantText(for:)` | Text drawn on top of a tinted bar/surface |
| `fullScreenBackground` | `fullScreenBackground(for:)` | Full-screen transition backdrop (`ImageTransition`) |
| `navigationBarBackground` | — (consumed directly by `SurfacePaletteNavigationBarAware`) | `UINavigationBarAppearance.backgroundColor` |
| `navigationBarTint` | — (consumed directly by `SurfacePaletteNavigationBarAware`) | Nav bar title/back-button/large-title tint |
| `settingsBackground` | `settingsBackground(for:)` | Backdrop behind settings/list table and collection views |
| `settingsCellBackground` | `settingsCellBackground(for:)` | Individual cell fill *inside* that backdrop |
| `listBackground` | `listBackground(for:)` | Feed list + timeline container backdrop |

The `settingsBackground`/`settingsCellBackground` pair (and the
`listBackground`/`settingsCellBackground` pair) exist specifically so a
palette can keep a **container** and the **cells drawn on top of it**
visually distinct — the cell color is always the lighter, more-legible one
of the pair in both appearances, e.g. Slate dark's `listBackground` is
`#16191E` against a `settingsCellBackground` of `#262B33`. Any new
card/cell/row that sits on top of a `listBackground` or `settingsBackground`
surface should read `settingsCellBackground`, not re-use the container's
own color — using the same color for both makes the row visually disappear
into its container instead of standing out, and reads as broken (not merely
flat) once a non-default palette is active. `MainTimelineCell` establishes
this pattern for timeline cards; `MainFeedCollectionViewCell`/
`MainFeedCollectionViewFolderCell` follow it for feed-list rows.

### Live-update pipeline shape

Setting `AppDefaults.shared.accentColor`/`.surfaceTint` posts
`.accentColorDidChange`/`.surfaceTintDidChange` **synchronously** (the
setter calls `NotificationCenter.default.post` directly, on the same
thread, before the setter returns), an observer forces a repaint, and the
repaint reads `Assets.Colors.*` fresh — these are deliberately non-cached,
live per-read properties, not resolved once and stored.

The synchronous-post detail matters for any screen that changes the
palette from inside a `UITableViewDelegate`/`UICollectionViewDelegate`
selection callback (`didSelectRowAt:`, etc.): setting
`AppDefaults.shared.surfaceTint` there re-enters the same view controller's
own `.surfaceTintDidChange` observer *before* `didSelectRowAt:` reaches any
code after the assignment. If that observer and the selection handler's own
follow-up code both call `reloadSections`/`reloadData` on the section
containing the just-tapped row, UIKit's post-selection bookkeeping
(restoring the checkmark/highlight after the delegate call returns) can run
against a section that was torn down and rebuilt twice underneath it,
leaving the checkmark on the previously-selected row instead of the one
just tapped. `ColorPaletteTableViewController` and
`AccentColorTableViewController` both guard against this the same way: a
`isHandling*Selection` flag suppresses the notification-driven reload while
the selection handler's own (single, combined) `reloadSections` call is in
flight, so the row's own section is only ever rebuilt once per tap. Any new
screen that both listens for `.surfaceTintDidChange`/`.accentColorDidChange`
*and* changes that same default from its own selection handling needs the
same guard, not just a same-section double-reload "coincidentally working."

Current observer list for each notification, kept here explicitly so the
next person adding a Surface-Palette-consuming view knows to add an
observer too:

**Accent Color** (`.accentColorDidChange`): `SceneDelegate`,
`MainFeedCollectionViewController`, `MainTimelineModernViewController`,
`AccentColorTableViewController`.

**Surface Palette** (`.surfaceTintDidChange`): `ArticleSearchBar`, which
bakes `barBackground` into a `CGColor` once in `didMoveToSuperview()` and so
needs its own observer to repaint on a live change (added as part of the
same fix that gave the article pipeline above its own live-invalidation
hook — same underlying shape, "new machinery added without the free
live-update behavior a dynamic system color would have given it");
`MainFeedCollectionViewController`, which repaints `listBackground` and
reloads the collection view so each row's `settingsCellBackground` fill
gets recomputed; `MainTimelineModernViewController`, same reasoning;
`ColorPaletteTableViewController`, `AccentColorTableViewController`, and
`SettingsBackgroundPalette`/`SurfacePaletteAware` (SwiftUI-facing), which
repaint the Settings screens' own `settingsBackground`/
`settingsCellBackground` fills; `SettingsViewController`. `Vibrant*` views
(`VibrantLabel`/`VibrantButton`/`VibrantTableViewCell`) deliberately don't
observe it, since they already re-read `.vibrantText` on every
highlight/selection state toggle, which happens far more often than a
Surface Palette change — the staleness window is bounded by the next
interaction, not indefinite the way `ArticleSearchBar`'s baked `CGColor`
was. `ImageTransition` deliberately doesn't observe it either, since it
reads `.fullScreenBackground` fresh at the start of each transition, which
is already "live" for practical purposes.

`SurfacePalette.HexSet` originally also carried `controlBackground` and
`sectionHeader` fields; both were removed (along with the corresponding
`Assets.Colors` properties) once grep confirmed zero non-definition call
sites for either — dead fields from early in Surface Palette's design, never
wired to an actual consumer. If a future engineer finds this file compared
against an old planning doc and wonders why `HexSet` looks incomplete,
that's why.

### Nav bar appearance: `SurfacePaletteNavigationBarAware`

`ArticleViewController`, `MainFeedCollectionViewController`, and
`MainTimelineModernViewController` all adopt
`SurfacePaletteNavigationBarAware` (`Shared/Extensions/`) and call
`applySurfacePaletteNavigationBarAppearance()` once from `viewDidLoad()`
and again from their own `.surfaceTintDidChange`/trait-change handlers. The
shared method always builds an opaque `standardAppearance`/
`compactAppearance` from `navigationBarBackground`/`navigationBarTint` (the
bar once a large title has collapsed, or in compact height), but branches on
a protocol property, `wantsTransparentScrollEdgeAppearance` (default
`false`), for `scrollEdgeAppearance` — the bar shown at the *top* of the
content, before any scrolling:

- `ArticleViewController` leaves it `false`: there's no card/list content
  behind the bar for it to blend with, so it wants the same opaque fill in
  every scroll state, and already configures `scrollEdgeAppearance` opaquely
  itself before its first call to `applySurfacePaletteNavigationBarAppearance()`.
- `MainFeedCollectionViewController` and `MainTimelineModernViewController`
  override it to `true`: both sit on top of a scrolling list of cards/rows,
  and want the system's normal large-title behavior where the bar is
  transparent at the top and only opaque once content has scrolled
  underneath it, so the bar matches whatever's drawn there (the transparent
  sidebar "glass," or a timeline card's own `settingsCellBackground`,
  visible through it) instead of imposing a flat `navigationBarBackground`
  fill that reads as a mismatched strip at the top of the screen.

This split exists because `applySurfacePaletteNavigationBarAppearance()`
was extracted from `ArticleViewController`'s own (correct, always-opaque)
implementation and reused as-is by the other two screens; unconditionally
setting `scrollEdgeAppearance` to the same opaque `appearance` object as
`standardAppearance` regressed both of their previously-transparent top
edges. Any *future* screen adopting this protocol should think about which
side of that split it's on before assuming the default (`false`, opaque) is
correct — the wrong choice is silent (nothing crashes) and only shows up as
a color mismatch at the very top of the content.

`Assets.Colors`'s existing dark/light-branching properties
(`barBackground`, `vibrantText`, `fullScreenBackground`) resolve their
branch via `UITraitCollection.current`, which Apple documents as valid only
inside specific framework-invoked callbacks (drawing methods,
dynamic-color/image resolution, trait-change handlers) — undefined
elsewhere, and `Assets.Colors` is a bare `static var` namespace with no
view/window reference, called from places like
`ArticleSearchBar.didMoveToSuperview()` that aren't among those blessed
contexts. This is flagged as theoretical fragility in a doc comment on
`barBackground`, not yet confirmed as a reproducing bug on-device. The
article-background pipeline above avoids the same trap by reading a real
view's `.traitCollection` (`WebViewController.applyResolvedBackgroundColors`
reads `webView.traitCollection`) rather than the ambient current one — any
*new* `Assets.Colors` property should follow that pattern, taking an
explicit trait collection parameter, rather than copying the existing
three properties' pattern.

## Settings screen structure

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list: icon size (0), number of lines
(1), no-icon preview (2), icon preview (3). Sections 2/3 render a live
`MainTimelineCell` built from a hardcoded `previewArticle` and reload on
`UserDefaults.didChangeNotification` for the two sliders currently wired up.

## Planning notes

`docs/` is gitignored, but is present in this working tree (a previous
version of this note said it wasn't — that was stale, or was written
before these files were checked in as an exception to the ignore rule).
It holds working notes for in-progress and completed fork work
(`nectar-plan-v3.md`, `nectar-fixes-plan.md`, `nectar-fixes-plan-2.md`,
`nectar-bug-report.md`, `nectar-loved-icon-heart-plan.md`,
`netnewswire-fork-plan.md`, `feed-api.md`). These are design/debugging
scratch documents, not guaranteed to reflect the shipped state — this file
is the source of truth for current architecture.
