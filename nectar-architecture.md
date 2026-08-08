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
