# Settings screen structure

`SettingsViewController` (`iOS/Settings/`) is a `UITableViewController`
driven by `Settings.storyboard`'s static cells, sectioned by the nested
`SettingsViewController.Section: Int` (8 sections, in table order):
`.feeds`, `.timeline`, `.articles`, `.appearance`, `.troubleshooting`,
`.help`, `.ao3Account`, `.backup`. Most sections have a corresponding
`*Row: Int` enum (`FeedsRow`, `TimelineRow`, `ArticlesRow`,
`AppearanceRow`, `TroubleshootingRow`, `HelpRow`, `BackupRow`) whose
`.allCases.count` (where declared `CaseIterable`) or manual row count
drives `numberOfRowsInSection` against the storyboard's static cells —
adding a row means adding both the enum case and the matching storyboard
cell in lockstep. `.ao3Account` has no row enum: it's a single row that
pushes `AO3AccountSettingsView` directly (see below).

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
- **`.backup`** (`BackupRow`, 2 cases): "Backup" (triggers
  `exportBackupDocumentPicker(sourceView:sourceRect:)` directly, no
  options screen) and "Restore from Backup…" (opens a `.zip` document
  picker via `BackupRestoreCoordinator.begin`). Not a preference the way
  every other section's rows are — both rows trigger an action rather
  than reading/writing an `AppDefaults` key directly. See
  `backup-restore.md` for the full export/import/merge behavior; this
  entry is only about the row's presence and wiring, same scope as every
  other bullet above.

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
`ToolbarsCustomizerViewController`, below — the row is still keyed by a
`TopToolbarRow` enum with a single `.toolbars` case, a naming leftover
from when this section held two rows for two separate screens), and a
third section holding Page Counter and Hide Notch in Full Screen.

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

## Toolbars screen

`ToolbarsCustomizerViewController` replaces the two formerly-separate
`ArticleToolbarCustomizerViewController` (top bar only) and
`BottomToolbarCustomizerViewController` (bottom bar only) screens with
one screen holding a `UISegmentedControl` (Top / Bottom) above a
3-section `UICollectionViewCompositionalLayout` list: Preview (0),
Functions (1), Overflow (2). Switching the segmented control sets
`activeBar: ToolbarBar` (`.top`/`.bottom`) and reloads the collection
view in place — no animation, since row counts themselves change
between bars (Overflow's candidate set depends on which functions are
inline on the active bar). A trailing `navigationItem.rightBarButtonItem`
"Reset" button resets whichever bar is active back to shipped defaults
(see "Reset" below).

The overflow-toggle row (Overflow section, item 0) greys out the same
way a Functions row does when flipping it on would push `slotsUsed()`
past `maxSlots(for:)` — it costs one slot once on (`slotsUsed(excluding:)`'s
`overflowCost`), so it's subject to the same cap the inline function rows
already visibly enforce.

The unification is driven by `ToolbarFunction`, a single 13-case,
`String`-rawValue `CaseIterable` enum (`theme`/`tableOfContents`/`find`/
`prevNext`/`lock`/`annotations`/`settings`/`checkForUpdates`/`read`/
`star`/`heart`/`nextUnread`/`action`) that replaces the formerly-disjoint
`ArticleToolbarToggle` (top-only, first 8 cases) and `BottomToolbarToggle`
(bottom-only, last 5 cases). The `String` rawValue lets a person's chosen
per-bar display order persist as an array of stable identifiers
independent of the enum's declaration order (see "Reordering" below) —
renaming an existing case's rawValue after shipping would orphan it from
any already-persisted order array, the same way renaming a
`UserDefaults` key would. Every function has an independent
inline/overflow placement *per bar* — a function can be inline on
`.top`, inline on `.bottom`, in either bar's overflow menu, or off
entirely — rather than a function's identity implying which single bar
it could ever appear on. Each `(function, bar)` pair also has an
independent `UIBarButtonItem` instance in `ArticleViewController` (see
"Cross-bar duplicates are now fully supported" below), so placing the
same function inline on both bars at once renders correctly on both,
not just whichever bar happened to build its items last.

- **Preview (0)**: one `ToolbarPreviewCell`, wrapping a real
  `UINavigationBar` for `.top` or a real `UIToolbar` for `.bottom`
  (only one is visible at a time, toggled by `configure(bar:)`), built
  with the same icons, order, and flexibleSpace-separated layout (bottom
  only) as `ArticleViewController.toolbarItems(for:overflowItem:)` /
  `displayOrder(for:)`. Synthetic rather than an embedded, real
  `ArticleViewController`, for the same reasoning the two prior preview
  cells documented: that controller needs a live `Article`,
  `SceneCoordinator`, and WebView machinery this screen has no reason to
  stand up. Both `ToolbarPreviewCell.configure(bar:)` and
  `ArticleViewController.displayOrder(for:)` now read the *same*
  `AppDefaults.toolbarFunctionOrder(for:)` call rather than two
  independently-hardcoded literal arrays, so the preview can no longer
  drift from the real reader's order the way the two separate copies
  risked before persisted ordering existed. When that bar's overflow
  switch (`AppDefaults.isToolbarOverflowMenuEnabled(on:)`) is on and at
  least one function is overflow-flagged there, `configure(bar:)`
  appends a single target-less command-glyph (⌘) item *after* the
  per-function icon list — mirroring `ArticleViewController`'s own
  additive overflow rendering.
