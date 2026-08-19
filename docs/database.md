# Database Layer

Nectar is built on SQLite throughout, accessed via FMDB (vendored as
Objective-C in `RSDatabaseObjC`) rather than a Swift-native SQLite wrapper.
There is no single "the database" — each subsystem owns its own `.db` file,
each with its own access pattern (serial dispatch queue vs. Swift actor).
This doc covers the shared low-level plumbing in `RSDatabase`, the main
per-account articles store in `ArticlesDatabase`, and the smaller
special-purpose databases scattered across other modules.

## Shared plumbing: `RSDatabase`

`RSDatabaseObjC` wraps the C SQLite3 library (`FMDatabase`/`FMResultSet`,
forked from FMDB) with a handful of NetNewsWire-specific convenience
categories (`FMDatabase+RSExtras`, `FMResultSet+RSExtras`,
`NSString+RSDatabase`). `RSDatabase` (Swift) builds the app-facing API on
top of that:

- `DatabaseDictionary = [String: Any]` — a row's values keyed by column name,
  used for generic insert/update helpers (`database.insertRow(_:insertType:tableName:)`
  etc., in `FMDatabase+Extras.swift`).
- `DatabaseTable` — a thin protocol (`name: String`) most per-table wrapper
  types conform to, mostly for `containsColumn(_:in:)` migration checks.
- **`DatabaseQueue`** — the workhorse. One `DatabaseQueue` per SQLite
  connection, wrapping a single `FMDatabase` behind a private serial
  `DispatchQueue` and an `OSAllocatedUnfairLock`-protected state struct
  (`isCallingDatabase`, mainly as a reentrancy precondition check). Exposes
  sync/async variants of "run a block against the database," with and
  without wrapping it in a transaction:
  - `runInDatabaseSync` / `runInDatabase`
  - `runInTransactionSync` / `runInTransaction`
  - `runCreateStatements(_:)` — runs every line beginning with `create`
    (case-insensitive) from a multi-line SQL string; the idiom used
    everywhere to define a table's initial schema.
  - `vacuum() async`

  On open, every database gets `PRAGMA journal_mode = DELETE` (not WAL —
  deliberate: every database here is single-connection and fully serialized
  through one queue, so WAL buys nothing and only adds `-wal`/`-shm` files
  on disk) and `PRAGMA synchronous = 1`, plus statement caching enabled.

- **`RSDatabaseInfoTable`** — a shared one-row-per-key metadata table
  (`RSDatabaseInfo`) that every database using `FMDatabase.vacuumIfNeeded()`
  gets automatically. Currently used only to persist `lastVacuumDate`, so a
  database only vacuums when it's been more than
  `defaultDaysBetweenVacuums` (13) days since the last one — vacuuming is a
  blocking, full-file-rewrite operation, so it's throttled rather than run
  on every launch.

Two connection styles are used across the codebase, chosen per-database:
- **`DatabaseQueue`-based** (`ArticlesDatabase`) — for the highest-traffic,
  `@MainActor`-adjacent store, where callers already think in terms of
  dispatch-queue-style async blocks.
- **Swift `actor`-based** (`SyncDatabase`, `ErrorLogDatabase`,
  `HTMLMetadataDatabase`, `ImageMetadataDatabase`) — newer code, where a
  single `FMDatabase` is captured directly by the actor and all access is
  serialized by actor isolation instead of a dispatch queue. These typically
  call `FMDatabase.openAndSetUpDatabase(path:)` (a convenience that opens,
  runs the same PRAGMAs as `DatabaseQueue`, and enables statement caching)
  directly rather than going through `DatabaseQueue` at all.

## `ArticlesDatabase` (per-account article store)

One `ArticlesDatabase` instance per account, at a `databaseFilePath` inside
that account's folder. This is the largest and most actively evolved
database in the app — its schema carries the marks of Nectar's AO3/Ambrosia
features layered on top of upstream NetNewsWire's original article model.

### Schema

