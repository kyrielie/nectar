# Settings screen structure

`SettingsViewController` (`iOS/Settings/`) is a `UITableViewController`
driven by `Settings.storyboard`'s static cells, sectioned by
`SettingsSection: Int` (7 sections, in table order): `.feeds`,
`.timeline`, `.articles`, `.appearance`, `.troubleshooting`, `.help`,
`.ao3Account`. Most sections have a corresponding `*Row: Int` enum
(`FeedsRow`, `TimelineRow`, `ArticlesRow`, `AppearanceRow`,
`TroubleshootingRow`, `HelpRow`) whose `.allCases.count` (where declared
`CaseIterable`) or manual row count drives `numberOfRowsInSection` against
the storyboard's static cells — adding a row means adding both the enum
case and the matching storyboard cell in lockstep (the "Show Article
Scrollbar" row is a recent, representative example of this pattern: a new
`ArticlesRow` case, a new `@IBOutlet`/`@IBAction`, and a new storyboard
cell added together). `.ao3Account` has no row enum: it's a single row that pushes
`AO3AccountSettingsView` directly (see below).

## Row inventory by section

- **`.feeds`** (`FeedsRow`): import subscriptions, export subscriptions,
  export articles (CSV).
- **`.timeline`** (`TimelineRow`): sort field, sort direction, group by
  feed, "refresh clears read articles," Timeline Layout (pushes
  `TimelineCustomizerCollectionViewController`, below), show-last-updated
  label.
- **`.articles`** (`ArticlesRow`, 12 cases): theme picker, "open links in
  NetNewsWire," full-screen articles, back-swipe, paging-swipe,
  feed-name-in-reader, prev/next article buttons, table-of-contents-and-
  find, hide-notch-in-fullscreen, page-counter display mode, disable
  article links, **show article scrollbar** (the newest addition — see
  `AppDefaults.shared.showArticleScrollbar`, consumed in
  `WebViewController`).
- **`.appearance`** (`AppearanceRow`): color palette (pushes
  `ColorPaletteTableViewController`, which also owns the
  `useTintedNavigationBar` switch — see `app-chrome-palette.md`), accent
  color.
- **`.troubleshooting`** (`TroubleshootingRow`): error log, activity log,
  account stats, "dinosaurs" (easter egg / debug row — not investigated
  further here), manage storage.
- **`.help`** (`HelpRow`): About.
- **`.ao3Account`**: single row, pushes `AO3AccountSettingsView` — a
  SwiftUI screen covering AO3 sign-in, kudos-on-like, refetch cadence, and
  the Ambrosia local-only-reader toggle. **Not covered by the row
  inventory above at all** — see `ao3-authenticated-reading.md` for its
  full contents. Anyone auditing "every setting Nectar has" needs both
  this file and that one.

## Settings living entirely outside this screen

Two storage tiers exist beyond `Settings.storyboard`'s rows:

- **`AppDefaults`** (`iOS/AppDefaults.swift`) backs everything listed
  above, plus some flags with no UI row at all (state like
  `hasShownAO3Onboarding`, `articleWindowScrollY` — restoration/onboarding
  bookkeeping, not a person-facing setting).
- **`NectarAppGroupUserDefaults`**-backed preferences, living in
  `Modules/Account` rather than `AppDefaults` specifically so
  Account-module code (`AO3ChapterFetcher`, `AO3KudosManager`) can read
  them without depending on the iOS app target: `AO3PrefaceRefetchPreference`,
  `AO3KudosOnLikePreference`, `AmbrosiaAO3NetworkPreference`,
  `AmbrosiaTransferFormatPreference`. All of the AO3-related ones are
  exposed via `AO3AccountSettingsView`, per above; whether
  `AmbrosiaTransferFormatPreference` has any UI at all has not been
  checked as part of this doc pass — flagged as an open item in the
  investigation checklist.

## Timeline Layout screen

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list: icon size (0), number of lines
(1), no-icon preview (2), icon preview (3). Sections 2/3 render a live
`MainTimelineCell` built from a hardcoded `previewArticle` and reload on
`UserDefaults.didChangeNotification` for the two sliders currently wired up.
