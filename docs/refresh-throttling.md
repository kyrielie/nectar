# AO3/host refresh throttling

Covers three related refresh-cycle concerns: per-feed skip logic, the
background-refresh time budget, and the Last Opened smart feed (which
`SceneCoordinator` updates on every article open, tying it to this same
refresh/state-update cycle). See `ao3-direct-feed-ingestion.md` for the
route that has an open gap in this throttling, and `refresh-throttling.md`'s
own note below on the missing remediation-plan doc.

`LocalAccountRefresher.feedShouldBeSkipped(_:_:)` runs once per feed per
refresh pass and decides whether that feed is skipped this time, checking
three independent reasons in order:

1. **Disallowed host** (`feedShouldBeSkippedForDisallowedHostReasons`) —
   permanently skips the `nectar-import://` pasted-AO3-link-list import
   feed (`Account.importedLinksFeedURL`; it has no real server behind it,
   articles are written directly via `updateAsync`, so refreshing it can
   never succeed) and a small `badHosts` list (`twitter.com`/`x.com`
   variants — feeds pointed at the old Twitter API, which no longer
   provides feeds). Both are inherited NetNewsWire behavior, not
   Nectar-specific.
2. **AO3 search-results feeds** (`feedShouldBeSkippedForAO3SearchResultsReasons`,
   `isAO3SearchResultsFeed`) — a normal scheduled/background/pull-to-refresh
   pass never re-fetches page 1 of an AO3 search/tag-listing feed once it's
   been added; only the one-off add-time fetch and explicit
   pagination/"load more" touch it after that. Matched on host (AO3's
   domain allowlist) + path shape (`/tags/.../works`, or `/works` with a
   `work_search[...]` query key) — deliberately not by file extension.
3. **Reddit** (`feedShouldBeSkippedForRedditReasons`) — Reddit allows one
   feed fetch per minute, so at most one Reddit feed refreshes per pass
   (the least-recently-checked one); this is also inherited NetNewsWire
   behavior, unrelated to Ambrosia/AO3.

This replaces upstream's general-purpose
`feedShouldBeSkippedForCacheControlReasons`/
`feedShouldBeSkippedForTimingReasons` (a courtesy minimum-refresh-interval
that protects small blog/podcast servers from being hammered), removed
with the comment "Nectar only ever refreshes feeds from the user's own
local Ambrosia server... never a public site the app needs to be polite
to."

**Open gap, not yet resolved:** that removal comment is incomplete. AO3
tag/user RSS/Atom feeds (see `ao3-direct-feed-ingestion.md`) *are* a
public, non-Ambrosia site, and `isAO3SearchResultsFeed`'s matching only
covers AO3's HTML search/tag-listing *pages* — not AO3's native
`.atom`/RSS feed URLs, which is the actual direct-subscription route. A
regular AO3 tag/user Atom feed subscription has no proactive
skip/minimum-interval protection today; it refreshes on every
scheduled/background/pull-to-refresh pass like an Ambrosia feed, backed
only by `Downloader`'s *reactive* per-host 429/Cloudflare-challenge
handling (see `ao3-preface-rendering.md`) as a backstop. This may be
fine in practice given AO3's own aggressive rate limiting, but it's an
open design question, not a settled one. In-code and this doc's prior
version both point to `nectar-audit-remediation-plan.md` for tracking,
but that file is not present anywhere in the current tree -- another
dangling reference (see also the Wire Contract note in
`sqlite-transfer.md`). Treat this as an open, untracked gap until that
file is found or the gap is re-triaged.

## AO3 prefetch queue budget

Separate from, and not a fix for, the open gap above: `AO3PrefetchQueue`
(backing `AO3PrefetchNewWorksPreference`, off by default — see
`ao3-integration.md`'s "Fetch triggers, philosophy") is its own
deliberately bounded and paced request source, not a general per-feed
throttle. Every newly-discovered AO3-work article from an ordinary
tag/user feed refresh, across every feed in that refresh pass, funnels
through this one shared actor:

- **Paced** at `AO3ChapterFetcher.secondsBetweenAO3PagedRequests` (5s)
  between each `fetchIfNeeded` call it fires — the same constant
  `AO3SeriesNavigator`'s own page-1-to-computed-page pacing uses, rather
  than a second "don't hammer AO3" number.
- **Capped** at `AO3PrefetchQueue.maxArticlesPerRefreshCycle` (20)
  fetches per top-level refresh pass, reset via
  `resetForNewRefreshCycle()` alongside `LocalAccountRefresher`'s own
  `newArticlesCount` reset. Articles beyond the cap in one pass are
  dropped from the queue, not carried into the next refresh's budget —
  a first-time subscription to a very active feed falls back to
  ordinary open-time fetching for whatever didn't fit, rather than this
  preference turning into a slow full-backlog crawl across many
  refreshes.

This budget exists because prefetching is inherently a burstier request
pattern than the rest of this app's AO3 traffic (one request per article
someone actually opens) — it's sized to cover ordinary day-to-day feed
activity, not to bound a large backlog import, and hasn't been tuned
against real subscription sizes.

## Background refresh budget and interrupted-feed retry

iOS background refresh runs on `BGTaskScheduler`
(`com.kyrielie.Nectar.FeedRefresh`, registered and scheduled from
`iOS/AppDelegate.swift`), which replaced upstream's in-process
`Timer`-based `AccountRefreshTimer` entirely (not a reimplementation under
a new name — a wholesale move to the standard iOS background-task API).

`AppDelegate` computes the OS-granted remaining execution time, subtracts
a safety margin, and stores the result as
`AccountManager.shared.backgroundRefreshDeadline`.
`LocalAccountRefresher` checks `Date() >= deadline` mid-pagination and, if
the deadline has passed, stops early rather than risking termination
mid-write; feeds it didn't get to are tracked as interrupted. On
completion, `LocalAccountDelegate` posts
`.refreshDidCompleteWithInterruptedFeeds` with the interrupted feed URLs,
which `AppDelegate` observes to decide whether to request another
background pass. `backgroundRefreshDeadline` is cleared (`nil`) once a
refresh pass completes normally or the app returns to the foreground, so
it never leaks a stale deadline into a later foreground-triggered refresh.

## Last Opened smart feed

`LastOpenedFeedDelegate` (`Shared/SmartFeeds/`, Nectar-original, no
upstream counterpart) is a fifth smart feed alongside
Today/Unread/Starred/Loved/Read: the 10 most recently opened articles,
mirroring `ReadFeedDelegate`/`LovedFeedDelegate`'s shape but with a fixed
`FetchType.lastOpened(10)` limit rather than an unbounded fetch — the cap
is enforced via `SQL LIMIT` in `ArticlesTable.fetchLastOpenedArticles`,
not client-side truncation. `SceneCoordinator` calls
`Account.recordBookOpened(articleID:)` (→ `BookStateTable.lastOpenedAt`)
whenever an article is opened, except when the *current* timeline feed is
itself the Last Opened feed (`SidebarItem.forcesLastOpenedSort`, `true`
only for this delegate) — opening an article from inside "Last Opened"
doesn't re-order the list out from under the user mid-browse. Unlike
Read/Loved/Read Later, there's no natural running total to show as a
badge count (the feed is always capped at 10, which says nothing about
library size), so `fetchUnreadCount` is hardcoded to `0` rather than
repurposing the badge for something misleading.
