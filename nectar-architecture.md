# Nectar Architecture

Nectar is a private iOS fork of NetNewsWire, repointed at "Ambrosia" — a JSON
Feed–based backend that extends the JSON Feed 1.1 spec with an `_ambrosia`
object carrying fic-reader metadata (word count, chapters, fandom,
rating/warnings, series). Confirmed against the current source tree.

## Module layout

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
- **Modules/Account** — account management, sync services (Feedbin, Feedly,
  Reader API, CloudKit, local), and `ArticlesDatabase`/`StatusesTable`,
  the SQLite-backed persistence layer. Scroll position and reading progress
  are columns here, not UserDefaults.
- **Shared/** — cross-platform (iOS/Mac) formatting and rendering:
  `ArticleStringFormatter` (title/summary truncation and caching),
  `ArticleRenderer` (HTML page assembly for the web view).
- **iOS/** — UIKit app target. Key areas for current work:
  - `iOS/MainTimeline` — the article list. `MainTimelineCellData` builds
    per-row display state from an `Article`; `MainTimelineCellLayout`
    computes rects; `MainTimelineCell` renders.
  - `iOS/Article` — `WebViewController` (article web view, scroll tracking,
    read-marking), `ArticleViewController`.
  - `iOS/Settings` — `SettingsViewController` (app settings list) and
    `TimelineCustomizerCollectionViewController` (Timeline Layout screen:
    icon size, line count, and a live `MainTimelineCell` preview).
  - `SceneCoordinator`/`SceneDelegate` — navigation, state restoration,
    Handoff.

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
   `account.saveScrollPosition(_:forArticleID:)`, and separately checks the
   existing 99%-of-height threshold to mark the article read.
3. `setArticle` restores position for the article being opened via
   `account.fetchScrollPosition(forArticleID:)` — correct, per-article.
4. `SceneCoordinator.restoreWindowState` / Handoff resume instead read the
   single global `AppDefaults.shared.articleWindowScrollY`, which every
   article's scroll updates overwrite — the source of the relaunch/Handoff
   restore bug.

## Settings screen structure

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list: icon size (0), number of lines
(1), no-icon preview (2), icon preview (3). Sections 2/3 render a live
`MainTimelineCell` built from a hardcoded `previewArticle` and reload on
`UserDefaults.didChangeNotification` for the two sliders currently wired up.
