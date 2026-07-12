# Nectar: Loved Smart Feed Icon — Yellow Bookmark → Red Heart

Small, self-contained change. Two files, ~4 lines total. No macOS target to worry
about — this codebase carries some `#if os(macOS)` branches left over from
NetNewsWire upstream, but none of them are ever compiled for Nectar, so they're not a
constraint on where anything below gets placed.

## Current state

`Shared/SmartFeeds/LovedFeedDelegate.swift`:
```swift
var smallIcon: IconImage? {
	// TODO: add a heart-icon asset catalog entry (e.g. Assets.Images.lovedFeed)
	// and point this at it. Asset catalog contents aren't part of this patch
	// series since they're not diffable as text.
	Assets.Images.starredFeed
}
```
This borrows the Starred smart feed's icon as a placeholder — there's already a TODO
flagging exactly this gap. `Assets.Images.starredFeed` (`Shared/Assets.swift`):
```swift
static let starredFeed = IconImage(starClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: Assets.Colors.star)
```
`starClosed` is SF Symbol `bookmark.fill`; `Assets.Colors.star` is a named color
asset (`starColor`, yellow). That's the "yellow bookmark."

`Shared/Assets.swift` also already defines a heart icon pair, added in an earlier
fork phase for the article toolbar's loved button, sitting in the same file:
```swift
// Phase 5/6 fork additions: Loved toolbar/action icons and the Theme
// nav-bar icon. Symbol-backed like the rest of this section pending a
// dedicated asset catalog entry (not part of this text-only patch series).
static let heartOpen = RSImage(symbol: "heart")!
static let heartClosed = RSImage(symbol: "heart.fill")!
```
No reason to redeclare the symbol — `heartClosed` is right there and already used
elsewhere for the same concept (loved = filled heart).

## The change

**1. `Shared/Assets.swift`** — add a new `IconImage` constant next to `heartOpen`/
`heartClosed`, in that same "Phase 5/6 fork additions" cluster:
```swift
static let lovedFeed = IconImage(heartClosed, isSymbol: true, isBackgroundSuppressed: true, preferredColor: RSColor.systemRed)
```

**2. `Shared/SmartFeeds/LovedFeedDelegate.swift`** — point `smallIcon` at it and drop
the resolved TODO:
```swift
var smallIcon: IconImage? {
	Assets.Images.lovedFeed
}
```

That's the entire functional change.

## Color: `.systemRed` now, named asset later (optional)

`Assets.Colors.star` is a bespoke named color asset (light/dark-aware), not a raw
system color. Matching that pattern properly for the heart would mean adding a new
`lovedColor` asset in the asset catalog — real Xcode work, not something a text patch
can do (same reason the icon itself has been sitting as a TODO). `RSColor.systemRed`
is a reasonable stand-in in the meantime: it's already an established token elsewhere
in the codebase (delete actions, error states), so this isn't a one-off color pick.

If a bespoke red is wanted later (to match Nectar's palette rather than the flat
iOS system red, or to tune it per light/dark mode independently), that's a follow-up:
add a `lovedColor` asset alongside `starColor`, then swap `RSColor.systemRed` for
`Assets.Colors.loved`. Not needed for this change.

## Verify

- Loved smart feed row in the sidebar/Bookshelves list shows a filled red heart
  instead of a yellow bookmark.
- Starred smart feed is untouched — it still uses `starClosed`/`Assets.Colors.star`
  directly, unaffected by this change since `lovedFeed` is a new, separate constant.
- Article toolbar's existing heart button (`heartBarButtonItem`,
  `ArticleViewController.swift`) is untouched — it references `Assets.Images.heartOpen`/
  `.heartClosed` directly for its filled/outline toggle, not `lovedFeed`, so this
  change doesn't alter its (currently untinted, default system tint) appearance.
