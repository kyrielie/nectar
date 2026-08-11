# AO3 Integration (Account layer)

This covers the networking, session, and orchestration layer built on top of
the pure HTML extractors in `ao3-feeds.md`, living in
`Modules/Account/Sources/Account/LocalAccount/`. Where the extraction layer
answers "what does this AO3 page say," this layer answers "when do we fetch
a page, with what credentials, how often, and what do we do with the
result." All of it is scoped to Nectar's Local account type — AO3 works are
ingested either as native AO3 tag/user feed subscriptions, AO3 search
subscriptions, or Ambrosia-sourced library items, and this layer is what
keeps their content current after the initial parse.

## `AO3ChapterFetcher` — on-demand chapter fetch and storage

The central piece: `AO3ChapterFetcher.shared` fetches an AO3 work's live
page (`?view_full_work=true&view_adult=true`) on demand and persists the
extracted `contentHTML` for any article whose `bookKey` identifies it as an
AO3 work (`"ao3-work:<id>"` prefix — see `ambrosia-feed.md` for `bookKey`
derivation). It's modeled directly on `HTMLMetadataDownloader`: the same
anti-hammering `attemptDates` gate, the same `ActivityLog`
start/complete/fail call sequence, and the same "leave existing content
alone on failure" philosophy.

### Eligibility and staleness

- Gated purely on `article.bookKey` having the `"ao3-work:"` prefix —
  **not** on `article.isAmbrosiaItem`. An Ambrosia-sourced article is
  exactly as eligible for a live fetch as a natively-subscribed AO3-RSS
  article; the only way to opt an Ambrosia-sourced article out entirely is
  `AmbrosiaAO3NetworkPreference.updatesEnabled` (see `ambrosia-feed.md`).
- Anthology/series-group book keys (`"ao3-series:"`, `"calibre-series:"`
  prefixes) are never eligible — there's no single AO3 work URL to fetch for
  a Calibre-merged compilation of several works.
- `isStale` becomes permanently `false` once a work's stored chapter count
  matches `chapterCurrent` from the feed — a "settled," complete work stops
  being auto-rechecked based on chapter count alone. **`AO3PrefaceRefetchPreference`**
  (`.yearly`/`.monthly`/`.weekly`/`.daily`/`.always`, default `.monthly`)
  is a second, independent trigger layered on top: refetch if the last
  successful preface fetch is older than the chosen interval, regardless of
  chapter-count settledness — this is what still picks up new comments/
  kudos/hit counts or a formatting fix on an otherwise-finished work.
