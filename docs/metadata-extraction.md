# HTML Metadata Extraction

Nectar pulls a small, fixed set of signals out of a page's `<head>` — favicon
links, Apple touch icons, feed autodiscovery links, Open Graph images, and a
Twitter card image — and caches the result per URL. This is used to find feed
icons, home-page favicons, and (indirectly) to help with feed discovery. It is
a two-layer system: a pure parser in `RSParser` that turns raw HTML bytes into
structured data, and a caching/download layer in the `HTMLMetadata` module
that fetches, persists, and republishes that data as notifications.

## Layer 1: parsing (`RSParser/HTML`)

### `HTMLMetadataParser`

`HTMLMetadataParser.htmlMetadata(with:)` is the entry point. It wraps the
generic SAX-style `HTMLScanner` (also used by `HTMLLinkParser` elsewhere in
`RSParser`) with a delegate, `MetadataParserDelegate`, that:

- Collects only `<link>` and `<meta>` tags.
- For `<link>`, requires both a non-empty `rel` and an `href`/`src` before
  keeping the tag — this mirrors the behavior of the Objective-C parser it
  replaced.
- Stops scanning the moment it hits a `<body>` tag, on the assumption that
  everything relevant lives in `<head>`.
- Makes one exception: if the URL string contains `youtube` (case-insensitive,
  so `youtubers.example.com` also matches — a harmless false positive), it
  keeps scanning past `<body>`, because YouTube is known to place its feed
  `<link>` tag inside the body rather than the head.

Every matched tag is captured as an `HTMLTag` (`.link` or `.meta`) with its
raw attribute dictionary, and handed to `HTMLMetadata.init(urlString:tags:)`
for categorization.

### `HTMLMetadata`

A plain, `Sendable` value type that takes the flat list of `HTMLTag`s from the
parser and buckets them into typed collections:

- `favicons: [HTMLMetadataFavicon]` — `<link>` tags whose `rel` list contains
  `icon` (case-insensitive), deduplicated by resolved absolute URL, each
  carrying an optional MIME `type`.
- `appleTouchIcons: [HTMLMetadataAppleTouchIcon]` — `rel="apple-touch-icon"`
  or `apple-touch-icon-precomposed`, with `sizes` parsed into a `CGSize`.
- `feedLinks: [HTMLMetadataFeedLink]` — `rel="alternate"` links whose `type`
  ends in `/rss+xml`, `/atom+xml`, or `/json`.
- `openGraphProperties.images: [HTMLOpenGraphImage]` — parsed from
  `<meta property="og:image...">` tags (url, secure_url, type, width, height,
  alt).
- `twitterProperties.imageURL` — from `<meta name="twitter:image">`.

All URLs are resolved to absolute form against the page's own URL at
categorization time, so downstream consumers never have to do relative-URL
math.

Relevant tests: `Modules/RSParser/Tests/RSParserTests/HTML/HTMLMetadataTests.swift`.

## Layer 2: fetch, cache, and republish (`Modules/HTMLMetadata`)

The `HTMLMetadata` Swift package (distinct from the `HTMLMetadata` struct
above, which lives in `RSParser`) is the app-facing surface. It owns:

### `HTMLMetadataRecord`

A `Codable`, `Sendable` DTO — essentially a flattened, storage-friendly
projection of the `RSParser.HTMLMetadata` struct (`Favicon`,
`AppleTouchIcon`, `FeedLink`, `OpenGraphImage`, plus `twitterImageURL`). It
adds icon-selection logic on top of the raw data:

- `bestWebsiteIconURL()` tries, in order: largest apple-touch-icon → largest
  Open Graph image → Twitter image.
- `largestAppleTouchIcon()` / `largestOpenGraphImageURL()` pick the biggest
  candidate while rejecting anything with an aspect ratio wider than 2:1
  (banner-shaped images are assumed not to be usable icons). Open Graph image
  selection also hard-excludes one known-bad WordPress placeholder URL
  (`https://s0.wp.com/i/blank.jpg`).

### `HTMLMetadataDatabase`

A `Sendable` `actor` (so all access is inherently serialized) wrapping a
single-table SQLite database at `HTMLMetadata.db` in the app's data folder.

Table `metadata`: `url TEXT PRIMARY KEY`, `lastChecked REAL`,
`statusCode INTEGER DEFAULT 200`, plus JSON-encoded text columns for
`favicons`, `appleTouchIcons`, `feedLinks`, `openGraphImages`, and a plain
text `twitterImageURL`. Row encoding/decoding for the JSON columns lives in
`HTMLMetadataTable`, which also owns all the raw SQL.

The actor keeps an in-memory `[String: CachedRecord]` mirror on top of the
table so repeated lookups within a session don't round-trip through SQLite;
the cache is dropped whenever the app goes to the background
(`.appDidGoToBackground`).

