# Reading Stats

Reading Stats is independent of Screen Time and is enabled by default. `ReadingStatsTracker` observes the active article and reading-progress updates from `WebViewController`.

Daily entries contain words, active seconds, completed work keys, overlapping fandom/tag word totals, and (as of the `worksByFandom`/`worksByTag` migration below) per-work-completion breakdowns by fandom and tag. The rolling history retains thirty-five dates. Per-work progress and all-time word totals are stored separately so the display history can be pruned without losing accounting state.

Fandoms and tags intentionally receive the full credited word count (or, under the "works" metric, the full completion credit) for a work when multiple values are present; their totals are attribution buckets, not mutually exclusive percentages. This means a period's fandom/tag totals can add up to more than that period's total words read or works completed — expected, not a bug, and disclosed in `ReadingStatsView`'s section footers.

## Baseline seeding

`setArticle(_:)` seeds `sessionBaseline` from
`max(AppDefaults.shared.readingStatsProgressByBookKey[key] ?? 0,
article.status.readingProgress ?? 0)` — the larger of the persisted
per-book high-water mark and the article's own last-known reading
progress. Previously it read only the persisted high-water mark with no
fallback, so a fresh install or a re-sync where that dictionary hadn't
caught up yet could seed at 0 and over-credit an already-partially-read
work as if it were being read from the start.

`readingStatsProgressByBookKey` itself no longer means "the position this
session started crediting from" — it's now purely "the furthest absolute
position ever reached for this book," used only to seed the *next*
session's baseline. It's written via `max(existing, clamped)` in
`recordProgress(_:)`, so it only ever grows for a given book.

