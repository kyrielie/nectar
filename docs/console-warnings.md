# Console warnings: what's fixed, what isn't

Catalogs the recurring Auto Layout / UIKit console warnings seen during
simulator runs, split into what was app-code-caused and fixed, and what
was investigated and found to be outside app code's control. Written up
so a future pass doesn't re-investigate the same warnings from scratch,
and doesn't mistake an unfixable one for a regression.

## Fixed: `RefreshProgressView` zero-width first-layout conflict

Pre-iOS-26 only. `RefreshProgressView(frame: .zero)` used as a
`UIBarButtonItem(customView:)` (`MainFeedCollectionViewController.swift`,
`MainTimelineModernViewController.swift`) let UIKit bridge that `.zero`
starting frame into an internal `'UIView-Encapsulated-Layout-Width'
... == 0` constraint, which briefly fought the bar's own leading/trailing
pins on the very first layout pass. Fixed by seeding both instances with
a nonzero placeholder frame (`CGRect(x: 0, y: 0, width: 1, height: 1)`)
instead of `.zero`; the real (label-driven) width still takes over once
layout runs.

Does not apply to iOS 26 devices/simulators -- see below.

## Fixed: `ArticleViewController`'s `fullScreenTapZone` width==150 conflict

`ArticleViewController.swift`'s `fullScreenTapZone` (the transparent
title-bar tap target that toggles chrome) had a `.required`
`widthAnchor.constraint(equalToConstant: 150)`. The system's own
`_UINavigationBarTitleControl` bridges its *actual* available title width
into a required constraint of its own (observed varying between ~83pt and
~143pt depending on layout state), which is always narrower than 150 and
always wins, so the app's `== 150` constraint was broken on every layout
pass that resized the title area. Changed to
`lessThanOrEqualToConstant: 150` -- the tap zone still gets up to 150pt
when available, without contending with the system's own width constraint
at all. The view's width isn't left ambiguous by dropping to `<=`: the
system's leading/trailing constraints on the title control already pin it
exactly; the `<=` is just a non-binding upper bound.

## Not fixable from app code: iOS 26 `ButtonWrapper`/`_UIModernBarButton` width==0 warnings

```
Unable to simultaneously satisfy constraints...
_TtC5UIKitP33_...ButtonWrapper.width == _UIButtonBarButton.width (active)
'IB_Leading_Leading' H:|-(N)-[_UIModernBarButton] (active)
'IB_Trailing_Trailing' H:[_UIModernBarButton]-(N)-| (active)
'UIView-Encapsulated-Layout-Width' ...ButtonWrapper.width == 0 (active)
```

Initially suspected (and partially, incorrectly, attributed to)
`RefreshProgressView`'s customView usage -- see the entry above. That
diagnosis doesn't hold up under iOS 26: `MainTimelineModernViewController
.updateToolbarProgressView` returns immediately when `#available(iOS 26,
*)`, its only caller of `rebuildToolbarItems()` (which is the only place
`refreshBarItem` is ever added to `toolbarItems`) is itself gated behind
`#unavailable(iOS 26)`, and `MainFeedCollectionViewController
.configureCurrentActivityButton()` only wires `refreshProgressView` as a
customView in the iOS-26-unavailable branch -- under iOS 26 it uses a
plain image-based `currentActivityButton` instead. None of the code paths
that use `RefreshProgressView` as a bar-button customView execute on iOS
26 at all, yet this warning persists unchanged on an iOS 26 simulator.

`ButtonWrapper`, `_UIModernBarButton`, and `_UIButtonBarButton` do not
appear anywhere in app source (confirmed by search) -- they're
Apple-private classes from iOS 26's toolbar redesign. Every bar button
item actually present at the points in the log where this fires
(`markAllAsReadButton`, `nextUnreadButton`, `filterButton`,
`navigationItem.searchBarPlacementBarButtonItem`, `currentActivityButton`)
is a plain system `UIBarButtonItem` with no custom view and no app-supplied
constraint for the internal wrapper to conflict with. The wrapping and the
`width == 0` constraint are both internal to UIKit's own iOS 26
first-layout-pass bridging for the new button style, not something app
code participates in constructing.

**Status:** treat as a known iOS 26 SDK first-layout artifact, not an app
bug. Worth an Apple Feedback Assistant report; not a target for further
app-side workarounds until/unless a later iOS 26 seed changes this or
Apple provides a documented mitigation.

## Investigated, not yet fixed: large-title snapshot warning

```
Snapshotting a view (..., _UINavigationBarLargeTitleView) that has not
been rendered at least once requires afterScreenUpdates:YES.
```

No app code calls `snapshotView`/`resizableSnapshotView` anywhere
(confirmed by search) -- this is UIKit's own navigation-transition
machinery snapshotting a view before it's completed a render pass.
Observed firing right after `MainFeedCollectionViewController
.viewWillAppear`, inside the same state-restoration navigation sequence
(`SceneCoordinator.restoreWindowState` ->
`restoreSelectedSidebarItemAndArticle` -> `selectArticle`/
`rootSplitViewController.show(...)`) that already has extensive in-code
comments (`SceneCoordinator.swift`, around
`restoreSelectedSidebarItemAndArticle`) documenting a *harder*,
previously-fixed crash from the same root cause: driving split-view
transitions before the window's first layout pass. That crash was fixed
by deferring the article-selection branch to
`DispatchQueue.main.async`; this warning looks like the same class of
problem resurfacing on a different branch of the same restoration chain
(possibly `rootSplitViewController.show(.primary)` reached via
`selectSidebarItem`, but not confirmed).

**Status:** not fixed. Given this code path's documented history of a
real crash from a similar-looking timing issue, and that the exact
triggering `show()`/transition call hasn't been pinned down from the log
alone, this needs a targeted on-device trace (breakpoint on
`-[UIView(UIViewRenderingSupport) snapshotViewAfterScreenUpdates:]-adjacent
transition calls, or Instruments' Core Animation instrument during a cold
launch with a restored article selection) before proposing a change --
not a good candidate for a guess-and-check fix in this area.

## Not app-caused: `BadgeColorPalettePreviewCell` transient height warning

```
Warning once only: Detected a case where constraints ambiguously suggest
a height of zero for a table view cell's content view...
Cell: <Nectar.VibrantBasicTableViewCell: ...>
```

Expected, by design -- see `BadgeColorPalettePreviewCell.swift`'s own
`configure()` comments. A fixed placeholder collection-view height (100)
is swapped for a measured real height after `layoutIfNeeded()`; the
transient conflict during that one-frame swap is the documented tradeoff
of that approach, not a bug. No action needed.
