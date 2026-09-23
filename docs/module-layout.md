# Module layout

Map of `Modules/`, `Shared/`, and `iOS/` and what each owns. Start here if
you don't yet know which package/target a change belongs in.

SPM packages live under `Modules/`. The ones with app-specific relevance:

- **Modules/RSParser** — feed/OPML/HTML parsing, no app dependencies.
- **Modules/AO3Kit** — AO3 HTML extraction, authenticated AO3 utilities,
  preferences, and search-result import mechanics. It never depends on Account.
  `JSONFeedParser` reads the standard JSON Feed fields (`summary`,
  `content_html`/`content_text`) and separately reads the `_ambrosia`
  extension object, producing a `ParsedItem` with both the standard fields
  and the Ambrosia-specific ones: `wordCount`, `chapterCurrent/Total`,
  `isComplete`, `fandoms`, `relationships`, `characters`, `ratings`,
  `warnings`, `categories`, `series`, plus the book-identity fields
  `ao3WorkID`, `isAnthology`, `ao3SeriesID`, and `seriesName` (the
  Calibre-derived fallback name for an anthology with no AO3 series id).
  `ParsedItem` also carries `tags: Set<String>?` — the standard JSON Feed
  1.1 field, not an `_ambrosia` one — which becomes `Article.additionalTags`
  (renamed, converted to a sorted `[String]?` for stable ordering; see
  `Modules/Articles`, below). `ParsedItem` also carries `isAmbrosiaItem` (true whenever an `_ambrosia`
  object is present at all, regardless of which fields inside it are
  populated) and a computed `bookKey`, used for identifying "the same book"
  across feeds/re-subscriptions/re-imports — see `book-identity.md`.
  `ParsedItem` separately carries a cluster of AO3-native fields that are
  **not** part of `_ambrosia` at all — `commentCount`/`kudosCount`/
  `bookmarkCount`/`hitCount`/`dateBookmarked` — populated from a live AO3
  fetch or listing-page scrape rather than the feed itself; see
  `ambrosia-feed.md` for the distinction and `ao3-feeds.md` for where each
  one is read.
  `ParsedItem` also carries a `markdown` field: when present, RSParser
  renders it to HTML via `Tidemark.markdownToHTML` and uses that as
  `contentHTML` (falling back to any provided `contentHTML` if the
  rendered result is empty). `JSONFeedParser` also logs, via `os.Logger`
  (`.notice`), an item-count summary for every parse plus a reason for
  each individual dropped item (missing `uniqueID`, missing content) and
  each same-`uniqueID` collision within one feed — read this log first
  when chasing "why did this item disappear." `RSParser` also has a
  second, independent ingestion path that doesn't go through
  `JSONFeedParser` at all — see `ao3-direct-feed-ingestion.md`.
- **Modules/Articles** — the persisted domain model. `Article` mirrors
  `ParsedItem` field-for-field, including the Ambrosia fields, `markdown`,
  and `bookKey` (always resolves to at least `uniqueID`, so it's
  non-optional), and a `summary: String?` distinct from
  `contentHTML`/`contentText` — with one exception: `ParsedItem.tags`
  becomes `Article.additionalTags`, above. `ArticleStatus` holds per-article mutable
  state — `read`, `starred`, `loved`, and `readingProgress: Double?`
  (local UI state, not synced, same tier as scroll position).
- **Modules/ArticlesDatabase** — SQLite-backed persistence for articles,
  status, and search (`ArticlesTable`, `StatusesTable`, `SearchTable`).
  `articles.contentHTML` is stored LZFSE-compressed and base64-encoded
  (`ContentHTMLCompression`), reusing the same compression Foundation API
  the CloudKit sync path already relies on; a row that fails to
  decode/decompress falls back to returning the stored string as-is rather
  than throwing. `BookStateTable` holds book-level state, one row per
  `bookKey` — see `book-identity.md`. `AmbrosiaSQLiteImportTable` /
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
  feed to one of two fetch paths per refresh (see `sqlite-transfer.md`) and,
  separately, decides per-refresh whether a feed should be skipped this pass
  at all (see `refresh-throttling.md`). A
  feed's fetch address (the Ambrosia server's LAN IP) can change without
  changing its `feedID` — see `feed-repointing.md`.
  Standalone Ambrosia identity, transfer-format, walk-state, and SQLite-fetch
  utilities live under `Sources/Account/LocalAccount/Ambrosia/`. They remain in
  Account because they orchestrate Account refreshes and database APIs; there
  is intentionally no standalone Ambrosia package or shared identity package.
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
- **Modules/HexColor** — `UIColor` <-> CSS hex string conversion and WCAG
  contrast-ratio comparison, extracted from `ArticleThemeColorExtractor.swift`
  (Modularization Stage 0a) because its reach turned out to span 14 files
  across the Accent Color / Surface Palette / Badge Color / Highlight
  Palette systems, not just that file's own CSS-stylesheet scanner.
  Dependency-free beyond `UIKit`.