```sql
CREATE TABLE if not EXISTS articles (
  articleID TEXT NOT NULL PRIMARY KEY, feedID TEXT NOT NULL, uniqueID TEXT NOT NULL,
  title TEXT, contentHTML TEXT, contentText TEXT, markdown TEXT,
  url TEXT, externalURL TEXT, summary TEXT, imageURL TEXT, bannerImageURL TEXT,
  datePublished DATE, dateModified DATE, searchRowID INTEGER, authors TEXT,
  wordCount INTEGER, chapterCurrent INTEGER, chapterTotal INTEGER, isComplete BOOL,
  fandoms TEXT, relationships TEXT, characters TEXT, ratings TEXT, warnings TEXT,
  categories TEXT, additionalTags TEXT, series TEXT
  -- plus columns added by later ALTER TABLE migrations, see below
);

CREATE TABLE if not EXISTS statuses (
  articleID TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0,
  starred BOOL NOT NULL DEFAULT 0, loved BOOLEAN NOT NULL DEFAULT 0,
  dateArrived DATE NOT NULL DEFAULT 0, scrollPosition REAL NOT NULL DEFAULT 0,
  readingProgress REAL, lastOpenedAt DATE
);

CREATE TABLE if not EXISTS bookState (
  bookKey TEXT NOT NULL PRIMARY KEY, read BOOL NOT NULL DEFAULT 0,
  starred BOOL NOT NULL DEFAULT 0, loved BOOL NOT NULL DEFAULT 0,
  scrollPosition REAL NOT NULL DEFAULT 0, readingProgress REAL, lastOpenedAt DATE,
  updatedAt DATE NOT NULL, kudosAttemptedAt DATE,
  kudosAttemptedAuthenticated BOOL NOT NULL DEFAULT 0
);

CREATE VIRTUAL TABLE if not EXISTS search using fts4(title, body);
```

Indexes: `articles(feedID, datePublished, articleID)`,
`statuses(starred)`, `articles(searchRowID)`, and (added later, see below)
`articles(bookKey)` and `articles(uniqueID)`.

`ArticlesDatabase.init` runs the base `CREATE TABLE`/`CREATE INDEX`
statements via `runCreateStatements`, then **synchronously** (not via the
normal async `runInDatabase`, specifically to guarantee every migration has
actually run before `init()` returns and callers can start querying) runs a
long, additive sequence of `containsColumn`-guarded `ALTER TABLE` statements.
This is the project's schema-migration strategy in its entirety: there is no
versioned migration framework — every change to the `articles`/`statuses`/
`bookState` shape is one more `if !containsColumn(...) { ALTER TABLE ... }`
block appended to this init method, run unconditionally (and cheaply, once
the column exists) on every launch.

Migrations of note, in the order they were added (each documents its own
rationale extensively in the source):

| Columns | Table | Purpose |
|---|---|---|
| `searchRowID`, `markdown`, `authors` | articles | early upstream additions |
| `wordCount`, `chapterCurrent`, `chapterTotal`, `isComplete`, `fandoms`, `relationships`, `characters`, `ratings`, `warnings`, `categories`, `series` | articles | Ambrosia's extension metadata (fic-specific fields) |
| `commentCount`, `kudosCount`, `bookmarkCount`, `hitCount` | articles | AO3 work-header stats, read from `dl.stats` on each live chapter fetch |
| `previousWorkURL`, `nextWorkURL` | articles | superseded by per-series navigation; columns kept reserved, no longer read/written |
| `lastPrefaceFetchDate`, `isAmbrosiaItem` | articles | preface refetch bookkeeping / Ambrosia-vs-native-AO3 marker |
| `pendingUpdateContentHTML`, `pendingUpdateDetectedAt`, `wordCountRegressionFlaggedAt` | articles | pending-content-update diff/regression guard |
| `scrollPosition` | statuses | per-article scroll position, replacing a single global default |
| `readingProgress` | statuses | nullable fraction (0...1); `NULL` means "never computed," distinct from `0` |
| `loved` | statuses | second independent boolean status alongside `starred` |
| `lastOpenedAt` | statuses, bookState | backing the "Last Opened" smart feed |
| `kudosAttemptedAt`, `kudosAttemptedAuthenticated` | bookState | kudos-on-like attempt tracking, forward-only |
| `bookKey` | articles | book-level read-state identity key (see below) |