- **Functions (1)**: exactly one `ToolbarFunctionCell` per
  `ToolbarFunction.allCases` (13 rows), in this bar's persisted display
  order (`AppDefaults.toolbarFunctionOrder(for:)`), configured via
  `configure(function:bar:isOn:isEnabled:)` — no master-switch row in
  this section (that moved to Overflow, item 0, below). Rows support
  drag-to-reorder: `collectionView.dragInteractionEnabled = true`,
  `canMoveItemAt(_:)` restricted to this section, and
  `moveItemAt(_:to:)` reads the current order, moves the dragged
  function, and writes it back via
  `AppDefaults.setToolbarFunctionOrder(_:for:)` — no custom
  `UICollectionViewDragDelegate`/`DropDelegate` pair needed, since this
  is same-section reordering rather than the cross-container drop
  `MainFeedCollectionViewController+Drag.swift` handles for the
  sidebar's folders. Each row carries a trailing `.reorder()`
  `UICellAccessory` as its drag handle. All rows are independent and
  freely combinable up to a per-bar icon cap
  (`ToolbarsCustomizerViewController.maxSlots(for:)`: 4 on `.top`, 5 on
  `.bottom` — top's is one lower to leave room for the navigation back
  button, which shares the top `UINavigationBar`'s width but isn't
  itself a `ToolbarFunction`; `AppDefaults.toolbarFunctionSlotCost(_:)`
  counts Previous & Next Article as 2 slots, everything else 1). The cap
  always applies, including when that bar's overflow switch is on:
  overflow is additive (the ⌘ item renders alongside inline icons, not
  instead of them — see Preview above), so it occupies one slot in the
  same fixed-width cluster the cap protects (`slotsUsed(excluding:)`
  adds 1 when the overflow switch is on). A row already on stays
  interactive (so it can be turned back off); an off row past the cap
  becomes non-interactive, disabled (`capReached` in
  `collectionView(_:cellForItemAt:)`) — existing over-cap configurations
  aren't trimmed, they just can't add further icons. The section header
  shows a "`used`/`cap`" badge (`TimelineHeaderView.detailLabel`, added
  purely additively to that shared header type so the Timeline
  customizer screen's single-centered-label usage is untouched),
  colored `.systemRed` when `used > cap`. Flipping a switch here writes
  through `AppDefaults.setToolbarFunctionEnabled(_:on:_:)`, which also
  clears that same function's overflow flag on that same bar (mutual
  exclusion enforced at the model layer, not just by which rows this
  screen chooses to show).
- **Overflow (2)**: `ToolbarOverflowToggleCell` at item 0
  (`AppDefaults.isToolbarOverflowMenuEnabled(on:)`/
  `setToolbarOverflowMenuEnabled(on:_:)` for the active bar; the row
  shows the same command-glyph icon as the collapsed preview/real
  toolbar item, not a distinct icon of its own), followed by either one
  `ToolbarFunctionCell` per function not currently inline on the active
  bar (`functionOrder.filter { !isToolbarFunctionEnabled($0, on:
  activeBar) }`, rendered indented via
  `configure(overflowFunction:bar:isOn:isEnabled:)`), or, when that
  filtered set is empty (every function is already placed inline on
  this bar), a single `ToolbarOverflowEmptyStateCell` explaining there's
  nothing left to pick from. These candidate rows are now *always*
  rendered, not conditioned on the master switch's own state — passed
  `isEnabled: overflowSectionIsShown`, so they render visible-but-greyed
  (label/toggle both disabled) when the switch is off, rather than
  disappearing from the section entirely the way the pre-split single
  table did. `numberOfItemsInSection` for this section is therefore
  always `1 + max(overflowCandidates.count, 1)`, independent of the
  master switch's state. Flipping a membership switch writes through
  `setToolbarFunctionInOverflow(_:on:_:)`, which clears the inline flag
  symmetrically to the Functions-section invariant above. There's no
  row-tap handling on this screen — selection is driven entirely by each
  cell's own `UISwitch.valueChanged` target, not
  `didSelectItemAt`/`shouldSelectItemAt`.

