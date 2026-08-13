# Upstream Drift: Nectar vs. NetNewsWire

Tracks how the Nectar fork's source tree differs from upstream
[NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire), so a future audit
(or an AI engineer onboarding onto this codebase) can see what changed without
re-running a full file-by-file sweep from scratch. This complements the
topic docs indexed in `CLAUDE.md`, which document what the code *does*;
this file tracks *where it differs from upstream* at the file level.

## Snapshot provenance

| | |
|---|---|
| Upstream snapshot source | Repomix dump of `Ranchero-Software/NetNewsWire`, supplied out-of-band (not committed to this repo) |
| Upstream version, per the snapshot's own `Technotes/Status.md` | iOS 7.1 (7105) shipping / iOS 7.1.1 (7107) beta / Mac 7.1.1 shipping |
| Upstream commit SHA | **not recorded in this snapshot** -- repomix doesn't embed one by default. See "Regeneration procedure" below; the next snapshot should be taken with the commit SHA noted at capture time. |
| Snapshot generated | 2026-08-10 (this audit) |
| Nectar tree compared | as uploaded for this audit (`nectar-claude.zip`) |

## Summary

Comparing every path common to both trees (content compared with trailing-newline
and line-ending differences ignored, since the repomix round-trip normalizes those
and they're not real diffs):

| Category | Count | Meaning |
|---|---|---|
| Byte-identical carryover | 466 | Unmodified from upstream |
| Modified from upstream | 173 | Same path, different content |
| Nectar-original | 224 | No upstream counterpart (excludes 28 scratch/build-artifact files -- crash log samples, `.swiftpm` scheme files, `Package.resolved` -- not worth tracking as fork features) |
| Upstream-only | 553 | No Nectar counterpart |

Corrected from this audit's original 225/1 split: `nectar-architecture.md`
was counted as Nectar-original when this snapshot was generated but has
since been deleted (its content split into the topic docs indexed in
`CLAUDE.md`). Removed from the itemized list below rather than left as a
stale entry; the rest of this table's counts were not independently
re-verified against that deletion.

The upstream-only count splits into two very different buckets:

- `Mac/` -- 262 files
- `Widget/` -- 18 files
- `NetNewsWire.xcodeproj/` -- 7 files
- `AppStore/` -- 1 files
- `Appcasts/` -- 3 files
- `AppleScript/` -- 5 files
- `Intents/` -- 3 files

These 299 files are **out of scope entirely**, not deleted features:
Nectar only builds the iOS target (per `module-layout.md`'s note that
"several `#if os(macOS)` branches survive... but nothing macOS is
currently built or shipped"). `Mac/`, `Widget/`, `NetNewsWire.xcodeproj/`,
`AppStore/`, `Appcasts/`, `AppleScript/`, and `Intents/` are all macOS-app-target
or non-source-tree content upstream has no iOS-only equivalent for. Not itemized
below -- if that ever changes (e.g. a macOS build gets revived), this section is
the place to start.

The remaining upstream-only files are genuine **deleted features/backends**,
itemized below.

## Deleted from upstream (intentional)

Confirms `module-layout.md`'s note that the non-local account
backends are "fully deleted from the tree, not merely unreachable-but-compiled."

**`Modules/Account/`** (69 files)

- `CloudKit/` -- 14 files
- `Feedbin/` -- 11 files
- `Feedly/` -- 10 files
- `NewsBlur/` -- 2 files
- `ReaderAPI/` -- 9 files
- 23 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**`Modules/CloudKitSync/`** (7 files)

- 7 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**`Modules/NewsBlur/`** (15 files)

- `Models/` -- 8 files
- 7 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**`Modules/RSCore/`** (30 files)

- `AppKit/` -- 25 files
- 5 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**`Modules/RSWeb/`** (2 files)

- 2 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**`Modules/Secrets/`** (6 files)

- 6 files directly under the module (Package.swift, top-level sources/tests, `.gitignore`, README)

**Other non-Modules deletions:**

- `.github/` -- 1 file
- `NetNewsWire-CI.xctestplan/` -- 1 file
- `NetNewsWire.xctestplan/` -- 1 file
- `Resources/Themes/` -- 25 files
- `Shared/` -- 1 file
- `Shared/Article Extractor/` -- 2 files
- `Shared/Article Rendering/` -- 1 file
- `Shared/Commands/` -- 1 file
- `Shared/ExtensionPoints/` -- 2 files
- `Shared/Importers/` -- 2 files
- `Shared/Settings/` -- 1 file
- `Shared/ShareExtension/` -- 6 files
- `Shared/SmartFeeds/` -- 1 file
- `Shared/Timer/` -- 1 file
- `Shared/Widget/` -- 4 files
- `Technotes/` -- 11 files
- `Technotes/Testing/` -- 1 file
- `Tests/NetNewsWireTests/` -- 18 files
- `buildscripts/` -- 3 files
- `buildscripts/certs/` -- 3 files
- `buildscripts/profile/` -- 2 files
- `iOS/` -- 1 file
- `iOS/Account/` -- 4 files
- `iOS/Article/` -- 1 file
- `iOS/IntentsExtension/` -- 3 files
- `iOS/Resources/` -- 10 files
- `iOS/Settings/` -- 2 files
- `iOS/ShareExtension/` -- 8 files
- `setup.sh/` -- 1 file
- `xcconfig/` -- 7 files

(Mostly extension targets removed alongside their backends -- ShareExtension,
IntentsExtension -- plus the account-specific storyboards/entitlements/xcconfig
files that went with them, and `iOS/Settings/ArticleThemesTableViewController.swift`,
superseded by Nectar's `iOS/Settings/ArticleThemeListView.swift`. Worth calling
out specifically: `Resources/Themes/` -- upstream's 25 built-in `.nnwtheme`
bundles -- are gone entirely, replaced by Nectar's own 20+ themes listed under
"Nectar-original" below. Confirm that's intentional (a full swap) rather than
an accidental loss of upstream themes worth porting forward, since it isn't
called out explicitly in `theme-system.md` or any other current topic doc.)

Full per-file list is mechanically reproducible (see Regeneration procedure) --
not enumerated file-by-file here since the directory-level grouping above is the
actionable unit (an entire backend, not individual files, is what's either present
or absent).

## Nectar-original (no upstream counterpart)

Files that are wholly new in Nectar -- new features, not modifications of
existing upstream files. Grouped by top-level directory.

### `.github/` (1 file)

- `.github/workflows/release.yml`

### `Modules/` (77 files)

- `Modules/Account/Sources/Account/AO3LinkListImporter.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3AuthenticatedFetcher.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3ChallengeSessionStore.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3ChapterFetcher.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3ChapterNotification.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3KudosFetcher.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3KudosManager.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3KudosNotification.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3KudosOnLikePreference.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3KudosRequest.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3PrefaceRefetchPreference.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3SearchResultsFetcher.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3SearchResultsImporter.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3SearchResultsPaginator.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3SeriesNavigator.swift`
- `Modules/Account/Sources/Account/LocalAccount/AO3SessionStore.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaAO3NetworkPreference.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaFeedIdentity.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaSQLiteTransferFetcher.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaSQLiteTransferWalkState.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaSQLiteWireFormat.swift`
- `Modules/Account/Sources/Account/LocalAccount/AmbrosiaTransferFormatPreference.swift`
- `Modules/Account/Sources/Account/LocalAccount/NectarAppGroupUserDefaults.swift`
- `Modules/Account/Tests/AccountTests/AO3ChapterFetcherTests.swift`
- `Modules/Account/Tests/AccountTests/AO3KudosRequestTests.swift`
- `Modules/Account/Tests/AccountTests/AO3LinkListImportAccountTests.swift`
- `Modules/Account/Tests/AccountTests/AO3LinkListImporterTests.swift`
- `Modules/Account/Tests/AccountTests/AO3SeriesNavigatorTests.swift`
- `Modules/Account/Tests/AccountTests/Resources/ambrosia_preface_fixture.html`
- `Modules/Account/Tests/AccountTests/Resources/ao3-series-nav-empty.html`
- `Modules/Account/Tests/AccountTests/Resources/ao3-series-nav-page1-with-work-one.html`
- `Modules/Account/Tests/AccountTests/Resources/ao3-series-nav-page1.html`
- `Modules/Account/Tests/AccountTests/Resources/ao3-series-nav-page2.html`
- `Modules/Account/Tests/AccountTests/Resources/ao3-work-single-chapter.html`
- `Modules/Articles/Sources/Articles/AO3RegressionThreshold.swift`
- `Modules/Articles/Tests/ArticlesTests/AO3RegressionThresholdTests.swift`
- `Modules/Articles/Tests/ArticlesTests/ArticleSeriesEntryTests.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/AmbrosiaSQLiteImportTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticleSQLiteExportTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/BookStateTable.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ContentHTMLCompression.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/AmbrosiaSQLiteImportAsymmetryTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/AmbrosiaSQLiteImportTableTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ArticleSQLiteExportTableTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ArticlesTableUpdateTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/BookKeySQLParityTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/BookStateTableTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ClearContentHTMLTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ContentHTMLCompressionTests.swift`
- `Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/TestFixtures.swift`
- `Modules/RSCore/Sources/RSCoreResources/RSCoreResources.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3ChapterHTMLExtractor.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3HTMLHelpers.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3IgnoreList.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3ListingPagination.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3PrefaceRenderer.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3SearchResultsExtractor.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3SeriesListingExtractor.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/Extensions/AO3SummaryExtractor.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/ParsedSeriesEntry.swift`
- `Modules/RSParser/Sources/RSParser/HTML/HTMLLiteTree.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3ChapterHTMLExtractorTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3IgnoreListTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3PrefaceRendererTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3SearchResultsExtractorTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3SeriesListingExtractorTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/Extensions/AO3SummaryExtractorTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Resources/ambrosia.json`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-search-results.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-series-listing.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-work-adult-content-gate.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-work-multi-chapter.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-work-single-chapter.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-work-two-series.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/ao3-work-workskin.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/longseries.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/testfeed.atom`

### `Nectar-CI.xctestplan/` (1 file)

- `Nectar-CI.xctestplan`

### `Shared/` (11 files)

- `Shared/ArticleStyles/ArticleThemeColorExtractor.swift`
- `Shared/ArticleStyles/ArticleThemeOverrides.swift`
- `Shared/ArticleStyles/CSSImportExtractor.swift`
- `Shared/Exporters/ArticleCSVExporter.swift`
- `Shared/Extensions/ArticleFeedNaming.swift`
- `Shared/Extensions/SurfacePaletteNavigationBarAware.swift`
- `Shared/ManageStorage/ManageStorageViewModel.swift`
- `Shared/SmartFeeds/LastOpenedFeedDelegate.swift`
- `Shared/SmartFeeds/LovedFeedDelegate.swift`
- `Shared/SmartFeeds/ReadFeedDelegate.swift`
- `Shared/SmartFeeds/SmartFeedArticleGrouping.swift`

### `Tests/` (16 files)

- `Tests/NetNewsWire-iOSTests/AccentColorIconHexSetTests.swift`
- `Tests/NetNewsWire-iOSTests/AccentColorTableViewControllerSelectionTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleCSVExporterTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleRendererSeriesNavigationTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleRendererStripFakeParagraphIndentsTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleThemeColorExtractorTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleThemePlistFamilyTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleThemePreviewSampleTests.swift`
- `Tests/NetNewsWire-iOSTests/ArticleThemeSelectorCoverageTests.swift`
- `Tests/NetNewsWire-iOSTests/BadgeColorPaletteMigrationTests.swift`
- `Tests/NetNewsWire-iOSTests/BadgeColorTableTests.swift`
- `Tests/NetNewsWire-iOSTests/CSSImportExtractorTests.swift`
- `Tests/NetNewsWire-iOSTests/SettingsAccentColorLiveUpdateTests.swift`
- `Tests/NetNewsWire-iOSTests/SettingsCellBackgroundHostingTests.swift`
- `Tests/NetNewsWire-iOSTests/SurfacePaletteHexSetTests.swift`
- `Tests/NetNewsWire-iOSTests/TimelineCustomizerCellAccentTintTests.swift`

### `Themes/` (73 files)

24 new `.nnwtheme` bundles (article-view CSS themes), not itemized
individually here -- see `docs/theme-system.md` for the theme system itself.
Names: `Aldine.nnwtheme`, `Beetlejuice.nnwtheme`, `Black & White.nnwtheme`, `Broadsheet.nnwtheme`, `Charcoal Rose.nnwtheme`, `Constellations.nnwtheme`, `Deco Line.nnwtheme`, `Dracula.nnwtheme`, `Dusky Purple.nnwtheme`, `Ember.nnwtheme`, `Kelmscott.nnwtheme`, `Kennerley.nnwtheme`, `Marigold Press.nnwtheme`, `Midnight Teal.nnwtheme`, `Moonlit Wisteria.nnwtheme`, `Pastel Whimsy.nnwtheme`, `Poudre et Plume.nnwtheme`, `Powder Pink.nnwtheme`, `Rosarivo.nnwtheme`, `Rosé Pine Dawn.nnwtheme`, `Rosé Pine Moon.nnwtheme`, `Rosé Pine.nnwtheme`, `Tumblr Blue.nnwtheme`, `Vintage Letter Green.nnwtheme`.

### `appstore/` (1 file)

- `appstore/source.template.json`

### `buildscripts/` (1 file)

- `buildscripts/theme-generation/generate_ported_themes.py`

### `docs/` (6 files)

This project's own documentation set (including this file).

### `iOS/` (31 files)

- `iOS/Article/ShareAO3SeriesLinkActivity.swift`
- `iOS/Article/TableOfContentsViewController.swift`
- `iOS/Import/AO3LinkListImportView.swift`
- `iOS/Import/OPMLImportCoordinator.swift`
- `iOS/MainFeed/AO3OnboardingView.swift`
- `iOS/MainTimeline/Cell/BadgeColorTable.swift`
- `iOS/Nectar-iOS-Bridging-Header.h`
- `iOS/Resources/About.rtf`
- `iOS/Resources/Assets.xcassets/archiveOfOurOwnFeedIcon.imageset/Contents.json`
- `iOS/Resources/Assets.xcassets/archiveOfOurOwnFeedIcon.imageset/archiveOfOurOwnFeedIcon.svg`
- `iOS/Resources/Assets.xcassets/listBackgroundColor.colorset/Contents.json`
- `iOS/Resources/Assets.xcassets/settingsBackgroundColor.colorset/Contents.json`
- `iOS/Resources/Assets.xcassets/settingsCellBackgroundColor.colorset/Contents.json`
- `iOS/Resources/Credits.rtf`
- `iOS/Resources/Dedication.rtf`
- `iOS/Resources/Nectar-dev.entitlements`
- `iOS/Resources/Nectar.entitlements`
- `iOS/Resources/Thanks.rtf`
- `iOS/Settings/AO3AccountSettingsView.swift`
- `iOS/Settings/AO3ChallengeSolverViewController.swift`
- `iOS/Settings/AO3LoginViewController.swift`
- `iOS/Settings/AO3SearchResultsFetchCoordinator.swift`
- `iOS/Settings/AccentColorTableViewController.swift`
- `iOS/Settings/ArticleThemeListView.swift`
- `iOS/Settings/ArticleThemePreviewWebView.swift`
- `iOS/Settings/BadgeColorPalettePreviewCell.swift`
- `iOS/Settings/ManageStorageCollectionViewController.swift`
- `iOS/Settings/SettingsBackgroundPalette.swift`
- `iOS/Settings/StatsVisibilityCell.swift`
- `iOS/Settings/SurfacePaletteAware.swift`
- `iOS/Settings/SurfacePalettePreviewCell.swift`

### `make-zip.sh/` (1 file)

- `make-zip.sh`

### `project.yml/` (1 file)

- `project.yml`

### `scripts/` (4 files)

- `scripts/repo.sh`
- `scripts/repo2.sh`
- `scripts/setup.sh`
- `scripts/update_source.py`
## Modified from upstream

Same path in both trees, different content. This is the highest-value list for
code review or regression triage -- anything not here is either untouched or
wholly new (see above). One-line reasons are given only where already confirmed
by this session's tracing or by one of the topic docs indexed in `CLAUDE.md`;
everything else is listed without a guessed reason, per this project's own
rule against asserting things that haven't been verified by reading the code.

### `.github/` (1 file)

- `.github/workflows/ci.yml`

### `.gitignore/` (1 file)

- `.gitignore`

### `.swiftlint.yml/` (1 file)

- `.swiftlint.yml`

### `CODE_OF_CONDUCT.md/` (1 file)

- `CODE_OF_CONDUCT.md`

### `CONTRIBUTING.md/` (1 file)

- `CONTRIBUTING.md`

### `Modules/` (67 files)

- `Modules/Account/Package.swift`
- `Modules/Account/Sources/Account/Account.swift`
- `Modules/Account/Sources/Account/AccountDelegate.swift`
- `Modules/Account/Sources/Account/AccountError.swift`
- `Modules/Account/Sources/Account/AccountManager.swift` -- AO3/Ambrosia account wiring
- `Modules/Account/Sources/Account/AccountSettings.swift`
- `Modules/Account/Sources/Account/DataExtensions.swift`
- `Modules/Account/Sources/Account/Feed.swift`
- `Modules/Account/Sources/Account/FeedSettings.swift`
- `Modules/Account/Sources/Account/FeedSettingsDatabase.swift`
- `Modules/Account/Sources/Account/FeedSettingsImporter.swift`
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountDelegate.swift` -- AO3/Ambrosia account delegate hooks
- `Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift` -- AO3/Ambrosia refresh routes
- `Modules/Account/Sources/Account/SidebarItem.swift`
- `Modules/Account/Tests/AccountTests/FeedSettingsImporterTests.swift`
- `Modules/ActivityLog/Package.swift`
- `Modules/ActivityLog/Sources/ActivityLog/Activity.swift`
- `Modules/ActivityLog/Sources/ActivityLog/ActivityKind.swift`
- `Modules/ActivityLog/Sources/ActivityLog/ActivityLog.swift`
- `Modules/ActivityLog/Sources/ActivityLog/ActivityOwner.swift`
- `Modules/ActivityLog/Sources/ActivityLog/Resources/Localizable.xcstrings`
- `Modules/Articles/Package.swift`
- `Modules/Articles/Sources/Articles/Article.swift`
- `Modules/Articles/Sources/Articles/ArticleStatus.swift`
- `Modules/ArticlesDatabase/Package.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesDatabase.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesTable.swift` -- bookKey/BookStateTable integration -- see docs/database.md
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/Constants.swift` -- new table/column constants for BookStateTable etc.
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/Extensions/Article+Database.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/Extensions/ArticleStatus+Database.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/Extensions/ParsedArticle+Database.swift`
- `Modules/ArticlesDatabase/Sources/ArticlesDatabase/StatusesTable.swift`
- `Modules/ErrorLog/Package.swift`
- `Modules/FeedFinder/Package.swift`
- `Modules/HTMLMetadata/Package.swift`
- `Modules/HTMLMetadata/Sources/HTMLMetadata/HTMLMetadataDownloader.swift`
- `Modules/Images/Package.swift`
- `Modules/Images/Sources/Images/IconImage.swift`
- `Modules/RSCore/Package.swift`
- `Modules/RSCore/Sources/RSCore/CoalescingQueue.swift`
- `Modules/RSCore/Sources/RSCore/RSScreen.swift`
- `Modules/RSCore/Sources/RSCore/UIKit/PoppableGestureRecognizerDelegate.swift`
- `Modules/RSCore/Tests/RSCoreTests/Resources/apple.html`
- `Modules/RSCore/Tests/RSCoreTests/Resources/daringfireball.html`
- `Modules/RSDatabase/Package.swift`
- `Modules/RSDatabase/Sources/RSDatabase/DatabaseTable.swift`
- `Modules/RSParser/Package.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/JSON/JSONFeedParser.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/ParsedItem.swift` -- carries new AO3/series metadata fields -- see ParsedSeriesEntry.swift (Nectar-original)
- `Modules/RSParser/Sources/RSParser/Feeds/XML/AtomParser.swift` -- AO3 Atom feed handling
- `Modules/RSParser/Sources/RSParser/Feeds/XML/RSSItem.swift`
- `Modules/RSParser/Sources/RSParser/Feeds/XML/RSSParser.swift` -- AO3 RSS feed handling
- `Modules/RSParser/Sources/RSParser/XML/XMLEncoding.swift`
- `Modules/RSParser/Tests/RSParserTests/Feeds/JSON/JSONFeedParserTests.swift`
- `Modules/RSParser/Tests/RSParserTests/Resources/coco.html`
- `Modules/RSParser/Tests/RSParserTests/Resources/donthitsave.xml`
- `Modules/RSParser/Tests/RSParserTests/Resources/kc0011.rss`
- `Modules/RSParser/Tests/RSParserTests/Resources/livemint.xml`
- `Modules/RSParser/Tests/RSParserTests/Resources/macworld.rss`
- `Modules/RSParser/Tests/RSParserTests/TestHelpers.swift`
- `Modules/RSParser/Tests/RSParserTests/XML/XMLEncodingTests.swift`
- `Modules/RSTree/Package.swift`
- `Modules/RSWeb/Package.swift`
- `Modules/RSWeb/Sources/RSWeb/Downloader.swift`
- `Modules/RSWeb/Sources/RSWeb/WebServices/TestingURLProtocol.swift`
- `Modules/SyncDatabase/Package.swift`
- `Modules/SyncDatabase/Sources/SyncDatabase/SyncStatus.swift`

### `NetNewsWire-iOS.xctestplan/` (1 file)

- `NetNewsWire-iOS.xctestplan`

### `README.md/` (1 file)

- `README.md`

### `Shared/` (33 files)

- `Shared/AccountType+Helpers.swift`
- `Shared/Activity/ActivityManager.swift`
- `Shared/ActivityLog/ActivityLogViewModel.swift`
- `Shared/Article Rendering/ArticleRenderer.swift`
- `Shared/Article Rendering/WebViewConfiguration.swift`
- `Shared/Article Rendering/core.css`
- `Shared/Article Rendering/main.js`
- `Shared/Article Rendering/stylesheet.css`
- `Shared/Article Rendering/template.html`
- `Shared/ArticleStyles/ArticleTheme.swift`
- `Shared/ArticleStyles/ArticleThemePlist.swift`
- `Shared/ArticleStyles/ArticleThemesManager.swift`
- `Shared/Assets.swift` -- accent-color and surface-palette asset accessors added
- `Shared/Commands/MarkStatusCommand.swift`
- `Shared/DefaultAccountNames.xcstrings`
- `Shared/Extensions/ArticleStringFormatter.swift`
- `Shared/Extensions/ArticleUtilities.swift`
- `Shared/Extensions/IconImageView.swift`
- `Shared/Extensions/RSImage+Extensions.swift`
- `Shared/Extensions/SmallIconProvider.swift`
- `Shared/IconImageCache.swift`
- `Shared/Localizable.xcstrings`
- `Shared/SmartFeeds/PseudoFeed.swift`
- `Shared/SmartFeeds/SmartFeed.swift`
- `Shared/SmartFeeds/SmartFeedsController.swift`
- `Shared/SmartFeeds/StarredFeedDelegate.swift`
- `Shared/SmartFeeds/TodayFeedDelegate.swift`
- `Shared/SmartFeeds/UnreadFeed.swift`
- `Shared/Timeline/ArticleArray.swift`
- `Shared/Timeline/ArticleSorter.swift`
- `Shared/Timeline/FetchRequestOperation.swift`
- `Shared/UserInfoKey.swift`
- `Shared/UserNotifications/UserNotificationManager.swift`

### `Technotes/` (1 file)

- `Technotes/Themes.md`

### `Tests/` (1 file)

- `Tests/NetNewsWire-iOSTests/ActivityItemSourceTests.swift`

### `Themes/` (9 files)

- `Themes/Appanoose.nnwtheme/template.html`
- `Themes/Biblioteca.nnwtheme/stylesheet.css`
- `Themes/Biblioteca.nnwtheme/template.html`
- `Themes/Hyperlegible.nnwtheme/stylesheet.css`
- `Themes/NewsFax.nnwtheme/template.html`
- `Themes/Promenade.nnwtheme/template.html`
- `Themes/Sepia.nnwtheme/stylesheet.css`
- `Themes/Tiqoe Dark.nnwtheme/stylesheet.css`
- `Themes/Verdana Revival.nnwtheme/stylesheet.css`

### `buildscripts/` (3 files)

- `buildscripts/build_and_test.sh`
- `buildscripts/crash-logs.sh`
- `buildscripts/quiet_build_and_test.sh`

### `iOS/` (49 files)

- `iOS/Account/Account.storyboard`
- `iOS/AccountStats/AccountStatsView.swift`
- `iOS/Add/AddComboTableViewCell.swift`
- `iOS/Add/AddFeedViewController.swift`
- `iOS/Add/SelectComboTableViewCell.swift`
- `iOS/AppDefaults.swift` -- AccentColor/SurfacePalette/BadgeColorPalette enums added (see app-chrome-palette.md)
- `iOS/AppDelegate.swift`
- `iOS/Article/ArticleSearchBar.swift`
- `iOS/Article/ArticleViewController.swift`
- `iOS/Article/ContextMenuPreviewViewController.swift`
- `iOS/Article/ImageTransition.swift`
- `iOS/Article/PreloadedWebView.swift`
- `iOS/Article/WebViewController.swift`
- `iOS/CurrentActivity/CurrentActivityView.swift`
- `iOS/Inspector/AccountInspectorViewController.swift`
- `iOS/Inspector/FeedInspectorViewController.swift`
- `iOS/Inspector/Inspector.storyboard`
- `iOS/KeyboardManager.swift`
- `iOS/MainFeed/Collection View Cells/MainFeedCollectionViewCell.swift`
- `iOS/MainFeed/Collection View Cells/MainFeedCollectionViewFolderCell.swift`
- `iOS/MainFeed/MainFeedCollectionViewController.swift` -- AO3/Ambrosia feed additions, accent-color button retinting (see accent-color-light-dark-fix.patch)
- `iOS/MainFeed/RefreshProgressView.swift`
- `iOS/MainTimeline/Cell/MainTimelineCell.swift`
- `iOS/MainTimeline/Cell/MainTimelineCellData.swift`
- `iOS/MainTimeline/Cell/MainTimelineCellLayout.swift`
- `iOS/MainTimeline/MainTimelineModernViewController.swift` -- AO3/Ambrosia timeline additions, accent-color button retinting (see accent-color-light-dark-fix.patch)
- `iOS/MainTimeline/MarkAsReadAlertController.swift`
- `iOS/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `iOS/Resources/Info.plist`
- `iOS/Resources/main_ios.js`
- `iOS/Resources/page.html`
- `iOS/RootSplitViewController.swift`
- `iOS/SceneCoordinator.swift`
- `iOS/SceneDelegate.swift` -- accent-color window.tintColor plumbing (see accent-color-light-dark-fix.patch)
- `iOS/Settings/AboutView.swift`
- `iOS/Settings/ActivityLogView.swift`
- `iOS/Settings/AddAccountViewController.swift`
- `iOS/Settings/ColorPaletteTableViewController.swift` -- Surface Palette settings screen -- see naming-scheme note (ColorPalette/SurfacePalette/surfaceTint three-namer)
- `iOS/Settings/DinosaursView.swift`
- `iOS/Settings/ErrorLogView.swift`
- `iOS/Settings/Settings.storyboard`
- `iOS/Settings/SettingsComboTableViewCell.swift`
- `iOS/Settings/SettingsViewController.swift`
- `iOS/Settings/TimelineCustomizerCell.swift`
- `iOS/Settings/TimelineCustomizerCollectionViewController.swift`
- `iOS/UIKit Extensions/UIViewController+Extras.swift`
- `iOS/UIKit Extensions/VibrantButton.swift`
- `iOS/UIKit Extensions/VibrantLabel.swift`
- `iOS/UIKit Extensions/VibrantTableViewCell.swift`

### `xcconfig/` (3 files)

- `xcconfig/NetNewsWire_iOSTests_target.xcconfig`
- `xcconfig/NetNewsWire_iOSapp_target.xcconfig`
- `xcconfig/common/NetNewsWire_codesigning_common.xcconfig`

## Regeneration procedure

1. **Capture a fresh upstream snapshot.** Run Repomix against
   `Ranchero-Software/NetNewsWire` at a known commit, and record that commit
   SHA and date in the "Snapshot provenance" section above -- this was the one
   gap in this pass, since the snapshot used here didn't carry that metadata.
2. **Unpack the snapshot into a real file tree.** Repomix's `<file
   path="...">...</file>` blocks parse directly into a directory tree with a
   short script (this pass used one, see below) -- no need to hand-copy files.
3. **Diff against the Nectar tree**, comparing on normalized content (line
   endings normalized, trailing-newline-at-EOF differences ignored -- the
   round-trip through Repomix changes both of those without changing the
   actual content, so a byte-for-byte comparison overcounts "modified" files
   by roughly 4x, as it did on the first pass this session).
4. **Categorize into the four buckets above** (identical / modified /
   Nectar-original / upstream-only), and split upstream-only into
   out-of-scope-target vs. genuinely-deleted-feature before writing anything
   into the "Deleted from upstream" section.
5. **Diff this run's four lists against the previous version of this file**
   to see what moved between buckets since the last audit -- a file leaving
   "identical" and entering "modified" is itself useful signal (something
   changed that wasn't previously flagged as fork-specific).
6. **Update the change log below** with the date, the snapshot's upstream
   version/commit, and a one-line summary of what moved.

The unpack-and-diff step is mechanical enough to script once and rerun --
worth turning into an actual checked-in script (e.g.
`scripts/upstream-diff.py`) next time this is done by hand, rather than
redoing the one-off version used to generate this file.

## Change log

- **2026-08-10**: First version of this file. Generated from a Repomix
  snapshot of upstream NetNewsWire (version identified via the snapshot's own
  `Technotes/Status.md` as iOS 7.1/7.1.1, Mac 7.1.1 -- exact commit SHA not
  captured, see "Snapshot provenance" above) diffed against the Nectar tree
  as of this audit. 466 identical, 173 modified, 225 Nectar-original
  (excluding scratch/build-artifact noise), 553 upstream-only (299 of which
  are out-of-scope macOS/widget/extension targets Nectar doesn't build; 254
  are genuinely deleted backends/features, itemized under "Deleted from
  upstream" above).
