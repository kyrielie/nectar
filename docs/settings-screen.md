# Settings screen structure

`SettingsViewController` (`iOS/Settings/`) is a `UITableViewController`
driven by `Settings.storyboard`'s static cells, sectioned by the nested
`SettingsViewController.Section: Int` (7 sections, in table order):
`.feeds`, `.timeline`, `.articles`, `.appearance`, `.troubleshooting`,
`.help`, `.ao3Account`. Most sections have a corresponding `*Row: Int` enum
(`FeedsRow`, `TimelineRow`, `ArticlesRow`, `AppearanceRow`,
`TroubleshootingRow`, `HelpRow`) whose `.allCases.count` (where declared
`CaseIterable`) or manual row count drives `numberOfRowsInSection` against
the storyboard's static cells — adding a row means adding both the enum
case and the matching storyboard cell in lockstep. `.ao3Account` has no
row enum: it's a single row that pushes `AO3AccountSettingsView` directly
(see below).

## Row inventory by section

- **`.feeds`** (`FeedsRow`): import subscriptions, export subscriptions
  (renamed "Export Feeds" — re-importing a feed you already have, for
  example after its network address changed, updates it automatically;
  you don't need to delete the old feed first), export articles (CSV or
  SQLite), and Feed Transfer Format — a disclosure row presenting a
  JSON/SQLite picker, backed by `AmbrosiaTransferFormatPreference.current`
  and read by `LocalAccountRefresher.url(for:)` on every refresh (see
  `sqlite-transfer.md`). This row only affects feeds that support the
  SQLite transfer protocol; most feeds are unaffected, which is why the
  explanation lives in the picker's own action-sheet message rather than
  the section footer (the footer already covers what exporting includes,
  and the two settings are otherwise unrelated).
- **`.timeline`** (`TimelineRow`): sort field, sort direction, group by
  feed, "refresh clears read articles," Timeline Layout (pushes
  `TimelineCustomizerCollectionViewController`, below), show-last-updated
  label.
- **`.articles`** (`ArticlesRow`, 5 cases): theme picker, "open links in
  Nectar," disable article links, feed-name-in-reader, and **Full Screen
  Reading** — a disclosure row pushing `FullScreenReadingViewController`
  (below). The first four affect the normal, non-fullscreen reading view;
  everything that only matters once you're actually in fullscreen reading
  mode now lives on the pushed screen instead of mixed into this list.
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
  `AmbrosiaTransferFormatPreference`. The three AO3-related ones are
  exposed via `AO3AccountSettingsView`, per above; `AmbrosiaTransferFormatPreference`
  has its own UI too, but on this screen rather than that one — the "Feed
  Transfer Format" row in `.feeds`, see above.

## Timeline Layout screen

`TimelineCustomizerCollectionViewController` is a 4-section
`UICollectionViewCompositionalLayout` list. Corrected here from a stale
description (this doc previously said icon size (0), number of lines (1),
no-icon preview (2), icon preview (3) — that predates
surface-palette-and-badge-colors-plan section 3.4, which fixed the section
layout to what's below and moved Badge Colors off this screen entirely,
onto `AccentColorTableViewController`): Number of Lines (0), Tag Display
(1), Stats Visibility (2), Preview (3). Section 0/1 are slider rows
(`TimelineCustomizerCell`/`TickMarkSlider`, dequeued from storyboard
prototype cells); section 2 is a `StatsVisibilityCell` (a plain
`UISwitch` row, registered in code, no storyboard prototype); section 3
renders a live `MainTimelineCell` built from a hardcoded `previewArticle`.
All four reload on `UserDefaults.didChangeNotification`-equivalent
per-setting notifications (`.timelineNumberOfLinesDidChange`,
`.timelineTagDisplayModeDidChange`, `.statsVisibilityDidChange`), plus
`.accentColorDidChange`/`.surfaceTintDidChange` for live palette/tint
repainting.

## Full Screen Reading screen