- An anti-hammering floor (`secondsBetweenAttempts = 60`) prevents the same
  article from being refetched twice in rapid succession regardless of the
  cadence preference — its only job is to stop duplicate requests from a
  fast re-open, not to pace legitimate refetches (that's the cadence
  preference's job).

### Fetch paths and triggers

1. **Open-time**: `WebViewController.setArticle` calls `fetchIfNeeded(for:)`
   when an article is displayed.
2. **Background sweep**: on `.AccountRefreshDidFinish`, `sweepStaleUnreadArticles(in:)`
   walks unread articles for stale AO3 content, bounded by
   `maxArticlesPerSweep` (5) and paced by `secondsBetweenSweepRequests` (5s,
   `internal` rather than `private` so `AO3SeriesNavigator`'s own bounded
   walk — see below — reuses the exact same pacing constant rather than
   inventing a second "don't hammer AO3" number). `sweepingAccountIDs`
   guards against two overlapping sweeps for the same account being started
   by back-to-back refresh-finished notifications.

The primary fetch is always anonymous — `Downloader` already forces
`httpShouldSetCookies = false`/`.never` app-wide, so no per-request change
was needed to keep it that way.

### Authenticated retry

If the anonymous fetch returns `AO3ChapterExtractionOutcome.registrationRequired`
and a session is stored (`AO3SessionStore.isSignedIn`), `retryAuthenticated(url:)`
retries once through `AO3AuthenticatedFetcher` — a request with the stored
session's Cookie header attached by hand. This deliberately bypasses
`Downloader.shared` entirely: `Downloader`'s response cache is keyed on URL
alone, and the anonymous fetch that just produced `.registrationRequired`
for this exact URL would already be cached — routing the retry back through
`Downloader` would silently hand back that same stale, unauthenticated
response instead of ever sending the Cookie header. `AO3AuthenticatedFetcher`
uses its own ephemeral, cache-free `URLSession` (mirroring `Downloader`'s
own cookie-disabling configuration, so the *only* cookie ever sent is the
one attached by hand) and is not a stored singleton, since it's used at
most once per retry. If the authenticated retry *also* comes back
`.registrationRequired`, the stored session is treated as no longer valid
and `AO3SessionStore.clearSession()` is called.

### Content-regression guard

`AO3RegressionThreshold` (`Modules/Articles/Sources/Articles/AO3RegressionThreshold.swift`)
is a shared value used by two independent call sites that must not drift
apart: `AO3ChapterFetcher`'s content-level check (comparing a live fetch's
re-derived word/chapter counts against the stored content's own re-derived
counts) and `Article+Database`'s metadata-level watch (comparing a
feed-reported word count alone, no `contentHTML` involved). It lives in the
`Articles` module specifically because both `ArticlesDatabase` and `Account`
depend on `Articles` but neither depends on the other.

```swift
isRegression(from oldCount: Int, to newCount: Int) -> Bool
// true when: newCount < oldCount
//         AND percent drop >= 10%
//         AND absolute drop >= 300
```

Both conditions must hold — a percentage-only rule is noisy on short works
(a 200-word ficlet trimmed by 20 words is a meaningless 10% drop), and an
absolute-only rule would flag ordinary large-work copy-edits. 10%/300 are
documented as reasoned starting constants (ordinary AO3 copy-edits move
counts well under 1%; real regressions — a deleted chapter, an orphaned/
gutted work — are typically 30%+ drops), not data-derived, and deliberately
not exposed as a Settings slider.

Reconstructing a `ParsedItem` for a refetch is subtle: `Account.updateAsync`
is the *only* write path for `contentHTML` (there's no single-field "update
just this" API), and `Article+Database.changesFrom` diffs the whole incoming
`ParsedItem` against the existing `Article` field by field — so every
existing field has to be carried through unchanged into the rebuilt item,
or an "update content" fetch would blank title/summary/fandoms/etc. on that
article. The work's `ao3WorkID` for the refetch URL is recovered directly
from the existing article's own `bookKey` (stripping the `"ao3-work:"`
prefix) rather than needing `isAnthology`/`ao3SeriesID`/`seriesName` carried
through separately, since `bookKey` only resolves to `"ao3-work:<id>"` when
`isAnthology` wasn't already true.

## Session storage: login and Cloudflare challenges

Two independent Keychain-backed stores, both scoped to a single stored
value (no generic "store any credential" API — the project has no existing
credentials wrapper elsewhere, so each is a minimal, purpose-built type):

| | `AO3SessionStore` | `AO3ChallengeSessionStore` |
|---|---|---|
| Represents | An AO3 login session (account-scoped) | A Cloudflare clearance cookie (anonymous — proves "real browser," not identity) |
| Captured via | `AO3LoginViewController` (WKWebView login) | `AO3ChallengeSolverViewController` (WKWebView challenge solve) |
| Lifetime | Long-lived until explicit sign-out or a rejected retry | Deliberately short: `cookieHeaderValueIfFresh` refuses to hand back a cookie older than a 20-minute freshness window, chosen conservatively shorter than Cloudflare's typical (unpublished, per-site) `cf_clearance` lifetime — serving with an already-expired cookie just costs one more challenge, but treating an expired one as fresh would silently hide a real wall from `AO3SearchResultsFetcher`. |
| Keychain accessibility | `kSecAttrAccessibleAfterFirstUnlock` — deliberately not `WhenUnlocked`, since background-refresh fetches can happen while the device is locked | — |
| Cleared by | Explicit "Sign Out" action, or a rejected authenticated retry | (analogous — a request sent with this cookie that still comes back challenged) |

