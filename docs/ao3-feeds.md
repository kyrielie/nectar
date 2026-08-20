# AO3 Feed & HTML Extraction Layer

This covers the pure-parsing side of Nectar's Archive of Our Own (AO3)
support: a cluster of files under
`Modules/RSParser/Sources/RSParser/Feeds/Extensions/` that turn AO3's HTML
(work pages, search-results listings, series listings, tag/user Atom feed
summaries) into structured data. Everything here is synchronous, has no
network or database dependency, and lives in `RSParser` specifically so it
can be reached from every AO3 ingestion path without a layering inversion
(`Account` depends on `RSParser`, never the reverse). The networking/session/
fetch-orchestration layer built on top of these extractors lives in the
`Account` module — see `ao3-integration.md`. The subscription/wiring layer
that actually invokes these extractors on incoming RSS/Atom items is
documented separately in `ao3-direct-feed-ingestion.md`.

All of these extractors operate on `HTMLLiteTree`/`HTMLLiteElement` — a
lightweight parsed-HTML tree type shared with the rest of `RSParser`'s HTML
parsing (`parseHTMLLiteTree`, `firstDescendant`, `descendants`,
`flattenedText` are the common traversal helpers used throughout this
cluster).

## Shared helpers: `AO3HTMLHelpers`

A single home for logic that used to be duplicated (and had drifted, in two
cases, into actual behavioral disagreement) across the extractor files:

- `absoluteURL(_:)` — resolves an AO3-relative `href` against
  `https://archiveofourown.org`.
- `classTokens(of:)` — splits an element's `class` attribute on whitespace.
- `workID(fromLI:)` / `isWorkRow(_:)` — recognizes a work-listing row,
  `<li class="... work-<id> ...">`, by scanning class tokens for a
  `work-<digits>` token rather than a fixed-position string match (since the
  full class list also carries `work`/`blurb`/`group` tokens in
  unconfirmed order).
- `seriesID(fromHref:)` — pulls a numeric series id out of an
  `/series/<id>` link, shared by search-results author metadata, chapter-
  page series links, and `AO3SummaryExtractor`'s parsed fields.
- `isRegistrationRequired(_:)` — detects AO3's login wall: requires **both**
  a `div#signin` element **and** that div's text containing the specific
  string "This work is only available to registered users of the Archive."
  (Presence of `div#signin` alone was an earlier, looser check in one of the
  two extractors that used to disagree; the stricter version was kept,
  since misreading some other `#signin`-bearing notice as a login wall
  would block a fetch that could otherwise have succeeded.)

`AO3IgnoreList` (see below) has its own independent copy of similar
class-token logic rather than depending on this file — not for lack of a
shared home, but because `AO3IgnoreList` predates the reconciliation and,
per its own header comment, is blocked from depending on `Account` in the
other direction.

## `AO3SummaryExtractor` — tag/user Atom feed entries

AO3's tag-subscription and user-subscription Atom feeds render each work's
byline, stats, series membership, and tag list as machine-generated HTML
inside the entry's `<summary>`. `AO3SummaryExtractor.extract(fromSummaryHTML:)`
parses that summary and returns `AO3ExtractionResult?` — `nil` if the HTML
doesn't look AO3-generated at all (specifically: there isn't exactly one
top-level `<p>` whose text starts with the literal `"Words:"`, AO3's
machine-generated stats paragraph), signaling the caller to fall back to
generic summary handling.

`AO3ExtractionResult` carries: `cleanedSummaryHTML`, `wordCount`,
`chapterCurrent`/`chapterTotal` (nil when AO3 itself shows `"?"`),
`isComplete`, `language`, `fandoms`/`ratings`/`warnings`/`categories`/
`characters`/`relationships`/`additionalTags`, `series: [ParsedSeriesEntry]?`,
and `ao3WorkID`. This is a second, independent source of the same kind of
metadata Ambrosia's `_ambrosia` JSON extension provides (same downstream
`ParsedItem` fields, different wire format) — used for native AO3 tag/user
RSS-Atom subscriptions rather than an Ambrosia-hosted library.

## `AO3SearchResultsExtractor` — AO3 listing pages