A one-time, self-limiting `INSERT OR IGNORE` / `DELETE` / `UPDATE` sequence
also runs on every launch to repoint `bookState` rows for AO3 series-group
items from their old `uniqueID`-as-`bookKey` fallback onto the newer
`ao3-series:<id>` scheme; it's idempotent because the `WHERE` clause only
matches rows that still have the old shape.

Two indexes on `articles(bookKey)` and `articles(uniqueID)` were added
specifically because `bookKeysForArticleIDs`/`articleIDsForBookKeys` run a
`WHERE ... IN (...)` lookup on every read/starred/loved toggle to write
through to book-level state — without an index this was a full table scan
per tap.

### Date fields: `datePublished`, `dateModified`, `dateArrived`

Three distinct date columns, not interchangeable:

- **`datePublished`** (articles) — the feed/source's own "originally published"
  date: Atom's `published`, JSON Feed's `date_published`, AO3's `dl.stats`
  "Published:" row. May be `nil` if the source never exposes it (see below).
- **`dateModified`** (articles) — the feed/source's own "last updated" date:
  Atom's `updated`, JSON Feed's `date_modified`, AO3's `dl.stats`
  "Updated:"/"Completed:" row. `AtomParser` also falls back `dateModified` to
  `datePublished` (and vice versa) when only one of Atom's two elements is
  present in the feed itself — that in-parser fallback is unrelated to the
  storage-layer one described below and is not affected by it.