Both are consulted, not verified independently — validity is only
discoverable by actually making a request; each store's caller is
responsible for clearing it when AO3/Cloudflare rejects what was sent.

## Kudos-on-like

`AO3KudosOnLikePreference.isEnabled` (default **off** — this POSTs to a
third-party service on the user's behalf, so it needs explicit opt-in) gates
`AO3KudosManager`, which has two entry points funneling into one shared
attempt path:

- **Piggyback path** (`attemptKudosIfNeeded(article:workID:csrfToken:)`) —
  called from `AO3ChapterFetcher.download`'s success handler, reusing the
  CSRF token that fetch's own page load already scraped. No extra request:
  opening/refreshing an already-loved article's chapter is common (every
  stale-check refetch), so this piggybacks for free.
- **List-view path** (`attemptImmediateKudosIfNeeded(for:)`) — called from
  `SceneCoordinator` when an article is loved from a list action (swipe/
  context menu) with no accompanying page fetch to piggyback a token off
  of. This dispatches its own dedicated, token-only fetch, since waiting
  for the next natural chapter refetch could mean never (once
  `AO3ChapterFetcher.isStale` goes permanently false).

Both paths share one eligibility gate: feature enabled, book loved, a CSRF
token available, and no already-authenticated kudos attempt on record for
that book (`Account.kudosAttempt`/`setKudosAttempted` on `BookStateTable`).
A prior *guest* attempt is retried once signed in — a guest kudos and an
authenticated kudos are distinct identities on AO3's side — but an
authenticated attempt, successful or not, is never auto-retried. Both
entry points are entirely fire-and-forget; failures surface only via the
Activity Log (`ActivityOwner.ao3KudosManager`).

### `AO3KudosRequest` — wire format

Kept separate from the actual networking (`AO3KudosFetcher`), the same way
`AO3ChapterHTMLExtractor` (pure) is kept separate from `AO3ChapterFetcher`
(networking) — lets the request/response shape be unit tested against
fixture data with no network involved. Posts to AO3's `kudos.js` XHR
endpoint (the same one the work page's own kudos button uses, not the
plain non-JS `/kudos` redirect endpoint), with `x-csrf-token`,
`x-requested-with: XMLHttpRequest`, a matching `referer`, and a
form-urlencoded body (`authenticity_token`, `kudo[commentable_id]`,
`kudo[commentable_type]=Work`). The endpoint/field shape was
cross-checked against — not ported from — the MIT-licensed `ao3_api`
project's `utils.kudos()`, per the project's licensing convention for
reverse-engineered AO3 behavior.

`AO3KudosOutcome` interprets AO3's documented response contract:
`.success` (HTTP 201), `.alreadyKudosed` (HTTP 422 with a `user_id`/
`ip_address` error — AO3's own idempotent response to a duplicate, treated
the same as success for storage purposes but logged distinctly),
`.authError` (422, `auth_error` — expired/mismatched CSRF token, not
retried automatically; the next natural page fetch will scrape a fresh
one), `.invalidWork` (422, `no_commentable`), `.rateLimited` (429), or
`.otherFailure`.

## AO3 search subscriptions

A person can subscribe to an AO3 search-results query as a feed. This has
its own fetch/retry/pagination stack, layered on top of
`AO3SearchResultsExtractor` (`ao3-feeds.md`):

