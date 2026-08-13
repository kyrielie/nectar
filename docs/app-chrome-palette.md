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
- **Nav bar tinting is a separate opt-in gate on top of Surface Palette** —
  see the dedicated section below (`useTintedNavigationBar`). A
  non-default Surface Palette does not, by itself, guarantee a tinted nav
  bar; check that setting too before assuming the palette alone controls
  it.

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
when `AppDefaults.shared.useTintedNavigationBar` is on — see below; the
other six fields are unconditional.

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
`AppDefaults.shared.useTintedNavigationBar` also posts
`.surfaceTintDidChange` (not a separate notification — see below), so it
reuses the exact same observer list and synchronous-post behavior as a
Surface Palette change.

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
`AccentColorTableViewController`, `ArticleViewController` (repaints its nav
bar via `applySurfacePaletteNavigationBarAppearance()` — added along with
its `.surfaceTintDidChange` observer below; previously this screen relied
only on the generic, non-synchronous `UserDefaults.didChangeNotification`,
which produced stale top-nav-bar colors on a live in-app palette switch,
fixed only by a full `viewDidLoad` re-run from exiting and re-entering the
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
which repaints its nav bar the same way the two screens below do. `Vibrant*` views
(`VibrantLabel`/`VibrantButton`/`VibrantTableViewCell`) deliberately don't
observe it, since they already re-read `.vibrantText` on every
highlight/selection state toggle, which happens far more often than a
Surface Palette change — the staleness window is bounded by the next
interaction, not indefinite the way `ArticleSearchBar`'s baked `CGColor`
was. `ImageTransition` deliberately doesn't observe it either, since it
reads `.fullScreenBackground` fresh at the start of each transition, which
is already "live" for practical purposes.

**Open investigation, not yet resolved:** `applySurfacePaletteNavigationBarAppearance()`
and `ArticleViewController` currently carry temporary diagnostic logging
("top-toolbar-colors-wrong-on-live-switch investigation") tracing which
adopting screen actually repaints, and when, during a live in-app palette
switch. Remove once confirmed fixed and fold the finding into this doc.

`SurfacePalette.HexSet` originally also carried `controlBackground` and
`sectionHeader` fields; both were removed (along with the corresponding
`Assets.Colors` properties) once grep confirmed zero non-definition call
sites for either — dead fields from early in Surface Palette's design, never
wired to an actual consumer. If a future engineer finds this file compared
against an old planning doc and wonders why `HexSet` looks incomplete,
that's why.

## Nav bar tinting opt-in: `useTintedNavigationBar`

Whether `SurfacePaletteNavigationBarAware` screens actually apply
`navigationBarBackground`/`navigationBarTint` at all is gated by
`AppDefaults.shared.useTintedNavigationBar` (`Key.useTintedNavigationBar`,
default `false`), toggled via a switch in `ColorPaletteTableViewController`
(the same screen as the Surface Palette picker). This is a separate
concern from *which* palette is active:

- **Off** (the fresh-install default): every `SurfacePaletteNavigationBarAware`
  screen calls `resetToSystemNavigationBarAppearance()` — clears
  `standardAppearance`/`compactAppearance`/`scrollEdgeAppearance` and any
  explicit tint colors back to `nil`, so the nav bar falls back to the
  normal system cascade/dynamic color regardless of which Surface Palette
  is selected. This is deliberately the same reset path used for the
  `.default` palette case, not a second copy of similar logic.
- **On**: the normal tinted-appearance path runs, reading
  `navigationBarBackground`/`navigationBarTint` from the active palette's
  `HexSet` as described in the table above.

Setting `useTintedNavigationBar` posts `.surfaceTintDidChange` (not a
dedicated notification), so it's picked up by the exact same observer list
as an ordinary Surface Palette change, listed above.

**One-time migration on existing installs:**
`AppDefaults.migrateNavigationBarTintingDefaultIfNeeded()`, called once
from `AppDelegate` at launch after `registerDefaults()`, exists because
shipping `useTintedNavigationBar` defaulting to `false` would otherwise
silently strip the tinted top bar from anyone who'd already chosen a
non-`.default` Surface Palette before this setting existed — that would
read as a regression, not a new opt-in. The migration is gated by its own
one-shot flag (`Key.hasMigratedNavigationBarTintingDefault`) and, the
first time it runs, sets `useTintedNavigationBar = true` if and only if
the person's current `surfaceTint != .default`; a fresh install with no
prior palette choice gets the new `false` default untouched. The migration
writes `Key.useTintedNavigationBar` directly via `AppDefaults.store` rather
than through the `useTintedNavigationBar` property setter, specifically to
avoid posting `.surfaceTintDidChange` to a view hierarchy that doesn't
exist yet this early in launch.

## Nav bar appearance: `SurfacePaletteNavigationBarAware`

`ArticleViewController`, `MainFeedCollectionViewController`, and
`MainTimelineModernViewController` all adopt
`SurfacePaletteNavigationBarAware` (`Shared/Extensions/`) and call
`applySurfacePaletteNavigationBarAppearance()` once from `viewDidLoad()`
and again from their own `.surfaceTintDidChange`/trait-change handlers.
When `useTintedNavigationBar` is on, the shared method builds an opaque
`standardAppearance`/`compactAppearance` from
`navigationBarBackground`/`navigationBarTint` (the bar once a large title
has collapsed, or in compact height), but branches on a protocol property,
`wantsTransparentScrollEdgeAppearance` (default `false`), for
`scrollEdgeAppearance` — the bar shown at the *top* of the content, before
any scrolling:

- `ArticleViewController` leaves it `false`: there's no card/list content
  behind the bar for it to blend with, so it wants the same opaque fill in
  every scroll state, and already configures `scrollEdgeAppearance` opaquely
  itself before its first call to `applySurfacePaletteNavigationBarAppearance()`.
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