`FullScreenReadingViewController` is a static-cell `UITableViewController`,
pushed from `.articles`'s Full Screen Reading row, grouping every setting
that only does anything once you're actually in fullscreen reading mode:
three bare (no header) sections — Gestures (enable full screen articles,
back-swipe, paging-swipe, show article scrollbar), Top Toolbar (pushes
`ArticleToolbarCustomizerViewController`, below), and a third section
holding Page Counter and Hide Notch in Full Screen.

Hide Notch and Page Counter interact: `WebViewController` forces
notch-hiding whenever Page Counter is anything other than Off, independent
of Hide Notch's own stored `AppDefaults` value. Rather than let the Hide
Notch switch keep showing its raw stored state while silently disagreeing
with what's actually on screen, `updateHideNotchAvailability()` disables
the switch outright (fixing it to "on") whenever Page Counter is active —
the same disabled-control pattern `AO3AccountSettingsView` already uses
for "Check for Updates" when its own prerequisite toggle is off, rather
than an inline per-row reason label. The "why" lives in this section's
footer instead. Hide Notch's own `AppDefaults` value is never touched by
this — only what the switch displays and whether it's interactive.

## Article Top Toolbar screen

`ArticleToolbarCustomizerViewController` is a 2-section
`UICollectionViewCompositionalLayout` list, modeled on
`TimelineCustomizerCollectionViewController`'s shape above but with the
preview *above* the toggles rather than below it: Preview (0), Top Toolbar
(1).

- **Preview (0)**: one `ArticleToolbarPreviewCell`, a real `UINavigationBar`
  built with the same icons and order as
  `ArticleViewController.rightBarButtonItems()` (theme, table of contents,
  find, then previous/next, then lock/annotations/settings/check for
  updates, each included only if its own toggle is on) — a synthetic bar
  rather than an embedded, real `ArticleViewController`, since that
  controller needs a live `Article`, `SceneCoordinator`, and WebView
  machinery this screen has no reason to stand up. If
  `rightBarButtonItems()`'s ordering ever changes, this cell's
  `configure()` needs the matching change or the preview silently drifts
  from the real reader. When `AppDefaults.articleToolbarUseOverflowMenu`
  is on, `configure()` takes an early branch instead: it shows a single
  target-less command-glyph (⌘) item if any toggle is enabled, or no
  items at all if every toggle is off — mirroring
  `ArticleViewController.rightBarButtonItems()`'s own overflow-mode
  branch (see below) rather than the per-toggle icon list.
- **Top Toolbar (1)**: `ArticleToolbarOverflowToggleCell` at item 0,
  followed by one `ArticleToolbarToggleCell` per `ArticleToolbarToggle`
  case (Theme / Table of Contents / Find in Article / Previous & Next
  Article / Lock Gestures / Highlights / Settings / Check for Updates) —
  `numberOfItemsInSection` for this section is
  `ArticleToolbarToggle.allCases.count + 1` to account for the leading
  overflow row. Both cell types are plain `UISwitch` rows (same shape as
  `StatsVisibilityCell`), replacing the earlier checkmark-style
  single-select picker, which itself had replaced the two independent,
  silently-conflicting switches this screen used to be reached by, back
  when it was a push row directly on the Articles list. All toggles are
  independent and freely combinable up to a 4-icon cap
  (`ArticleToolbarCustomizerViewController.maxSlots`; Previous & Next
  Article counts as 2 slots) — **except** the cap is lifted entirely once
  `ArticleToolbarOverflowToggleCell`'s switch
  (`AppDefaults.articleToolbarUseOverflowMenu`) is on, since a menu has no
  fixed-width leading cluster to run out of room in (see `capReached` in
  `collectionView(_:cellForItemAt:)`). Flipping a switch writes straight
  to its own `AppDefaults` property (`setArticleToolbarToggleEnabled(_:_:)`
  for the per-function toggles, `articleToolbarUseOverflowMenu` directly
  for the overflow row); there's no row-tap handling on this screen —
  selection is driven entirely by each cell's own `UISwitch.valueChanged`
  target, not `didSelectItemAt`/`shouldSelectItemAt`.