**Known gap:** because `readingStatsProgressByBookKey` only ever grows,
once a book's persisted mark reaches 1.0 (fully read), every future
session's baseline reseeds at 1.0 regardless of where the person actually
restarts reading — so re-reading a finished work does **not** currently
credit new words, contrary to what might be assumed from the session
model below. This was implemented exactly per spec; flagged here as a
follow-up rather than silently changed, since fixing it would need a
product decision (e.g. a separate "high-water mark since last full
read-through," or an explicit re-read affordance).

## Per-sample cap

`recordProgress(_:)` bounds how many words a single scroll sample can
credit by a plausible reading speed — `ReadingStatsTracker.maxWordsPerMinute`
(500 words/minute) times the elapsed time since the previous sample —
so a table-of-contents jump, a scroll-to-bottom, or a fast scrollbar drag
can't credit every word it skips over as if it had been read. The
session's *first* sample is exempt from this cap: there's no meaningful
elapsed time to measure against yet, and capping it would incorrectly
zero out legitimate baseline-seeded credit (e.g. resuming a book already
40% read). 500 words/minute is a starting constant, not a researched
value for this app's readers.

## Session model

A "session" is `ReadingStatsTracker`'s notion of one continuous stretch of
reading a given book, tracked via `sessionStartProgress` (the position the
session began crediting from) and `sessionCreditedWords` (words already
credited within it). A session starts (via `startSessionIfNeeded()`) the
first time `setArticle(_:)` or `recordProgress(_:)` runs with no session
currently open, and ends (`endSession()`) when:

- `setArticle(_:)` is called with a different book than the one currently
  open, or with `nil`.
- The app resigns active (`willResignActive`).
- No scroll sample has arrived within `idleSessionThresholdSeconds` (see
  below) — checked at the top of every `tick()`.

This replaces the old model, where credit was computed directly against
the persistent per-book high-water mark with no session concept at all.
See "Baseline seeding" above for the known gap in how re-reads interact
with this model.

## Interaction-gated seconds

`secondsActive` only accrues for a tick if a scroll sample
(`recordProgress(_:)`) has arrived within the last
`idleSessionThresholdSeconds` (180 seconds) — so leaving the reader open,
unscrolled, in the foreground while doing something else in the real
world stops crediting active reading time until the next scroll. 180
seconds is an explicit starting constant, not a value derived from actual
reading-pattern data; it doubles as the idle-session-end threshold above,
so the two can't disagree about what counts as "idle."

## The provisional-content guard

`WebViewController.isContentProvisional` is true while the rendered
content is a not-yet-fetched AO3 stub (`isProvisionalAO3Stub(_:)`: the
article's `bookKey` has the `ao3-work:` prefix and `contentHTML` is nil or
empty), or briefly while a fetched chapter's content is being swapped in.
While true, the scroll-position message handler discards the sample
entirely — no `windowScrollY` write-back, no `recordProgress`/Reading
Stats credit, and no mark-read or position-persistence side effects —
since none of those numbers reflect the real document yet.

The guard is set in three places:

- `setArticle(_:updateView:)`, from `isProvisionalAO3Stub(article)`, for
  the initial (possibly-stub) render.
- `ao3ChapterFetchDidComplete(_:)`, unconditionally set to `true` right
  before `loadWebView(reason:)` swaps in the real fetched content —
  making the provisional window explicit around the content swap itself.
- Cleared in the `scrollRestoreComplete` message handler, once the newly
  rendered content's scroll position has settled; this also re-calls
  `ReadingStatsTracker.shared.setArticle(article)` so the tracker's
  snapshot (word count, fandoms, tags) reflects the real fetched content
  rather than the stub's.

`ReadingStatsTracker.setArticle(nil)` is also now called from
`viewWillDisappear`, so leaving the reader (returning to the timeline,
opening settings, etc.) doesn't leave `secondsActive` accruing against
whatever book was last open.

Separately: RSS/Atom-imported AO3 stubs already carry a real `wordCount`
(from the feed's own word-count field, via `AO3SearchResultsExtractor`/
`RSSItem`'s `result.wordCount`) before the chapter content is ever
fetched, and `AO3ChapterHTMLExtractor` preserves `existingArticle.wordCount`
unchanged rather than overwriting it. So `ReadingStatsTracker`'s existing
`wordCount > 0` guard in `setArticle(_:)` does not, by itself, block
tracking on a stub — the `isContentProvisional` guard above is what
prevents provisional-content scroll samples from being credited.

## `worksByFandom` / `worksByTag` migration

`ReadingStatsDailyEntry` gained `worksByFandom`/`worksByTag: [String:
Set<String>]`, populated in `recordProgress(_:)` alongside
`completedBookKeys` whenever a work crosses the 99% completion threshold.
`ReadingStatsCalendar.totals(history:range:calendar:)` unions these sets
across the requested date range (not a per-day sum, since the same
completed book can appear in more than one day's entry within a range)
and reports each fandom/tag's `.count` as `ReadingStatsTotals.worksByFandom`/
`.worksByTag`.

`ReadingStatsDailyEntry` has a custom `Decodable` implementation
(`decodeIfPresent` for the two new fields, defaulting to `[:]`) rather
than relying on synthesized `Codable` conformance. `AppDefaults.decode`
decodes the entire `[String: ReadingStatsDailyEntry]` dictionary with a
single `try?` — if `Decodable` synthesis required the new keys and a
single pre-migration day's entry lacked them, that one entry's decode
failure would throw for the whole dictionary, silently wiping all 35 days
of every user's history on first launch post-upgrade. The custom decode
means old days simply report an empty per-work breakdown instead.

## Reading Stats UI

`ReadingStatsView` has a shared words/works metric toggle
(`StatsMetric.words`/`.works`) that scopes both the fandom pie chart and
the top-tags list — `.words` reads from `totals.byFandom`/`.byTag` (word
totals, as before), `.works` reads from `totals.worksByFandom`/
`.worksByTag` (completed-work counts, from the migration above). Both
sections' footers disclose the multiple-counting caveat, worded per the
active metric.

The period picker's segments are labeled "Last 7 days"/"Last 30 days"
(previously "This week"/"This month", which read as calendar-aligned
periods rather than the trailing N-day windows the code actually
computes). The "Words per day" bar chart is intentionally always a fixed
trailing 7 days regardless of which period is selected — a 30-bar chart
doesn't read usefully at phone width — and its section is no longer
positioned directly under the period picker, to avoid visually implying
the chart's window follows the picker's selection.

The fandom-legend percent labels use `.monospacedDigit()` and
`.fixedSize()` so a value like "100%" can't be clipped by neighboring
flexible-width text. The top-tags list was rewritten from a
`GeometryReader`-based proportional bar chart (which clipped long AO3 tag
names regardless of available width) to plain label/value rows.

