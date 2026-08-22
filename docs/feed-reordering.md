# Feed reordering

Manual drag-to-reorder for feeds within a container (an account's top
level, or within a single folder). See `settings-screen.md`'s
"Reordering" section for the unrelated toolbar-customizer reorder
feature — this doc is about the sidebar feed list, not that screen.

## `OrderedSet<Feed>` and where it lives

`Modules/RSCore/Sources/RSCore/OrderedSet.swift` defines
`OrderedSet<Element: Hashable>`, a `Set`-like collection that preserves
insertion order. It matches `Set`'s membership semantics — inserting an
already-present element is a no-op that leaves it at its existing
position — while adding `insert(_:at:)`, the positional-insert operation
a bare `Set` had no way to express. Unit tests:
`Modules/RSCore/Tests/RSCoreTests/OrderedSetTests.swift`.

`OrderedSet` is deliberately not `Sendable`, not even conditionally on
`Element: Sendable`. `Feed` is `@MainActor`-isolated and its `Hashable`
conformance is therefore main-actor-isolated too; the compiler cannot fit
an isolated `Hashable` witness into a `Sendable` conformance's
requirements, so `OrderedSet<Element: Hashable>: Sendable where Element:
Sendable` fails to build the moment `Element` is actually `Feed` — this
was caught by CI, not by re-reading the type in isolation. `Container`
and every call site that touches `topLevelFeeds` are already
`@MainActor`-isolated, so dropping `Sendable` costs nothing in practice.

## `Container.topLevelFeeds` type change

`Container.topLevelFeeds` (and both conformers' backing storage,
`Account.topLevelFeeds`/`Folder.topLevelFeeds`) changed from `Set<Feed>`
to `OrderedSet<Feed>`. Because `OrderedSet` implements
`insert`/`contains`/`formUnion`/`subtract`/`Sequence`/`Collection`, most
call sites were unaffected. One call site needed a real change beyond
the type swap:

- `Folder.replaceTopLevelFeeds(_:)`'s parameter type changed to
  `OrderedSet<Feed>`. It has no callers anywhere in the tree today, so
  this was a signature-only change.

`Container.folders` (and both conformers' backing storage) later also
changed from `Set<Folder>?` to `OrderedSet<Folder>?`, as part of nested
folders — see `docs/nested-folders.md`, which also covers why
`Folder.flattenedFeeds()`'s override was removed entirely rather than
updated in place: the `Container` protocol extension's default (which
now recurses into subfolders) became the correct implementation once
folders can nest.

## OPML order fix

Both `OPMLString` implementations (`Account.swift`, `Folder.swift`)
previously called `topLevelFeeds.sorted()`, which re-sorted feeds
alphabetically on every OPML write regardless of manual order — meaning
a reorder would appear to work in-session and then silently revert to
alphabetical on next launch, since OPML is the persistence layer and
load order comes from OPML document order. Both now do a plain
`for feed in topLevelFeeds` instead, writing the container's own order.
`Account.OPMLString`'s `folders!.sorted()` was fixed the same way as
part of folder reordering (see "Folder order" below) — it's no longer
alphabetical either.

## The reorder operation

### Sidebar row order

`SidebarTreeControllerDelegate.childNodesForContainerNode` used to build
one combined feeds+folders array and alphabetize the whole thing via
`sortedAlphabeticallyWithFoldersAtEnd()` (folders forced last regardless
of name, feeds alphabetized among themselves). It now splits the built
node list into a feed-representing subsequence and a folder-representing
subsequence, **both** left in the container's own (manually-ordered)
order — folders are no longer alphabetized, see "Folder order" below —
then concatenates feeds + folders. This preserves the invariant that
every feed node precedes every folder node within one container's own
`childNodes` — depended on by the drop-handler's index math below.
`TreeController.rebuildChildNodes` trusts the delegate's order completely
(no independent resort at the tree layer), so this is the only place the
fix needs to live for the visible sidebar order to update.

### Computing drop position

