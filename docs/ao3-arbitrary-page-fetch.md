# AO3 search-results: fetching an arbitrary page

Companion to `ao3-integration.md`'s "AO3 search subscriptions" section
(the fetch/retry/pagination stack this builds on) and `settings-screen.md`
(the feed inspector, where the UI described below lives). Confirmed
against the code as of this doc's own commit — see "Keeping this
current" in `CLAUDE.md` for what that means.

## What this is

Beyond "Load more results" (always the next sequential page), a person
can type any page number into the feed inspector for an AO3
search-results feed and fetch that page directly. Fetching is always
additive — refetching an already-fetched page adds any new works, never
removes any (same rule "Load more" already followed).

## Data model

`FeedSettings.ao3SearchFetchedPages: Set<Int>?` — every page
successfully fetched so far for this feed, stored as JSON text on the
`feedSettings` row (`FeedSettingsDatabase.swift`, `Column.ao3SearchFetchedPages`).
Replaces the old single-integer `ao3SearchLastFetchedPage`, which is left
in the schema, unused, for existing rows to backfill from
(`FeedSettingsDatabase.backfillFetchedPagesFromLegacyColumn(_:)`, run once
inside the same migration block that adds the column). The backfill is
exact, not a guess: every page fetched before this feature existed was
fetched sequentially with no gaps, so `Set(1...oldValue)` is the correct
reconstruction.

`FeedSettings.ao3SearchTotalPages: Int?` — the total page count AO3's own
pagination widget reports (`AO3ListingPagination.totalPages(_:)`),
refreshed from whichever page most recently returned one. No legacy value
to backfill from; starts `nil` for pre-existing rows until the feed is
next fetched. For a feed added after this shipped, it's populated from
the moment the feed is created, since page 1 is always fetched at add
time either way (see "Where `totalPages` is written" below).

Both properties live on `Feed` too (`Feed.ao3SearchFetchedPages`,
`Feed.ao3SearchTotalPages`), thin wrappers over the `FeedSettings`
storage, same pattern every other `FeedSettings`-backed `Feed` property
uses — writes go through `postSettingDidChange`/`.feedSettingDidChange`
so UI can observe them reactively rather than needing the value handed
back synchronously from a specific call.

## The infill rule

`AO3SearchResultsPaginator.nextPageToFetch(fetchedPages:)` — the smallest
positive integer not already in the set. For a feed with no gaps this is
identical to the old "highest + 1"; the difference only matters once an
arbitrary-page fetch has jumped ahead and left a gap behind (fetched =
`{1, 2, 3, 7}` → next is `4`, not `8`). Both `loadNextPage` (the "Load
more" action) and the Cloudflare-retry bookkeeping in
`MainTimelineModernViewController`'s load-more flow call this one shared
function — it must not be duplicated, since a caller that independently
recomputes "highest + 1" would silently mis-attribute a retried fetch to
the wrong page once gaps exist.

## Authenticated-first fetching for signed-in users

`AO3SearchResultsFetcher.fetchRequiringSignIn(url:feedURL:)` — the fetch
path this doc's `fetchSpecificPage`/`fetchPage` route through whenever a
session is stored, not just for the always-private listing types — is
now authenticated-first: it tries the stored session before any
anonymous request, falling back to the plain anonymous `fetch(url:feedURL:)`
only on an authentication-shaped failure. See `ao3-integration.md` and
`ao3-authenticated-reading.md` for the full shape. Practically, this
means an arbitrary-page fetch (this doc) for a signed-in person now goes
through the authenticated path by default for every AO3 listing page, not
just subscriptions/marked-for-later — the three call sites that gate on
`LocalAccountRefresher.isAlwaysAuthenticatedAO3ListingFeed(_:)` widen that
check to `isAlwaysAuthenticatedAO3ListingFeed(_:) || AO3SessionStore.isSignedIn`.

## Validation against a known total

`AO3SearchResultsPaginator.validate(page:against:)` checks a typed page
number against `feed.ao3SearchTotalPages` without a network request:
- Total known, page in range → `.valid`.
- Total known, page out of range → `.outOfRange(totalPages:)`.
- Total unknown → `.valid` (the caller should fetch page 1 first to learn
  the total, then re-check — `fetchSpecificPage` below does this step
  automatically, so this case is rare in practice once feeds are past
  add-time).

`AO3SearchResultsPaginator.fetchSpecificPage(_:for:account:)` is the
entry point for an arbitrary-page fetch:
1. If `ao3SearchTotalPages` isn't known yet, fetch page 1 first (this
   both populates the total and is itself a legitimate, additive
   refetch), then re-validate the requested page against the now-known
   total.
2. If the page is out of range, return `.noResults` without a network
   request for the requested page.
3. Otherwise fetch it, sharing the same `fetchPage` implementation
   `loadNextPage`/`refreshFirstPage` use. `refreshFirstPage` is a thin
   wrapper: `fetchSpecificPage(1, ...)`.

## Where `totalPages` is written

Sourced once, at the bottom of the call graph
(`AO3SearchResultsExtractor.extract`, RSParser — reads AO3's own
pagination widget), and threaded up through exactly the layers that need
it to reach `feed.ao3SearchTotalPages`:

- `AO3SearchResultsOutcome.success`/`.noResults` (RSParser) both carry
  `totalPages: Int?`. `.noResults` carries it too, not just `.success`:
  a zero-result response for an otherwise-nonempty search can still
  render a pagination widget with the true (possibly since-shrunk)
  total, letting a caller self-correct a stale cached value instead of
  leaving it wrong indefinitely.
