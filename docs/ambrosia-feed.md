# Ambrosia Feed Integration

Ambrosia is a companion, self-hosted local server (not part of this
repository) that exposes a person's Calibre-managed fic library — typically
AO3 works downloaded as epub — as a feed Nectar can subscribe to on the same
LAN. Nectar treats Ambrosia as just another Local-account feed source, but
one that carries a rich, fic-specific extension of the article model
(word count, chapters, fandoms/relationships/characters/ratings, AO3 series,
kudos/comment/bookmark/hit stats) and, for large libraries, a dedicated
paginated SQLite bulk-transfer route that bypasses ordinary feed parsing
entirely.

There are two independent transfer routes for the same data, selected by a
single app-wide setting (`AmbrosiaTransferFormatPreference.current`, `.json`
or `.sqlite`, no per-feed override):

## Route 1: JSON Feed extension

Ambrosia's `LocalFeedServer` can serve a normal JSON Feed 1.1 document with
one addition: each item may carry an `_ambrosia` extension object. This is
parsed by `RSParser`'s existing `JSONFeedParser` (`Modules/RSParser/Sources/RSParser/Feeds/JSON/JSONFeedParser.swift`) —
Ambrosia items are not a separate feed type, just JSON Feed items with an
extra key, recognized by the presence of `Key.ambrosia = "_ambrosia"`.

```json
{
  "id": "ambrosia-book-42",
  "url": "https://archiveofourown.org/works/123456",
  "title": "A Long Way From Home",
  "content_html": "...",
  "_ambrosia": {
    "word_count": 84213,
    "chapter_current": 12, "chapter_total": 15, "is_complete": false,
    "fandoms": ["Example Fandom"],
    "relationships": ["Character A/Character B"],
    "characters": ["Character A", "Character B"],
    "ratings": ["Teen And Up Audiences"],
    "warnings": ["No Archive Warnings Apply"],
    "categories": ["M/M"],
    "series": [{ "name": "The Long Way Home Series", "index": 2, "ao3_id": "987654" }],
    "date_modified": "2024-06-15T08:30:00Z",
    "comment_count": 57, "kudos_count": 1203, "bookmark_count": 88, "hit_count": 15420
  }
}
```

There is no `_ambrosia_schema_version` field on the wire — Ambrosia has never
needed to version this extension, so `JSONFeedParser` doesn't gate parsing on
one; every `_ambrosia` field is simply optional. An item with `_ambrosia`
present but empty is still treated as a book (`isAmbrosiaItem = true`) — a
book with zero AO3 metadata is not the same as a non-book item.
`_ambrosia.date_modified` is folded into JSON Feed's own top-level
`date_modified` rather than kept separately, since it's the same concept.

Parsed fields land in `ParsedItem` (`Modules/RSParser/Sources/RSParser/Feeds/ParsedItem.swift`):
`isAmbrosiaItem`, `wordCount`, `chapterCurrent`/`chapterTotal`, `isComplete`,
`fandoms`/`relationships`/`characters`/`ratings`/`warnings`/`categories`,
`series: [ParsedSeriesEntry]?`, the four stat counts, and identity fields
`ao3WorkID`, `isAnthology`, `ao3SeriesID`, `seriesName`. These map directly
onto the Ambrosia extension columns added to `ArticlesDatabase`'s `articles`
table (see `database.md`).

Two independent sources can populate the AO3 stats fields
(`commentCount`/`kudosCount`/`bookmarkCount`/`hitCount`): a self-hosted
Ambrosia server publishing its own already-scraped numbers under
`_ambrosia`, or `AO3ChapterFetcher.rebuildParsedItem` populating them from a
live AO3 chapter fetch. Neither source is gated by
`AmbrosiaAO3NetworkPreference.updatesEnabled` once the data is already in
hand — that preference only controls whether a *new* live AO3 network
request is allowed to happen at all, not whether already-downloaded metadata
gets displayed.

### `bookKey` derivation

`ParsedItem.bookKey` (also mirrored, deliberately kept in exact precedence
sync, as a SQL `CASE` expression in `AmbrosiaSQLiteImportTable` for the bulk
SQLite route) computes the stable book-identity key used for read-state
dedup across feeds and re-subscriptions:

