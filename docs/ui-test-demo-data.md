# Screenshot demo feed (`fastlane snapshot`)

`fastlane snapshot` needs a populated app to photograph: a sidebar with a feed, a timeline with
articles, and an article to open. The screenshot run subscribes the app to a small **plain JSON Feed
hosted on GitHub Pages**, so **screenshot runs need network access**.

This only happens when the app is launched with `-UITestSeedDemoData`. Nothing here runs in a normal
install, and Nectar does not import any default feeds on first run.

## The hosted feed

- Source: `demo-feeds/feed.template.json` (8 items, original placeholder text).
- Built by `demo-feeds/build.py`, published by `.github/workflows/gallery.yml` to
  `https://kyrielie.github.io/nectar/demo-feeds/feed.json`.
- It is a standard JSON Feed 1.1. It deliberately has no `_ambrosia` extension and no AO3 URLs, so the app
  never treats its items as AO3/Ambrosia works (no AO3 chapter fetch, no AO3 preface).
- Item dates are written as `days_ago` in the template and turned into real dates when the feed is built.
  The app ignores articles older than 90 days (`ArticlesTable.articleCutoffDate`), so fixed dates would
  eventually stop populating the timeline. The workflow republishes daily (`schedule:`) to keep the feed
  fresh, which means one small commit to `gh-pages` per day.
- `build.py` validates the feed against what `RSParser/JSONFeedParser` requires (version marker, feed
  title, unique item `id`, `content_html` or `content_text`) and fails the build instead of letting the
  app silently drop items. Preview locally with `python3 demo-feeds/build.py --out /tmp/demo`.

The feed must be published before screenshots work. Until the first workflow run completes, the URL does
not exist. Run **Publish site** with `workflow_dispatch`, or push a change under `demo-feeds/`.

## Activation

`-UITestSeedDemoData` as a launch argument, read by `Platform.isUITestingWithSeedDemoData`
(`Modules/RSCore/.../Platform.swift`). `UITestDemoData.seedIfNeeded()` (`iOS/UITestDemoData/`), called
from `AppDelegate.didFinishLaunchingWithOptions`, imports the bundled `DemoFeeds.opml`, which contains
one subscription to the hosted feed. `NectarUITests.setUp()` always adds the flag itself, so a bare
`xcodebuild test` and `fastlane screenshots` behave the same.

The flag also affects two things, both unchanged for normal installs and for unit tests:

- `DownloadSession`, `Downloader` and `URLSession.webservice` route through `TestingURLProtocol` only when
  `Platform.isRunningUnitTests && !Platform.isUITestingWithSeedDemoData`. The screenshot run fetches the
  feed for real. (The app-under-test can also read as "running unit tests", so the flag has to opt out
  explicitly.)
- `LocalAccountDelegate.refreshAll()` keeps its `|| Platform.isUITestingWithSeedDemoData` carve-out. For the
  same reason as above, without it `importOPML`'s follow-up refresh silently no-ops and the feed appears in
  the sidebar but never fetches articles.

`-UITestReadingProfile personal` is a second flag that sets the article font and line height in Swift
(`ArticleThemeOverrides` is one JSON string that a fastlane launch argument can't carry).

## UI test flow

`Tests/NetNewsWire-iOSUITests/NectarUITests.swift`: wait for the feed's sidebar row (Main screenshot),
open it and wait for all 8 articles (Timeline screenshot), open "A Quiet Kind of Orbit" and wait for the
web view (Article screenshot). One feed means no back navigation. There are no accessibility identifiers
in `iOS/MainFeed`, `iOS/MainTimeline` or `iOS/Article`; rows are cells matched by label prefix (the cell
is a single accessibility element, so `staticTexts` do not match). The feed name and item count in the
test must be kept in step with `DemoFeeds.opml` and `feed.template.json`.

On failure the test attaches the accessibility tree and a screenshot to the `.xcresult`, and prints
`[NectarUITest]` lines you can grep from the log.

## Fastlane

The project is generated, so run `xcodegen generate` first (`brew install xcodegen`); there is no checked-in
`NetNewsWire.xcodeproj`.

```sh
bundle exec fastlane screenshots
```

Each entry in the `variants` hash in `fastlane/Fastfile` is **one space-joined string** passed as
`launch_arguments: [string]`. fastlane snapshot runs the whole UI test once per element of that array
(`launcher_configuration.rb`), and `SnapshotHelper` splits the string into tokens on the app side, so
passing the flags as separate array elements would run the test once per flag with only that flag set.
`frame_screenshots` needs `imagemagick`.

To run the same UI test without fastlane artifacts, or to capture a full log and result bundle:

```sh
./test.sh screenshots
```

Plain `./test.sh` runs the `Nectar-CI` unit/package test plan and does not launch UI tests.