- `AO3SearchResultsFetchOutcome.success`/`.noResults` (`AO3SearchResultsFetcher`)
  mirror the same field, purely to carry it across the fetch wrapper —
  `AO3SearchResultsPaginator.fetchPage` and the two add-time call sites
  below only ever see this type, never the raw `AO3SearchResultsOutcome`.
- Nothing above this layer needs it threaded further — `PageOutcome`,
  `AO3SearchResultsImporter.ImportOutcome`, and
  `AO3SearchResultsFetchCoordinator.Outcome` don't carry `totalPages`;
  the write happens inside whichever function already has both `feed`
  and the raw fetch outcome, before that function constructs its own
  return value. UI reads `feed.ao3SearchTotalPages` reactively via
  `.feedSettingDidChange` instead.

Four call sites write `feed.ao3SearchFetchedPages`/`.ao3SearchTotalPages`
on a successful fetch — all four must move together, since they share
one bookkeeping contract:

| Site | When it runs |
| --- | --- |
| `LocalAccountDelegate.createFeed`'s AO3 branch | Manual Add Feed, page-1 add-time fetch |
| `LocalAccountRefresher.fetchAndImportAO3SearchResults` | OPML-import add-time fetch |
| `AO3SearchResultsPaginator.fetchPage` | Shared by `loadNextPage`, `refreshFirstPage`, `fetchSpecificPage` |
| `AO3SearchResultsImporter.importFetchedPage` | Cloudflare-WKWebView-harvest bookkeeping, shared by the create-time and load-more/arbitrary-fetch challenge retries |

## Feed naming: set once, at creation, only

Automatic naming off a fetched page's `<title>` happens once, at add
time; nothing overwrites it automatically after that (a person's own
rename always wins). `AO3SearchResultsFetchCoordinator.presentSolverAndRetry`
takes an explicit `updatesFeedName: Bool` parameter for this reason —
`AddFeedViewController` (create-time Cloudflare challenge) passes `true`;
every other caller (load-more's Cloudflare retry, the inspector's
arbitrary-fetch Cloudflare retry) passes `false`. This is a separate,
explicit parameter rather than inferred from `advancePageTo == 1`,
since the inspector's arbitrary-fetch action can deliberately refetch
page 1 itself (a real, expected case under the "additive" rule) without
that meaning "this is the initial add-time fetch."

## Delete-and-re-add

Fetched-page history clears at re-add time (both the manual delete/re-add
path and an OPML re-import of the same URL land on the same
`FeedSettings` row and reset it via the add-time write sites in the
table above), but a system Undo of a delete restores the same
`Feed`/`FeedSettings` object with no fetch and no reset — a perfect,
instant revert. Clearing inside `removeFeed` itself was deliberately not
done, since that would make Undo restore a feed that's lost its
page-fetch history.

## UI: feed inspector

`FeedInspectorViewController` (`iOS/Inspector/`) is a storyboard-driven
(`Inspector.storyboard`) static-cell `UITableViewController`. Rather than
extend the storyboard itself, the "AO3 Pages" section is appended in
code as one additional section after every storyboard section — present
only when `feed.isAO3SearchResultsFeed`, always the table's last
section, handled by a parallel set of guards in each
`UITableViewDataSource`/`UITableViewDelegate` override rather than
folded into the existing storyboard-index `shift(_:)` machinery. The
section holds one self-contained cell, `AO3PagesInspectorCell`
(private, same file):

```
Fetched: 1, 2, 3, 7  (12 pages total)

Fetch a page:  [   4   ]  [ Fetch ]

Fetched pages are additive -- refetching a
page adds any new works, never removes any.
```

- "(N pages total)" only appears once `feed.ao3SearchTotalPages` is
  known — true from add time onward for any feed added after this
  shipped.
- Numeric-keyboard text field; the Fetch button is disabled until the
  typed text parses as a positive integer.
- A fetch in flight shows a spinner in place of the Fetch button.
- Validation (`AO3SearchResultsPaginator.validate(page:against:)`) runs
  before any network request; an out-of-range page shows an inline
  error without fetching.
- A Cloudflare challenge shows the same opt-in verification alert
  pattern the "Load more" footer already uses
  (`MainTimelineModernViewController.presentAO3LoadMoreVerificationPrompt`) —
  never presents the WKWebView solver automatically.
- Error copy for the shared failure cases (rate-limited,
  registration-required, not-signed-in, Cloudflare-blocked) reuses the
  same strings `AO3LoadMoreFooterView` already produces, rather than
  writing new copy for the same underlying failures.
- The cell refreshes reactively via `.feedSettingDidChange` (observed
  only when `feed.isAO3SearchResultsFeed`, scoped to `object: feed`) —
  a successful fetch anywhere (this cell, "Load more", a background
  refresh) updates the "Fetched:"/"(N pages total)" line without the
  inspector needing to re-fetch anything itself.
- Tappable "already fetched" page numbers for one-tap refetch are
  deferred — type-a-number-and-tap-Fetch only, for this first pass.

## Symbols touched, for search

`FeedSettings.ao3SearchFetchedPages`, `FeedSettings.ao3SearchTotalPages`,
`Feed.ao3SearchFetchedPages`, `Feed.ao3SearchTotalPages`,
`AO3SearchResultsPaginator.nextPageToFetch(fetchedPages:)`,
`AO3SearchResultsPaginator.validate(page:against:)`,
`AO3SearchResultsPaginator.fetchSpecificPage(_:for:account:)`,
`AO3SearchResultsImporter.importFetchedPage`,
`AO3SearchResultsFetchCoordinator.presentSolverAndRetry`'s
`updatesFeedName` parameter, `FeedInspectorViewController`'s AO3 Pages
section, `AO3PagesInspectorCell`.
