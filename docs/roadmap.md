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
storage and FTS5 search (with cooperative `sqlite3_progress_handler` cancellation
and corrupt-index recovery), AO3 feed and on-demand work fetching (including
inline stub/error notices and schema self-healing), reading progress and
statistics, annotations, theme customization, SwiftUI Settings, backup/restore,
and `ZIPFoundation`/`SwiftSoup`-backed EPUB3 export.
Use `CLAUDE.md` to route changes to the relevant technical documentation.

## Next initiative

AO3 request coordination is approved for further planning. Existing page and
work requests are generally user-triggered and use current pacing/gates. AO3
HTML listing pages are skipped during routine refresh; native AO3 RSS/Atom
subscriptions still refresh as ordinary metadata feeds. They bypass the
coordinator, but additional pacing is only an open policy question, not an
approved implementation requirement. The kudos POST also bypasses the
coordinator while honoring the shared cooldown.

Planning has been expanded to address the batch link import gap (`Account.importAO3Links`).
Ground truth analysis of the OTW Archive backend confirmed that Page 1 / Preface
metadata requests without `view_full_work=true` are orders of magnitude lighter
on OTW servers (avoiding MySQL `MEDIUMTEXT` reads and leveraging Memcached fragment
caching). The dedicated serialized metadata queue (`AO3ImportMetadataQueue`, 3.0-second pacing)
populates imported work stubs while preserving the invariant that full chapter bodies are never
downloaded in bulk. Track A implementation and tests are complete. The working plan is indexed in
`plans/plan-ao3-polite-request-coordinator.md`.

The faceted AO3 search builder remains an open proposal; no decision is needed
now.

## Proposal inventory

This is the authoritative classification of the proposals indexed in
`plans/README.md`. “Unverified” means source inspection found no implementation
or docs reference; it is not a claim that no partial work exists.

- **Implemented:** Track A: AO3 request coordination & batch import pacing (`AO3ImportMetadataQueue`,
  `AO3ChapterHTMLExtractor.extractLightweightMetadata`). Batch link import metadata pacing (3.0s delay,
  1-slot serialized queue, 429 rate-limit cooldown suspension, zero bulk chapter text scraping).
  See `docs/ao3-integration.md` and `docs/ao3-feeds.md`. Phases 1–5 of the coordinator
  blueprint (`ContinuousClock` pacing, waiter cancellation fix, `AO3RequestKey` coalescing,
  caller/`AO3KudosFetcher` consolidation, and `DownloadSession` 429 sync) remain open.
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
  SQLite `BLOB` (saving ~33%) and upgraded `search` from FTS4 to standard FTS5 in `ArticlesDatabase`
  schema version 2 (Option A approved: keep standard FTS5 rather than `content=''`); implemented
  two-step WIP update detection in `AO3ChapterFetcher`; and added the reader "Hide Creator's Style"
  toggle. **Remaining from this blueprint:** normalized tag/facet tables (`tags`, `article_tags`)
  and sharing FTS5 table SQL / corrupt-index recovery across unordered search.
- **Partially implemented:** FTS5 snippets, cancellation & self-healing index.
  Implemented: `SQLiteCancellationToken` (`sqlite3_progress_handler`) cooperative search
  cancellation and `SQLITE_CORRUPT`/`SQLITE_NOTADB` self-healing index recovery in
  `ArticlesTable` and `SearchTableAndDatabaseTests`. **Remaining:** FTS5 `snippet()`
  passage excerpts.
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
Move completed plans into `plans/finished/`; keep lasting behavior documented
in tracked topic docs. Do not link this roadmap to individual gitignored plan
files.
