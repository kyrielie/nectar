# AO3Link: URL policy for AO3

`Modules/AO3Kit/Sources/AO3Kit/AO3Link.swift` is the single home for every
decision about what an AO3 URL is. It is a caseless `public enum` of static
functions and `Sendable` constants: no state, no networking, no async.
Tests: `Modules/AO3Kit/Tests/AO3KitTests/AO3LinkTests.swift`.

## Two host lists

Recognizing a link as AO3 and trusting a host with a cookie are different
jobs, so there are two lists.

- `recognizedHosts` (16 entries): AO3's own `permitted_hosts` list, the one
  its work-skin proxy-detection script carries (the work and series
  fixtures under `AO3KitTests/Resources` embed it). Exact match,
  case-insensitive. Includes three raw IPs that are AO3's own server
  addresses (not Ambrosia's; Ambrosia feed identity is host-independent, see
  `ambrosia-feed.md`). Used to RECOGNIZE: `isAO3Host`, `workID`,
  `isListingFeed`, `isAlwaysAuthenticatedListing`.
- `credentialHosts` (10 entries): the subset that may be sent a stored
  cookie. Leaves out the raw IPs, `insecure.` and `download.` hosts.
  `mayReceiveSession(_:)` additionally requires `https`.
  `sessionURL(for:)` upgrades an `http` URL on a credential host to `https`
  (a feed can be stored as `http://archiveofourown.org/...`; the app allows
  arbitrary loads) and returns nil for everything else.
  `isAO3CookieDomain(_:)` ignores one leading dot and exact-matches
  `credentialHosts`.

## Ids and builders

- `workID(from:)` / `workID(fromPermalink:)`: requires an AO3 host and a
  path starting `/works/<id>` or `/collections/<name>/works/<id>`. Query and
  fragment never take part. The id is the leading run of ASCII digits
  (`123abc` is `123`; non-ASCII digits are not digits). A host-less string
  such as `/works/123` is nil.
- `seriesID(fromHref:)`: path starts `/series/<digits>`. No host check (it is
  fed raw markup hrefs).
- `workURL(id:fullWork:adultView:)`, `seriesURL(id:page:)`: built with
  `URLComponents`; nil unless the id is one or more ASCII digits. Query
  order for both flags is `view_full_work=true&view_adult=true`.
- `kudosURL`, `workReferer(id:)`, `absoluteURL(_:)`.
  `absoluteURL("//host/x")` deliberately stays on AO3 with a double slash.

## Listing classifiers

`isListingFeed(_:)` (which URL shapes are subscribable/pageable AO3 listings)
and `isAlwaysAuthenticatedListing(_:)` (subscriptions and marked-for-later).
The second checks the host itself. Shape rules are documented on the
functions.

## Adoption status

Moved so far: URL builders (`AO3ChapterFetcher.download`,
`AO3KudosManager`, `AO3SeriesNavigator.fetchListingPage` and its placeholder
stub, `AO3KudosRequest`, `Article.ao3SeriesURL`) and the extractors'
`absoluteURL`/`seriesID` (the per-extractor wrappers and the
`AO3HTMLHelpers` copies are gone). Still on their own logic: work-id parsing,
host checks, listing classifiers, credential gating. This section is removed
once every caller has moved.

`AO3SeriesNavigator.downloadAndAwait` refuses a malformed work id up front:
`AO3ChapterFetcher.download` returns without posting a completion or failure
notification when it cannot build a URL, which would leave the awaiting
continuation suspended forever.
