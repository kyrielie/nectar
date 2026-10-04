# AO3 preface rendering and on-demand chapter fetch

How an article's AO3-style metadata preface gets rendered (synthesized vs.
fetched-and-real), when a chapter is fetched from AO3 on-demand, and the
networking/rate-limit layer that fetch goes through. See `ao3-feeds.md`
for the underlying HTML extractors, and `ao3-direct-feed-ingestion.md`
for the separate RSS/Atom subscription path (this doc's fetch/render
logic applies to both Ambrosia-sourced and direct-feed AO3 articles once
opened in the reader). See `ao3-integration.md` for the authenticated-
first/anonymous-fallback shape of the underlying `AO3ChapterFetcher`
fetch itself — when a session is stored, the fetch this doc describes
tries the authenticated path before any anonymous request, not after.

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
article is opened in the reader), regardless of the article's read
state. It requires `article.bookKey` to have the
`ao3-work:` prefix (`AO3FetchPolicy.workID(fromBookKey:)` returns
`nil` otherwise):

- **Anthology/combined-series articles still can't be individually
  refetched, but this is no longer a silent no-op.** `ParsedItem.bookKey`
  resolves anthologies (`isAnthology == true`) to `ao3-series:<id>` or
  `calibre-series:<name>`, never `ao3-work:<id>`, so
  `AO3FetchPolicy.workID(fromBookKey:)` still returns `nil` immediately
  (`AO3FetchPolicyTests` asserts this directly — deliberate scope, not
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
- **An already-fetched work's content only ever updates via an open or an
  explicit "Check for updates," never in the background.** There is no
  sweep, timer, or refresh-triggered *re*fetch of any kind: an AO3-work
  article that already has `contentHTML` and sits unread and unopened
  does not pick up new formatting, comments, kudos, or hit counts on its
  own, no matter how long it sits there or how many account refreshes
  happen in the meantime. The only way its stored content becomes
  current again is the person opening it (which runs `fetchIfNeeded`
  above, regardless of read state) or tapping "Check for updates"
  (`checkForUpdates(for:)`, unconditional on read state and on
  `AO3FetchPolicy.isStale`'s cadence check). This applies equally to read and unread
  articles — there is no read-state distinction anywhere in this path.
  This is specifically about *updates* to a work already fetched at
  least once — a brand-new article with no `contentHTML` yet can still
  get its first fetch at refresh time rather than open time, if
  `AO3PrefetchNewWorksPreference` is on (see `ao3-integration.md`'s
  "Fetch triggers, philosophy"). That's a one-time initial capture, not
  a background re-check, and it's off by default.

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
cooldown, in addition to that article's own 60-second floor.

### Work-page classification and the missing flag

`AO3WorkPageClassifier.classify(data:statusCode:)` (AO3Kit) turns a fetched
work page into content or one typed `AO3FetchFailure`, and both the
anonymous and the authenticated paths in `AO3ChapterFetcher` use it. Order:
429 gives `.rateLimited`; 404 or 410 gives `.workMissing`; a Cloudflare
challenge on a non-2xx status gives `.challenge` (so a 403 challenge page
is not reported as `.http(403)`); a 5xx gives `.http`, or
`.serviceUnavailable` when the body is AO3's 503 page; other non-2xx gives
`.http`; an empty body gives `.http`; otherwise the extractor outcome is
mapped (see `ao3-feeds.md`). A 2xx body is deliberately left to the
extractor, which tests for a real work first, so story text that happens to
contain a challenge marker phrase is not read as an interstitial.
`AO3WorkPageClassifier.isInterstitial(_:)` is the predicate meant for a
caching veto.

`ao3ConfirmedMissingAt` is set only on positive evidence
(`AO3FetchFailure.evidencesMissing`, which is true only for
`.workMissing`: HTTP 404/410 or AO3's explicit not-found copy). When signed
in, the authenticated attempt must also have reported `.workMissing`
(dual confirmation). An unrecognized page, a Cloudflare page, AO3's 503 page
and every other failure are transient and set no flag. Each failure's
message comes from `AO3FetchFailure.localizedMessage`, which reuses the
earlier English strings, so a generic non-429 failure still reads "Could not
reach AO3 (HTTP `<code>`)" and a 429 still reads "AO3 rate limit hit --
backing off before retrying".

Typed failures are kept per article: `AO3ChapterFetcher.lastFetchFailure(forArticleID:)`
returns the `AO3FetchFailure`, and `lastFetchFailureMessage(forArticleID:)`
returns its `localizedMessage`, which is what `ArticleRenderer` and the
`.ao3ChapterFetchDidFail` notification's `message` key carry. A failure
that Nectar does not recognize (`.unrecognizedPage`) is logged to the
Activity Log with its own message so real deleted-work page shapes can be
learned.

Not yet changed: existing `ao3ConfirmedMissingAt` values written before
this classification are not cleared until the schema 6 migration (T11).

## Table of contents and author headings

`main_ios.js`'s `tocNodes()` (document-wide `h1, h2.heading,
h2.toc-heading`) drives the table of contents, and `annotations.js`'s
`buildHeadingIndex` keeps a copy of the same selector for `chapterTitle`.
For AO3-fetched works both now skip everything inside `#workskin` except
the extractor's own chapter headings, via `isAuthorContentHeading` (defined
in `main_ios.js`, copied into `annotations.js`; keep the two in sync).

The contract between the two sides: `AO3ChapterHTMLExtractor.extractedChapter`
rewrites each chapter's `h3.title` into `h2.heading`, and that `h2` stays a
direct child of its `div.chapter.preface.group`. The JS treats exactly that
shape as a chapter and everything else under `#workskin` as author content.
`AO3ChapterHTMLExtractorTests.everyChapterHeadingIsADirectChildOfItsChapterPrefaceGroup`
pins the Swift half; `Tests/JS/toc/toc-nodes.test.js` pins the JS half. If
the extractor's chapter-heading shape changes, both must change together, or
the TOC silently loses every chapter.

Why this exists: authors write their own `<h1>`s (and occasionally
`<h2 class="heading">`s) inside chapters, e.g. a work styled as a
news feed with dozens of headlines. Every `h1` counts as a "book" in
`TableOfContentsViewController`, so one such work flipped the TOC into its
anthology layout with dozens of bogus books and chapters nested under the
wrong ones (a real 32-chapter work produced 72 entries instead of 33).
Author markup is deliberately left in the DOM untouched, because a work skin's
own `#workskin h1 { ... }` rules must keep applying; the headings just aren't
navigable. The rule is structural, not marker-based, so works fetched before
it existed are corrected without a refetch. Non-AO3 content (Calibre/Ambrosia
anthologies) has no `#workskin` and is unaffected.

Consequence for single-chapter works: an author's own `h2.heading` sections
inside a one-chapter work are no longer TOC rows; the TOC shows the lone
template `<h1>` row, same as any other single-chapter work.

Not covered: `Shared/Article Rendering/main.js`'s theme-opt-in
`applyChapterDividers`/`applyVersalCaps` select `h2.heading, h3.title`
independently, so an author-written `<h2 class="heading">` inside a work can
still receive a chapter divider under a theme that enables them.

## Work skin CSS round trip

The author's `<style>` block is captured by `precedingStyleElement` and
re-serialized through `HTMLLiteTree.swift`'s `serializeHTMLLiteNodes`. The
scanner delivers `<style>` contents verbatim (raw text, no entity decoding),
so the serializer writes `<style>` text back verbatim too. Escaping it, as
every other text node is, turned CSS child combinators (`a>b`) into
`a&gt;b`, which a browser does not decode inside `<style>`; the selector
became invalid and the author's rule was silently dropped.
`<script>` text is intentionally still escaped. Comments between the skin's
`</style>` and `<div id="workskin">` (AO3 emits two) do not break
`precedingStyleElement`, because `HTMLScanner` discards comments before the
tree builder sees them.