- **Modules/ArticleTheming** — `.nnwtheme` bundle loading, the theme
  registry (`ArticleThemesManager`), per-reader font/color overrides
  (`ArticleThemeOverrides`), and CSS color extraction
  (`ArticleThemeColorExtractor` / `ArticleResolvedColors`). Extracted from
  `Shared/ArticleStyles/` (Modularization Stage 0b). Needs one piece of
  app-target state it can't own itself (the persisted current theme name,
  which is `AppDefaults`) -- see `ArticleThemeNameStoring` for the
  protocol seam `AppDefaults` conforms to, injected by `AppDelegate.swift`
  before `ArticleThemesManager.start()` is called. Depends on `RSCore`,
  `HexColor`, and `Zip`.
- **Shared/** — cross-platform (iOS/Mac target scaffolding, though only iOS
  is actually built — see below) formatting and rendering:
  `ArticleStringFormatter` (title/summary truncation and caching),
  `ArticleRenderer` (HTML page assembly for the web view), `Assets.swift`
  (icon/color constants, including the fork's Loved/heart and Ambrosia
  additions), `ReadingProgress/ReadingProgressEvaluator` (the pure math
  behind per-scroll-sample reading progress and the shared completion
  threshold, split out of `WebViewController` so it can be unit-tested; see
  `reading-progress.md`), and `SmartFeeds/` (Today/Unread/Starred/Loved/Read/**Last
  Opened** smart feeds — `LovedFeedDelegate` uses a dedicated filled-heart
  icon, not the Starred bookmark icon; `LastOpenedFeedDelegate` is a
  Nectar-original smart feed with no upstream counterpart, described in
  `refresh-throttling.md`).
- **iOS/** — the only compiled app target. Key areas for current work:
  - `iOS/MainTimeline` — the article list. `MainTimelineCellData` builds
    per-row display state from an `Article`; `MainTimelineCellLayout`
    computes rects; `MainTimelineCell` renders.
  - `iOS/Article` — `WebViewController` (article web view, scroll
    tracking, read-marking; the per-sample progress math itself lives in
    `Shared/ReadingProgress`), `ArticleViewController`.
  - `iOS/AppDefaults.swift`: the settings singleton. Feature-owned settings
    are split into `extension AppDefaults` files next to the feature
    (`iOS/ScreenTime/AppDefaults+ScreenTime.swift`,
    `iOS/ReadingStats/AppDefaults+ReadingStats.swift`); see
    `settings-screen.md`. Other groups (reader, toolbar, annotations, text
    replacement) are still in the main file under `// MARK:` banners and are
    the next candidates to move.
  - `iOS/Settings` — `SettingsViewController` (app settings list) and
    `TimelineCustomizerCollectionViewController` (Timeline Layout screen:
    icon size, line count, and a live `MainTimelineCell` preview). See
    `settings-screen.md`.
  - `SceneCoordinator`/`SceneDelegate` — navigation, state restoration,
    Handoff.

Note: several `#if os(macOS)` branches survive from the upstream NetNewsWire
codebase but nothing macOS is currently built or shipped for Nectar.

## Lint size ratchet

`.swiftlint.yml` enables `file_length` and `type_body_length` as
warnings only. They exist to make growth in the app target's largest
files visible, not to enforce a target size: `swiftlint lint --strict`
runs in CI (`.github/workflows/ci.yml`) and promotes any reported warning
to a failure, so each threshold must stay above the current worst file or
it breaks the build.

- `file_length` is set just above `iOS/Article/WebViewController.swift`
  (3,135 lines as of this writing).
- `type_body_length` (2600) was not measured against the real largest type
  body and is likely far too loose; measure with a local `swiftlint` run
  and lower it to just above the real maximum.
- Lower both numbers as the large files shrink. Do not jump to SwiftLint's
  defaults (400 / 250), which would flag most of the largest files at once.

The files this is aimed at are the ones over 1,000 lines in `iOS/`, all of
which are view controllers, a coordinator, or a settings singleton:
`WebViewController`, `SceneCoordinator`, `AppDefaults`,
`MainTimelineModernViewController`, `MainFeedCollectionViewController`,
`ArticleViewController`, `AnnotationsListView`, `SettingsViewController`.
`Shared/` and `Modules/` have essentially none. The pattern that keeps
them from growing further is to extract logic downward into plain
value types or the owning package (e.g. `Shared/`, `ArticlesDatabase`) and
test it there, rather than adding more to the view controller; see
`ProvisionalAO3StubDetectionTests` and
`SurfacePaletteNavigationBarAwareToolbarStyleTests` for the two extraction
patterns already used in this repo.

## Test plans

CI runs `Nectar-CI.xctestplan` (`-testPlan Nectar-CI` in
`.github/workflows/ci.yml` and `test.sh`); `NetNewsWire-iOS.xctestplan` is
the default plan and runs only `Nectar-iOSTests`. A package's test target
only runs in CI if it is listed in `Nectar-CI.xctestplan`: having a
`.testTarget` in a package's `Package.swift` is not enough. When adding a
package test target, add its entry there too. Both plans have
`codeCoverage` enabled so coverage of the large `iOS/` files can be tracked
over time; it does not change test behavior.
