# Module layout

Map of `Modules/`, `Shared/`, and `iOS/` and what each owns. Start here if
you don't yet know which package/target a change belongs in.

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
  `ParsedItem` also carries `tags: Set<String>?` — the standard JSON Feed
  1.1 field, not an `_ambrosia` one — which becomes `Article.additionalTags`
  (renamed, converted to a sorted `[String]?` for stable ordering; see
  `Modules/Articles`, below). `ParsedItem` also carries `isAmbrosiaItem` (true whenever an `_ambrosia`
  object is present at all, regardless of which fields inside it are
  populated) and a computed `bookKey`, used for identifying "the same book"
  across feeds/re-subscriptions/re-imports — see `book-identity.md`.
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
  Nectar-original smart feed with no upstream counterpart, described in
  `refresh-throttling.md`).
- **iOS/** — the only compiled app target. Key areas for current work:
  - `iOS/MainTimeline` — the article list. `MainTimelineCellData` builds
    per-row display state from an `Article`; `MainTimelineCellLayout`
    computes rects; `MainTimelineCell` renders.
  - `iOS/Article` — `WebViewController` (article web view, scroll
    tracking, read-marking), `ArticleViewController`.
  - `iOS/Settings` — `SettingsViewController` (app settings list) and
    `TimelineCustomizerCollectionViewController` (Timeline Layout screen:
    icon size, line count, and a live `MainTimelineCell` preview). See
    `settings-screen.md`.
  - `SceneCoordinator`/`SceneDelegate` — navigation, state restoration,
    Handoff.

Note: several `#if os(macOS)` branches survive from the upstream NetNewsWire
codebase but nothing macOS is currently built or shipped for Nectar.