Despite its name (predates this section's broadening — see
`nectar-toolbar-ao3-listing-feeds.md`), this extracts one `ParsedItem`
per work row from *any* AO3 listing page, not just search-results
pages: a `GET .../works?work_search[...]&view_adult=true` page, a
`/tags/<tag>/works` tag-listing page, an author's `/users/<name>/works`
(or pseud-scoped `/users/<name>/pseuds/<pseud>/works`) page, someone's
`/users/<name>/bookmarks`, `/users/<name>/subscriptions`,
`/users/<name>/readings?show=to-read` (marked for later), a
`/collections/<name>/works` collection, or a `/series/<digits>` series
listing (confirmed by `AO3SeriesListingExtractorTests`'s
`searchResultsExtractorParsesAllTenRowsFromSeriesListingFixture` to
work unmodified against the same fixture `AO3SeriesListingExtractor`
uses — see that extractor's own section below). All of these share the
same `.index.group` blurb-row markup and `ol.pagination` pager; the
extractor selects `li.work-<id>` rows anywhere in the document rather
than scoping to a page-type-specific container, so no page-type
branching was needed to support the rest of AO3's listing types beyond
the original two — only routing (`LocalAccountRefresher.isAO3ListingFeed(_:)`,
see `refresh-throttling.md`) needed broadening.

For subscriptions specifically: the extractor currently recognizes work
rows only, not the series blurbs a subscriptions page can also contain
— subscribed-series handling is deliberately deferred (Option B in
`nectar-toolbar-ao3-listing-feeds.md` item 2), not silently dropped.
Series blurbs on a subscriptions page are simply not matched by
`isWorkRow(_:)` and so don't appear in the result today.

```swift
enum AO3SearchResultsOutcome {
    case success([ParsedItem], hasNextPage: Bool, pageTitle: String?)
    case noResults(pageTitle: String?)
    case registrationRequired
}

static func extract(fromResultsPageHTML html: String, feedURL: String) -> AO3SearchResultsOutcome
```

Flow: checks the registration wall first; finds every `<li>` matching
`isWorkRow(_:)`; maps each to a `ParsedItem`; filters the result through
`AO3IgnoreList.shouldExclude(_:)`; if filtering empties an otherwise
non-empty result, that's reported as `.noResults` too (an ignored-to-empty
page has no meaningful "next page" signal). `hasNextPage` comes from
`AO3ListingPagination.hasNextPage(_:)`. `pageTitle` is the page's own
`<title>`, suffix-stripped and trimmed, carried on both `.success` and
`.noResults` so a create-time caller can name the feed after the page
rather than leaving it "Untitled" — see `LocalAccountDelegate.createFeed`'s
AO3 branch.

Two listing types — subscriptions and marked-for-later — are always
private to the signed-in account, so a plain anonymous fetch of them is
expected to always hit the registration wall. `AO3SearchResultsFetcher`'s
`fetchRequiringSignIn(url:feedURL:)` (see that file) wraps `fetch(url:feedURL:)`
with an anonymous-then-authenticated retry for exactly these two types,
gated by `LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(_:)`
— see `ao3-authenticated-reading.md` for the authenticated-fetch
mechanism itself.

The header comment is candid about provenance: the row/title/stats
selectors were validated by reading (not transcribing — the source is
explicit about this licensing boundary) the selector *choices* of the
third-party GPL-3.0 tool `ao3downloader`, then independently reimplemented
in Swift, plus later reconciliation against a real captured search-results
page and a user-supplied View Source capture for date/language/stats
selectors specifically. Several selectors are flagged in-source as
"plausible but not independently confirmed" against every page shape (e.g.
the disabled-`next`-on-last-page pagination case) — a documented, explicit
uncertainty rather than a guess presented as fact, consistent with the
project's rule against asserting unverified markup.

`AO3SearchResultsOutcome` deliberately has no rate-limit case of its own:
AO3's search-results rate limiting is a genuine HTTP 429, already
intercepted by `Downloader`'s per-host cooldown before any HTML reaches this
extractor (unlike chapter fetches, which can return HTTP 200 for what is
actually a rate-limit interstitial — see `AO3ChapterExtractionOutcome`
below).

## `AO3SeriesListingExtractor` — series listing pages

Extracts work permalinks from a fetched `GET .../series/<id>` page — the
same `li.work-<id>` row shape as search results (confirmed byte-for-byte
identical against a real captured page), just under a differently-classed
`<ul>` container (not relied upon; the row selector alone is sufficient).
Used for two purposes:
1. Finding the "first work" in a series (AO3's work page has previous/next
   Work links but no "first work in series" link anywhere — reaching work
   #1 requires fetching the series-listing page itself).
2. (Inline-series-navigation phase) `workPermalinks(fromSeriesListingHTML:)`
   extracts every work row on one page plus whether another page exists,
   for `AO3SeriesNavigator`'s bounded multi-page walk (see
   `ao3-integration.md`). This extractor is deliberately page-scoped — it
   parses whatever single page it's handed and does not itself walk
   pagination.

## `AO3ListingPagination`

One shared `hasNextPage(_:)` check (`li.next` wrapping a live `<a href>`)
used by both `AO3SearchResultsExtractor` and `AO3SeriesListingExtractor`,
hoisted out once both needed byte-identical logic on confirmed-identical
markup.

## `AO3ChapterHTMLExtractor` — full work pages

The largest and most heavily-used extractor: turns a fetched
`GET .../works/<id>?view_full_work=true&view_adult=true` page into
storable article content.

AO3 wraps a work's title, its own summary, and every concatenated posted
chapter in a single `<div id="workskin">` — present and non-empty even for
works with no custom skin. When a work has one, an immediately-preceding
`<style>` block (its rules scoped `#workskin .classname {...}`) has to be
captured alongside the wrapper, since neither means anything without the
other. Separately, the Work Header metadata (rating/warning/category/
fandom/relationships/characters/tags/language/series/collections/stats)
lives in its own `<dl class="work meta group">`, a sibling of `#work-skin`
outside it entirely — this is parsed independently and re-rendered by
`AO3PrefaceRenderer` before being prepended to `contentHTML` as its own
unit.

