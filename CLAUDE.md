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
- **What counts as an AO3 URL (host lists, work/series id parsing, URL builders, which hosts may receive a cookie, listing-shape classifiers)** → `ao3-link.md`
- **AO3 preface rendering or on-demand chapter fetch in the reader** → `ao3-preface-rendering.md`
- **The AO3 "Works Needing Attention" screen (pending updates, regression flags, works flagged missing; its Retry Now / Review Update / Clear Content actions)** → `ao3-works-needing-attention.md`
- **Article scroll position / reading progress** → `reading-progress.md`
- **"Same book" identity across feeds/re-imports** (`bookKey`) → `book-identity.md`
- **Large (`.sqlite`) library import** → `sqlite-transfer.md`
- **Feed drag-reorder within a container (sidebar manual ordering)** → `feed-reordering.md`
- **Folder drag-reorder, or folders nested inside folders (up to 3 levels)** → `nested-folders.md` (and `feed-reordering.md` for the shared `OrderedSet` mechanism)
- **A feed's address changing / OPML repoint** → `feed-repointing.md`
- **Refresh not firing, firing too often, or background refresh** → `refresh-throttling.md`
- **Article background/notch color, or webview appearance live-update** → `article-color-pipeline.md`
- **Accent Color / Surface Palette / nav bar tinting (app chrome)** → `app-chrome-palette.md`
- **Badge Colors (timeline rating/category/warning pill tinting)** → `app-chrome-palette.md`
- **Article theme (`.nnwtheme`) system itself** → `theme-system.md`
- **Creating a new theme (start here), required names, bundle checklist** → `creating-a-theme.md`
- **`.nnwtheme` bundle format / authoring reference / theme families** → `nnwtheme-format.md`
- **Theme color probe/store tests, check matrix, article fixtures, `nnwdump`, regenerating `ThemeColorTable.json`, when to bump the probe version** → `theme-testing.md`
- **Theme mockups, review page, title check, mockup-to-bundle conversion history** → `theme-mockups.md`
- **The theme gallery (`gallery/`), its build pipeline, or the install deep link** → `theme-gallery.md`
- **Landing page (`landing/`), its `site.json` config and optional sections** → `landing-page.md`
- **Database schema / SQLite storage layer** → `database.md`
- **Settings screen, any toggle, or "does setting X exist"** → `settings-screen.md` (main screen) **and** `ao3-authenticated-reading.md` (the separate AO3 account screen — easy to miss)
- **Reading Time limits / bedtime lockout / enforcement overlay** → `reading-time.md`
- **Reading Stats (words/time tracking, streaks)** → `reading-stats.md`
- **UI vocabulary (Shelf/Chapter/Work/Library) vs. the underlying Feed/Article code vocabulary, or wording for a new user-facing string** → `terminology.md`
- **Full device backup / restore, the Backup settings section** → `backup-restore.md`
- **The in-app Guide (Settings → Help → Guide), its overlay presentation, or its static page content** → `guide.md`
- **Favicon / page metadata extraction** → `metadata-extraction.md`
- **"What differs from upstream NetNewsWire"** → `upstream-drift.md`
- **A recurring Auto Layout / UIKit console warning** (before re-investigating one from scratch) → `console-warnings.md`
- **`fastlane snapshot` screenshots, offline UI-test demo data, `-UITestSeedDemoData`, `appstore/screenshots`** → `ui-test-demo-data.md`
- **Cutting a release: `release.yml`, tag creation, `source.json`, `scripts/update_source.py`, `ci.yml`'s App Store assets check** → `release-pipeline.md`
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
| `OrderedSet<Folder>`, `Container.folders`, `Folder.parent`/`.pathNames`, `addFolderToTree(_:at:)`, `AccountDelegate.moveFolder`, `ContainerIdentifier.folder`/`SidebarItemIdentifier.folder`'s path encoding, `OPMLNormalizer`'s nesting behavior, the depth-3 cap | `nested-folders.md` |
| `AO3IgnoreList` (including its labels), `AO3IgnoreListView`, the reader's "Ignore This Work"/"Ignore Author" actions (`ArticleIgnoreActions`, shared by the full-screen context menu and the `ToolbarFunction.ignore` toolbar item), `AO3SummaryExtractor` call sites in `RSSItem`/`AtomParser`, AO3 RSS/Atom subscription wiring | `ao3-direct-feed-ingestion.md` |
| `FeedSettings.ao3SearchFetchedPages`/`.ao3SearchTotalPages`, `AO3SearchResultsPaginator.nextPageToFetch`/`.validate`/`.fetchSpecificPage`, `AO3SearchResultsImporter.importFetchedPage`, `AO3FilterURLLength`, `AO3FilterFallbackPage`, `AddFeedViewController`'s long-URL warning, `AO3SearchResultsFetchCoordinator.presentSolverAndRetry`'s `updatesFeedName` parameter, `FeedInspectorViewController`'s AO3 Pages section | `ao3-arbitrary-page-fetch.md` |
| The AO3 HTML extractors themselves (`Modules/AO3Kit/Sources/AO3Kit/`) | `ao3-feeds.md` |
| `Feed.repoint(to:)`, `collectionKeyIndex`, `rewriteAmbrosiaJSONFeedURLs` | `feed-repointing.md` |
| `LocalAccountRefresher.feedShouldBeSkipped`, `BGTaskScheduler`/`backgroundRefreshDeadline`, `LastOpenedFeedDelegate` | `refresh-throttling.md` |
| `WebViewController`'s scroll-position tracking, `ReadingProgressEvaluator`/`ReadingProgressSample`, the completion threshold, `BookStateTable` reading-progress fields, `articleWindowScrollY` | `reading-progress.md` |
| `AO3ChapterFetcher`, `AO3ChapterHTMLExtractor`, `AO3PrefaceRenderer`, `Downloader`'s per-host 429 handling | `ao3-preface-rendering.md` |
| `AO3Link`, or any AO3 host check, id parse, hand-built AO3 URL, or listing-shape classifier | `ao3-link.md` |
| `AO3WorksNeedingAttentionView`, `AO3WorksNeedingAttentionViewModel`, `ArticleAttentionInfo`, `fetchAO3AttentionInfo` | `ao3-works-needing-attention.md` |
| `AO3SessionStore`, `AO3AuthenticatedFetcher`, `AO3AuthenticatedWebViewController`, `AO3ChallengeSessionStore`, `AO3KudosManager`, `AO3AccountSettingsView`, or any `NectarAppGroupUserDefaults`-backed AO3 preference | `ao3-authenticated-reading.md` |
| `ArticleThemeColorExtractor`, `ArticleResolvedColors`, `WebViewController.applyResolvedBackgroundColors`/`registerForTraitChanges` | `article-color-pipeline.md` |
| `SurfacePalette`, `AccentColor`, `SurfacePaletteNavigationBarAware`, `ToolbarStyle`/`toolbarStyle`, `BadgeColorPalette`, `BadgeColorTable` | `app-chrome-palette.md` |
| `.nnwtheme` bundles, `ArticleTheme`, `ArticleThemesManager`, `core.css`/`stylesheet.css` structure | `theme-system.md` |
| `iOS/Resources/ThemeColorTable.json`, `ThemeColorTableGeneratorTests`/`ThemeColorTableGuardTests`, `ArticleThemeColorProbe.version`, editing `core.css` or a bundled theme's `stylesheet.css`/`template.html` (the table must be regenerated) | `theme-testing.md` (and `article-color-pipeline.md`) 
| `ArticleThemeCheckMatrixTests`, `ArticleThemeSmokeTests`, `ArticleThemeRenderDiffTests`, `ThemeCheckColumns`, `Tests/NetNewsWire-iOSTests/Fixtures/ThemeCheck/` (article fixtures, `upstream-core.css`), the `nnwdump` capture command, which suites CI skips (`ci.yml`'s `theme_suites` input), `scripts/regenerate-theme-colors.sh`, `.github/workflows/theme-color-table.yml`, `Nectar-Performance.xctestplan` | `theme-testing.md` (and `module-layout.md`, `release-pipeline.md` for the plans and the gate) |
| `.nnwtheme` bundle-file layout, `Info.plist` `CreatorName`/`License.md` (description, attribution), per-theme fonts, theme families, `template.html` conventions, styleable blocks and ornament placement, full-screen title spacing, AO3 preface styling variables, `--nnw-*` color tokens and the page-color rule | `nnwtheme-format.md` |
| Creating a new theme end to end, required file/key/selector names, `buildscripts/theme-generation/theme_inventory.py` (current bundle counts) | `creating-a-theme.md` |
| Theme mockups (fixed page layout, sample text, review page, title check), mockup-to-bundle conversion, `buildscripts/theme-mockups/` (not in this checkout) | `theme-mockups.md` |
| `gallery/build.py` (zip naming, bundle checks, `--check-release-identity`), `gallery/test_build.py`, `gallery/test_upstream_pins.py`, `gallery/index.template.html`, `BUNDLED`/`BUNDLED_ID_PREFIXES`, `.github/workflows/gallery.yml`, the `theme-gallery` and `upstream-compat` jobs in `.github/workflows/ci.yml`, `gallery/upstream-compatible.txt`, `gallery/upstream_compat.py`, `gallery/test_upstream_compat.py` | `theme-gallery.md` |
| `landing/` (`build.py`, `template.html`, `site.json`), the optional-section rules, `gallery.yml` (publishes landing page and gallery) | `landing-page.md` |
| `ArticlesDatabase` schema/tables not covered by a more specific doc above | `database.md` |
| Any row/case in `SettingsViewController`'s `*Row` enums, `Settings.storyboard`, `AppDefaults`, or an `AppDefaults+<Feature>.swift` extension file | `settings-screen.md` |
| `.swiftlint.yml`'s `file_length`/`type_body_length` thresholds, or adding a large new file/type to `iOS/` | `module-layout.md` |
| `ReadingTimeTracker`, `ReadingTimeEnforcementOverlay`, `ReadingTimeSettingsView` | `reading-time.md` |
| `ReadingStatsTracker`, `ReadingStatsView`, how completed works are counted | `reading-stats.md` |
| Any new or renamed user-facing string, or a decision about which vocabulary (UI vs. code) a screen should use | `terminology.md` |
| `BackupManager`, `BackupRestoreCoordinator`, the backup zip's file layout | `backup-restore.md` |
| `GuideOverlayView`, `GuideContent`, `HelpRow.guide` | `guide.md` |
| `HTMLMetadata`/favicon extraction | `metadata-extraction.md` |
| `AnnotationsTable`, `Annotation`, `AnnotationsKit`, `annotations.js`, the `textWasSelected`/`annotationWasTapped` message-handler cases, `AnnotationCSVExporter`, the `annotations` table in `ArticleSQLiteExportTable` | `annotations.md` |
| Anything you deliberately did differently from upstream NetNewsWire behavior | `upstream-drift.md` |
| `Platform.isUITestingWithSeedDemoData`, `TestingURLProtocol` wiring in `DownloadSession`/`Downloader`/`URLSession+Webservice`, `iOS/UITestDemoData/`, `demo-feeds/`, `Tests/NetNewsWire-iOSUITests/NectarUITests.swift`, `fastlane/Fastfile` (all lanes), `appstore/screenshot-manifest.json` | `ui-test-demo-data.md` |
| `.github/workflows/release.yml`, `scripts/update_source.py`, `appstore/source.template.json`, the `appstore-assets` job in `.github/workflows/ci.yml` | `release-pipeline.md` |

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
