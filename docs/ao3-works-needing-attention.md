# AO3 Works Needing Attention

A pushed screen under Settings, Archive of Our Own, that lists works Nectar
could not finish refreshing from AO3 or is holding a changed version of.
It is separate from Manage Storage because that list is built from
`where contentHTML is not null order by storedSize desc`
(`ArticlesTable.fetchArticleStorageInfo`), so a work flagged missing that
has no stored text can never appear there.

Files:

- `iOS/Settings/AO3WorksNeedingAttentionView.swift`: the SwiftUI list.
- `iOS/Settings/AO3WorksNeedingAttentionViewModel.swift`: row mapping,
  `refresh()`, `retryNow(_:)`, `clearContent(_:)`.
- `Modules/ArticlesDatabase/.../ArticlesTable.swift`
  `fetchAO3AttentionInfo(limit:)`, surfaced as
  `ArticlesDatabase.fetchAO3AttentionInfo(limit:)` and
  `Account.fetchAO3AttentionInfo(limit:)`, returning `ArticleAttentionInfo`
  (see `database.md`).
- Tests: `AO3AttentionInfoTests` (ArticlesDatabaseTests),
  `AO3WorksNeedingAttentionViewModelTests` (Nectar-iOSTests).

## How it is reached

`AO3AccountSettingsView` has a "Works Needing Attention" row. That view is
hosted in a `UIHostingController` pushed on Settings' navigation
controller, so the row calls an `onShowWorksNeedingAttention` closure and
`SettingsViewController.pushWorksNeedingAttention()` does the push, the same
closure pattern `AnnotationsSettingsView` uses. See
`ao3-authenticated-reading.md` for the rest of that screen.

## Which works are listed

Any article with a non-null `pendingUpdateContentHTML`,
`wordCountRegressionFlaggedAt`, or `ao3ConfirmedMissingAt`, newest first by
`coalesce(pendingUpdateDetectedAt, wordCountRegressionFlaggedAt,
ao3ConfirmedMissingAt)`. The query selects only
`(pendingUpdateContentHTML is not null) as hasPending`, never the pending
body. Each account contributes at most 200 rows; the merged list is trimmed
to the newest 100. The list loads when the screen appears and is not
observed live.

One row per article. When several flags are set the label follows this
precedence:

| State | Label | Set by |
|---|---|---|
| Pending update | "Pending update" | a fetch whose content looked like a regression, stashed for review (`setPendingContentUpdateAsync`) |
| Not found | "Not found on AO3" | `AO3ChapterFetcher` on positive evidence only (see `ao3-preface-rendering.md`) |
| Flagged | "Flagged after a smaller-than-expected feed report" | a feed item with a much smaller word count than stored |

## Row actions

- **Retry Now** (not shown for a pending update). Clears
  `ao3ConfirmedMissingAt` and `wordCountRegressionFlaggedAt`, fetches the
  `Article`, and calls `AO3ChapterFetcher.shared.checkForUpdates(for:)`. Its
  `Bool` selects the message shown afterwards. `false` is not only the 60
  second per-article floor: `checkForUpdates` also returns `false` for an
  Ambrosia work with updates turned off, an anthology bookKey, or an
  unresolved pending update, so the message says "may have already checked"
  rather than asserting the floor. Both flags are cleared before the call,
  so a throttled retry leaves the work unflagged and the row gone after the
  reload. The list is reloaded after every retry.
- **Review Update** (pending update only). Dismisses Settings and calls
  `SceneCoordinator.selectArticleDirectly(_:account:)`
  (`SettingsViewController.openArticleFromSettings(articleID:accountID:)`,
  modeled on `navigateToAnnotationFromSettings`). The review alert comes from
  `WebViewController.presentPendingContentUpdateAlertIfNeeded()` when the
  article loads; that hand-off has not been confirmed on a device.
  `openArticleFromSettings` needs `presentingParentController` to be the
  `RootSplitViewController` and does nothing otherwise.
- **Clear Content** (trailing swipe and context menu). Calls
  `Account.clearContent(articleIDs:)`, the same call Manage Storage uses; the
  row is removed locally without a reload. That call also nulls the pending
  and flag columns (see `ArticlesTable`), so the work stops being listed.

Empty state: "Nothing Needs Attention".

## Not done

- No count on the settings row.
- The reader toolbar button still stays disabled while an update is
  pending; only the reader menu item changed (see `ao3-integration.md`).
- No automatic refresh while the screen is open.
