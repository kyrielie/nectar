# AO3 preface rendering and on-demand chapter fetch

How an article's AO3-style metadata preface gets rendered (synthesized vs.
fetched-and-real), when a chapter is fetched from AO3 on-demand vs. via
background sweep, and the networking/rate-limit layer that fetch goes
through. See `ao3-feeds.md` for the underlying HTML extractors, and
`ao3-direct-feed-ingestion.md` for the separate RSS/Atom subscription path
(this doc's fetch/render logic applies to both Ambrosia-sourced and
direct-feed AO3 articles once opened in the reader).

Two independent paths feed the same `AO3PrefaceRenderer` markup
(`<dl class='tags'>` of flat `<dt>`/`<dd>` pairs): `ArticleRenderer.
ao3SyntheticPrefaceHTML` synthesizes a preface from `Article`'s
already-parsed fields when `contentHTML == nil` (plain-text values, no AO3
links); `AO3ChapterHTMLExtractor.parseWorkHeader` parses AO3's real `<dl
class="work meta group">` off a live-fetched page into the same row/stats
shape (real tag `href`s included) once a chapter fetch has succeeded. The
synthetic path is guarded to never fire when `contentHTML` is already
non-nil — which is always true for Ambrosia items, since Ambrosia's JSON
feed sets `content_html` directly, including its own preface. So an
Ambrosia-sourced article's preface is either Ambrosia's own embedded HTML
(as imported) or, after a successful `AO3ChapterHTMLExtractor` fetch,
AO3's structure re-rendered through `AO3PrefaceRenderer` — `ArticleRenderer`
never synthesizes a preface for an Ambrosia item.

Each row of that shared markup is either bounded (renders inside the
label-adjacent value column) or wide (`AO3PrefaceRow.isWide`, renders
`class='wide'` on both `<dt>`/`<dd>`, spanning the preface's full width on
its own line below the label instead of squeezed into a `1fr` column --
see `AO3PrefaceRenderer.swift`'s doc comment on `isWide` for the layout
rationale). Both paths agree on which rows are wide:
`AO3ChapterHTMLExtractor.parseWorkHeader` sets it from the AO3 `<dt>`'s
class token -- `fandom`/`relationship`/`character`/`freeform` (unbounded
value count), plus `warning` (bounded count, but each value is a long
fixed AO3 phrase and works commonly carry two or three at once) and
`collections` (comma-joined without a `<ul>` wrapper, same overflow
problem as the others) -- while `ArticleRenderer.ao3SyntheticPrefaceHTML`
hardcodes the same wide set for the fields it can synthesize (Archive
Warning, Fandom, Relationships, Characters) by literal label, since it has
no AO3 class tokens to read. Rating and Category are bounded on both
paths. Collections and Additional Tags (freeform) have no synthetic-path
equivalent and so only ever appear after a real `AO3ChapterHTMLExtractor`
fetch: `Article` carries no `collections` field to synthesize from
(Ambrosia's own collections list comes from a different data source than
the Atom feed this app parses), and Workstream 1 doesn't parse a distinct
freeform-tags bucket off the Atom feed either. The Series row is wide
unconditionally via a separate flag (`isSeriesNavigation`, not `isWide`)
-- see `seriesNavigationRowsHTML` -- since its per-entry First/Previous/
Next links need the same full-width treatment regardless of entry count.

`AO3ChapterFetcher.fetchIfNeeded(for:)` is called from
`WebViewController.setArticle(_:updateView:)` (i.e. whenever an
article is opened in the reader) and, since the fixes below, also from a
throttled background sweep. It requires `article.bookKey` to have the
`ao3-work:` prefix (`AO3ChapterFetcher.ao3WorkID(fromBookKey:)` returns
`nil` otherwise):

- **Anthology/combined-series articles still can't be individually
  refetched, but this is no longer a silent no-op.** `ParsedItem.bookKey`
  resolves anthologies (`isAnthology == true`) to `ao3-series:<id>` or
  `calibre-series:<name>`, never `ao3-work:<id>`, so
  `ao3WorkID(fromBookKey:)` still returns `nil` immediately
  (`AO3ChapterFetcherTests` asserts this directly — deliberate scope, not
  an oversight, since there's no single AO3 URL a Calibre-merged
  compilation could fetch from; fetching+merging every member work was
  explicitly deferred in `ao3-merged-plan.md` — cited in-code but, like
  `nectar-audit-remediation-plan.md` and `nectar-implementation-plan.md`
  (see `refresh-throttling.md` and `sqlite-transfer.md`), not present
  anywhere in the current tree). What changed:
  `fetchIfNeeded` now calls `noteAnthologyUnsupportedIfNeeded`, which logs
  an `ActivityKind.skipAO3SeriesFetch` entry and records a
  `lastFetchFailureMessage` ("Combined AO3 series can't be refreshed
  individually — showing imported content") the first time each such
  article is seen, reusing the `attemptDates` dictionary as an
  already-noted gate so reopening the same article repeatedly doesn't
  spam the Activity Log. These articles remain locked to whatever HTML
  Ambrosia supplied at import; `ArticleRenderer`'s "Full text
  unavailable" notice still only fires when `contentHTML == nil`, which
  never happens for an Ambrosia-sourced row, so the failure message
  currently surfaces only in the Activity Log, not inline in the reader.
- **Non-anthology (single-work) articles no longer depend solely on being
  opened.** `AO3ChapterFetcher.init` now observes
  `.AccountRefreshDidFinish` and runs `sweepStaleUnreadArticles(in:)` on
  each account after a refresh: it fetches the account's unread articles,
  filters to those with a resolvable `ao3WorkID` and a stale `isStale`
  result, and calls `fetchIfNeeded` for up to `maxArticlesPerSweep` (5) of
  them, sleeping `secondsBetweenSweepRequests` (5s) between each — scoped
  to unread and bounded/throttled deliberately, since this is the one
  path that can fire several AO3 requests back-to-back with no user
  action in between. `sweepingAccountIDs` guards against two
  `AccountRefreshDidFinish` notifications in quick succession starting
  overlapping sweeps for the same account. An unread single-work article
  can now pick up new formatting/content on the sync cadence rather than
  only the next time it's opened; read articles and combined-series
  articles are unaffected by the sweep.

CSS for the preface (`#ao3SyntheticPreface`/`#ao3Preface`, `dl.tags`
grid layout with `dt`/`dd` on the same row) now lives in `Shared/Article
Rendering/core.css`, not `stylesheet.css`. `ArticleTheme.init(url:
isAppTheme:)` builds a custom theme's CSS as `core.css` + that theme's own
`stylesheet.css` (from its `.nnwtheme` bundle under `Themes/`) —
`core.css` is the one file guaranteed to load for every theme, default or
custom, where `Shared/Article Rendering/stylesheet.css` only loads for the
default theme. Moving the rules fixes the same-line `dt`/`dd` grid layout
for any custom theme (confirmed none of the bundled ones, e.g. Sepia,
define their own `dl`/`dt`/`dd`/`ao3Preface` rules), which previously fell
back to the browser's default `<dl>` box model under a non-default theme.

