# Nested folders

Folders can now contain other folders, up to 3 levels deep. Builds on
top of `docs/feed-reordering.md`'s `OrderedSet`/manual-order work — read
that first; this doc only covers what's specific to nesting.

## The depth cap

Nesting is capped at 3 levels (a top-level folder, its child, its
grandchild — no great-grandchild). The cap is enforced in three
independent places, each guarding a different way a folder could exceed
it:

- **OPML import** (`Account.addOPMLItems(_:into:container:depth:)`):
  a 4th-level named folder in the source document doesn't get created.
  Its own feeds (and, recursively, any further-nested folders' feeds)
  are flattened into the depth-3 folder instead of being silently
  dropped — see `flattenIntoContainer`.
- **`ensureFolder(withFolderNames:)`**: a path longer than 3 names is
  truncated to its first 3 segments before walking/creating the chain.
- **Drag-and-drop / `LocalAccountDelegate.moveFolder`**: rejects (throws
  `AccountError.invalidParameter`) a move that would push the dragged
  folder's deepest descendant past level 3. The check is
  `destinationDepth + 1 + folder.maxDescendantDepth <= 3`, where
  `destinationDepth` is the destination container's own depth (0 for an
  account, `pathNames.count` for a folder) and `maxDescendantDepth` is
  how many levels below the *dragged* folder its own subfolders already
  extend — so dragging a folder that itself has grandchildren can be
  rejected even if the drop target alone looks shallow enough.

The number 3 isn't a named constant shared across these three sites —
each computes/checks it locally (`let maxDepth = 3` in the OPML/
ensureFolder cases, a literal `<= 3` in the delegate). If the cap ever
changes, all three need updating together.

## `Folder.parent` and `pathNames`

`Folder` gained a `weak var parent: Container?` — the folder's own
container, either another `Folder` (nested) or the owning `Account`
(top-level). It's `weak` deliberately: the strong ownership chain runs
the other direction, `Account.folders`/`Folder.folders` (both
`OrderedSet<Folder>`) strongly own their children, so a strong `parent`
back-reference would create a retain cycle. `parent` is set explicitly
at every insertion call site (`Account`/`Folder`'s
`addFolderToTree(_:at:)`, `Container.ensureChildFolder(named:)`) rather
than kept in sync via a property observer — there's no single mutation
point on `OrderedSet` to hook.

`Folder.pathNames: [String]` walks `parent` up to the top and returns
the ancestor chain, ending with the folder's own `nameForDisplay`. Does
not include the account. This is the identity nested folders use in
place of a bare name wherever a single folder needs to be addressed
unambiguously — see the identifier section below for why a bare name
stopped being enough.

## Why folder identifiers needed a path, not just a name

Before nesting, a folder's name was unique enough within an account to
serve as its identity in `ContainerIdentifier.folder`,
`SidebarItemIdentifier.folder`, and persisted state
(`AppDefaults.expandedContainers`, `.foldersShowingReadArticles`,
`.addFeedFolderPath`). With nesting, two folders with different parents
can share a name ("Tech/News" and "Podcasts/News"), so both enum cases'
associated `String` (folder name) became `[String]` (folder path,
ancestor-first).

### Path encoding in persisted storage

`ContainerIdentifier.userInfo` is `[AnyHashable: AnyHashable]` in the
type signature, but every real persistence path it round-trips through
(`UserDefaults`, via `AppDefaults.expandedContainers`'s
`[[String: String]]` cast) only holds `String` values in practice.
`SidebarItemIdentifier.userInfo` is `[String: String]` outright — no
cast needed to see the constraint. Neither type can store a `[String]`
path as a dictionary value under these constraints, so both encode the
path as a single string, joined with a private separator
(`"\u{1}"`, a control character unlikely to appear in a real folder
name), under a new key (`"folderPath"`, replacing the old
`"folderName"`). `AppDefaults.foldersShowingReadArticles` needed the
same treatment for its own `[String: Set<String>]` →
`[String: Set<[String]>]` change, using a matching separator constant
(`AppDefaults.folderPathSeparator`).

