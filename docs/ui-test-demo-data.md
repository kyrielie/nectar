# Offline UI-test demo data (`fastlane snapshot`)

`fastlane snapshot` needs a populated, deterministic app state to photograph: a sidebar with feeds,
timelines with a real mix of read/unread/starred/loved articles, and at least one article with real
chapter text to show reading themes, a highlight, and scroll position against. This is seeded entirely
offline, on-device, at launch — no real network request is made anywhere in the path.

## Activation

`-UITestSeedDemoData` as a launch argument. Checked via `Platform.isUITestingWithSeedDemoData`
(`Modules/RSCore/Sources/RSCore/Platform.swift`), called from `UITestDemoData.seedIfNeeded()`
(`iOS/UITestDemoData/UITestDemoData.swift`), invoked from `AppDelegate.didFinishLaunchingWithOptions`.

This is a separate flag from `Platform.isRunningUnitTests` on purpose: `isRunningUnitTests` also gates
unrelated behavior (`ErrorLogDatabase`, `AuthorCache`, the `ScreenTimeTracker`/`ReadingStatsTracker`
`.start()` calls in `AppDelegate`) that shouldn't change just because a screenshot is being taken.

One exception: `LocalAccountDelegate.refreshAll()` (called by `Account.importOPML(_:completion:)`
immediately after the seeded feeds are added to the tree) is gated
`!Platform.isRunningUnitTests || Platform.isUITestingWithSeedDemoData` rather than plain
`!Platform.isRunningUnitTests`. This was a real bug, not a design choice: `isRunningUnitTests` reads
`true` for the app-under-test process during a UI test too (XCTest gets loaded into it for in-process
automation), so without the `isUITestingWithSeedDemoData` carve-out here, `refreshAll()` silently
no-ops during every `-UITestSeedDemoData` launch -- the four seeded feeds land in the sidebar (their
names come from `editedName`, set synchronously during `importOPML`, not from this refresh) but never
actually fetch articles, so the Timeline/Article screenshots' cell-count/element waits time out
identically on every device and every one of the `screenshots` lane's launch-argument variants.

`-UITestReadingProfile personal` is a second, independent flag: it sets
`AppDefaults.shared.articleThemeOverrides` directly in Swift (serif font "Iowan Old Style", line height
1.2) rather than through a launch argument, because `articleThemeOverrides` is one JSON-encoded
UserDefaults string, and `SnapshotHelper.swift`'s launch-argument parser (whitespace-split with a
`"..."`-quoted-token exception) can't carry a value containing embedded double quotes.

## How seeding stays offline

`TestingURLProtocol` (`Modules/RSWeb/Sources/RSWeb/WebServices/TestingURLProtocol.swift`) already existed
for the unit test suites — a canned-response `URLProtocol`. It was wired into `Downloader.shared` and
`URLSession.webservice` behind `Platform.isRunningUnitTests`, but not into `DownloadSession` (the class
`LocalAccountRefresher` actually uses for feed refreshes). All three now also check
`Platform.isUITestingWithSeedDemoData`. Since `TestingURLProtocol.canInit(with:)` always returns `true`,
every HTTP request issued through any of these three while the flag is set is intercepted — a
request with no registered canned response gets a harmless empty `200`, not a real network attempt.

`UITestDemoData.seedIfNeeded()` registers canned responses for four fake feed URLs (all on the
`.invalid` TLD — RFC 2606, guaranteed non-resolving even if interception were ever bypassed), then calls
`AccountManager.shared.defaultAccount.importOPML(_:completion:)` against a bundled `DemoFeeds.opml`. It
also explicitly sets `AmbrosiaTransferFormatPreference.current = .json` before importing — that
preference already defaults to `.json`, but pinning it here means a future change to that default can't
silently route the Ambrosia feed below through `AmbrosiaSQLiteTransferFetcher`, which has its own
dedicated `URLSession` and isn't wired to `TestingURLProtocol`.

## Content, and why it's two different feed shapes

All seeded content is original, invented Star Trek fan-fiction-style placeholder text — never reproduced
from any real AO3 work. Ratings never exceed `Teen And Up Audiences`; warnings are limited to `No
Archive Warnings Apply`/`Creator Chose Not To Use Archive Warnings`. See `iOS/UITestDemoData/*.atom` and
`focus-work.json` for the actual fixtures.