- **`dateArrived`** (statuses) — when the article/book entered the local
  library (`ArticlesTable.swift:1637`'s "Recently Added" comment). Never
  derived from the other two; always set once, at first insert.

**AO3 items specifically expose these two dates across two separate
fetches, not one:** `AO3SearchResultsExtractor` (a feed/search-results row)
only has AO3's "last updated" text available and sets `dateModified`,
leaving `datePublished` nil (`ao3-feeds.md` covers the extractor itself).
`AO3ChapterHTMLExtractor` (the full work-page fetch, triggered later when
the article is actually opened/read) parses both the real `datePublished`
and `dateModified` from `dl.stats`. For any work updated after its original
posting, the real `datePublished` that shows up on the second fetch is
*earlier* than the `dateModified` already known from the first.

**Storage rule: each column is written and updated exactly as parsed, with
no cross-field coercion.** `Article.init(parsedItem:maximumDateAllowed:...)`
(`Article+Database.swift`) previously copied `dateModified` into
`datePublished` whenever `parsedItem.datePublished` was `nil`, before that
value ever reached the database. That coercion is what caused the "timeline
date moves backward after content fetch" bug: it made the DB's
`datePublished` column hold a placeholder (the AO3 search-result's "last
updated" date) instead of staying `nil`, and `changesFrom(_:)`'s
if-changed-and-non-nil update rule (further down in the same file) then
couldn't tell that placeholder apart from a genuine value — so the real,
earlier `datePublished` supplied by the later content fetch always looked
like a legitimate change and overwrote it. Both `datePublished` and
`dateModified` are now stored independently: a genuinely `nil` value from
the parser stays `nil` in the row (never coerced from the other field), and
an existing non-nil value is only ever overwritten by a new non-nil value
(the pre-existing "don't blank out data we already have" rule, unchanged).
Both date columns can still be individually clamped to `nil` by
`maximumDateAllowed` (a feed lying about a far-future date), independently
of each other.

**Display/sort rule: the later of the two wins, not `datePublished`
unconditionally.** `Article.logicalDatePublished`
(`Shared/Extensions/ArticleUtilities.swift`, used by the timeline cell,
`ArticleSorter`, `SmartFeedArticleGrouping`, the in-article dateline, and
the share-sheet preview) resolves to `max(datePublished, dateModified)`
when both are set, falling back to whichever one is set, falling back to
`status.dateArrived` when neither is. This is a display/sort-time decision,
not a storage decision — the two fields keep their own, independently
correct values in the database regardless of which one
`logicalDatePublished` currently prefers.

Any SQL query that orders by "the article's effective date" (four
limit-bounded fetches in `ArticlesTable.swift`, plus the Dinosaurs debug
screen's per-feed latest-date aggregate) uses the same logic via the shared
`ArticlesTable.logicalDatePublishedSQL` SQL fragment,
`coalesce(max(datePublished, dateModified), datePublished, dateModified,
dateArrived)` — the outer `coalesce` is required because SQLite's
multi-argument `max()` returns `NULL` if *either* argument is `NULL`
(unlike `coalesce`), so `max(datePublished, dateModified)` only resolves
anything when both columns are non-null. Any new query that needs "this
article's effective/displayed date" for ordering or filtering should use
`Self.logicalDatePublishedSQL` rather than hand-rolling
`coalesce(datePublished, dateModified, dateArrived)` again, which silently
reintroduces the datePublished-first bug at the SQL layer.

### `bookKey` and book-level state

`bookKey` is a stable identity key for "the same book/fic," independent of
which feed or how many times it's been re-subscribed to — the same AO3 work
appearing in more than one Ambrosia collection feed shares one `bookState`
row, so a read/starred/loved toggle or scroll-position update through any
copy is immediately reflected on every copy. `statuses` (keyed by
`articleID`) remains as a fallback for rows that can't resolve a `bookKey`
(nearly unreachable in practice, per source comments, but cheap to keep).
`BookStateTable` (`Modules/ArticlesDatabase/Sources/ArticlesDatabase/BookStateTable.swift`)
is what upserts/reads this table; it consolidated what used to be three
separate single-column tables (read/starred/loved) plus ad hoc scroll state.

### Content compression

`ContentHTMLCompression` (`ContentHTMLCompression.swift`) compresses
`contentHTML` at rest using `NSData.compressed(using: .lzfse)`, then
base64-encodes the compressed bytes into the existing `TEXT` column (no
schema change to `BLOB` needed, since every FMDB row accessor used elsewhere
is String-based). `compress` degrades gracefully — nil/empty input passes
through unchanged, and a compression failure falls back to storing the
original string rather than losing content. `decompress` likewise falls
back to returning the stored string as-is if it isn't valid base64/LZFSE,
so a row written before this landed doesn't crash the reader.

### Full-text search

`search` is an FTS4 virtual table (`title`, `body`), populated and queried
via `SearchTable.swift`; `articles.searchRowID` links an article row to its
FTS row. `indexUnindexedArticles()` is kicked off asynchronously right after
table creation/migration finishes, to backfill any articles that predate
indexing or were added while search was unavailable.

### Bulk export/import

- **`ArticleSQLiteExportTable`** — bulk `CREATE TABLE ... AS SELECT` against
  the live `articles`/`statuses` tables into an `ATTACH`ed export database
  file, for exporting a full snapshot.
- **`AmbrosiaSQLiteImportTable`** — the reverse: `ATTACH DATABASE`s a
  downloaded Ambrosia SQLite transfer file on the *same* `DatabaseQueue`
  connection and bulk-copies rows into `articles`/`statuses`. This is why
  `ArticlesDatabase.queue` is `internal` rather than `private` — it's the
  one deliberate exception allowing a second table type direct queue access
  for an `ATTACH`-based bulk copy, everything else goes through
  `articlesTable`. See `ambrosia-feed.md` for the wire format this consumes.
- **`ArticlesDatabaseFullSnapshotExportTable`** — `VACUUM INTO ?` against
  the live database, exposed as `ArticlesDatabase.exportFullSnapshot(toPath:)`.
  Unlike `ArticleSQLiteExportTable` above, this is an atomic, consistent,
  whole-file copy that includes every table -- `bookState` and the FTS4
  `search` table included -- not a per-feed `CREATE TABLE ... AS SELECT`
  subset. Used only by device backup (see `backup-restore.md`); the
  existing per-feed "Export…" feature keeps using
  `ArticleSQLiteExportTable` as before, deliberately excluding `bookState`
  and not meant to be restorable.
- **`BackupSQLiteImportTable`** — the reverse of the snapshot export:
  `ATTACH DATABASE`s a backup's `DB.sqlite3` (a full-snapshot export, from
  this device or another one) on the same `DatabaseQueue` connection and
  non-destructively merges `articles`/`statuses`/`bookState`/`annotations`
  in, exposed as `ArticlesDatabase.importBackupSnapshot(backupDatabasePath:)`.
  Every statement is additive-only (`INSERT OR IGNORE`, an OR-of-booleans,
  or a later-`updatedAt`-wins `UPDATE`) -- never `DELETE` or
  `INSERT OR REPLACE`. See `backup-restore.md` for the full per-table merge
  rules and their reasoning.

### Public API shape

`ArticlesDatabase.swift`'s header comment states the file "is the entirety
of the public API for ArticlesDatabase.framework" — everything else
(`ArticlesTable`, `StatusesTable`, `BookStateTable`, `SearchTable`, etc.) is
internal implementation reached only through this `@MainActor final class`.
Key public value types: `ArticleChanges` (new/updated/deleted sets from a
feed update), `ArticleCounts` (aggregate total/unread/starred/statuses
counts), `ArticleStorageInfo` (per-article compressed `contentHTML` size,
for the Manage Storage screen), and `RetentionStyle` (`.feedBased` for
Local/iCloud accounts vs. `.syncSystem` for accounts whose sync service
defines retention).

## Other databases

| Database | Module | Connection style | Notes |
|---|---|---|---|
| `HTMLMetadata.db` | `HTMLMetadata` | `actor` | single `metadata` table; see `metadata-extraction.md`. |
| `ImageMetadataDatabase` | `Images` | — | favicon/feed-icon URL caching; consumed by `FaviconDownloader`/`FeedIconDownloader`. |
| `SyncDatabase` | `SyncDatabase` | `actor` | queue of pending read/starred sync operations (`SyncStatus` rows) for account types that need to push local state changes upstream. |
| `ErrorLogDatabase` | `ErrorLog` | `actor` | one `errors` table (`id`, `date`, `sourceName`, `sourceID`, `operation`, `fileName`, `functionName`, `lineNumber`, `errorMessage`); auto-prunes to the most recent 200 rows on init and subscribes to `.appDidEncounterError` to record entries automatically. Backs the in-app Activity/Error Log UI. |
| `FeedSettingsDatabase` | `Account` | — | per-feed settings (home page URL, icon/favicon URLs, edited name, conditional-GET/cache-control HTTP caching info, folder relationship, AO3 search pagination cursor, etc.), keyed by `feedID`. |
| `AccountSettingsDatabase` | `Account` | — | marked `// TODO: Delete this file in 7.2` — a read-only, one-shot credential migration shim (`init?` returns nil if the legacy file doesn't exist) that reads old `accountSettings` rows to migrate `username`/`endpointURL` forward, not a database Nectar continues to write to. |

`AccountSettingsDatabase`, `FeedSettingsDatabase`, and the Ambrosia-specific
tables live in the `Account` module rather than `ArticlesDatabase`, since
they describe account/feed configuration rather than article content.

## Design conventions across all of these

- **Additive-only migrations.** No database in this codebase ever drops or
  renames a column in place; every schema change is a new nullable (or
  `DEFAULT`-guarded) column behind a `containsColumn` check, run
  unconditionally at startup. This keeps upgrades cheap and safe at the cost
  of an ever-growing migration block in each database's `init`.
- **One `.db` file per concern**, not one shared database — `ArticlesDatabase`
  is per-account (so accounts are trivially deletable/movable as a unit),
  while `HTMLMetadata`, `SyncDatabase`, and `ErrorLog` are shared,
  app-global stores.
- **`vacuumIfNeeded()` everywhere**, backed by the shared
  `RSDatabaseInfoTable` convention, so compaction happens roughly weekly
  without needing to be wired into each database's specific call sites.
- **Serialization via either a dedicated `DatabaseQueue` or Swift actor
  isolation** — never ad hoc locking around a shared `FMDatabase` instance.