1. `ao3SeriesID` present → `"ao3-series:<id>"` (covers both an anthology with
   a known AO3 series id, and an Ambrosia series-group item — multiple
   Calibre books sharing one AO3 series, merged at request time — which sets
   `ao3SeriesID` without `isAnthology`).
2. `isAnthology == true` and a `seriesName` → `"calibre-series:<name>"`
   (fallback for an anthology with no AO3 series id).
3. `ao3WorkID` present → `"ao3-work:<id>"`.
4. Otherwise → the bare `uniqueID` (`"ambrosia-book-<calibre_id>"`).

This precedence must stay in sync with Ambrosia's own `book_key()` on the
server side; the source comments explicitly warn against reordering it
without re-checking against Ambrosia's `LocalFeedServer` output.

## Route 2: paginated SQLite transfer

For large libraries, Ambrosia can serve a `.sqlite` file directly instead of
JSON — a much cheaper wire format for thousands of items. This is a
dedicated, versioned binary protocol, not RSS/JSON Feed parsing at all.

### Wire format versioning

`AmbrosiaSQLiteWireFormat.version` (currently `1`) must match the
`PRAGMA user_version` Ambrosia stamps into every `.sqlite` file it writes.
`AmbrosiaSQLiteImportTable.readWireFormatVersion(atPath:)` opens the
downloaded file standalone (a bare `sqlite3_open`, not through the app's own
`DatabaseQueue`) and checks this **before** attaching it to the app
database at all. Any mismatch is a hard failure with no fallback and no
partial-compatibility handling — the source treats this as strictly a
build/version-skew bug between the two codebases, never something to
degrade gracefully around.

### Pagination and the walk protocol

A full transfer is fetched as a sequence of pages
(`AmbrosiaSQLiteTransferFetcher.fetchAndImportWalk(baseURL:feedID:into:)`),
each requested with `page=N` appended to the feed's base `.sqlite` URL. Every
page carries its own `transfer_manifest` table describing:

```swift
struct AmbrosiaSQLiteTransferManifest {
    let walkID: String
    let pageNumber: Int
    let hasMore: Bool
    let pageRowCount: Int
    let expectedTotalRowCount: Int
}
```

The fetcher validates each page's manifest — via
`ArticlesDatabase.readAmbrosiaSQLiteTransferManifest` — **before** importing
a single row from it:

- A page that fails validation (missing/inconsistent manifest, or an
  ordinary network failure) is retried up to `maxAttemptsPerPage` (3) times
  with short exponential backoff.
- A `walkID` mismatch on a resumed walk means Ambrosia started a fresh walk
  server-side; the client discards its resume state and restarts at page 1.
- If retries are exhausted, or the final page's manifest disagrees with the
  actual imported row count, the whole walk is reported `.incomplete` — a
  first-class result (`AmbrosiaSQLiteWalkResult.incomplete`), not thrown as
  an error, so callers can surface a distinct "sync incomplete" status
  rather than routing it through the generic feed-refresh-error path. An
  incomplete walk is retried automatically on the next scheduled refresh,
  resuming from persisted state.

Progress is durably persisted after every single page import — not just held
in memory — via `AmbrosiaSQLiteTransferWalkState`
(`feedID`, `walkID`, `lastImportedPage`, `expectedTotalRowCount`,
`importedRowCountSoFar`, `status: .inProgress/.complete/.incomplete`),
stored as JSON in the shared app-group `UserDefaults` suite
(`NectarAppGroupUserDefaults.store`) under `ambrosiaSQLiteTransferWalkState.<feedID>`.
This is what lets a relaunch, background suspension, or crash mid-walk
resume from the correct page instead of silently restarting from page 1 or
mistaking a half-finished import for a complete one.

### Networking