A flat collection-view `IndexPath.row` is not a reliable proxy for
"position within this container's feeds," because an expanded folder's
children can be interleaved into the flat row list between one
container's rows and the next. `MainFeedCollectionViewController+Drop.swift`
instead computes position from the `Node` tree directly:
`destNode.parent?.indexOfChild(destNode)`, which is exact and needs no
offset arithmetic — this works only because feed nodes always precede
folder nodes among a container's children (the invariant above).

`targetIndex` is computed only for the ordinary reorder gesture (dropping
onto a specific feed row); it's left `nil` for the folder-drop case
(dropping onto a folder row to file the feed into it), where position
within the folder isn't implied by the gesture and the existing
append-to-end behavior via `addFeedToTreeAtTopLevel(_:at:)` with a `nil`
index is correct.

### `addFeedToTreeAtTopLevel(_:at:)`

`Container` now declares `addFeedToTreeAtTopLevel(_ feed: Feed, at index:
Int?)`, with a protocol-extension default (`addFeedToTreeAtTopLevel(_:)`
→ `addFeedToTreeAtTopLevel(_:at: nil)`) so the many existing unpositioned
call sites across the tree don't need touching. `Account` and `Folder`'s
implementations: `nil` index appends (`topLevelFeeds.insert(feed)`,
unchanged behavior); non-nil index inserts positionally
(`topLevelFeeds.insert(feed, at: index)`).

### `AccountDelegate.moveFeed`'s `targetIndex` parameter

`AccountDelegate.moveFeed`/`LocalAccountDelegate.moveFeed`/
`Account.moveFeed(_:from:to:targetIndex:completion:)` all gained a
`targetIndex: Int?` parameter, threaded from the drop handler through to
`addFeedToTreeAtTopLevel(_:at:)` on the destination container.
`LocalAccountDelegate.moveFeed` no longer needs a same-container special
case to *reject* the move — the old
`MainFeedCollectionViewController+Drop.swift`'s `moveFeedInAccount` had a
`guard sourceContainer !== destinationContainer else { return }` early
return that silently no-op'd same-container drags (the actual reorder
gesture). That guard is removed; a same-container drop with a
`targetIndex` is now treated as an ordinary reorder.

## Folder order

Folders are now reorderable the same way feeds are — see
`docs/nested-folders.md` for the full mechanism (`Account`/
`Folder.addFolderToTree(_:at:)`, `Account.reorderFolder(_:toIndex:)`,
`AccountDelegate.moveFolder`, and the drop handler's folder-drag branch).
This was originally a deliberate v1 scope decision to ship feed
reordering alone; folder reordering (and nesting) followed as a
subsequent piece of work, at which point `Container.folders` also
switched from `Set<Folder>` to `OrderedSet<Folder>` (see above) and both
`Account.OPMLString`'s `folders!.sorted()` and
`SidebarTreeControllerDelegate`'s folder-subsequence sort (described
above) stopped alphabetizing.

## Upgrade path for existing users

No migration code. Every existing user's on-disk OPML was already
alphabetical (written by the old, alphabetically-sorting writer), so on
first load after this ships, `topLevelFeeds` is constructed from OPML
document order that happens to already be alphabetical. Feeds simply
continue to appear alphabetical until manually reordered for the first
time.

## Backup/restore feed order

Export: `BackupManager.exportBackup` copies `Subscriptions.opml` as a raw
file copy rather than regenerating it, so once the OPML fix above lands,
export carries manual order through automatically with no further work.

Restore: `Account.addOPMLItems` calls `newFeed(with:)` unconditionally for
every OPML entry and relies on `OrderedSet<Feed>.insert(_:)`'s no-op-on-
duplicate behavior for de-dup. Net effect: restoring onto an account with
zero pre-existing feeds gets correct order for free (every entry is
genuinely new, so `addFeedToTreeAtTopLevel`'s natural sequential-append
produces the OPML's implied order). Restoring onto an account with any
pre-existing feeds leaves their positions untouched, regardless of what
order the backup implies — this is a deliberate decision, matching
`docs/backup-restore.md`'s existing conservative,
never-destructively-overwrite posture for every other merge rule in that
file, and requires no code change since `addOPMLItems`'s current
no-op-on-duplicate behavior already produces exactly this outcome.