```swift
enum AO3ChapterExtractionOutcome {
    case success(AO3ChapterExtractionResult)
    case adultContentGate     // expected unreachable now that every fetch sends view_adult=true
    case registrationRequired
    case notFound             // deleted/moved work, or any other unsampled gate shape
}
```

All four outcomes are distinguished purely by document shape — AO3 returns
HTTP 200 for every one of them, including the gate pages, so there is no
status-code signal to branch on.

`AO3ChapterExtractionResult` carries: `contentHTML` (the merged
metadata+workskin unit, ready to store/render), `chapters:
[AO3ExtractedChapter]` (id + title, document order, for table-of-contents
UI only — chapter content itself lives in `contentHTML`, not per-chapter),
the four live stat counts (`commentCount`/`kudosCount`/`bookmarkCount`/
`hitCount`, each independently nilable — Comments and Bookmarks rows are
known to sometimes be absent even on a normal page), a `wordCount` distinct
from `Article.wordCount` (this one exists purely to feed
`AO3ChapterFetcher`'s content-regression guard — see `ao3-integration.md`
— by comparing the fetched page's own count against the stored content's
re-derived one, independent of whatever the originating feed reported),
`csrfToken` (scraped from AO3's `<meta name="csrf-token">`, present on
every page regardless of sign-in state, used for the kudos-on-like
feature), and `seriesEntries: [AO3SeriesSpanResult]` — per-series-membership
previous/next-work data read off each `<span class="series">` block's own
navigation links (superseding an earlier design that collapsed multiple
series memberships into one article-wide previous/next pair, which lost
information for a work belonging to more than one series).

## `AO3PrefaceRenderer` — synthesizing the preface

Once `AO3ChapterHTMLExtractor` (or, before a live fetch has ever succeeded,
a feed-derived synthetic source) has structured preface data, this file
renders it into the app's own preface presentation:

- `AO3TagEntry` — one value within a row (a tag, a fandom, a series link).
  `href` is nil for plain text and for every field of a pre-fetch synthetic
  preface (no AO3 URLs exist yet to link to); `prefix` holds unlinked text
  ahead of the value (used only by series rows, e.g. `"Part 1 of "` ahead of
  a linked series name). `ao3ID`/`previousWorkURL`/`nextWorkURL` carry
  inline-series-navigation data on entries that belong to a series-navigation
  row, so the renderer can build First/Previous/Next links right alongside
  the series name in one pass rather than a parallel array that could drift
  out of sync positionally.
- `AO3PrefaceRow` — one renderable row (Rating/Warning/Category/Fandom/
  Relationships/Characters/Additional Tags/Language/Series/Collections),
  `label` already carrying its own trailing colon exactly as AO3's own
  `<dt>` markup does.

This same renderer produces both the real, post-fetch preface (from
`AO3ChapterExtractionResult`'s parsed Work Header) and a pre-fetch synthetic
preface built from feed-derived metadata alone (Ambrosia's `_ambrosia`
fields or `AO3SummaryExtractor`'s output) — see `ArticleRenderer`'s
`ao3SyntheticPrefaceHTML(for:)` in `ao3-integration.md`/`theme-system.md`
for where that synthetic path is invoked.

## `AO3IgnoreList` — by-work / by-author filtering

A `UserDefaults`-backed (app-group suite) allow/deny list of AO3 work IDs
and author URLs, consulted at `ParsedItem` construction time —
`shouldExclude(_:)` is called from `RSSParser`/`AtomParser` right after
mapping raw items to `ParsedItem`s, and from `AO3SearchResultsExtractor`.
Filtering this early is what makes one mechanism simultaneously solve
"don't show," "don't fetch," and "don't save": an excluded item never
becomes a persisted `Article` at all, so it never reaches account update,
`AO3ChapterFetcher`, or the timeline.

- `ignoredWorkIDs: Set<String>` — bare numeric AO3 work IDs (matching
  `ParsedItem.ao3WorkID`'s shape), not full permalinks.
- `ignoredAuthorURLs: Set<String>` — full author URLs, matched by exact
  string equality (display names collide and are never used for matching).
- `shouldExclude(_:)` — excludes on `ao3WorkID` membership, or if *any*
  co-author's URL is in the ignored set (multi-author default: any one
  ignored co-author is sufficient to hide the whole work).
- Explicitly **not retroactive**: adding a rule only affects items parsed
  after the rule was added. There is no cleanup pass over already-stored
  articles, and none is planned — a documented, deliberate scope
  limitation, not an oversight.

Lives in `RSParser` rather than `Account` specifically so every AO3
ingestion path (native tag/user RSS-Atom, the search extractor, and a
pasted-link-list import) can reach it without `RSParser` having to depend on
`Account`.