All three sections reload on the generic
`UserDefaults.didChangeNotification` — the toggle setters don't post a
dedicated notification, and `ArticleViewController` itself already
relies on this same generic notification to repaint its real bars (see
`ArticleViewController.userDefaultsDidChange(_:)`), so this screen's
preview and the real reader deliberately stay on the same live-update
path rather than gaining a second, parallel one. This screen's own
`userDefaultsDidChange()` skips the `reloadData()` while
`collectionView.hasActiveDrag`/`hasActiveDrop` is true, so a
drag-reorder's own write to `AppDefaults` (which posts this same
notification) doesn't stomp the interactive move animation mid-gesture.

54 `Bool` properties on `AppDefaults`, one per (`ToolbarFunction`,
`ToolbarBar`, inline-or-overflow) triple, are the source of truth
`ArticleViewController.toolbarItems(for:)` /
`isToolbarFunctionInOverflow(_:on:)` read — see
`AppDefaults.toolbarFunctionKeys`, a private `[ToolbarFunction:
[ToolbarBar: (inline: String, overflow: String)]]` table, for the single
place that maps a (function, bar) pair onto its two on-disk key names,
rather than a 52-case hand-written switch. `isToolbarFunctionEnabled(_:on:)`/
`setToolbarFunctionEnabled(_:on:_:)` and
`isToolbarFunctionInOverflow(_:on:)`/`setToolbarFunctionInOverflow(_:on:_:)`
are the read/write dispatch pairs every call site (this screen's row
loop, the preview cell, `ArticleViewController`, the Settings summary
label) uses instead of a per-function switch of their own.

The former `ArticleToolbarToggle`/`BottomToolbarToggle` enums and their
eight/five backing `articleToolbarShowX`/`bottomToolbarShowX` `Bool`
properties, plus the single top-only `articleToolbarUseOverflowMenu`
`Bool`, are all still present on `AppDefaults` (read/write, backing the
same on-disk keys as before) but are no longer read by
`ArticleViewController` or this screen directly — they exist now only so
`AppDefaults.migrateUnifiedToolbarsIfNeeded()` (called once from
`AppDelegate`, *after* the pre-existing
`migrateArticleToolbarTogglesIfNeeded()` since it reads that migration's
own output properties rather than the raw legacy keys underneath them,
guarded by `Key.hasMigratedUnifiedToolbars`) can derive the unified
model's initial placement from whatever was already on disk: every
legacy top toggle that was on becomes that function placed inline on
`.top`; every legacy bottom toggle that was on becomes that function
placed inline on `.bottom`; nothing is placed on the *other* bar just
because cross-bar duplication is now possible — migration preserves
prior behavior exactly, it doesn't opt anyone into the new feature. The
legacy `articleToolbarUseOverflowMenu` Bool becomes
`toolbarTopUseOverflowMenu`; since the pre-unification switch had no
concept of *which* functions were "in" the collapsed menu (it collapsed
whatever was already enabled, with no separate per-function membership),
migration does not populate any function's overflow flag — an upgrader
who had it on keeps seeing the same functions the same way, until they
visit this screen and explicitly move something into overflow.
`toolbarBottomUseOverflowMenu` has no legacy counterpart at all (the
bottom bar never had an overflow concept before unification) and stays
at its registered-default `false`.

The Toolbars row's detail label (`updateToolbarsModeLabel()`, on
`FullScreenReadingViewController`) shows "Off" when no function is
inline on either bar, or "N Shown" for the count of distinct functions
inline on `.top` and/or `.bottom` (a function placed on both bars counts
once). This replaces the two separate pre-unification per-bar labels
(`updateArticleTopToolbarModeLabel()`/`updateArticleBottomToolbarModeLabel()`)
now that one row covers both bars.

### Cross-bar duplicates are now fully supported

Placing the same `ToolbarFunction` inline on both `.top` and `.bottom`
at once is fully supported end to end — this is no longer a
settings-screen-only state that the real toolbars could only partially
honor. `ArticleViewController` gives every `(function, bar)` pair its
own `UIBarButtonItem` instance (`barButtonItemInstances(for:on:)`,
alongside the six `@IBOutlet`-backed items retained for their
storyboard-only `userDefinedRuntimeAttributes`/action wiring), so a
`UIBarButtonItem` never has to sit in both
`navigationItem.rightBarButtonItems` and `toolbarItems` simultaneously
the way the pre-fix single-shared-instance model required. Anywhere a
mutation (image, `accLabelText`, `isEnabled`) needs to stay in sync
across whichever bar(s) currently show a function —
`updateUI()`, `toggleLoved(_:)`, `toggleGesturesLocked(_:)` — sweeps
`allBarButtonItemInstances(for:)`, which deduplicates the functions
whose top/bottom instance is actually the same object. `.prevNext`'s
two per-bar instances have independent `isEnabled` state
(`coordinator.isPrevArticleAvailable`/`isNextArticleAvailable` aren't
the same value), so `allPrevArticleBarButtonItems`/
`allNextArticleBarButtonItems` pick out just the prev- or just the
next-labeled item per bar rather than sweeping the whole pair together.
`showActivityDialog(_:)` anchors the share popover to whichever
`UIBarButtonItem` was actually tapped (`sender as? UIBarButtonItem`),
since `.action` can now be showing on either bar or both and only
`sender` reliably identifies which one the person touched.
`applyBottomToolbarStyle()` styles whatever `bottomToolbarItems()`
currently returns rather than a hardcoded native-bottom-function list,
so it no longer misses a non-native function placed on `.bottom` or
tints the wrong bar's instance for a function placed on both.

