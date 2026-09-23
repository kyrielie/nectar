# Nectar modularization: Stage 6, AO3Kit — final plan

Companion to the Stage 0-4 plan (`nectar-modularization-stage-0-4.md`),
the Stage 5 plan (`nectar-modularization-stage-5-annotations.md`), and
the Stage 7 plan (`nectar-modularization-stage-7-ambrosia.md`).
Everything in the 0-4 plan's package template, `project.yml` wiring,
doc-update discipline, and uniform `@testable import` rule applies here
unless this doc says otherwise.

Line/file counts below are from the snapshot this plan was written
against (`wc -l`, direct `grep`, per-symbol reference scans — not
estimated). **Re-verify before cutting.**

## Decisions already made (do not reopen)

| Question | Decision |
|---|---|
| Package name | `Modules/AO3Kit` |
| Does AO3Kit depend on `Account`? | **No.** Zero exceptions. This is the whole point of the stage. |
| `HTMLLiteTree.swift` | Moves with the extractors. Zero consumers outside the AO3 cluster. |
| `HTMLScanner.swift` | **Does not move.** Public, used by `HTMLLinkParser`/`HTMLMetadataParser` too. AO3Kit consumes it via `import RSParser`. |
| The 3 RSParser call sites (`RSSItem.toParsedItem`, `RSSParser`/`AtomParser` filtering) | Resolved with a provider-injection seam owned by RSParser (Sub-stage 6a). RSParser gains **no** new package dependency. |
| `AmbrosiaAO3NetworkPreference` | Moves into AO3Kit (Sub-stage 6b). Zero code-level `Account` coupling; see "Where `AmbrosiaAO3NetworkPreference` lives" below. |
| The `AO3ChapterFetcher` cluster (`AO3ChapterFetcher`, `AO3KudosManager`, `AO3PrefetchQueue`, `AO3SeriesNavigator`) | **Deferred to a later stage.** Not attempted here. See Sub-stage 6d. |
| `bookKey` prefix constants (`"ao3-work:"`, `"ao3-series:"`, `"calibre-series:"`) | Untouched by this stage. Stay exactly where they are (`ParsedItem.bookKey` in RSParser, `AO3ChapterFetcher`'s private constants in Account) — Stage 7 territory. |
| `WebViewController.swift`'s AO3 code (series-nav tap handling, chapter-fetch notification observers, the provisional-stub check) | **Out of scope.** ~150 scattered lines, not a contiguous block. See "Coordination with Stage 5." |
| SwiftUI/UIKit AO3 screens (`AO3AccountSettingsView`, `AO3LoginViewController`, etc.) | Stay in the app target, keep importing `Account` (none of the 7 import `RSParser`/AO3Kit types directly today). |

## Where `AmbrosiaAO3NetworkPreference` lives

`AmbrosiaAO3NetworkPreference.swift` is `import Foundation` only — zero
code-level reference to any `Account` or `AccountManager` type. It
reads and writes one `UserDefaults` key via the same
`NectarAppGroupUserDefaults.store` app-group suite every other
AO3/Ambrosia preference in `Account` already uses
(`AO3PrefaceRefetchPreference`, `AO3KudosOnLikePreference`,
`AO3IgnoreList`'s own duplicated store). It moves into `AO3Kit` in
Sub-stage 6b, structurally identical to the other 13 files moving
there.

This introduces no backward dependency: `AO3ChapterFetcher` (which
reads it, and stays in `Account` per Sub-stage 6d) gains
`import AO3Kit`, which it needs regardless — `Account` already depends
on `AO3Kit` for the RSParser-layer AO3 extraction types
(`AO3ChapterHTMLExtractor`, etc.) that Sub-stage 6a moves and that
`AO3ChapterFetcher`/`AO3KudosManager`/`AO3SeriesNavigator` already
import today. Adding one more type to that same, already-necessary
import costs nothing.

The `bookKey` prefix constants are a separate, pre-existing
duplication (`ParsedItem.bookKey` in RSParser core, not moving;
`AO3ChapterFetcher`'s own private constants in Account, staying per
Sub-stage 6d) and are untouched by this stage in either direction —
see Stage 7's plan for that duplication's ownership.

## Why the `AO3ChapterFetcher` cluster is deferred

A reference count across every Account-layer AO3 file, counting only
non-comment code references, shows two structurally different groups:

| File | Code refs to `AO3ChapterFetcher` | Distinct `Account`/`AccountManager` APIs touched |
|---|---|---|
| `AO3SearchResultsImporter` | 0 | 2 (`account.updateAsync`, `account.sendNotificationAbout`) + `Feed` field writes |
| `AO3SearchResultsPaginator` | 0 | same 2, via `AO3SearchResultsImporter`'s helper, plus `Feed` |
| `AO3ChapterFetcher` | — (itself) | 6 (`AccountManager.shared.existingAccount`, `account.fetchArticlesAsync`, `.setPendingContentUpdateAsync`, `.updateAsync`, `.setAO3ConfirmedMissingAsync`, `.clearAO3ConfirmedMissingAsync`) + reads `AmbrosiaAO3NetworkPreference` |
| `AO3KudosManager` | 2 | 3 (`AccountManager.shared.existingAccount`, `.kudosAttempt`, `.setKudosAttempted`) |
| `AO3PrefetchQueue` | 3 | 0 directly, but calls `AO3ChapterFetcher.shared.fetchIfNeeded`/`.secondsBetweenAO3PagedRequests` — inseparable from the cluster |
| `AO3SeriesNavigator` | 6 | 5+ (`account.fetchArticlesAsync` ×2, `account.updateAsync` ×3, `account.existingFeed`) plus calling `AO3ChapterFetcher.shared.download`/`.ao3WorkID(fromBookKey:)`/`.bookKey(forWorkID:)`/`.secondsBetweenAO3PagedRequests` directly |

`AO3SearchResultsImporter`/`AO3SearchResultsPaginator` are genuinely
independent of `AO3ChapterFetcher` and need exactly two `Account`
methods plus `Feed` field access — a narrow seam, the same shape as
Stage 5's `AnnotationPersisting`. `AO3ChapterFetcher`, `AO3KudosManager`,
`AO3PrefetchQueue`, and `AO3SeriesNavigator` are mutually coupled
(`AO3SeriesNavigator` calls `AO3ChapterFetcher` directly as a
same-module sibling 6 times; `AO3PrefetchQueue` and `AO3KudosManager`
each call it too) and each touches substantially more of `Account`'s
surface. Moving this second cluster needs a materially bigger seam —
on the order of `Account`'s whole article-mutation/session surface,
not two methods — plus it has direct iOS-layer callers
(`WebViewController`, `ArticleViewController`, `SceneCoordinator`,
`LocalAccountRefresher`) that would all need their imports reworked in
the same change. That is its own stage; see Sub-stage 6d.

## What Stage 6 is, and is not

**Is:**
- Move the 9-file RSParser AO3 extraction cluster (`AO3SummaryExtractor`,
  `AO3ChapterHTMLExtractor`, `AO3SearchResultsExtractor`,
  `AO3SeriesListingExtractor`, `AO3PrefaceRenderer`,
  `AO3ListingPagination`, `AO3HTMLHelpers`, `AO3IgnoreList`,
  `HTMLLiteTree`) into `AO3Kit`, with a provider-injection seam
  replacing the 3 RSParser call sites.
- Move the 14 self-contained Account-layer AO3/Ambrosia files (zero
  `Account`/`AccountManager` code coupling) into `AO3Kit` unchanged.
- Move `AO3SearchResultsImporter`/`AO3SearchResultsPaginator` into
  `AO3Kit` behind a 2-method `AccountArticleUpdating` protocol seam,
  the same shape as Stage 5's `AnnotationPersisting`.
- Wire `project.yml`, `Nectar-CI.xctestplan`, relocate the matching
  test files and fixtures.

**Is not:**
- Moving `AO3ChapterFetcher`, `AO3KudosManager`, `AO3PrefetchQueue`, or
  `AO3SeriesNavigator`. See Sub-stage 6d for what a later stage doing
  this needs.
- Touching `WebViewController.swift`'s AO3-adjacent code at all.
- Touching `ParsedItem`'s Ambrosia fields, `Article`'s mirrored
  fields, `bookKey`, or `AmbrosiaSQLiteImportTable`'s SQL mirror —
  Stage 7's territory, explicitly.
- Touching the 7 dedicated AO3 SwiftUI/UIKit screens
  (`AO3AuthenticatedWebViewController`, `ShareAO3SeriesLinkActivity`,
  `AO3LinkListImportView`, `AO3AccountSettingsView`,
  `AO3ChallengeSolverViewController`, `AO3LoginViewController`,
  `AO3SearchResultsFetchCoordinator`) beyond adding an `import AO3Kit`
  where a moved symbol requires it.

## Sub-stage order

```
6a  RSParser extraction cluster -> AO3Kit, provider-injection seam
6b  Independent Account-layer AO3/Ambrosia files -> AO3Kit
6c  AO3SearchResultsImporter/Paginator -> AO3Kit, AccountArticleUpdating seam
    (6d AO3ChapterFetcher cluster: separate future stage, not part of this plan)
```

Each sub-stage must build and pass the full test plan on its own. Do
not combine sub-stages into one commit.

---

## 6a — RSParser extraction cluster

### What moves (every file below imports only `Foundation`; their only intra-RSParser dependency is the public `HTMLScanner` and the public `ParsedItem`/`ParsedFeed`/`ParsedSeriesEntry` types)

| File | LOC |
|---|---|
| `AO3SummaryExtractor.swift` | 301 |
| `AO3ChapterHTMLExtractor.swift` | 1,043 |
| `AO3SearchResultsExtractor.swift` | 567 |
| `AO3SeriesListingExtractor.swift` | 174 |
| `AO3PrefaceRenderer.swift` | 336 |
| `AO3ListingPagination.swift` | 53 |
| `AO3HTMLHelpers.swift` | 121 |
| `AO3IgnoreList.swift` | 128 |
| `HTML/HTMLLiteTree.swift` | 215 |

9 files, 2,938 lines. A full-repo grep confirms
`HTMLLiteElement`/`HTMLLiteNode`/`parseHTMLLiteTree`/`flattenedText`/
`firstDescendant`/`serializeHTMLLiteNodes` have no consumer outside
this cluster (`HTMLLinkParser.swift`/`HTMLMetadataParser.swift` use
`HTMLScanner` directly, not the lite tree).

**Public API:** already close to fully `public` (these are consumed
today from `Account`, a different module, so the public pass mostly
already happened). After the move, build; fix any "inaccessible due to
internal protection level" error with `public` on exactly that member.
`AO3IgnoreList`'s `shouldExclude(_:)` needs to additionally be
reachable through the new seam protocol (below), not just `public`.

### The 3 call sites needing a seam (all three, no others)

- `Feeds/XML/RSSItem.swift:81` — `AO3SummaryExtractor.extract(fromSummaryHTML:)`
- `Feeds/XML/RSSItem.swift:113` — `AO3SummaryExtractor.ao3WorkID(fromPermalink:)`
- `Feeds/XML/RSSParser.swift:58` — `AO3IgnoreList.shouldExclude(_:)`
- `Feeds/XML/AtomParser.swift:73` — `AO3IgnoreList.shouldExclude(_:)`

`docs/ao3-direct-feed-ingestion.md` describes these as the only three
fork-specific additions to `RSSItem`/`RSSParser`/`AtomParser`.

### Design: provider injection

SPM has no circular package dependencies. `AO3Kit` needs `RSParser`
for `ParsedItem`/`HTMLScanner`; `RSParser` cannot depend back on
`AO3Kit`. The fix, used elsewhere in this modularization effort
(`ArticleThemesManager.nameStorage` in Stage 0b,
`AnnotationsJavaScriptEvaluating`/`AnnotationPersisting` in Stage 5c),
is a protocol **owned by the side that can't take the dependency**,
with a static injection point set once at app startup. RSParser
declares the seam, AO3Kit conforms, the app wires them together:

```swift
// Modules/RSParser/Sources/RSParser/Feeds/XML/AO3FeedExtending.swift (new)

/// Optional extension point for AO3-specific handling of RSS/Atom
/// items. RSParser has no compile-time dependency on the type that
/// conforms to this -- see AO3FeedExtensionPoint.provider below.
/// Modules/AO3Kit is the real implementation.
public protocol AO3FeedItemExtending: Sendable {
	/// Tries to parse `summaryHTML` (an RSS/Atom item's <summary>) as
	/// AO3's machine-generated summary markup. Returns nil for
	/// anything that isn't AO3-shaped, so the caller falls through to
	/// the generic body/summary promotion.
	func extractedItem(fromSummaryHTML summaryHTML: String, permalink: String?, language: String?) -> AO3SummaryExtractionResult?

	/// Whether `item` should be dropped before it's ever turned into
	/// a persisted ParsedItem (ignored work/author). A no-op (false)
	/// for anything not AO3-sourced.
	func shouldExclude(_ item: ParsedItem) -> Bool
}

public struct AO3SummaryExtractionResult: Sendable {
	// mirrors AO3SummaryExtractor.ExtractionResult's public fields --
	// language, cleanedSummaryHTML, wordCount, chapterCurrent,
	// chapterTotal, isComplete, fandoms, relationships, characters,
	// ratings, warnings, categories, series, additionalTags, ao3WorkID
	// ... (copy the exact field list from AO3SummaryExtractor.swift's
	// current ExtractionResult type)
}

public enum AO3FeedExtensionPoint {
	/// Set once, before the first feed is parsed -- see AppDelegate.swift,
	/// the same injection pattern as ArticleThemesManager.nameStorage
	/// from Stage 0b. Defaults to nil: with no provider set, AO3 feeds
	/// parse as ordinary RSS/Atom (no AO3 field extraction, no ignore-
	/// list filtering) rather than crashing -- the same "safe no-op
	/// default" philosophy as Stage 0b's InMemoryThemeNameStorage.
	public nonisolated(unsafe) static var provider: AO3FeedItemExtending?
}
```

`RSSItem.toParsedItem()` and `RSSParser`/`AtomParser`'s
`buildParsedFeed()` call `AO3FeedExtensionPoint.provider?.extractedItem(...)`
/ `AO3FeedExtensionPoint.provider?.shouldExclude(item) ?? false`
instead of calling `AO3SummaryExtractor`/`AO3IgnoreList` directly.

In `AO3Kit`, the conforming type and its registration:

```swift
// Modules/AO3Kit/Sources/AO3Kit/AO3FeedExtension.swift (new)

public struct AO3FeedExtension: AO3FeedItemExtending {
	public init() {}

	public func extractedItem(fromSummaryHTML summaryHTML: String, permalink: String?, language: String?) -> AO3SummaryExtractionResult? {
		guard let result = AO3SummaryExtractor.extract(fromSummaryHTML: summaryHTML) else { return nil }
		return AO3SummaryExtractionResult(/* map result's fields + AO3SummaryExtractor.ao3WorkID(fromPermalink: permalink) */)
	}

	public func shouldExclude(_ item: ParsedItem) -> Bool {
		AO3IgnoreList.shouldExclude(item)
	}
}
```

App-target side, one line, in `AppDelegate.swift` alongside Stage 0b's
own injection line:

```swift
AO3FeedExtensionPoint.provider = AO3Kit.AO3FeedExtension()
```

Position it before the app can first parse a feed (same ordering
requirement Stage 0b's `nameStorage` injection has). Add a debug-build
assertion, `assert(AO3FeedExtensionPoint.provider != nil)`, at the top
of the app's first refresh call, mirroring Stage 0b's own guard.

**Why a result struct instead of returning `ParsedItem` directly:**
`RSSItem.toParsedItem()` needs to combine the extraction result with
fields only it has (`uniqueID`, `feedURL`, `link`, `title`, `datePublished`,
`dateModified`, `authors`, `markdown`, `attachments`) — the seam
returns AO3-specific data, not the whole `ParsedItem` across a package
boundary. This mirrors why Stage 5's `AnnotationPersisting` takes and
returns plain values rather than reaching into `WebViewController`'s
state.

### Wiring

- `AO3Kit/Package.swift`: `dependencies: [.package(path: "../RSParser"), .package(path: "../RSWeb"), .package(path: "../RSCore"), .package(path: "../ActivityLog")]` (RSWeb/ActivityLog are needed by Sub-stage 6b's files, added now so 6a and 6b share one manifest edit).
- `RSParser/Package.swift`: **no change.** RSParser gains no new dependency; that is the point of the seam.
- `project.yml`: add under `packages:`
  ```yaml
  AO3Kit:
    path: Modules/AO3Kit
  ```
  `- package: AO3Kit` with `embed: true` under `Nectar-iOS`, and
  `- package: AO3Kit` under `Nectar-iOSTests`'s dependencies (needed
  once app-level tests exercise moved AO3 UI call sites — see "Import
  edits" below).
- `Nectar-CI.xctestplan`: add an `AO3KitTests` entry, same shape as the
  existing `RSParserTests`/`ArticlesTests` entries
  (`containerPath: container:Modules/AO3Kit`, `identifier`/`name` both
  `AO3KitTests`). **Skipping this silently drops the moved tests from
  CI.**
- `iOS/AppDelegate.swift`: the `AO3FeedExtensionPoint.provider = ...`
  line, as above.

### Test relocation

Move, with their fixtures:

| Test file | LOC | Fixtures used |
|---|---|---|
| `AO3ChapterHTMLExtractorTests.swift` | 668 | `ao3-work-single-chapter.html`, `ao3-work-multi-chapter.html`, `ao3-work-adult-content-gate.html`, `ao3-work-two-series.html`, `ao3-work-workskin.html`, `ao3-series-nav-43794-page1.html`, `ao3-series-nav-lastpage.html` |
| `AO3IgnoreListTests.swift` | 125 | none |
| `AO3PrefaceRendererTests.swift` | 133 | none |
| `AO3SearchResultsExtractorTests.swift` | 274 | `ao3-search-results.html` |
| `AO3SeriesListingExtractorTests.swift` | 179 | `ao3-series-listing.html` |
| `AO3SummaryExtractorTests.swift` | 138 | `ao3-bookmarks.html` |

6 files, ~1,517 lines, 10 fixture files (~9,349 lines of fixture HTML).
All `@testable import RSParser` → `@testable import AO3Kit`.

**Fixture duplication:** `ao3-series-nav-43794-page1.html`,
`ao3-series-nav-lastpage.html`, and `ao3-work-single-chapter.html` are
byte-identical to copies also in
`Modules/Account/Tests/AccountTests/Resources/`, used by
`AO3SeriesNavigatorTests.swift`/`AO3ChapterFetcherTests.swift` — both
of which stay in `Account` per Sub-stage 6d. Moving RSParser's copies
into `AO3KitTests` relocates one of the two existing copies rather
than creating a new duplicate. Leave Account's copies as-is. A real
fixture share would need a small `AO3KitTestFixtures` resource product
other test targets could import — worth doing once a future 6d moves
`AO3SeriesNavigatorTests`/`AO3ChapterFetcherTests` into `AO3Kit` too,
not before.

### Docs

`docs/ao3-feeds.md` (primary owner of the extraction layer — update
every `Modules/RSParser/Sources/RSParser/Feeds/Extensions/...` path
reference), `docs/ao3-direct-feed-ingestion.md` (describe the seam
replacing the direct call), `docs/module-layout.md` (new
`Modules/AO3Kit` package bullet; RSParser's own bullet loses the
AO3-specific paragraph). `AO3IgnoreList.swift`'s own header comment
describes the injection seam rather than a direct-dependency
constraint, since it now lives behind `AO3FeedExtensionPoint` rather
than being called directly by `RSSParser`/`AtomParser`.

---

## 6b — Independent Account-layer AO3/Ambrosia files

### What moves (zero code-level reference to any `Account`/`AccountManager`/`Feed` type in any of the 14 — comment mentions only)

| File | LOC | Imports |
|---|---|---|
| `AO3LinkListImporter.swift` | 91 | Foundation, RSParser |
| `AO3AuthenticatedFetcher.swift` | 76 | Foundation, RSWeb, os |
| `AO3ChallengeSessionStore.swift` | 155 | Foundation, Security |
| `AO3ChapterNotification.swift` | 33 | Foundation |
| `AO3FilterURLLength.swift` | 53 | Foundation |
| `AO3KudosFetcher.swift` | 61 | Foundation, RSWeb, os |
| `AO3KudosNotification.swift` | 27 | Foundation |
| `AO3KudosOnLikePreference.swift` | 37 | Foundation |
| `AO3KudosRequest.swift` | 134 | Foundation, RSWeb |
| `AO3PrefaceRefetchPreference.swift` | 88 | Foundation |
| `AO3PrefetchNewWorksPreference.swift` | 51 | Foundation |
| `AO3SearchResultsFetcher.swift` | 460 | Foundation, os, RSParser, RSWeb, ActivityLog |
| `AO3SessionStore.swift` | 108 | Foundation, Security |
| `AmbrosiaAO3NetworkPreference.swift` | 59 | Foundation |

14 files, 1,433 lines. A pure relocation: confirm each still compiles
standalone, move, done. No protocol seam needed.

**Public API:** these were already consumed across the
`RSParser -> Account` boundary or are self-contained
singletons/enums; do a build pass and add `public` wherever the
compiler flags it, nothing more.

### Wiring

- `AO3Kit/Package.swift`: same manifest as 6a — `dependencies: [RSParser, RSWeb, RSCore, ActivityLog]` (Security is a system framework, no package entry needed). No further `project.yml`/`Nectar-CI.xctestplan` changes beyond what 6a already added — these files land in the same `AO3Kit`/`AO3KitTests` targets.
- `Modules/Account/Package.swift`: gains `.package(path: "../AO3Kit")` and `AO3Kit` in the `Account` target's `dependencies:` array (needed by Sub-stage 6d's deferred cluster today, and by every `Account` file below).

### Import edits (verified call sites)

- `iOS/Add/AddFeedViewController.swift` — uses `AO3FilterURLLength.exceedsLimit(url)`/`.limit` (lines 108, 202). Add `import AO3Kit`.
- `iOS/Inspector/FeedInspectorViewController.swift`, `iOS/MainTimeline/MainTimelineModernViewController.swift` — use `AO3SearchResultsPaginator` (moves in 6c, not 6b — add `import AO3Kit` when 6c lands).
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`, `LocalAccountDelegate.swift`, `Account.swift`, `AccountError.swift`, `Feed.swift`, `FeedSettings.swift`, `FeedSettingsDatabase.swift` — reference `AO3SessionStore.isSignedIn`, `AO3ChallengeSessionStore.lastChallengedURL`, `AO3LinkListImporter.importedLinks`/`.permittedHosts`, `AO3FilterURLLength`. Add `import AO3Kit` to each; these already `import RSParser`/`import RSWeb`, so this is a same-shape addition.
- `iOS/MainFeed/MainFeedCollectionViewController.swift` — constructs `AO3LinkListImportView()` (an app-target SwiftUI view, unaffected). Check whether it also references `AO3LinkListImporter` directly before assuming no import is needed.
- `iOS/SceneCoordinator.swift` — `AO3KudosManager.attemptImmediateKudosIfNeeded` stays (`Account`, deferred in 6d); no change from 6b.

**Do not** add `@_exported import AO3Kit` to `Account.swift` to paper
over the per-file import additions — Stage 0-4 and Stage 5 both
established the per-file explicit-import convention; mixing re-export
in for this one stage would be inconsistent with the rest of the
modularization effort.

### Test relocation

| Test file | LOC | Moves to |
|---|---|---|
| `AO3FilterURLLengthTests.swift` | 69 | `AO3KitTests` |
| `AO3KudosRequestTests.swift` | 92 | `AO3KitTests` |
| `AO3LinkListImporterTests.swift` | 138 | `AO3KitTests` |

`@testable import Account` → `@testable import AO3Kit` in each.

**Stays in `Account`, does not move:** `AO3LinkListImportAccountTests.swift`
(165 lines) exercises `Account.importPastedAO3Links(_:destination:)`,
an `Account`-owned API that happens to call `AO3LinkListImporter`
internally, not `AO3LinkListImporter` itself. Add `import AO3Kit`
alongside its existing `@testable import Account` (it likely needs
`AO3LinkListImporter.ImportedLink` or similar for constructing
expected values — verify the exact type references before editing).

### Docs

`docs/ao3-authenticated-reading.md` (session-store paths, kudos
paths), `docs/ao3-integration.md` (most file paths become
`Modules/AO3Kit/...` instead of
`Modules/Account/Sources/Account/LocalAccount/...` — update
throughout, but do **not** touch the sections describing
`AO3ChapterFetcher`/`AO3KudosManager`/`AO3PrefetchQueue`/`AO3SeriesNavigator`
behavior, since those stay in `Account` per 6d), `docs/ambrosia-feed.md`
(the `AmbrosiaAO3NetworkPreference` path), `docs/module-layout.md`.

---

## 6c — `AO3SearchResultsImporter` / `AO3SearchResultsPaginator`

### What moves

| File | LOC |
|---|---|
| `AO3SearchResultsImporter.swift` | 78 |
| `AO3SearchResultsPaginator.swift` | 246 |

324 lines. Both are `@MainActor`-annotated
(`AO3SearchResultsImporter` is `@MainActor public enum`; confirm
`AO3SearchResultsPaginator`'s isolation the same way before cutting —
its doc comment describes it as "a standalone `@MainActor` enum").

### The seam

The exact `Account`/`Feed` surface used (both files combined):

- `account.updateAsync(feedID:parsedItems:deleteOlder:)` — `Account.swift:1117`
- `account.sendNotificationAbout(_:)` — `Account.swift:1857`
- `feed.ao3SearchFetchedPages` (get/set) — `Feed.swift:191-197`
- `feed.ao3SearchTotalPages` (get/set) — `Feed.swift:202-208`

One protocol, the same pattern as Stage 5's `AnnotationPersisting`,
declared in `AO3Kit` and conformed to by `Account` in the app-facing
module:

```swift
// Modules/AO3Kit/Sources/AO3Kit/AO3SearchResultsImporting.swift (new)

@MainActor public protocol AO3ArticleUpdating: AnyObject {
	func updateAsync(feedID: String, parsedItems: Set<ParsedItem>, deleteOlder: Bool) async -> ArticleChanges
	func sendNotificationAbout(_ articleChanges: ArticleChanges)
}

@MainActor public protocol AO3SearchFeedPageTracking: AnyObject {
	var ao3SearchFetchedPages: Set<Int>? { get set }
	var ao3SearchTotalPages: Int? { get set }
}
```

`AO3Kit` can freely depend on `Articles` (a leaf package, no `Account`
dependency risk), so `AO3ArticleUpdating.updateAsync` returns
`Articles.ArticleChanges` directly rather than introducing a mirror
type. `extension Account: AO3ArticleUpdating {}` and
`extension Feed: AO3SearchFeedPageTracking {}` need no bodies, since
`Account`/`Feed`'s existing signatures already match — the same shape
as Stage 5's `extension Account: AnnotationPersisting {}`. Confirm
`Feed`'s `@MainActor` isolation independently before implementing;
`Account.swift:74` declares `@MainActor public final class Account`,
but `Feed`'s isolation may not carry the same annotation.

### Where the conformances live

`Modules/Account/Package.swift` already has `AO3Kit` as a dependency
(added in 6b); `extension Account: AO3ArticleUpdating {}` and
`extension Feed: AO3SearchFeedPageTracking {}` go in `Account.swift`/`Feed.swift`
directly (same file the type is declared in, matching Stage 5's
placement of `extension Account: AnnotationPersisting {}`).

### Import edits

- `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift` — mentions `AO3SearchResultsPaginator` only in a comment for the "load more" note; it calls `AO3SearchResultsFetcher` directly, which stays in 6b. No import change expected — re-verify before assuming.
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountDelegate.swift` — no direct reference to either moved type.
- `iOS/Inspector/FeedInspectorViewController.swift` — `AO3SearchResultsPaginator.validate(page:against:)` (line 281), `.fetchSpecificPage(_:for:account:)` (line 293). Add `import AO3Kit`.
- `iOS/MainTimeline/MainTimelineModernViewController.swift` — `AO3SearchResultsPaginator.loadNextPage(for:account:)` (line 1235), `.nextPageToFetch(fetchedPages:)` (line 1275). Add `import AO3Kit`.

### Test relocation

`AO3SearchResultsImporterTests.swift` (154 lines) → `AO3KitTests`,
`@testable import Account` → `@testable import AO3Kit`. Build a small
in-package fake conforming to `AO3ArticleUpdating`/`AO3SearchFeedPageTracking`
for the moved tests, rather than reaching for `Account`'s real
`TestAccountManager` fixture across a package boundary — `AO3Kit` must
not depend on `Account` even in its test target.

### Docs

`docs/ao3-integration.md`'s "AO3 search subscriptions" section — paths
for `AO3SearchResultsImporter`/`AO3SearchResultsPaginator` change to
`Modules/AO3Kit/...`; the `AO3SearchResultsFetcher` paths in the same
section stay `Modules/Account/...` (6b, not 6c — different files, same
section), `docs/ao3-arbitrary-page-fetch.md` (cites
`AO3SearchResultsPaginator.nextPageToFetch`/`.validate`/`.fetchSpecificPage`
directly — update paths).

---

## 6d — The `AO3ChapterFetcher` cluster (separate future stage)

Not attempted in this plan, for the reasons given above. What that
stage needs, so it isn't re-derived from scratch:

- **A materially bigger seam than 6c's.** `AO3ChapterFetcher` alone
  touches 6 distinct `Account`/`AccountManager` methods; `AO3KudosManager`
  touches 3 more; `AO3SeriesNavigator` touches 5 more plus calls
  `AO3ChapterFetcher` directly 6 times; `AO3PrefetchQueue` calls
  `AO3ChapterFetcher` 3 times. All four move together (or none do)
  because of the direct same-module calls between them.
- **Direct iOS-layer callers that need reworking in the same change:**
  `iOS/Article/WebViewController.swift`
  (`AO3ChapterFetcher.shared.fetchIfNeeded`/`.checkForUpdates`/`.canCheckForUpdates`/`.isAO3NetworkRequestAllowed`,
  `AO3SeriesNavigator.openSeriesWork`/`.Direction`),
  `iOS/Article/ArticleViewController.swift`
  (`AO3ChapterFetcher.shared.canCheckForUpdates`/`.checkForUpdates`/`.isAO3NetworkRequestAllowed`),
  `iOS/SceneCoordinator.swift` (`AO3KudosManager.attemptImmediateKudosIfNeeded`),
  `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift`
  (`AO3PrefetchQueue.shared`, `AO3ChapterFetcher.ao3WorkID(fromBookKey:)`/`.isAO3NetworkRequestAllowed`).
- **The `AmbrosiaAO3NetworkPreference`/bookKey-prefix-constant
  ownership question is already settled by this plan** — the
  preference lives in `AO3Kit` (6b); the prefix constants stay split
  exactly as they are today. A future 6d does not need to revisit
  either, only wire `import AO3Kit` into whatever ends up owning
  `AO3ChapterFetcher`.
- **The right model is the same split Stage 5c uses for
  `WebViewController`'s annotation code:** a package-owned "mechanics"
  half (HTML extraction results already handled by 6a, HTTP
  fetch/retry logic, the regression-guard math) behind a
  persistence-and-session protocol conformed to by `Account`, with the
  `WebViewController`/`ArticleViewController` call sites staying
  exactly where they are, now importing the package instead of
  reaching into `Account`-internal types. Read Stage 5c end to end
  before attempting this — it is the closest precedent in this
  codebase for a seam this size.

Sequence it after Stage 6 lands and bakes for at least one release,
the same discipline the 0-4 plan gives for `ReadingStatsTracker`'s own
deferred seam.

---

## Summary table

| Sub-stage | Files moved | Lines moved | New package dependencies | Design work | Risk |
|---|---|---|---|---|---|
| 6a | 9 (RSParser extraction cluster) | 2,938 | AO3Kit: RSParser, RSWeb, RSCore, ActivityLog | Provider-injection seam for 3 call sites (small, precedented shape) | Low-medium |
| 6b | 14 (independent Account-layer files) | 1,433 | none beyond 6a's manifest | None — pure relocation | Low |
| 6c | 2 (`AO3SearchResultsImporter`/`Paginator`) | 324 | Account: AO3Kit | 1-2 protocol seam, same shape as Stage 5's `AnnotationPersisting` | Low-medium |
| 6d (separate future stage) | 4 (`AO3ChapterFetcher` cluster) | ~1,308 (860+209+150+889) | TBD by that stage | Large seam, Stage 5c-scale | Medium-high |

Stage 6 as scoped here (6a-6c) moves 25 files, ~4,695 lines, into a new
package with zero `AO3Kit -> Account` dependency, at Low/Low-medium
risk throughout. 6d is real remaining work with its own plan, reviewed
on its own.

## Coordination with Stage 5 (Annotations)

No file overlap: Stage 5's `WebViewController.swift` surgery is
entirely in the `// MARK: Annotations` extension (lines ~1044-1826) and
the annotation message-handler cases; this stage leaves
`WebViewController`'s AO3 code (the series-nav handler, chapter-fetch
notification observers) untouched, so the two stages' edits to that
file are in disjoint regions. Land whichever of Stage 5c or a future
6d finishes first, then rebase the other, rather than developing both
against the same file concurrently.

## Coordination with Stage 7 (Ambrosia)

Stage 7's file-grouping work (`AmbrosiaFeedIdentity`,
`AmbrosiaTransferFormatPreference`, `AmbrosiaSQLiteWireFormat`,
`AmbrosiaSQLiteTransferWalkState` into a
`Modules/Account/LocalAccount/Ambrosia/` subfolder) has no overlap with
this stage's file list — none of those four are AO3Kit candidates,
and `AmbrosiaAO3NetworkPreference` (the one Ambrosia-named preference
this stage does move) is AO3-session behavior, not a transfer-route
type, which is why it moves here rather than into Stage 7's subfolder.
`docs/module-layout.md`'s package list needs both stages' new entries
added in the same pass if they land close together — whoever lands
second should re-read the file rather than assume the other stage's
edit is still current.