Both sections reload on the generic `UserDefaults.didChangeNotification`
— the toggle setters don't post a dedicated notification, and
`ArticleViewController` itself already relies on this same generic
notification to repaint its real nav bar (see
`ArticleViewController.userDefaultsDidChange(_:)`), so this screen's
preview and the real reader deliberately stay on the same live-update
path rather than gaining a second, parallel one.

Four independent `Bool` properties on `AppDefaults` —
`articleToolbarShowTheme`, `articleToolbarShowTableOfContents`,
`articleToolbarShowFind`, `articleToolbarShowPrevNext` (registered
defaults: theme/TOC/find true, prevNext false) — are the source of truth
`ArticleViewController.rightBarButtonItems()` reads, one `if` per toggle
in that fixed order, no `else`. `AppDefaults.isArticleToolbarToggleEnabled(_:)`/
`setArticleToolbarToggleEnabled(_:_:)`, keyed by the `ArticleToolbarToggle`
enum (`.theme`/`.tableOfContents`/`.find`/`.prevNext`), give a single
dispatch point over the four properties so call sites (the customizer's
row loop, the preview cell, the Settings summary label) don't each need
their own four-way switch.

The former `showTableOfContentsAndFind`/`showPrevNextArticleButtons`
`Bool` properties are still present on `AppDefaults` (read/write, backing
the same on-disk keys as before) but are no longer read by
`ArticleViewController` or `SettingsViewController` directly — they exist
now only so `AppDefaults.migrateArticleToolbarTogglesIfNeeded()` (called
once from `AppDelegate`, guarded by
`Key.hasMigratedArticleToolbarToggles`, same shape as the pre-existing
`migrateNavigationBarTintingDefaultIfNeeded()`) can derive the four
toggles' initial values from whatever was already on disk:
`showTableOfContentsAndFind` maps onto both `articleToolbarShowTableOfContents`
and `articleToolbarShowFind` (it used to govern that pair together), and
`showPrevNextArticleButtons` maps onto `articleToolbarShowPrevNext`.
`articleToolbarShowTheme` has no legacy source — the theme button was
unconditionally present before this setting existed — so it simply keeps
its registered `true` default regardless of what the migration does with
the other three.

The Top Toolbar row's detail label (`updateArticleTopToolbarModeLabel()`,
on `FullScreenReadingViewController`) no longer names a single mode; it
shows "Off" when all four toggles are off, or "N Shown" for the count of
toggles currently on.

`AppDefaults.articleToolbarUseOverflowMenu` (`Bool`, off by default, not
in `registerDefaults()`'s dictionary — same implicit-false path as
`articleToolbarShowLock`/`articleToolbarShowAnnotations`/
`articleToolbarShowSettings`) is a display-mode switch, not a ninth
per-function toggle: it doesn't gate whether a top-toolbar function is
available, only whether the enabled set renders as one
`UIBarButtonItem` per toggle (today's default) or collapses into a
single command-glyph (⌘) button whose tap opens a native `UIMenu`
listing every enabled function. `ArticleViewController.rightBarButtonItems()`
branches on it first, before building any per-toggle item, and delegates
menu construction to `rebuildOverflowMenu()`, which is also called from
`updateUI()` (both the early `article == nil` return and its main body)
and from `toggleGesturesLocked(_:)` — anywhere those methods mutate a
bar item's `isEnabled`/`image` in place, since a static `UIMenu` doesn't
observe those mutations the way an on-screen `UIBarButtonItem`'s own
properties do. `ArticleToolbarToggle.title`/`.icon` (an extension on the
enum itself, in `AppDefaults.swift`) is the single source of truth
`rebuildOverflowMenu()`, `ArticleToolbarToggleCell`, and
`ArticleToolbarPreviewCell` all read from for display name and icon —
`.lock` and `.prevNext` are excluded from `.icon`'s use in
`rebuildOverflowMenu()` since both have runtime-only state (lock's
open/closed image, prevNext's next/previous availability) that a static
per-case icon can't represent.