The key rename (`folderName` → `folderPath`) is deliberate, not
cosmetic: it means old-format persisted `userInfo` (which has no
`folderPath` key at all) fails the `guard` in `init?(userInfo:)` cleanly
and returns `nil`, rather than being misinterpreted as a single-segment
path or crashing. No explicit migration code was written or is needed —
a `nil` decode just means that one persisted expanded-folder-state or
read-filter-state entry is dropped on first load after upgrading,
which is a fully acceptable, self-healing outcome for UI state (as
opposed to article/feed data, which has no equivalent silent-drop
tolerance).

### Path-based lookup: `existingFolder(withPath:)`

`Container.existingFolder(withPath:)` resolves a specific folder by its
full ancestor-to-self path, walking one segment at a time via
`folders?.first(where: { $0.nameForDisplay == segment })` at each level.
This is distinct from the pre-existing `existingFolder(with:)`, which
still does an unqualified, first-match, any-depth name search (used
where genuine ambiguity between same-named folders isn't a practical
concern). `AccountManager.existingContainer(with:)` and
`.existingFeed(with:)` (used by state restoration, deep links, and
`SceneCoordinator.handleSelectFeed`) now resolve `.folder` cases via
`existingFolder(withPath:)`.

## OPML import: the real flattening bug lived in `OPMLNormalizer`

`Account.addOPMLItems` alone recursing into nested `OPMLItem.children`
wasn't sufficient — `OPMLNormalizer.normalize`, which runs first (see
`Account.loadOPMLItems`), had its own independent flattening bug.

`normalize`'s `parentFolder` parameter, the `OPMLItem` that
newly-discovered feeds/folders should attach to, was previously only
ever set once: the *first* named folder encountered on the way down.
Every deeper level of recursion inherited that same `parentFolder`
instead of updating it to the folder currently being processed. The
practical effect: a document with `Parent > Child > Feed` produced a
`Parent` outline and a `Child` outline as if they were siblings, both
attached to the top level, with `Feed` re-parented one level higher
than the source document actually specified — nesting appeared to
"round-trip" only in the narrow sense that no data was lost, not in the
sense that structure was preserved.

The fix: `normalize` now passes `item` itself (the folder just
appended to `feedsToAdd`) as the new `parentFolder` at every level,
not only when `parentFolder` was previously `nil`. Deduplication (by
feed URL, one level at a time) and "unnamed folder folds its contents
up one level" both still work exactly as before — those behaviors
never depended on the buggy single-assignment pattern.

`Account.addOPMLItems(_:into:depth:)` then does its own straightforward
recursion on top of `OPMLNormalizer`'s now-correctly-nested output,
enforcing the depth-3 cap described above via `flattenIntoContainer`.

No separate on-disk migration was needed for this fix: folder structure
has no independent serialized representation — it's derived entirely
from `Subscriptions.opml` via `OPMLFile.load` →
`Account.loadOPMLItems` on every launch, and written back via
`Account.OPMLString`/`Folder.OPMLString` (`OPMLFile.saveToDiskIfNeeded`).
Fixing both the read path (`OPMLNormalizer`/`addOPMLItems`) and the write
path (`Folder.OPMLString` now also writes its own `folders`, not only
`topLevelFeeds`) together makes the round-trip self-consistent from the
next save onward.

## Drag-and-drop

`MainFeedCollectionViewController+Drop.swift`'s `performDropWith` gained
a second branch alongside the pre-existing feed-drag branch, keyed off
`dragNode.representedObject as? Folder`. Folder drags are same-account
only (no cross-account equivalent of `moveFeedBetweenAccounts` — a
`Folder`, unlike a `Feed`, isn't a value that makes sense to
recreate on a different account). Before calling
`moveFolderInAccount`, it checks `draggedFolder.isAncestor(of:
destinationFolder)` to reject dropping a folder into itself or one of
its own descendants (which would disconnect it from the tree — no
depth-cap check catches this case, since depth alone doesn't detect a
cycle).