`AmbrosiaSQLiteTransferFetcher` deliberately bypasses the shared
`DownloadSession` (whose default 15s `timeoutIntervalForRequest` would kill
a multi-minute whole-library transfer). It uses its own ephemeral
`URLSession` configured with a 300-second timeout for both request and
resource, following the same bare-`URLSession` pattern used elsewhere for
`next_url`-style pagination fetches, kept on its own session so the
generous timeout doesn't leak into unrelated requests. Response bodies are
LZFSE-decompressed client-side (no `Content-Encoding` header on the wire —
decompression is an explicit step per the wire contract, not something
`URLSession` handles transparently).

### Import

`AmbrosiaSQLiteImportTable.importPage` does the entire per-page import in
one shot: `ATTACH DATABASE` the downloaded, decompressed page file under the
alias `ambrosia_transfer` on the **same connection** as the app's own
`ArticlesDatabase` queue, then a single `INSERT OR REPLACE ... SELECT`
straight from the attached `items` table into `articles`/`statuses` — not a
row-by-row Swift-struct decode. This is an explicit design trade-off, called
out in the source as accepted rather than incomplete: there is no post-copy
search re-indexing and no `BookStateTable` writes performed as part of the
bulk import.

Because this needs direct queue access to run `ATTACH DATABASE` against the
live connection, `ArticlesDatabase.queue` is exposed as `internal` (not
`private`) specifically for `AmbrosiaSQLiteImportTable` — the one
deliberate exception to "everything goes through `articlesTable`" in that
module (see `database.md`).

## Feed identity and LAN re-pairing

Because Ambrosia is a self-hosted LAN server, its IP address can change
(DHCP lease renewal, different network) while remaining "the same" feed from
the person's point of view. `AmbrosiaFeedIdentity.collectionKey(for:)`
extracts a host-independent identity key from an Ambrosia feed URL's path
alone, recognizing three route shapes:

| URL path pattern | Identity key |
|---|---|
| `.../feed/search.json` | `"ambrosia-search"` |
| `.../feed/random-daily.json` | `"ambrosia-random-daily"` |
| `.../feed/collection/<id>.json` | `"ambrosia-collection-<id>"` |

`LocalAccountDelegate.repointIfAmbrosiaRepair(urlString:account:container:)`
uses this at OPML-import time: if an incoming feed URL resolves to the same
collection key as an existing feed (just with a different host/port), the
existing feed is repointed to the new URL instead of a duplicate sidebar
entry being created. This is the client-side half of surviving a LAN IP
change; see `feed-repointing.md` for the broader refresh-time repointing
behavior (not duplicated here).

## Settings

| Preference | Type | Default | Purpose |
|---|---|---|---|
| `AmbrosiaTransferFormatPreference.current` | `.json` / `.sqlite` | `.json` | Applies uniformly to every Ambrosia-paired feed; no per-feed override or automatic size-based switching. |
| `AmbrosiaAO3NetworkPreference.updatesEnabled` | `Bool` | `false` | Gates whether *any* live AO3 network fetch happens for an Ambrosia-sourced article. Off by default so a person using Nectar purely as a local archive reader isn't automatically making outbound AO3 requests. Content and stats are always applied together from one fetch when this is on — content is still subject to `AO3RegressionThreshold` regardless of this setting. |

Both preferences live in the `Account` module (not the iOS app target),
backed by `NectarAppGroupUserDefaults.store` (the same app-group suite used
elsewhere), specifically because the code that needs to read them
(`LocalAccountRefresher`, `AO3ChapterFetcher`) can't depend on the iOS app
target.

`AmbrosiaAO3NetworkPreference` was formerly two separate flags
(content-updates vs. stats-updates); they were collapsed into one because
both come off the same underlying HTTP fetch — `AO3ChapterHTMLExtractor`
reads chapter content and stats off one downloaded page, so splitting "fetch
the numbers" from "fetch the text" never actually saved a request.

## Relationship to AO3 integration

Ambrosia-sourced articles and natively-subscribed AO3-RSS articles converge
on the same downstream machinery once parsed: both can be picked up by
`AO3ChapterFetcher` for live refetches (gated on `article.bookKey` having
the `"ao3-work:"` prefix, not on `isAmbrosiaItem`), both are subject to
`AO3RegressionThreshold`'s content-regression guard, and both render through
the same AO3 preface-synthesis path in `ArticleRenderer`. See
`ao3-integration.md` for that shared machinery.