### Reordering

Display order is now persisted per bar, not hardcoded.
`AppDefaults.toolbarFunctionOrder(for:)`/`setToolbarFunctionOrder(_:for:)`
back two `[String]` keys (`toolbarTopFunctionOrder`/
`toolbarBottomFunctionOrder`, an array of `ToolbarFunction.rawValue`),
registered in `registerDefaults()` from
`AppDefaults.defaultToolbarFunctionOrder(for:)` — `[theme,
tableOfContents, find, prevNext, lock, annotations, settings,
checkForUpdates]` on `.top`, `[read, star, heart, nextUnread, action]`
on `.bottom`, each followed by any remaining case not in that native
list — so a fresh install's rendering is unchanged from before this key
existed. `toolbarFunctionOrder(for:)` decodes the stored rawValue array
back into `ToolbarFunction`, silently dropping any string that no
longer maps to a case, and appends (in `defaultToolbarFunctionOrder(for:)`
order) any `ToolbarFunction` missing from the stored array — covering a
case added after someone already saved a custom order, and a first run
before `registerDefaults()` has populated the key.
`ArticleViewController.displayOrder(for:)`, `ToolbarPreviewCell.configure(bar:)`,
and this screen's Functions-section row lookup all call this one
property now, replacing what were three independent hardcoded-array
copies (two of which had already drifted into separate literals with no
shared source) with a single source of truth. Reorder handles
(`.reorder()` `UICellAccessory`) exist only on the Functions section —
the Overflow section's candidate list has no rendering-order meaning of
its own, since the overflow *menu* itself is built by filtering the
Functions section's order down to overflow-flagged functions, so
reordering Functions already reorders the overflow menu for free.

The drag itself is driven by `UICollectionViewDragDelegate`/`DropDelegate`
(`ToolbarsCustomizerViewController+Drag.swift`/`+Drop.swift`), not the
older long-press `installsStandardGestureForInteractiveMovement` system
— a `.reorder()` accessory is a handle for the former, and only starts a
drag once `itemsForBeginning` hands back a `UIDragItem`;
`collectionView.dragInteractionEnabled = true` on its own, with no drag
delegate, never begins a drag at all. An earlier version of this screen
set `dragInteractionEnabled` without implementing either delegate and
relied on the data source's `canMoveItemAt`/`moveItemAt` instead, which
belongs to the long-press-only system `dragInteractionEnabled`
supersedes rather than composes with — those two overrides were dead
code (never called), and reordering silently did not work as a result.
`+Drop.swift`'s `performDropWith` now writes the reordered array through
`AppDefaults.setToolbarFunctionOrder(_:for:)` directly and drives the
visual move via `performBatchUpdates`, rather than relying on
`moveItemAt` to do either.

### Reset

A trailing "Reset" button, scoped to whichever bar the segmented control
currently has active — this screen already frames everything
per-`activeBar`, so "Reset" reads as "reset the bar I'm looking at," not
both at once (flagged as a judgment call worth confirming with product,
since a person could just as reasonably expect "Reset" to mean
everything). Matches the one existing reset affordance in Settings
(`ArticleThemeListView.resetToThemeDefaults()`): resets immediately, no
confirmation alert — though a toolbar reset arguably loses more (a
custom order plus placements) than that screen's theme-color reset does,
so this convention match is also worth a second opinion.
`AppDefaults.resetToolbarDefaults(for:)` removes (not overwrites) that
bar's on-disk keys — every `toolbarFunctionKeys[fn][bar]` inline/overflow
pair for all 13 functions, that bar's `toolbarTopUseOverflowMenu`/
`toolbarBottomUseOverflowMenu` key, and that bar's
`toolbarTopFunctionOrder`/`toolbarBottomFunctionOrder` key — so the
default only has to be correct in `registerDefaults()` (placement/overflow)
and `defaultToolbarFunctionOrder(for:)` (order), not duplicated a third
time. `UserDefaults.removeObject(forKey:)` posts
`.didChangeNotification` on `.standard`, so this screen's existing
generic-notification reload picks the reset up with no additional
wiring.