`destination`, as resolved by the existing `destinationContainer`
closure, already correctly resolves to the target folder itself when
`isFolderDrop` is true (that closure's `destNode` is the folder's own
node in that case) — no special-casing was needed there for nesting to
work; this was verified by reading the closure rather than assumed.

`moveFolderInAccount` mirrors `moveFeedInAccount`: calls
`Account.moveFolder(_:from:to:targetIndex:completion:)`, which calls
`AccountDelegate.moveFolder`/`LocalAccountDelegate.moveFolder` (new,
alongside the pre-existing `moveFeed`), which does the actual
`removeFolderFromTree`/`addFolderToTree(_:at:)` pair after the
depth-cap check described above.

## Sidebar cell indentation

Both `MainFeedCollectionViewCell.indentationLevel` and the newly-added
`MainFeedCollectionViewFolderCell.indentationLevel` changed from a
binary 0/1 (only "is this feed inside a folder at all") to an arbitrary
non-negative depth, with the favicon leading constraint computed as
`16 + 16 * level`. A feed's level is its parent folder's own
`pathNames.count` (0 if the feed has no parent folder). A folder's own
level is `pathNames.count - 1` (0 for a top-level folder).

`MainFeedCollectionViewFolderCell` previously had no leading constraint
on its favicon at all in code — indentation wasn't a concept that
applied to folders before nesting existed. `Main.storyboard` did have a
*fixed* leading constraint on that view (`id="9l7-Qb-ElX"`, `leading =
16`), unlike the feed cell's storyboard entry, which genuinely has none
(matching that cell's existing "no leading constraint is set on the
storyboard" code comment). That fixed constraint was removed from the
storyboard so the new programmatic, depth-aware
`faviconLeadingConstraint` (added in `awakeFromNib`, mirroring the feed
cell's own pattern) doesn't conflict with it at runtime.

`MainFeedCollectionViewController`'s separator-inset closure, which
previously special-cased exactly `cell.indentationLevel == 1` to widen
the separator's leading inset, now checks `> 0` — any nested depth, not
only depth 1 — since depth is no longer binary.

## Delete/undo of a nested folder

`LocalAccountDelegate.removeFolder(with:)`/`.restoreFolder(folder:)`
previously always operated on `account` directly
(`account?.removeFolderFromTree(folder)`/`.addFolderToTree(folder)`),
which was correct back when every folder's parent was necessarily the
account. With nesting, that would have silently un-nested a folder on
delete-then-undo (`DeleteCommand`'s restore path): removing it from the
account's `folders` (a no-op, since a nested folder was never there)
while never removing it from its real parent folder, then restoring it
to the account's top level instead of back into its original parent.

Both methods now use `folder.parent` (falling back to `account` only if
`parent` is somehow `nil`) instead of always `account`. This works
without any protocol signature change because `removeFolderFromTree`
doesn't clear `folder.parent` — the weak reference is still valid after
removal, which is exactly what `restoreFolder` needs to put the folder
back in the right place. A deleted folder's own subfolders are
unaffected either way: they stay attached to the deleted folder's own
`folders`, so restoring the top-level deleted folder reattaches its
whole subtree intact.

## `existingContainers(withFeed:)` recursion

`Account.existingContainers(withFeed:)` (used by
`LocalAccountDelegate`'s `disallowFeedInMultipleFolders` check and the
Dinosaurs feature's per-feed container list) previously checked
top-level feeds plus one level of folders. With arbitrary nesting, a
feed several levels deep would have been invisible to this method. It
now recurses through `Folder.existingContainers(withFeed:)` (a new
matching method, not part of the `Container` protocol since every real
caller invokes it only on `Account`) at every level.