Three feeds (`tos-academy-days.atom`, `tng-diplomatic-corps.atom`, `ds9-promenade-life.atom`) use the
AO3-style RSS/Atom shape `AO3SummaryExtractor` parses (see `ao3-direct-feed-ingestion.md`,
`ao3-feeds.md`) — 7 entries each, giving a populated, badge-varied timeline. These items carry no
chapter body text (real AO3 feeds don't either), which is fine for a timeline screenshot but means they
can't be opened for the Article screenshot: opening any article calls `AO3ChapterFetcher.fetchIfNeeded`
(`ao3-preface-rendering.md`), which does a **live** fetch when `article.bookKey` has an `ao3-work:`
prefix — exactly the non-determinism this whole mechanism exists to avoid.

A fourth feed (`focus-work.json`) uses the Ambrosia JSON Feed route instead (`ambrosia-feed.md`) for
exactly one item, `"A Quiet Kind of Orbit"`. Ambrosia items carry `content_html` directly and
`ArticleRenderer` never synthesizes a preface over that content, so this item's `content_html` is
hand-authored: a short AO3-style preface block plus real prose. Its JSON deliberately omits
`_ambrosia.ao3_work_id`, so per `book-identity.md`'s `bookKey` precedence, `bookKey` falls back to the
bare `uniqueID` (not `ao3-work:`-prefixed) — `AO3ChapterFetcher.ao3WorkID(fromBookKey:)` returns nil and
`fetchIfNeeded` no-ops. This is the only seeded article the UI test opens.

A person manually opening one of the three AO3-Atom items outside the automated screenshot flow will
still trigger a real (and, offline, failing) `AO3ChapterFetcher` fetch — expected and out of scope here.

## Article status and the seeded highlight

After import completes, `UITestDemoData` fetches the seeded articles back
(`Account.fetchArticlesAsync(.feed(feed))`) and marks a fixed set of titles `starred` ("Read Later"),
`loved`, and `read` via `Account.markArticles(articleIDs:statusKey:flag:)`, so the timeline shows a real
mix rather than an all-unread inbox. See the `starredTitles`/`lovedTitles`/`readTitles` sets in
`UITestDemoData.swift`.

One `Annotation` (`annotations.md`) is saved on the focus article, highlighting one full sentence of its
prose. `startOffset`/`endOffset` are a best-effort computation against the paragraphs as authored
(joined with single spaces), not the real DOM canonicalization — per `annotations.md`, `quoteExact` is
stored alongside the offsets specifically so a quote search recovers the correct anchor even if position
drifts, so this isn't as fragile as hardcoded offsets might otherwise be, but it hasn't been visually
confirmed against a real render.

## UI test flow

`Tests/NetNewsWire-iOSUITests/NectarUITests.swift`: wait for the sidebar (Main screenshot) → open the
TOS demo feed for a populated Timeline screenshot → back to the sidebar → open the single-item "My
Library" feed → open the focus article, `swipeUp()` twice past the preface, Article screenshot. No
accessibility identifiers exist anywhere in `iOS/MainFeed`/`iOS/MainTimeline`/`iOS/Article`, so
navigation matches on the seeded titles' static text, and the back button is matched as the leading
navigation-bar button (`app.navigationBars.buttons.element(boundBy: 0)`) rather than by identifier —
both are known fragility points if the UI changes.

## Fastlane

`fastlane/Fastfile`'s `screenshots` lane passes `-UITestSeedDemoData` (plus `-UITestReadingProfile
personal` for two of them) on every one of 6 style combinations (light/dark × accent/surface/reading-
theme variations), then runs `frame_screenshots` to add a framed copy of each screenshot alongside the
raw one. Each launch configuration is passed as separate launch-argument tokens; combining a whole
configuration into one string prevents the app from seeing `-UITestSeedDemoData` and the other flags.
`frame_screenshots` requires `imagemagick` on the machine running fastlane.

For local or CI validation of the same UI test without generating Fastlane artifacts, run:

```sh
./test.sh screenshots
```

Plain `./test.sh` continues to run the `Nectar-CI` unit/package test plan and does not launch UI tests.