AO3 fetch requests (`AO3ChapterFetcher.download`) go through
`Downloader.shared`, not `DownloadSession` — a deliberate choice per the
class's own doc comment (one-shot download vs. a feed-refresh session).
`Downloader`'s `URLSessionConfiguration` sends the app's real User-Agent
(`UserAgent.headers()`, from Info.plist's `UserAgent`/`UserAgentExtended`
keys — now `"Nectar (https://github.com/kyrielie/nectar; ...)"`, pointing
at the Nectar project itself rather than the upstream NetNewsWire fork it
was inherited from), forces cookies off, and caps
`httpMaximumConnectionsPerHost` at 1. `Downloader` now has its own
per-host 429/`Retry-After` handling, mirroring (not sharing code with)
`DownloadSession`'s `handle429Response`/
`requestShouldBeDroppedDueToActive429`: a 429 response is parsed into an
`HTTPResponse429` (`Retry-After` header if present and positive, else a
10-minute default — the same default `DownloadSession` uses) and recorded
per lowercased host in `retryAfterMessages`. Any subsequent `download(_:)`
call for that host before the recorded `resumeDate` short-circuits with a
synthetic 429 `HTTPURLResponse` and no network request, until the cooldown
expires. This is a genuine behavior change from `AO3ChapterFetcher`'s own
60-second `attemptDates` floor, which is still per-`articleID` and
unrelated: a rate-limit response for one AO3 article's fetch now also
pauses `Downloader`-routed fetches for *other* AO3 articles (or anything
else on the same host) opened in the same window, via the new per-host
cooldown, in addition to that article's own 60-second floor. A Cloudflare
challenge or other non-429 failure still just fails `response.statusIsOK`
and produces a generic "Could not reach AO3 (HTTP `<code>`)" message; only
the 429 case gets the distinct "AO3 rate limit hit — backing off before
retrying" message and the per-host cooldown.
