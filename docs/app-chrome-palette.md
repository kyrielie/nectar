# App chrome color pipeline (Accent Color / Surface Palette)

How native UIKit chrome (icons, bars, list/settings backgrounds) gets
tinted, independent of the article-reader theme pipeline documented in
`article-color-pipeline.md` — a "Slate" surface palette and a light
article theme can legitimately show different chrome colors at the same
time, that's intended, not a bug to reconcile.

- **Accent Color** (`Assets.Colors.primaryAccent`/`.secondaryAccent`) tints
  icons and progress indicators.
- **Surface Palette** (`SurfacePalette`, `AppDefaults.shared.surfaceTint`)
  tints chrome surface backgrounds as a coordinated set. The Swift type is
  `SurfacePalette`; the `AppDefaults` property, `UserDefaults` key, and
  notification name are still spelled `surfaceTint`/`.surfaceTintDidChange`
  — that's a deliberate leftover from before the type was renamed from
  `SurfaceTint`, kept to avoid a defaults migration, not an inconsistency to
  "fix." `.default` falls back to the existing asset-catalog colorset value
  for each field, same contract `AccentColor.default` uses. Five cases ship
  today: `.default`, `.slate`, `.sepia`, `.forest`, `.berry`.
- **Toolbar Style is a separate, three-way choice layered on top of Surface
  Palette** — see the dedicated section below (`ToolbarStyle`). A
  non-default Surface Palette does not, by itself, guarantee a tinted top
  nav bar or bottom toolbar; check that setting too before assuming the
  palette alone controls it.

## SurfacePalette.HexSet: one struct, two appearances, eight fields

Each non-default `SurfacePalette` case supplies a `lightHexSet` and a
`darkHexSet` (both `nil` for `.default`), each a complete `HexSet` of eight
hex-string fields. Every field has a matching `Assets.Colors` accessor that
takes an explicit `UITraitCollection` and branches light/dark off
`traitCollection.userInterfaceStyle`, falling back to the pre-existing
asset-catalog colorset of the same base name when the resolved hex is `nil`
(the `.default` case) or fails to parse:

| `HexSet` field | `Assets.Colors` accessor | Used for |
| --- | --- | --- |
| `barBackground` | `barBackground(for:)` | `ArticleSearchBar`'s bar fill |
| `vibrantText` | `vibrantText(for:)` | Text drawn on top of a tinted bar/surface |
| `fullScreenBackground` | `fullScreenBackground(for:)` | Full-screen transition backdrop (`ImageTransition`) |
| `navigationBarBackground` | — (consumed directly by `SurfacePaletteNavigationBarAware`) | `UINavigationBarAppearance.backgroundColor` |
| `navigationBarTint` | — (consumed directly by `SurfacePaletteNavigationBarAware`) | Nav bar title/back-button/large-title tint |
| `settingsBackground` | `settingsBackground(for:)` | Backdrop behind settings/list table and collection views |
| `settingsCellBackground` | `settingsCellBackground(for:)` | Individual cell fill *inside* that backdrop |
| `listBackground` | `listBackground(for:)` | Feed list + timeline container backdrop |

`navigationBarBackground`/`navigationBarTint` are only actually applied
when `AppDefaults.shared.toolbarStyle == .tinted` — see below; the other
six fields are unconditional. The same two fields are also reused, as-is,
for the bottom `UIToolbar`'s fill/tint under `.tinted` — see "The bottom
`UIToolbar`" below.

The `settingsBackground`/`settingsCellBackground` pair (and the
`listBackground`/`settingsCellBackground` pair) exist specifically so a
palette can keep a **container** and the **cells drawn on top of it**
visually distinct — the cell color is always the lighter, more-legible one
of the pair in both appearances, e.g. Slate dark's `listBackground` is
`#16191E` against a `settingsCellBackground` of `#262B33`. Any new
card/cell/row that sits on top of a `listBackground` or `settingsBackground`
surface should read `settingsCellBackground`, not re-use the container's
own color — using the same color for both makes the row visually disappear
into its container instead of standing out, and reads as broken (not merely
flat) once a non-default palette is active. `MainTimelineCell` establishes
this pattern for timeline cards; `MainFeedCollectionViewCell`/
`MainFeedCollectionViewFolderCell` follow it for feed-list rows.

## Live-update pipeline shape

