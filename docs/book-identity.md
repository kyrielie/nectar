# Book identity (`bookKey`) and `BookStateTable`

How Nectar recognizes "the same book" across re-imports, re-extractions, and
duplicate collection feeds, and where that identity's state lives. See
`reading-progress.md` for how scroll position specifically flows through
this table during article open/close.

Ambrosia items can be re-imported (Calibre re-exports), re-extracted (AO3
metadata arriving later than the initial import), or appear in more than one
collection feed at once. `bookKey` is the identity used to recognize "the
same book" across all of that, distinct from `uniqueID`
(`"ambrosia-book-<calibre_id>"`, which stays stable forever) and from
`articleID` (per feed/guid pair). Precedence, mirrored exactly between
`ParsedItem.bookKey` (Swift) and the SQL `CASE` expression in
`AmbrosiaSQLiteImportTable`: an anthology's AO3 series id, else its
Calibre-derived series name, else the item's own AO3 work id, else the bare
`uniqueID` as a last resort.

`BookStateTable` (`ArticlesDatabase`) stores one row per `bookKey` — `read`,
`starred`, `loved`, `scrollPosition`, `readingProgress`, `updatedAt` — and is
now the *primary* store for read/starred/loved and scroll position:

- Marking read/starred/loved on any `articleID` looks up its `bookKey`
  (falling back to `uniqueID` for pre-migration rows with no `bookKey`
  persisted yet), writes the flag to `BookStateTable`, and also
  live-propagates the same flag to every other `articleID` sharing that
  `bookKey` via `StatusesTable`, so every open copy of the same book across
  feeds repaints immediately rather than waiting for its next
  import/refresh.
- Scroll position (`ArticlesTable.saveScrollPosition`/`fetchScrollPosition`)
  is likewise `bookKey`-keyed through `BookStateTable` when a `bookKey`
  resolves, so it survives feed deletion/re-subscription and is shared
  across every feed's copy of the same book. `StatusesTable`'s own
  `scrollPosition` column remains only as a last-resort fallback for an
  `articleID` that doesn't resolve to any key at all.
- `readingProgress` is also part of `BookStateTable`'s write-through:
  `ArticlesTable.saveReadingProgress` looks up the `articleID`'s `bookKey`,
  writes through `BookStateTable.setReadingProgress`, and propagates the
  same value to every other `articleID` sharing that `bookKey` via
  `StatusesTable`, the same pattern as read/starred/loved/scrollPosition
  above. Two copies of the same book reached through different feeds are
  the same book to read -- if you're partway through one feed's copy,
  opening the other feed's copy should show the same position rather than
  resetting to 0 and risking a stale overwrite on the next scroll-position
  write.

`StatusesTable`'s parallel read/starred/loved/scrollPosition columns remain
as the fallback path for the rare row with no resolvable `bookKey`; these
fallback rows are ordinary `statuses` rows and are cleaned up automatically
whenever a feed's articles/statuses are deleted.
