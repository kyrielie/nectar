# Nectar roadmap

This roadmap is the shared summary of project direction. It records the current
app state, the proposal inventory, and the currently approved planning work. Detailed
specifications live in the gitignored `plans/` directory; the index there must
agree with this roadmap. A specification's own status (for example, “Final
Specification”) means the design is written, not that the work is approved or
implemented.

## Current project

Nectar is an iOS reading and library app forked from NetNewsWire. Its current
implemented foundations include JSON Feed/Ambrosia ingestion, SQLite-backed
storage and FTS5 search (with cooperative `sqlite3_progress_handler` cancellation,
corrupt-index recovery, and `search`-stripped backup snapshots), AO3 feed and
on-demand work fetching (including unified `AO3RequestCoordinator` pacing/coalescing,
synchronized `DownloadSession`/`Downloader` 429 cooldowns, inline stub/error
notices, and schema self-healing), reading progress and statistics, annotations,
theme customization, SwiftUI Settings, backup/restore, and
`ZIPFoundation`/`SwiftSoup`-backed EPUB3 export.
Use `CLAUDE.md` to route changes to the relevant technical documentation.

## Next initiative

AO3 request coordination (Track A batch import pacing and Phases 1–5 coordinator
hardening, caller consolidation, and `DownloadSession` 429 synchronization) is
now complete.

The remaining active items from partially implemented blueprints are:
1. **Normalized `tags` / `article_tags` tables** (`plan-storage-and-parsing-optimization.md`,
   best paired with `plan-persistent-library-search-and-filters.md`)
2. **`FeedSettings.db` stale cache pruning** during backup export (Phase 3 of
   `docs/backup-size-optimization-plan.md`).

Beyond those cleanup/optimization items, the open feature proposals (such as the
faceted AO3 search builder, persistent library search & AO3-style filters, or
EPUB3 DOM sanitization & in-reader series continuity) await prioritization.

## Proposal inventory

This is the authoritative classification of the proposals indexed in
`plans/README.md`. “Unverified” means source inspection found no implementation
or docs reference; it is not a claim that no partial work exists.

- **Implemented:** AO3 request coordination & batch import pacing (`AO3ImportMetadataQueue`,
  `AO3ChapterHTMLExtractor.extractLightweightMetadata`, `ContinuousClock`-based `AO3Pacer`,
  waiter-cancellation-safe `AO3RequestCoordinator`, `AO3RequestKey` guest/authenticated/clearance
  separation and ref-counted `RequestCoalescer`, caller consolidation including `AO3KudosFetcher`
  slot bounding, `DownloadSession`/`Downloader` 429 cooldown synchronization, and
  `AO3RequestCoordinatorTests`). See `docs/ao3-integration.md` and `docs/ao3-feeds.md`.
- **Implemented:** SwiftUI Settings redesign & polish (`SettingsView`, `SettingsModel`,
  `SettingsHostingController`, `SurfacePaletteAware`, `SettingsSearchIndex`, and retired
  `Settings.storyboard`). See `docs/settings-screen.md`.
- **Implemented:** Architecture, dependency & code-quality modernization (`ZIPFoundation`
  0.9.20 with uncompressed EPUB3 `mimetype`, `SwiftSoup` 2.13.6 DOM parsing in `EPUB3Generator`,
  `.swiftlint.yml` `force_try`/`force_cast` enforcement, `AppDefaults` feature extensions,
  `NSOutlineView+RSTree` dead-code removal, and `docs/epub-export.md`).
- **Open proposal; not prioritized:** Faceted AO3 search builder. Existing
  app search results and pagination are in place; the plan's query builder,
  native filter UI, and saved-search behavior are not evidenced in current
  source.
- **Partially implemented:** Storage, parsing, and
  update optimization. Implemented: migrated compressed HTML from Base64 `TEXT` to native
  SQLite `BLOB` (saving ~33%), upgraded `search` from FTS4 to standard FTS5 in `ArticlesDatabase`
  schema version 2 (Option A approved: keep standard FTS5 rather than `content=''`), shared
  `ArticlesDatabase.searchTableCreationStatement` / `resetCorruptSearchIndex`, stripped `search`
  and `searchRowID` from exported backup snapshots (`ArticlesDatabaseFullSnapshotExport`),
  implemented two-step WIP update detection in `AO3ChapterFetcher`, and added the reader
  "Hide Creator's Style" toggle. **Remaining from this blueprint:** normalized tag/facet tables
  (`tags`, `article_tags`).
- **Implemented:** FTS5 snippets, cancellation & self-healing index
  (`SQLiteCancellationToken` / `sqlite3_progress_handler` cooperative search cancellation,
  `SQLITE_CORRUPT`/`SQLITE_NOTADB` self-healing index recovery in `ArticlesTable`, and FTS5
  `snippet()` passage excerpts with highlighted matches in `ArticleSearchMatch`,
  `SmartFeed`, and `MainTimelineCell`).
- **Unverified proposals:** WIP update checker; mature-content privacy gate;
  native AO3 comments viewer, author profiles, and account hub; native fandom
  catalog; reading queues/collections; recently deleted recovery; user EPUB
  import; custom font import; iCloud folder sync; manual theme presets;
  on-device semantic/hybrid search; persistent library search, AO3-style filters &
  search suggestions; EPUB3 DOM sanitization & in-reader series continuity.
- **Theme process/design proposals:** theme quality review, theme provenance
  and unification, and theme-management UI mockup. These should be handled as
  discrete design or maintenance projects, not presumed app features.
- **Completed in current app:** backup-to-EPUB proposal. Both the desktop
  converter and native per-work EPUB export exist; see `docs/backup-restore.md`.

Manual theme presets are still indexed as a draft proposal, not in the finished
archive; the former roadmap statement that it was archived was incorrect.

## Roadmap maintenance

Before marking work active or complete, compare its acceptance criteria with
current source and tests, check relevant topic docs, and record verified scope
here. Keep the inventory and order in `plans/README.md` aligned with this file.
Move completed plans into `docs/plans/finished/`; keep lasting behavior documented
in tracked topic docs. Do not link this roadmap to individual gitignored plan
files.
