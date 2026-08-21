# Nectar docs index

Nectar is a private iOS fork of NetNewsWire, repointed at "Ambrosia" — a
JSON Feed–based backend that extends the JSON Feed 1.1 spec with an
`_ambrosia` object carrying fic-reader/book metadata (word count,
chapters, fandom, rating/warnings, series, book identity), plus a
paginated SQLite transfer route for large-collection sync. `nectar-
architecture.md` (repo root) no longer exists as a single file — its
content has been split into the topic docs below, each scoped to what an
engineer needs for one system. **Read only the doc(s) relevant to your
task**, not this whole index cover-to-cover.

## Read this first if you're fixing something in...

- **Feed parsing / JSON Feed / `_ambrosia` extension** → `module-layout.md`, `ambrosia-feed.md`
- **Annotations (highlights + notes), anchor resolution, the annotations toolbar/settings UI** → `annotations.md`
- **AO3 RSS/Atom subscription (the feed itself)** → `ao3-direct-feed-ingestion.md`, `ao3-feeds.md`
- **AO3 search-results pagination, "Load more", or fetching a specific page number** → `ao3-arbitrary-page-fetch.md`, `ao3-integration.md`
- **AO3 HTML extraction internals** (summary/work-page/series parsing) → `ao3-feeds.md`
- **AO3 login/session, kudos-on-like, the in-app AO3 browser** → `ao3-authenticated-reading.md`
- **AO3 networking/session layer generally** → `ao3-integration.md`
- **AO3 preface rendering or on-demand chapter fetch in the reader** → `ao3-preface-rendering.md`
- **Article scroll position / reading progress** → `reading-progress.md`
- **"Same book" identity across feeds/re-imports** (`bookKey`) → `book-identity.md`
- **Large (`.sqlite`) library import** → `sqlite-transfer.md`
- **Feed drag-reorder within a container (sidebar manual ordering)** → `feed-reordering.md`
- **A feed's address changing / OPML repoint** → `feed-repointing.md`
- **Refresh not firing, firing too often, or background refresh** → `refresh-throttling.md`
- **Article background/notch color, or webview appearance live-update** → `article-color-pipeline.md`
- **Accent Color / Surface Palette / nav bar tinting (app chrome)** → `app-chrome-palette.md`
- **Badge Colors (timeline rating/category/warning pill tinting)** → `app-chrome-palette.md`
- **Article theme (`.nnwtheme`) system itself** → `theme-system.md`
- **`.nnwtheme` bundle format / authoring / theme families** → `nnwtheme-format.md`
- **Database schema / SQLite storage layer** → `database.md`
- **Settings screen, any toggle, or "does setting X exist"** → `settings-screen.md` (main screen) **and** `ao3-authenticated-reading.md` (the separate AO3 account screen — easy to miss)
- **Favicon / page metadata extraction** → `metadata-extraction.md`
- **"What differs from upstream NetNewsWire"** → `upstream-drift.md`
- **A recurring Auto Layout / UIKit console warning** (before re-investigating one from scratch) → `console-warnings.md`
- **An open question that used to have temporary debug logging attached to it** → `investigate-later.md`

If nothing above fits, grep the codebase before assuming it's
undocumented — this split is complete as of the date below, but the
codebase moves faster than docs do. See "Keeping this current" below.

## Conventions every doc here follows

- **Confirmed-vs-inferred language.** These docs describe what the code
  currently does, verified by reading it — not what a comment claims, not
  what a variable name implies, not what's "supposed to" happen. Where a
  doc can't confirm something, it says so rather than asserting it.
- **Describes behavior, not grievances.** Known bugs/gaps are called out
  inline where relevant to understanding the system, but this doc set is
  not a bug tracker or a TODO list.
- **Cross-references by filename**, e.g. `see book-identity.md`, not "see
  above/below" — these docs are meant to be read individually, not as
  chapters of one long file.
- **A "dangling reference" pattern is called out, not silently fixed,
  wherever found.** Several docs note in-code comments citing a planning
  file (`docs/nectar-audit-remediation-plan.md`,
  `docs/nectar-implementation-plan.md`, `ao3-merged-plan.md`,
  `ao3-merged-plan-nectar.md`, `nectar-ao3-features-plan-FINAL.md`,
  `nectar-theme-background-toolbar-plan.md`, `toolbar-style-plan.md`,
  `nectar-navbar-toggle-plan.md`, and — present in one snapshot of this
  repo, absent from a later one — `nectar-fixes-plan-3.md`) that is not
  present anywhere in the current tree. This is now an eight-plus-file
  pattern, not a one-off. `.gitignore` only excludes
  `plans/`, not `docs/`, so gitignore status alone doesn't explain it —
  treat the cause as an open question (see "Keeping this current" below),
  not a solved mystery, and don't assume a missing file means the work
  described around it didn't happen. The code and tests are the ground
  truth; a missing plan doc is a missing citation, not missing evidence.

## Keeping this current

**If you're an AI engineer (or anyone) making a change, update the
relevant doc(s) below as part of the same change — not as a follow-up,
not "someone will get to it."** A stale doc is worse than no doc, because
it's trusted by default. Specifically:

| If your change touches... | Update... |
| --- | --- |
| `RSParser`/`JSONFeedParser`, the `_ambrosia` extension fields, `ParsedItem` | `module-layout.md`, `ambrosia-feed.md` |
| `bookKey` computation (Swift or the SQL `CASE` mirror), `BookStateTable` | `book-identity.md` |
| `AmbrosiaSQLiteImportTable`, `AmbrosiaSQLiteTransferFetcher`, the `.sqlite` route | `sqlite-transfer.md` |
| `OrderedSet<Feed>`, `Container.topLevelFeeds`, `addFeedToTreeAtTopLevel(_:at:)`, `AccountDelegate.moveFeed`'s `targetIndex` parameter | `feed-reordering.md` |
| `AO3IgnoreList`, `AO3SummaryExtractor` call sites in `RSSItem`/`AtomParser`, AO3 RSS/Atom subscription wiring | `ao3-direct-feed-ingestion.md` |
| `FeedSettings.ao3SearchFetchedPages`/`.ao3SearchTotalPages`, `AO3SearchResultsPaginator.nextPageToFetch`/`.validate`/`.fetchSpecificPage`, `AO3SearchResultsImporter.importFetchedPage`, `AO3SearchResultsFetchCoordinator.presentSolverAndRetry`'s `updatesFeedName` parameter, `FeedInspectorViewController`'s AO3 Pages section | `ao3-arbitrary-page-fetch.md` |
| The AO3 HTML extractors themselves (`Modules/RSParser/.../Feeds/Extensions/`) | `ao3-feeds.md` |
| `Feed.repoint(to:)`, `collectionKeyIndex`, `rewriteAmbrosiaJSONFeedURLs` | `feed-repointing.md` |
| `LocalAccountRefresher.feedShouldBeSkipped`, `BGTaskScheduler`/`backgroundRefreshDeadline`, `LastOpenedFeedDelegate` | `refresh-throttling.md` |
| `WebViewController`'s scroll-position tracking, `BookStateTable` reading-progress fields, `articleWindowScrollY` | `reading-progress.md` |
| `AO3ChapterFetcher`, `AO3ChapterHTMLExtractor`, `AO3PrefaceRenderer`, `Downloader`'s per-host 429 handling | `ao3-preface-rendering.md` |
| `AO3SessionStore`, `AO3AuthenticatedFetcher`, `AO3AuthenticatedWebViewController`, `AO3ChallengeSessionStore`, `AO3KudosManager`, `AO3AccountSettingsView`, or any `NectarAppGroupUserDefaults`-backed AO3 preference | `ao3-authenticated-reading.md` |
| `ArticleThemeColorExtractor`, `ArticleResolvedColors`, `WebViewController.applyResolvedBackgroundColors`/`registerForTraitChanges` | `article-color-pipeline.md` |
| `SurfacePalette`, `AccentColor`, `SurfacePaletteNavigationBarAware`, `ToolbarStyle`/`toolbarStyle`, `BadgeColorPalette`, `BadgeColorTable` | `app-chrome-palette.md` |
| `.nnwtheme` bundles, `ArticleTheme`, `ArticleThemesManager`, `core.css`/`stylesheet.css` structure | `theme-system.md` |
| `.nnwtheme` bundle-file layout, per-theme fonts, theme families, `template.html` conventions | `nnwtheme-format.md` |
| `ArticlesDatabase` schema/tables not covered by a more specific doc above | `database.md` |
| Any row/case in `SettingsViewController`'s `*Row` enums, `Settings.storyboard`, or `AppDefaults` | `settings-screen.md` |
| `HTMLMetadata`/favicon extraction | `metadata-extraction.md` |
| `AnnotationsTable`, `Annotation`, `annotations.js`, the `textWasSelected`/`annotationWasTapped` message-handler cases, `AnnotationCSVExporter`, the `annotations` table in `ArticleSQLiteExportTable` | `annotations.md` |
| Anything you deliberately did differently from upstream NetNewsWire behavior | `upstream-drift.md` |

If a change doesn't fit any row above — new system, new cross-cutting
concern, or something genuinely new — **add a new doc** rather than
folding it into an unrelated one (see `ao3-authenticated-reading.md` for
a recent example: a big enough new feature cluster to earn its own file
rather than being wedged into `ao3-preface-rendering.md`), and add a row
to both the routing list above and this table.

If you're an AI engineer and can't tell which doc(s) your change touches,
err toward updating more rather than fewer — a doc that mentions a system
in passing, even briefly, should still get its cross-reference or a
one-line note refreshed if that mention goes stale, not just the doc
that's "primarily about" that system.

**On the dangling-reference problem specifically:** if you're about to
cite a planning/spec doc in a comment (`// see docs/whatever-plan.md`),
either (a) confirm the file exists in the tree first, or (b) fold the
relevant decision directly into the nearest doc above instead of citing a
scratch file that may not survive to the next snapshot. Six-plus missing
citations in this codebase already is a sign this practice isn't working
as a durable record.

## Files not covered by any topic doc

As of this audit, there are none — every module/file cluster below has at
least one topic doc that covers it, per the routing table above. This
section exists to list any gap that turns up later, not to leave a claim
of completeness unverifiable; if a file or system stops fitting any row
above, name it here rather than leaving it silently undocumented.

`nectar-architecture.md` itself is retired — deleted once this split was
verified to cover its full section list 1:1. It is not one of the "files
not covered" above; it simply no longer exists. If you find a stray
reference to it (comments, other docs, tooling), replace it with the
specific current topic doc from the routing table above, not with a
reference to this section.