A `CachedRecord` stores the record (`nil` for a failure-only row),
`lastChecked`, and `statusCode`, and classifies itself as:
- **persistent failure** — `statusCode` in `400...499`
- **transient failure** — `statusCode == 0` (a pre-response failure: DNS,
  TLS, connection-level)

Time-based policy constants:

| Constant | Value | Meaning |
|---|---|---|
| `cacheExpirationHours` | 149 (a prime near 6 days) | A successful record younger than this is served without a refetch. |
| `maximumDaysWithoutCheck` | 30 | Rows older than this (success or failure) are purged at startup. |
| `persistentFailureRetryDays` | 11 | How long a 4xx blocks retries. |
| `transientFailureRetryHours` | 5 | How long a transient failure blocks retries. |

Failure rows are written with a guarded `INSERT ... ON CONFLICT DO UPDATE ...
WHERE statusCode >= 400 OR statusCode = 0` so a later failure can never
clobber an existing 2xx success row — a stale success is preferred over
recording a blip as the row's new state.

Public queries exposed to the downloader:
- `cachedRecord(for:)` — non-expired success only.
- `staleCachedRecord(for:)` — success regardless of age (used as a fallback
  when a fresh fetch fails).
- `lastDownloadDate(for:)`, `recentlyFailed(for:)`.

`performStartupMaintenance()` runs once at actor init: purges expired rows
and conditionally vacuums.

### `HTMLMetadataDownloader`

The public, `nonisolated`, `Sendable` singleton (`HTMLMetadataDownloader.shared`)
that the rest of the app actually talks to. Its contract is synchronous-first:

```
cachedMetadata(for url: String) -> HTMLMetadataRecord?
```

If it has an in-memory record, it returns it immediately. Otherwise it
returns `nil` and kicks off an async fetch (checking the on-disk cache first,
then downloading if needed); callers are expected to re-query after
observing the `.htmlMetadataAvailable` notification (posted on the main
thread, carrying `HTMLMetadataUserInfoKey.record` and `.url`).

An in-memory `[String: HTMLMetadataRecord]` cache (an `OSAllocatedUnfairLock`-
protected dictionary, not the database actor's own cache) is cleared on both
`.appDidGoToBackground` and `.lowMemory`.

Download flow (`downloadMetadata(url:)`):
1. Logs an `ActivityLog` entry (`ActivityKind.downloadHTMLMetadata`) so
   metadata fetches are visible in the app's Activity Log alongside feed
   refreshes.
2. Downloads via the shared `RSWeb` `Downloader`.
3. On success (non-empty body, 2xx): parses with `HTMLMetadataParser`, builds
   an `HTMLMetadataRecord`, saves it to `HTMLMetadataDatabase`, updates the
   in-memory cache, and posts `.htmlMetadataAvailable`.
4. On HTTP failure: records a persistent failure for 4xx codes, then falls
   back to serving a stale cached record if one exists (so a temporarily
   errored page doesn't blank out an icon that used to resolve).
5. On network-level failure (thrown error before any response): records a
   transient failure and likewise falls back to stale cache.

A retry throttle (`attemptDates`, `hoursBetweenAttempts = 3`) prevents
re-downloading the same URL more than once every 3 hours regardless of cache
state, independent of the database-level failure-retry windows above.

`SpecialCase` (from `RSWeb`) is consulted to skip metadata downloads entirely
for a couple of known hosts (`rachelByTheBayHostName`, `openRSSOrgHostName`).

## Consumers

- **`Images/FaviconDownloader`** and **`Images/FeedIconDownloader`** are the
  primary consumers: both call `HTMLMetadataDownloader.shared.cachedMetadata(for:)`
  keyed on a feed's home page URL, and both observe `.htmlMetadataAvailable`
  to re-check any feeds that were waiting on a fetch in flight.
  `FaviconDownloader` additionally filters candidate favicons through its own
  `shouldAllowFavicon(_:)` before accepting one.
- Activity-log surfaces (`ActivityLogViewModel`, `CurrentActivityViewModel`)
  and a couple of feed-list view controllers reference the module only for
  its notification name/user-info keys, to reflect in-progress metadata
  fetches in the UI.

## Data flow summary

```
HTML bytes
  -> HTMLScanner (generic SAX-ish tag scanner)
  -> MetadataParserDelegate (collects <link>/<meta> in <head>)
  -> HTMLMetadata (RSParser) — categorizes into favicons/icons/feedLinks/OG/Twitter
  -> HTMLMetadataRecord (HTMLMetadata module) — Codable projection + icon-picking logic
  -> HTMLMetadataDatabase (SQLite, actor-isolated, time-boxed cache)
  -> HTMLMetadataDownloader (public API, in-memory cache, retry throttling, ActivityLog)
  -> .htmlMetadataAvailable notification
  -> FaviconDownloader / FeedIconDownloader
```
