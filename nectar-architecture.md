# Nectar Architecture

Nectar is a private iOS fork of NetNewsWire, repointed at "Ambrosia" — a JSON
Feed–based backend that extends the JSON Feed 1.1 spec with an `_ambrosia`
object carrying fic-reader metadata (word count, chapters, fandom,
rating/warnings, series). Confirmed against the current source tree.

## Module layout

SPM packages live under `Modules/`. The ones with app-specific relevance:

- **Modules/RSParser** — feed/OPML/HTML parsing, no app dependencies.
  `JSONFeedParser` reads the standard JSON Feed fields (`summary`,
  `content_html`/`content_text`) and separately reads the `_ambrosia`
  extension object, producing a `ParsedItem` with both the standard fields
  and the Ambrosia-specific ones (`wordCount`, `chapterCurrent/Total`,
  `isComplete`, `fandoms`, `relationships`, `characters`, `ratings`,
  `warnings`, `categories`, `series`).
- **Modules/Articles** — the persisted domain model. `Article` mirrors
  `ParsedItem` 1:1, including the Ambrosia fields and a `summary: String?`
  distinct from `contentHTML`/`contentText`. `ArticleStatus` holds
  per-article mutable state — `read`, `starred`, and `readingProgress:
  Double?` (local UI state, not synced, same tier as scroll position).
- **Modules/ArticlesDatabase** — SQLite-backed persistence for articles,
  status, and search (`ArticlesTable`, `StatusesTable`, `SearchTable`).
  Scroll position and reading progress are columns here, not UserDefaults.
- **Modules/Account** — account management and sync services (Feedbin,
  Feedly, Reader API, NewsBlur, CloudKit, local/Ambrosia), built on top of
  `ArticlesDatabase`.
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

## Data flow: feed to card

1. `JSONFeedParser` parses an Ambrosia JSON Feed response into `ParsedItem`s,
   reading `summary` and `_ambrosia.*` as sibling fields to `content_html`.
2. Account sync code persists these into `ArticlesDatabase`, producing
   `Article` values with `summary` and the Ambrosia fields populated.
3. `MainTimelineCellData.init(article:...)` calls
   `ArticleStringFormatter.shared.truncatedSummary(article)` for the card's
   body preview, and reads `article.wordCount`/`fandoms`/`isComplete`/
   `ratings`/`warnings` directly for the metadata line.
4. `ArticleStringFormatter.truncatedSummary` prefers `article.summary` when
   present and non-empty, falling back to `article.body`
   (`contentHTML ?? contentText ?? summary`) otherwise, then truncates to
   300 characters and caches the result keyed by `(articleID, accountID)`.

## Reading-progress data flow

1. `WebViewController` tracks `windowScrollY` via a JS bridge and coalesces
   scroll updates through a 0.3s `CoalescingQueue`.
2. On each coalesced update it evaluates JS to read `scrollY`/`scrollHeight`/
   `innerHeight`, writes the raw offset via
   `account.saveScrollPosition(_:forArticleID:)` (per-article, in
   `ArticlesDatabase`), and separately checks the existing 99%-of-height
   threshold to mark the article read.
3. `setArticle` restores position for the article being opened via
   `account.fetchScrollPosition(forArticleID:)` — correct, per-article.
   `isAwaitingInitialScrollFetch` suppresses `viewDidLoad`'s unconditional
   render-at-0 while this fetch is in flight, and `pendingLoadResets`
   (a count, not a single boolean) suppresses the corresponding N
   post-load scroll-reset events for overlapping loads.
4. `SceneCoordinator.restoreWindowState` / Handoff resume instead read the
   single global `AppDefaults.shared.articleWindowScrollY`. `windowScrollY`'s
   `didSet` still writes that global on every scroll update, alongside the
   per-article write in (2) — deliberately left in place (see the comment
   in `WebViewController`) because relaunch/Handoff restore still depends
   on it. This remains a known source of restore inaccuracy across
   relaunch/Handoff specifically (every open article's scroll updates
   overwrite the one global slot), distinct from the same-session
   reopen race that has since been fixed via `isAwaitingInitialScrollFetch`
   and `pendingLoadResets` above.

## Settings screen structure

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list: icon size (0), number of lines
(1), no-icon preview (2), icon preview (3). Sections 2/3 render a live
`MainTimelineCell` built from a hardcoded `previewArticle` and reload on
`UserDefaults.didChangeNotification` for the two sliders currently wired up.

## Planning notes

`docs/` holds working notes for in-progress and completed fork work
(`nectar-plan-v3.md`, `nectar-fixes-plan.md`, `nectar-loved-icon-heart-plan.md`,
`netnewswire-fork-plan.md`, `feed-api.md`). These are design/debugging
scratch documents, not guaranteed to reflect the shipped state — this file
is the source of truth for current architecture.