Setting `AppDefaults.shared.accentColor`/`.surfaceTint` posts
`.accentColorDidChange`/`.surfaceTintDidChange` **synchronously** (the
setter calls `NotificationCenter.default.post` directly, on the same
thread, before the setter returns), an observer forces a repaint, and the
repaint reads `Assets.Colors.*` fresh — these are deliberately non-cached,
live per-read properties, not resolved once and stored. Setting
`AppDefaults.shared.toolbarStyle` also posts `.surfaceTintDidChange` (not a
separate notification — see below), so it reuses the exact same observer
list and synchronous-post behavior as a Surface Palette change. Unlike
Accent Color/Surface Palette, though, `toolbarStyle`'s `.blend` state also
depends on the current article theme and any per-theme override, neither
of which `.surfaceTintDidChange`/`.accentColorDidChange` cover — see
"Live-update for `.blend`" below.

The synchronous-post detail matters for any screen that changes the
palette from inside a `UITableViewDelegate`/`UICollectionViewDelegate`
selection callback (`didSelectRowAt:`, etc.): setting
`AppDefaults.shared.surfaceTint` there re-enters the same view controller's
own `.surfaceTintDidChange` observer *before* `didSelectRowAt:` reaches any
code after the assignment. If that observer and the selection handler's own
follow-up code both call `reloadSections`/`reloadData` on the section
containing the just-tapped row, UIKit's post-selection bookkeeping
(restoring the checkmark/highlight after the delegate call returns) can run
against a section that was torn down and rebuilt twice underneath it,
leaving the checkmark on the previously-selected row instead of the one
just tapped. `ColorPaletteTableViewController` and
`AccentColorTableViewController` both guard against this the same way: a
`isHandling*Selection` flag suppresses the notification-driven reload while
the selection handler's own (single, combined) `reloadSections` call is in
flight, so the row's own section is only ever rebuilt once per tap. Any new
screen that both listens for `.surfaceTintDidChange`/`.accentColorDidChange`
*and* changes that same default from its own selection handling needs the
same guard, not just a same-section double-reload "coincidentally working."

Current observer list for each notification, kept here explicitly so the
next person adding a Surface-Palette-consuming view knows to add an
observer too:

**Accent Color** (`.accentColorDidChange`): `SceneDelegate`,
`MainFeedCollectionViewController`, `MainTimelineModernViewController`,
`AccentColorTableViewController`, `ArticleViewController` (repaints both its
nav bar and bottom toolbar via `applyToolbarStyle()` — added along with its
`.surfaceTintDidChange` observer below; previously this screen relied only
on the generic, non-synchronous `UserDefaults.didChangeNotification`, which
produced stale top-nav-bar colors on a live in-app palette switch, fixed
only by a full `viewDidLoad` re-run from exiting and re-entering the
article).

