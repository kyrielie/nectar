# Offline UI-test demo data (`fastlane snapshot`)

`fastlane snapshot` needs a populated, deterministic app state to photograph: a sidebar with feeds,
timelines with a real mix of read/unread/starred/loved articles, and at least one article with real
chapter text to show reading themes, a highlight, and scroll position against. This is seeded entirely
offline, on-device, at launch — no real network request is made anywhere in the path.

Nectar does not import any default feeds on a normal first run, and the app never seeds anything on its
own. Nothing in this doc runs unless the app is launched with `-UITestSeedDemoData`, and the hosted feed
described under "The hosted feed (manual, not seeded)" below is never subscribed automatically either —
it exists to be added by hand, the same way any other feed is.

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

`NectarUITests.setUp()` also appends `-UITestSeedDemoData` to `app.launchArguments` itself if it isn't
already present, so a bare `xcodebuild test` (`./test.sh screenshots`) seeds the same way `fastlane
screenshots` does without depending on fastlane's own cache file. `Platform.isUITestingWithSeedDemoData`
does a `contains` check, so a duplicate flag from both sources is harmless.

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
accessibility identifiers exist anywhere in `iOS/MainFeed`/`iOS/MainTimeline`/`iOS/Article`. Sidebar and
timeline rows are single accessibility elements (the cell itself is the accessibility element; its child
labels are not), so navigation matches on `app.cells` by label prefix
(`label BEGINSWITH <seeded title>`), not on `staticTexts`. The back button is matched as the leading
navigation-bar button (`app.navigationBars.buttons.element(boundBy: 0)`) rather than by identifier —
both are known fragility points if the UI changes.

On failure the test attaches the accessibility tree and a screenshot to the `.xcresult` (also on
`tearDown()` for any failure, not just an explicit assertion at the end), and prints `[NectarUITest]`
lines you can grep from the log.

## Fastlane

The project is generated, so run `xcodegen generate` first (`brew install xcodegen`); there is no
checked-in `NetNewsWire.xcodeproj`.

```sh
bundle exec fastlane screenshots
```

Each entry in the `variants` hash in `fastlane/Fastfile` is **one space-joined string** passed as
`launch_arguments: [string]`. fastlane snapshot runs the whole UI test once per element of that array
(`launcher_configuration.rb`), and `SnapshotHelper` splits the string into tokens on the app side, so
passing the flags as separate array elements would run the test once per flag with only that flag set.
`-UITestSeedDemoData` is added by `NectarUITests.setUp()` itself, so it isn't listed in `variants`.
`frame_screenshots` needs `imagemagick`.

To run the same UI test without fastlane artifacts, or to capture a full log and result bundle:

```sh
./test.sh screenshots
./test.sh screenshots-debug   # fixed result-bundle path + full log, see test.sh
```

Plain `./test.sh` runs the `Nectar-CI` unit/package test plan and does not launch UI tests. Both
`screenshots` subcommands reset the app's container first (`xcrun simctl uninstall`) since
`UITestDemoData.seedIfNeeded()` imports additively into whatever account is already on disk, and a
container left over from an earlier run can be stale.

Use `./results.sh <path-to.xcresult>` afterwards to pull the summary, per-test details, and any
attachments (screenshots/accessibility dumps) out of a result bundle.

## The hosted feed (manual, not seeded)

Separately from all of the above, `demo-feeds/` builds a small, plain JSON Feed and
`.github/workflows/gallery.yml` publishes it to
`https://kyrielie.github.io/nectar/demo-feeds/feed.json`, alongside the landing page and theme gallery.

This is **not** wired into `-UITestSeedDemoData`, `UITestDemoData.swift`, or `DemoFeeds.opml`, and the UI
test does not subscribe to it. It exists so a person can add it manually (Settings → Add Feed → that URL)
when they want a lightweight, non-AO3, no-`_ambrosia` feed to poke at in the Simulator — for example to
sanity-check plain-JSON-Feed rendering without pulling in AO3 metadata or the Ambrosia extension at all.

- Source: `demo-feeds/feed.template.json` (8 items, original placeholder text, no `_ambrosia` extension
  and no AO3 URLs).
- Built by `demo-feeds/build.py`. Item dates are written as `days_ago` in the template and turned into
  real dates at build time, since the app ignores articles older than 90 days
  (`ArticlesTable.articleCutoffDate`). The workflow republishes daily (`schedule:`) to keep the feed from
  aging out, which means one small commit to `gh-pages` per day.
- `build.py` validates the feed against what `RSParser/JSONFeedParser` requires (version marker, feed
  title, unique item `id`, `content_html` or `content_text`) and fails the build instead of letting the
  app silently drop items. Preview locally with `python3 demo-feeds/build.py --out /tmp/demo`.
- The feed must be published before the URL resolves. Until the first workflow run completes it 404s.
  Run **Publish site** with `workflow_dispatch`, or push a change under `demo-feeds/`.
