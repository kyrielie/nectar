# SQLite transfer route (large-collection sync)

The second, higher-throughput sync path for `.sqlite`-suffixed feed URLs,
used for large-collection import instead of the normal JSON Feed HTTP path.
See `module-layout.md` for how this fits alongside `ArticlesDatabase` and
`refresh-throttling.md` for how a feed gets routed here vs. skipped.

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

`AmbrosiaSQLiteImportTable.copyItems`'s bulk `INSERT OR REPLACE ... SELECT`
moves most `items` columns straight across because their wire type already
matches the local `articles` column's storage type (TEXT-to-TEXT,
INTEGER-to-INTEGER/BOOL). `date_published`/`date_modified` are the one
column pair where that's not true: the wire format sends them as ISO 8601
TEXT (`docs/nectar-implementation-plan.md` is cited in-code as the source for
this Wire Contract, but that file is not present anywhere in the current
tree — treat the field-name/type claim below as confirmed against the
Swift/SQL source, not against that missing doc), but
`articles.datePublished`/`dateModified` are read/written everywhere else as
numeric `timeIntervalSince1970` doubles, via FMDB's automatic `Date`→double
binding. A straight `SELECT`-and-copy of the TEXT column skipped that
conversion — SQLite's TEXT-to-REAL coercion on read parses only the leading
digit run of an ISO 8601 string (`"2024-01-15T10:30:00Z"` → `2024.0`), so
every date imported via the `.sqlite` transfer route silently became a
~1970-01-01 timestamp, which is what a `.sqlite`-fed article's timeline date
would end up showing (via `Article.logicalDatePublished`'s
`datePublished ?? dateModified ?? status.dateArrived` fallback — a
near-1970 `datePublished` is non-nil, so the `dateArrived` fallback never
kicked in to mask it). Fixed the same way `content_html` already was: left
out of the bulk `INSERT...SELECT` and filled in afterward, one row at a
time, by `copyParsedDates` — parsed with `RSParser.DateParser` (the same
parser `JSONFeedParser` uses for these fields on the ordinary HTTP JSON Feed
path) and written via parameter binding so FMDB does the correct
Date→double conversion. Any *future* column added to this bulk copy should
be checked against this same TEXT-vs-numeric-storage question before
assuming a straight `SELECT` is safe — `content_html` and the dates are the
two columns that needed the one-row-at-a-time treatment so far, not because
they're special-cased on principle but because they're the only two whose
wire type doesn't already match the local column's storage type.