**Surface Palette** (`.surfaceTintDidChange`): `ArticleSearchBar`, which
bakes `barBackground` into a `CGColor` once in `didMoveToSuperview()` and so
needs its own observer to repaint on a live change (added as part of the
same fix that gave the article pipeline (`article-color-pipeline.md`) its
own live-invalidation hook — same underlying shape, "new machinery added
without the free live-update behavior a dynamic system color would have
given it"); `MainFeedCollectionViewController`, which repaints
`listBackground` and reloads the collection view so each row's
`settingsCellBackground` fill gets recomputed; `MainTimelineModernViewController`,
same reasoning; `ColorPaletteTableViewController`, `AccentColorTableViewController`,
and `SettingsBackgroundPalette`/`SurfacePaletteAware` (SwiftUI-facing), which
repaint the Settings screens' own `settingsBackground`/
`settingsCellBackground` fills; `SettingsViewController`; `ArticleViewController`,
which repaints both its nav bar and bottom toolbar the same way the two
screens above do (`toolbarStyle`'s setter reuses this exact notification,
not a dedicated one — see below). `Vibrant*` views
(`VibrantLabel`/`VibrantButton`/`VibrantTableViewCell`) deliberately don't
observe it, since they already re-read `.vibrantText` on every
highlight/selection state toggle, which happens far more often than a
Surface Palette change — the staleness window is bounded by the next
interaction, not indefinite the way `ArticleSearchBar`'s baked `CGColor`
was. `ImageTransition` deliberately doesn't observe it either, since it
reads `.fullScreenBackground` fresh at the start of each transition, which
is already "live" for practical purposes.

**Live-update for `.blend`:** `toolbarStyle == .blend` sources its color
from `ArticleResolvedColors.current(isDark:)` — the current article theme
plus any per-theme override — inputs the `.surfaceTintDidChange`/
`.accentColorDidChange`/trait-change observers above don't cover.
`ArticleViewController` additionally observes
`.CurrentArticleThemeDidChangeNotification` (fires when the selected
`.nnwtheme` changes) and `.articleThemeOverridesDidChange` (fires when a
per-theme/override background color changes in Settings), both calling
`applyToolbarStyle()`, so switching themes or editing an override color
with an article already open repaints `.blend`'s toolbar color immediately
instead of leaving it stale until the article is re-entered.
`MainFeedCollectionViewController`/`MainTimelineModernViewController` don't
observe either notification — they have no article/theme concept and don't
support `.blend` at all (see "Toolbar Style" below), so there's nothing on
those screens for these notifications to invalidate.

**Open investigation, not yet resolved:** `applySurfacePaletteNavigationBarAppearance()`
was carrying temporary diagnostic logging ("top-toolbar-colors-wrong-on-live-switch
investigation") tracing which adopting screen actually repaints, and when,
during a live in-app palette switch. The logging has been removed as part
of a vibecoding cleanup pass (it was cheap to re-add and had accumulated
alongside other stale scaffolding) — the underlying question is still
open and is now tracked in `docs/investigate-later.md` instead of inline
logging. See that doc for the working theory (same observer-list gap the
Accent Color paragraph above describes) and what re-adding the logging
would take if this needs to be picked back up.

`SurfacePalette.HexSet` originally also carried `controlBackground` and
`sectionHeader` fields; both were removed (along with the corresponding
`Assets.Colors` properties) once grep confirmed zero non-definition call
sites for either — dead fields from early in Surface Palette's design, never
wired to an actual consumer. If a future engineer finds this file compared
against an old planning doc and wonders why `HexSet` looks incomplete,
that's why.

## Toolbar Style: `ToolbarStyle`

Whether `SurfacePaletteNavigationBarAware` screens apply any of the
palette's or the article's colors at all — and, on `ArticleViewController`,
whether its bottom `UIToolbar` does too — is controlled by
`AppDefaults.shared.toolbarStyle` (`ToolbarStyle`, `Key.toolbarStyle`,
default `.system`), picked via a three-row checkmark section in
`ColorPaletteTableViewController` (the same screen as the Surface Palette
picker). This is a separate concern from *which* palette is active, and
from the article theme:

- **`.system`** (the fresh-install default): every `SurfacePaletteNavigationBarAware`
  screen calls `resetToSystemNavigationBarAppearance()` — clears
  `standardAppearance`/`compactAppearance`/`scrollEdgeAppearance` and any
  explicit tint colors back to `nil`, so the nav bar falls back to the
  normal system cascade/dynamic color regardless of which Surface Palette
  is selected. This is deliberately the same reset path used for the
  `.default` palette case, not a second copy of similar logic. See "The
  scroll-edge/standard split" below for the one place this isn't simply
  "everything nil."
- **`.tinted`**: the normal tinted-appearance path runs, reading
  `navigationBarBackground`/`navigationBarTint` from the active palette's
  `HexSet` as described in the table above.
- **`.blend`**: a new path, only meaningful on a screen with an actual
  article on it (see "supportsBlendToolbarStyle" below) — fills the bar
  with the article's own resolved background/text color
  (`ArticleResolvedColors.current(isDark:)`, "Live-update for `.blend`"
  above) instead of a palette hex. Palette-independent: switching Surface
  Palette while `.blend` is active doesn't change the bar at all.

`ToolbarStyle`'s internal case names (`system`/`blend`/`tinted`) don't
match their UI labels ("Default"/"Blend"/"Tinted") verbatim — `system` is
used instead of `default` only because `default` collides with Swift's
`switch`/`case` keyword.

Setting `toolbarStyle` posts `.surfaceTintDidChange` (not a dedicated
notification), so it's picked up by the exact same observer list as an
ordinary Surface Palette change, listed above.

**One-time migration on existing installs:**
`AppDefaults.migrateToolbarStyleDefaultIfNeeded()`, called once from
`AppDelegate` at launch after `registerDefaults()`, exists because shipping
`toolbarStyle`'s `.system` default would otherwise silently strip the
tinted top bar from anyone who'd already turned the old
`useTintedNavigationBar` switch on (or who predates that switch but had
already chosen a non-`.default` Surface Palette) — that would read as a
regression, not a new opt-in. The migration is gated by its own one-shot
flag (`Key.hasMigratedToolbarStyleDefault`, distinct from the older,
now-unused `Key.hasMigratedNavigationBarTintingDefault`) and, the first
time it runs, sets `toolbarStyle = .tinted` if either the legacy
`useTintedNavigationBar` Bool key reads `true` or the person's current
`surfaceTint != .default`; a fresh install with neither legacy signal gets
the new `.system` default untouched. `useTintedNavigationBar` itself is no
longer backed by a live property — the key is renamed rather than reused
under a new type, since a `Bool` and a `String` sharing one
`UserDefaults` key would crash or silently fail to decode depending on
read order — but the raw key is still read directly here for upgraders.
The migration writes `Key.toolbarStyle` directly via `AppDefaults.store`
rather than through the `toolbarStyle` property setter, specifically to
avoid posting `.surfaceTintDidChange` to a view hierarchy that doesn't
exist yet this early in launch.

## Nav bar appearance: `SurfacePaletteNavigationBarAware`

`ArticleViewController`, `MainFeedCollectionViewController`, and
`MainTimelineModernViewController` all adopt
`SurfacePaletteNavigationBarAware` (`Shared/Extensions/`) and call
`applySurfacePaletteNavigationBarAppearance()` once from `viewDidLoad()`
and again from their own `.surfaceTintDidChange`/trait-change handlers
(`ArticleViewController` calls it, alongside its own bottom-toolbar
equivalent, via a combined `applyToolbarStyle()` — see "The bottom
`UIToolbar`" below). Under `.tinted`, the shared method builds an opaque
`standardAppearance`/`compactAppearance` from
`navigationBarBackground`/`navigationBarTint` (the bar once a large title
has collapsed, or in compact height), but branches on a protocol property,
`wantsTransparentScrollEdgeAppearance` (default `false`), for
`scrollEdgeAppearance` — the bar shown at the *top* of the content, before
any scrolling:

- `ArticleViewController` leaves it `false`: there's no card/list content
  behind the bar for it to blend with, so it wants the same opaque fill in
  every scroll state.
- `MainFeedCollectionViewController` and `MainTimelineModernViewController`
  override it to `true`: both sit on top of a scrolling list of cards/rows,
  and want the system's normal large-title behavior where the bar is
  transparent at the top and only opaque once content has scrolled
  underneath it, so the bar matches whatever's drawn there (the transparent
  sidebar "glass," or a timeline card's own `settingsCellBackground`,
  visible through it) instead of imposing a flat `navigationBarBackground`
  fill that reads as a mismatched strip at the top of the screen.

This split exists because `applySurfacePaletteNavigationBarAppearance()`
was extracted from `ArticleViewController`'s own (correct, always-opaque)
implementation and reused as-is by the other two screens; unconditionally
setting `scrollEdgeAppearance` to the same opaque `appearance` object as
`standardAppearance` regressed both of their previously-transparent top
edges. Any *future* screen adopting this protocol should think about which
side of that split it's on before assuming the default (`false`, opaque) is
correct — the wrong choice is silent (nothing crashes) and only shows up as
a color mismatch at the very top of the content.

**The scroll-edge/standard split, and the `.system`-state bugfix it
needed:** `resetToSystemNavigationBarAppearance()` (the `.system` path)
also branches on `wantsTransparentScrollEdgeAppearance`, mirroring the
`.tinted`/`.blend` paths' own split, rather than unconditionally nil-ing
`standardAppearance`/`compactAppearance`/`scrollEdgeAppearance` the way it
used to. The old unconditional-nil version had a real bug on
`ArticleViewController`: nil-ing `scrollEdgeAppearance` falls through to
`UINavigationBar`'s own OS default, which since iOS 15 is fully
*transparent* at scroll-offset-zero — exactly the state an article opens
into — distinct from `standardAppearance`'s opaque-blur OS default.
`ArticleViewController` wants a permanently opaque bar in every scroll
state (it has no card/list content behind the bar to blend with, the same
reasoning that gives it `wantsTransparentScrollEdgeAppearance == false`),
so this reset path now rebuilds the same opaque baseline
`configureWithDefaultBackground()` appearance for adopters with that
property `false`, and only nils everything for adopters (`MainFeed`/
`MainTimeline`) that actually want the transparent-until-scrolled system
look. `UIToolbar` has no standard/scroll-edge split, so this specific
failure mode doesn't have a toolbar equivalent — see "The bottom
`UIToolbar`" below for how its own `.system` state is defined instead.

**`supportsBlendToolbarStyle`:** a second protocol property (default
`false`) scoping `.blend` to screens that actually have an article to
blend with. `ArticleViewController` overrides it to `true`;
`MainFeedCollectionViewController`/`MainTimelineModernViewController` don't
override it, so `toolbarStyle == .blend` on those two screens falls back
to the same `.system` reset described above rather than painting from
`ArticleResolvedColors.current(isDark:)` — which would otherwise read a
color describing whichever article happened to be open elsewhere (or was
last open), not anything meaningfully tied to the feed list or timeline
itself. `.tinted` has no equivalent restriction and applies to all three
screens, matching its behavior from before `toolbarStyle` existed.

**`SurfacePalettePreviewCell`** (`iOS/Settings/SurfacePalettePreviewCell.swift`):
a live-rendered preview of the currently-selected `SurfacePalette`, built
in code rather than a storyboard prototype cell, registered and reloaded
by `ColorPaletteTableViewController` on the palette-change notification.
Reads `Assets.Colors.barBackground(for:)`/`vibrantText(for:)`/
`fullScreenBackground(for:)`/`settingsBackground(for:)`/
`settingsCellBackground(for:)`/`listBackground(for:)` directly rather
than re-deriving hex values from `AppDefaults.shared.surfaceTint` itself,
since those accessors already encode the fallback contract (`.default`
→ asset catalog) the preview needs.

## The bottom `UIToolbar`

`ArticleViewController`'s bottom toolbar (`navigationController?.toolbar`,
shown/hidden via `setToolbarHidden(_:animated:)`) had no appearance
customization at all before `toolbarStyle` — it only ever set
`toolbarItems` (the buttons). `SurfacePaletteNavigationBarAware` has no
bottom-toolbar equivalent (`MainFeedCollectionViewController`/
`MainTimelineModernViewController` don't have a bottom toolbar), so this is
new code on `ArticleViewController` itself, not an extension of the shared
protocol: `applyToolbarStyle()` calls both
`applySurfacePaletteNavigationBarAppearance()` (nav bar) and
`applyBottomToolbarStyle()` (this toolbar) together, from every place
either one used to be called alone, so the two bars can't drift out of
sync with each other. `UIToolbar` has no standard/scroll-edge split the
way `UINavigationBar` does — only `standardAppearance`/`compactAppearance`
to set, mirroring the nav bar's `.tinted`/`.blend` handling exactly (same
`navigationBarBackground`/`navigationBarTint` fields for `.tinted`, same
`ArticleResolvedColors.current(isDark:)` call — not a second one — for
`.blend`, so the two bars can never disagree on the article's resolved
color). Its `.system` state resets `compactAppearance` to `nil` (an
optional property, same as the nav bar's own reset) but reassigns
`standardAppearance` a fresh `UIToolbarAppearance()` rather than `nil`:
unlike `UINavigationItem.standardAppearance`, `UIToolbar.standardAppearance`
is **not optional** — `nil` doesn't type-check there at all, not a style
choice. A fresh, unconfigured `UIToolbarAppearance()` is that property's
own implicit default value on a toolbar nothing has ever touched (confirmed
by grep: zero `UIToolbarAppearance`/`standardAppearance` references
anywhere in the tree before this feature), so reassigning a new one is
what reproduces the untouched look.

`Assets.Colors`'s existing dark/light-branching properties
(`barBackground`, `vibrantText`, `fullScreenBackground`) resolve their
branch via `UITraitCollection.current`, which Apple documents as valid only
inside specific framework-invoked callbacks (drawing methods,
dynamic-color/image resolution, trait-change handlers) — undefined
elsewhere, and `Assets.Colors` is a bare `static var` namespace with no
view/window reference, called from places like
`ArticleSearchBar.didMoveToSuperview()` that aren't among those blessed
contexts. This is flagged as theoretical fragility in a doc comment on
`barBackground`, not yet confirmed as a reproducing bug on-device. The
article-background pipeline (`article-color-pipeline.md`) avoids the same
trap by reading a real view's `.traitCollection`
(`WebViewController.applyResolvedBackgroundColors`
reads `webView.traitCollection`) rather than the ambient current one — any
*new* `Assets.Colors` property should follow that pattern, taking an
explicit trait collection parameter, rather than copying the existing
three properties' pattern.
