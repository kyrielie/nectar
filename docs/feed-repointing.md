# Feed LAN-IP repointing

How a feed's fetch address can change (LAN IP reassignment) without losing
its identity or history. See `book-identity.md` for why this deliberately
avoids merging by `bookKey`.

`Feed.url` (`Modules/Account`) is `nonisolated(unsafe) public
private(set) var`, not a `let` — a feed's fetch address can change without
changing its `feedID`, via `Feed.repoint(to:)`. This exists because the
Ambrosia server is addressed by LAN IP, which can change (DHCP lease
renewal, network switch) independent of anything about the feed's
identity; repointing in place means existing articles, statuses, and
`BookStateTable` rows stay associated with the feed with no merge step,
where creating a new feed at the new URL would orphan all of that history.

`LocalAccountDelegate` drives repointing from two entry points, both
routed through one shared `collectionKeyIndex` helper (no duplicated
matching logic between the two paths):

- **OPML import** (`reconcileRepairedFeeds`/`repointAndRefresh`): after
  importing OPML, newly-created feeds are matched against existing ones by
  `AmbrosiaFeedIdentity.collectionKey(for:)` — a collection identity, not
  the URL — and a match under a different URL repoints the *existing*
  feed rather than keeping the OPML-created duplicate. This supersedes an
  earlier merge-by-`bookKey` approach (noted in-code).
- **Manual single-feed add** (`repointIfAmbrosiaRepair`, called from
  `createFeed`): the same collection-key matching, checked before falling
  through to ordinary feed creation.

A third, related piece: **`rewriteAmbrosiaJSONFeedURLs`** rewrites an
Ambrosia-exported OPML's `xmlUrl` from the RSS 2.0 route it ships (no
`_ambrosia` metadata) to the sibling `.json` route before subscribing, so
an OPML round-trip doesn't silently lose book-card data.

Repointing deliberately avoids the `bookKey`-merge path in favor of
`feedID` stability — consistent with `articleID` being `feedID`-derived
(see `book-identity.md`): a repoint keeps the same `feedID`, so no
article identity changes at all, whereas a `bookKey` merge would try to
reconcile two different `feedID` lineages after the fact.