- **`AO3SearchResultsFetcher`** — fetches through the shared `Downloader`
  (inheriting its per-host 429/Retry-After cooldown for free, deliberately
  not reimplemented here), with its own bounded retry budget covering both
  5xx responses and timeouts under one counter. Adds two outcomes
  `AO3SearchResultsOutcome` (RSParser) has no way to represent, since that
  type only ever sees HTML AO3 itself sent:
  - `.rateLimited` — a genuine 429, not retried here since `Downloader`
    has already recorded its own cooldown by the time this returns.
  - `.cloudflareChallenge(challengedURL:)` — sniffed from the response
    body independently of status code (a Cloudflare block/challenge page
    can arrive as a 200, 403, or overlapping a 429).
- **`AO3SearchResultsImporter`** — factors out the shared "parse fetched
  HTML and import it" sequence (`AO3SearchResultsExtractor.extract` →
  `account.updateAsync` → `account.sendNotificationAbout` → advance
  `feed.ao3SearchLastFetchedPage`) so it's usable both by the ordinary
  headless fetch path and by a WKWebView HTML-harvest fallback (iOS target,
  outside this module) used when a headless fetch comes back
  Cloudflare-challenged. `deleteOlder` is always `false` for any single
  page import — a page is a partial view of the search, not the whole
  feed, so treating it as authoritative for pruning would delete every
  work that only appears on a different page.
- **`AO3SearchResultsPaginator`** — the explicit "Load more results" user
  action. A standalone `@MainActor` enum, deliberately **not** routed
  through `LocalAccountRefresher.refreshFeeds`'s shared batch-refresh
  session state (`isRefreshing`, `outstandingParseTasks`,
  pending-feed coalescing) — that machinery exists to coordinate many feeds
  finishing together for one overall progress UI, and piggybacking a
  single-feed, user-triggered "load more" tap on it risks silent
  interaction with an in-flight full refresh. `loadNextPage(for:account:)`
  fetches `(feed.ao3SearchLastFetchedPage ?? 1) + 1` and advances the
  counter on success; `refreshFirstPage(for:account:)` re-fetches page 1
  without advancing it (plumbing for a future "check for new results"
  affordance, not yet wired to a user action). Page URLs are built by
  replacing/appending a `page` query item on the feed's stored (page-1)
  URL — page 1 itself is passed through unmodified, since AO3's own
  listing pagination omits `page=1` on its links (confirmed against a
  captured pagination widget).

## Series navigation

`AO3SeriesNavigator.openSeriesWork(ao3SeriesID:direction:targetWorkURL:targetIndex:existingArticle:account:)`
handles First/Previous/Next taps on a per-series inline navigation link
(see `AO3PrefaceRenderer`/`AO3ChapterHTMLExtractor.seriesEntries` in
`ao3-feeds.md`). It's bounded to **at most two series-listing page fetches**
regardless of series length, via a fixed sequence:

1. **Cache check** (skipped for `.first`, whose target id isn't known yet) —
   if an already-fetched article for the target work id exists under the
   same feed, return it directly with no listing fetch at all.
2. **Fetch page 1**, always — series listings run in ascending Part order,
   so work #1 is never on a later page, and this is the only fetch `.first`
   ever needs. Every work found is batch-stubbed into the feed in one
   `account.updateAsync` call (not one per work). `.previous`/`.next`
   targets that land on page 1 resolve here too.
3. **Fetch the computed page** — only for `.previous`/`.next` whose target
   wasn't on page 1. The target page number is computed from
   `targetIndex`/page size, paced by
   `AO3ChapterFetcher.secondsBetweenSweepRequests` before the request. The
   target's presence is *verified against the actually-parsed listing*,
   never trusted from the index math alone — a mismatch returns
   `.seriesListingMismatch` rather than trying a third page. This
   verification is what makes "two pages maximum" a structural guarantee,
   not just a soft cap.
4. **Fetch the target's real content** via the same `AO3ChapterFetcher.shared.download`
   + notification-wait shape used elsewhere.

**Accepted gap**: works strictly between the two fetched pages are never
pre-stubbed by this flow. They still work correctly if opened directly
later (bookKey/BookStateTable sharing doesn't depend on pre-stubbing) —
they just don't appear as timeline rows until then. This is a deliberate
cost of the two-page cap, not an incomplete-import bug.

**Dedup**: every series-listing page necessarily includes whatever work the
person is currently reading. A naive stub-every-row pass would create a
duplicate row for it whenever its existing `uniqueID` doesn't equal its
bare AO3 work id (the normal case for an Ambrosia-synced article).
`Article.bookKey` — resolved through `AO3ChapterFetcher.ao3WorkID(fromBookKey:)`
— is used as a scheme-independent identity key to both skip re-stubbing an
already-present work and resolve which existing `articleID` a target should
be refetched under.

### Tracing a nav tap: log lines by category

Every leg of a First/Previous/Next tap now logs at `.debug` via `os.Logger`,
following the app's established `Self.logger.debug("Prefix: message
key=\(value, privacy: .public)")` convention (see `ArticlesDatabase.swift`,
`Account.swift`). Filter Console.app on these categories, in the order a tap
actually flows through them, to see the whole path from tap to opened work:

1. **`WebViewController`** -- `handleNectarSeriesLink: tapped ...` (the tap
   itself, with direction/ao3ID/workURL), then either `... ignored, already
   in flight ...` (double-tap guard) or `... starting openSeriesWork ...`,
   and finally `... openSeriesWork succeeded ...` or the pre-existing `...
   navigation failed ...` line.
2. **`AO3SeriesNavigator`** -- the interesting decisions all happen here:
   `openSeriesWork` entry (full parameters), the Step 1 same-feed cache-check
   result (content already fetched / stub needing a fetch / no hit), the
   Step 1b cross-feed cache-check result (a fetched copy of the same work
   found under a different feed and copied in, or no hit), Step 2's page 1
   fetch/parse/stub counts, target resolution (found on page 1, or falling
   through to Step 3), Step 3's computed page number and its
   fetch/parse/stub counts, and the final match/mismatch outcome. Then
   `downloadAndAwait`'s own start/success/failure lines, which are the only
   place this trace observes `AO3ChapterFetcher`'s `.ao3ChapterFetchDidComplete`/
   `.ao3ChapterFetchDidFail` notification pair.
3. **`SceneCoordinator`** -- `SceneCoordinator: navigateToTimelineAndSelectArticle
   articleID=...`, the last leg of a successful tap, once the reader hands
   off back to the timeline.

A stall with no further log lines after `AO3SeriesNavigator: openSeriesWork
fetching computed page N ...` means the second listing fetch (or the
`AO3ChapterFetcher.secondsBetweenSweepRequests` pacing sleep before it) is
still in flight -- that sleep is real wall-clock time, not a bug, before
the second `fetchListingPage` call goes out.

## Summary of preferences

| Preference | Type/default | Purpose |
|---|---|---|
| `AO3PrefaceRefetchPreference.current` | `.yearly/.monthly/.weekly/.daily/.always`, default `.monthly` | Time-based refetch trigger independent of chapter-count staleness. |
| `AO3KudosOnLikePreference.isEnabled` | `Bool`, default `false` | Master gate for kudos-on-like. |

Both, plus `AmbrosiaTransferFormatPreference` and
`AmbrosiaAO3NetworkPreference` (see `ambrosia-feed.md`), live in the
`Account` module rather than the iOS app's `AppDefaults`, and are backed by
the same `NectarAppGroupUserDefaults.store` app-group suite — the
consistent pattern across every AO3/Ambrosia setting is: the code that
actually needs to read the preference (a fetcher/manager in `Account`)
shouldn't have to depend on the iOS app target, and a later Settings UI
should read/write the exact same key rather than risk a second UserDefaults
suite drifting out of sync with it.
