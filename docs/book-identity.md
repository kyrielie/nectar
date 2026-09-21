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
`starred`, `loved`, `scrollPosition`, `readingProgress`, `lastOpenedAt`,
`updatedAt`, `kudosAttemptedAt`, `kudosAttemptedAuthenticated` — and is
now the *primary* store for read/starred/loved and scroll position.
`lastOpenedAt` is written by `Account.recordBookOpened(articleID:)`, read
by the Last Opened smart feed — see `refresh-throttling.md`.
`kudosAttemptedAt`/`kudosAttemptedAuthenticated` back `AO3KudosManager`'s
per-`bookKey` kudos dedup/retry-once-signed-in logic — see
`ao3-authenticated-reading.md`.

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
  across every feed's copy of the same book. `fetchScrollPosition` reads
  `BookStateTable` first and falls back to `StatusesTable`'s own
  `scrollPosition` column in two cases: the `articleID` doesn't resolve to
  any key at all, **or** it resolves but `bookState` has no row for that key
  yet (a position saved back when `statuses.scrollPosition` was the only
  store, for a book not since re-opened). The second case is distinguished
  from a real saved position of 0 by `BookStateTable.scrollPosition(for:)`
  returning `nil` for "no row", not 0; regression coverage is
  `ScrollPositionFallbackTests`. `saveScrollPosition` writes `bookState`
  and the `statuses` column for the one `articleID` only; it deliberately
  does not propagate to siblings, because a sibling only ever reads its own
  `statuses` column in the no-row fallback case above, and the
  `bookState` write has already created the shared row that sibling's next
  fetch will find.

### `readingProgress`: durable record vs. live read model

`readingProgress` is **not** the mirror image of the other flags by
accident; it has a different read pattern, and that dictates which store
is authoritative for what:

| | `scrollPosition` | `readingProgress` |
| --- | --- | --- |
| Read pattern | one point read when an article opens | bulk-loaded into every `ArticleStatus` for timeline cards |
| Store the UI reads | `bookState` (statuses only as fallback) | `statuses`, via `ArticleStatus.readingProgress` |
| Role of `bookState` | primary | durable cross-feed record, seeds new `statuses` rows |
| Role of `statuses` | fallback | live read model |

- `ArticlesTable.saveReadingProgress` looks up the `articleID`'s `bookKey`,
  writes `BookStateTable.setReadingProgress`, then writes `statuses` for
  the `articleID` **and every sibling** sharing that `bookKey`. The
  sibling loop is what makes an already-loaded copy in another feed repaint
  live; it is not optional the way it is for `scrollPosition`.
- `bookState.readingProgress` is read in bulk (never per key) by
  `ArticlesTable.update`, which seeds a newly created `statuses` row from
  it, the same way read/starred/loved are seeded, so a re-subscribed or
  newly collection-imported copy of a book the reader already has progress
  on doesn't reset to nil. Regression coverage:
  `ArticlesTableUpdateTests.readingProgressSeedsNewArticleIDOnSameBookKey`.
- There is intentionally no single-key `readingProgress` getter on
  `BookStateTable`. An earlier one existed and had no callers; it was
  removed so nobody assumes that path is live. Moving the UI's read path
  onto `bookState` would mean joining it into every bulk article fetch;
  that trade was considered and rejected.
- Two copies of the same book reached through different feeds are the same
  book to read: if you're partway through one feed's copy, opening the
  other feed's copy shows the same position.

`StatusesTable`'s parallel read/starred/loved/scrollPosition columns remain
as the fallback path for the rare row with no resolvable `bookKey`; these
fallback rows are ordinary `statuses` rows and are cleaned up automatically
whenever a feed's articles/statuses are deleted.
