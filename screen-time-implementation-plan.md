# Screen Time feature: implementation plan

Confirmed-vs-inferred, same convention as the rest of `docs/`: everything
below is checked against the actual tree at
`/mnt/user-data/uploads/nectar-claude.zip` as of this plan, not guessed
from symbol names. File/line references are to that snapshot.

**Revision note:** this version adds a Reading Stats feature (Sections
8-12 below) — a separate weekly/monthly reading-activity page, distinct
from the Screen Time weekly summary (Section 7), reachable from its own
Settings row and a dedicated toolbar icon, with words-read/pace/streak
metrics and fandom/tag breakdowns modeled on The StoryGraph's stats page.
Sections 1-7 are unchanged from the original screen-time-only plan.
Also corrects a citation problem found while researching the addition:
several "Docs to write/update" items below (and Section 6) cited
`docs/CLAUDE.md` with specific line numbers for a routing table — that
file does not exist anywhere in this tree. Only a top-level `CLAUDE.md`
exists, and it's four short "Approach" bullets with no routing table.
Those citations have been corrected in place rather than carried forward
unchecked; see "Docs to write/update" for the fix.

## Scope recap

- Daily reading time limit, per weekday (weekend can differ from
  weekday).
- Bedtime/downtime window (wraparound-safe, e.g. 22:00-07:00).
- Enforcement: fade-to-black overlay, no grace period, triggers the
  instant the threshold is crossed.
- In-toolbar countdown icon (design/icon TBD later; this plan scopes the
  wiring only).
- Weekly usage summary screen.
- No bypass. Internal `Date()`/`Calendar` only — device-clock changes are
  an accepted, out-of-scope weakness per product decision.
- Explicitly out: notification-suppression during downtime (unrelated,
  already handled), any override/extension mechanism.
- **Added this revision:** a Reading Stats page — words read, words/hour,
  works read, day-streak, this-week-vs-last-week comparison, a
  words-per-day bar chart, and two breakdowns (by fandom as a pie chart,
  by tag as a ranked bar list). Its own Settings row (sibling to Screen
  Time, not nested under it) and its own toolbar icon that jumps straight
  to the page. Independent of `screenTimeEnabled` — a person who never
  turns on limits can still see stats.
- **Added this revision, explicitly out:** exporting/sharing a stats
  image, per-book detail pages beyond what the fandom/tag breakdowns
  already surface, any goal-setting/streak-freeze mechanic. Nothing here
  should block Sections 1-7.

## New files

```
Modules/Account/Sources/Account/ScreenTime/ScreenTimeCalendar.swift   (pure logic, testable, no UIKit)
iOS/ScreenTime/ScreenTimeTracker.swift                                (session tracking, singleton, mirrors UserNotificationManager)
iOS/ScreenTime/ScreenTimeEnforcementOverlay.swift                     (the fade-to-black UIView/UIWindow)
iOS/ScreenTime/ScreenTimeSettingsViewController.swift  (or .swift SwiftUI View, see below)
iOS/ScreenTime/ScreenTimeSummaryView.swift                            (weekly summary, SwiftUI)
Tests/NetNewsWire-iOSTests/ScreenTimeCalendarTests.swift
Tests/NetNewsWire-iOSTests/ScreenTimeTrackerTests.swift
Tests/NetNewsWire-iOSTests/ScreenTimeAppDefaultsTests.swift
docs/screen-time.md

Modules/Account/Sources/Account/ReadingStats/ReadingStatsCalendar.swift   (pure logic, testable, no UIKit — streak/range math, mirrors ScreenTimeCalendar)
iOS/ReadingStats/ReadingStatsTracker.swift                               (session/word/fandom/tag tracking, singleton, mirrors ScreenTimeTracker's active/foreground lifecycle but is a separate type — see Section 9)
iOS/ReadingStats/ReadingStatsView.swift                                  (the stats page itself, SwiftUI — see Section 10)
Tests/NetNewsWire-iOSTests/ReadingStatsCalendarTests.swift
Tests/NetNewsWire-iOSTests/ReadingStatsAppDefaultsTests.swift
docs/reading-stats.md
```

Putting the day/window arithmetic (`ScreenTimeCalendar`) in `Modules/Account`
rather than the iOS target is a deliberate split: it has zero UIKit
dependency, and putting pure date-math where it can be unit tested without
spinning up the iOS test host keeps it fast, same reasoning already
applied to `AO3SearchResultsPaginator`-style logic living in the module
rather than the app target. Confirm `Modules/Account/Package.swift`
exposes a `Foundation`-only target before adding the file — if the
module's public API surface is deliberately kept narrow, a new
`ScreenTime` subfolder under `Sources/Account/` is the least invasive
place, but check for a `Sources/Account/Exports.swift`-equivalent that
needs the new types added to its access list before assuming `public`
alone is sufficient. `ReadingStatsCalendar` should live next to it under
the same `Modules/Account/Sources/Account/` root for the same reason —
same module, same access-list check applies.

**Naming note, checked against the tree:** this codebase already has an
unrelated `AccountStatsView`/`AccountStatsViewModel`
(`iOS/AccountStats/AccountStatsView.swift`,
`Shared/AccountStats/AccountStatsViewModel.swift`, wired into Settings'
`.troubleshooting` section per `SettingsViewController.swift:338`) — a
database/account-health screen (feed counts, database size, unread/
starred counts per account), nothing to do with reading activity. Named
`ReadingStats`, not `Stats` or `ReadingActivity`, specifically to avoid
colliding with or being confused for that existing feature — worth
knowing before assuming "Stats" already means this, or that the two
screens should share code. They shouldn't; they answer unrelated
questions.

## 1. `AppDefaults` additions

Add to `struct Key` (`iOS/AppDefaults.swift:920`), following the exact
naming/comment convention already used for the toolbar-function key block
at line 981 onward:

```swift
static let screenTimeEnabled = "screenTimeEnabled"
// One Int per weekday (Calendar's 1...7, Sunday = 1), minutes. Stored as
// a single Data-encoded [Int: Int] rather than 7 flat keys, since every
// existing multi-value settings-screen thing in this file that isn't a
// fixed enum (foldersShowingReadArticles, articleThemeOverrides) already
// uses one archived-dictionary key rather than N flat keys -- see
// articleThemeOverrides below for the pattern this mirrors.
static let screenTimeDailyLimitMinutesByWeekday = "screenTimeDailyLimitMinutesByWeekday"
static let screenTimeBedtimeEnabled = "screenTimeBedtimeEnabled"
static let screenTimeBedtimeStartMinutesFromMidnight = "screenTimeBedtimeStartMinutesFromMidnight"
static let screenTimeBedtimeEndMinutesFromMidnight = "screenTimeBedtimeEndMinutesFromMidnight"
// Running counters, reset by ScreenTimeCalendar.isSameUsageDay(_:_:)
// rather than a scheduled job -- see ScreenTimeTracker.tick() below.
static let screenTimeMinutesUsedToday = "screenTimeMinutesUsedToday"
static let screenTimeUsageDate = "screenTimeUsageDate"
// Rolling history for the weekly summary screen -- Data-encoded
// [String: Int] keyed by "yyyy-MM-dd" rather than [Date: Int] (Date
// isn't a valid plain UserDefaults/JSON dictionary key), pruned to the
// last 14 entries on every write. See ScreenTimeTracker.recordDailyTotal().
static let screenTimeDailyUsageHistory = "screenTimeDailyUsageHistory"
```

Check `articleThemeOverrides`'s getter/setter (search for it in the same
file) before writing the weekday-limit dictionary property — it already
solves "archive a `[K: V]` into a single `UserDefaults` key" for this
codebase, and the screen-time key should use the identical
`PropertyListEncoder`/`Data` (or `NSKeyedArchiver`, whichever
`articleThemeOverrides` actually uses — read it, don't assume) approach
rather than inventing a second one.

Computed properties, same shape as `timelineGroupByFeed` (line 1311):

```swift
var screenTimeEnabled: Bool {
	get { AppDefaults.bool(for: Key.screenTimeEnabled) }
	set { AppDefaults.setBool(for: Key.screenTimeEnabled, newValue) }
}

func screenTimeDailyLimitMinutes(for weekday: Int) -> Int {
	screenTimeDailyLimitMinutesByWeekday[weekday] ?? Self.defaultScreenTimeLimitMinutes
}

func setScreenTimeDailyLimitMinutes(_ minutes: Int, for weekday: Int) {
	var dict = screenTimeDailyLimitMinutesByWeekday
	dict[weekday] = minutes
	screenTimeDailyLimitMinutesByWeekday = dict
}
```

with `screenTimeDailyLimitMinutesByWeekday` itself the private
archived-dictionary property backing both. `weekday` here should be typed
as plain `Int` (matching `Calendar.component(.weekday, from:)`'s return
type) rather than inventing a `Weekday` enum — there's no existing
weekday enum anywhere in this codebase (checked), and one isn't needed
for 7 fixed integer slots.

Register defaults in `registerDefaults()` (the big dictionary literal
ending at `iOS/AppDefaults.swift:2585`) — every weekday defaulting to the
same starting value (e.g. 120 minutes) so a fresh install's "different on
weekends" state starts uniform until the person actually customizes it,
matching the "migration preserves prior behavior, doesn't opt anyone into
new UI state by default" philosophy already stated for
`toolbarBottomUseOverflowMenu` at line 336-338. `screenTimeEnabled`
defaults to `false` — this is an opt-in feature, not on by default for
existing installs.

Add a `Notification.Name` next to the existing block at line 891-900:

```swift
public static let screenTimeUsageDidChange = Notification.Name("ScreenTimeUsageDidChangeNotification")
public static let screenTimeLimitReached = Notification.Name("ScreenTimeLimitReachedNotification")
```

`.screenTimeUsageDidChange` fires on every tick (drives the toolbar icon
label and the summary screen if it's open). `.screenTimeLimitReached`
fires once, at the moment of crossing, and is what
`ScreenTimeEnforcementOverlay` listens for — keeping "did the number
change" and "did we cross the line" as separate notifications avoids the
overlay having to re-derive "is this the crossing tick or just another
tick past it" from raw minute counts on every post.

## 2. `ScreenTimeCalendar` (pure logic, in `Modules/Account`)

[Unchanged from the original plan — see Section 2's own content: pure,
`Date()`-free bedtime-window and same-usage-day arithmetic, fully unit
testable. Not reproduced again here since nothing about Reading Stats
changes it; `ReadingStatsCalendar` (Section 8) is a sibling type with the
same "pure, no UIKit, testable" shape, not an extension of this one.]

## 3. `ScreenTimeTracker` (session tracking)

[Unchanged from the original plan — active/foreground lifecycle via
`UIApplication.willResignActiveNotification`/`didBecomeActiveNotification`,
per-second `Timer`-driven `tick()`, `rolloverIfNeeded()` day-boundary
handling, enforcement-reason tracking (limit vs. bedtime). Reading Stats'
own tracker (Section 9) reuses this same foreground-lifecycle pattern but
is a **separate singleton**, not a shared one — see Section 9 for why.]

## 4. `ScreenTimeEnforcementOverlay`

[Unchanged from the original plan.]

## 5. Toolbar icon

Add a case to `ToolbarFunction` (`iOS/AppDefaults.swift:763`):

```swift
case screenTimeRemaining
```

and fill in its `title`/`icon` in the extension starting at line 789 —
`icon` can return a placeholder `UIImage(systemName: "timer")` for now
per the "design/icon later" note; the wiring below doesn't depend on the
final asset. This single addition gets the function into
`ToolbarsCustomizerViewController`'s existing placement/reorder/overflow
UI for free (per `docs/settings-screen.md`'s "Reordering"/"Reset"
sections) — no new customizer UI needed.

In `ArticleViewController.swift`:

- Add `screenTimeRemainingBarButtonItem`/`screenTimeRemainingBottomBarButtonItem`
  lazy vars next to the existing pairs at lines 145-155 (this one has no
  action — it's display-only, so pass `target: nil, action: nil` or use
  a custom `UIBarButtonItem(customView:)` wrapping a `UILabel` if you
  want the remaining-minutes text inline on the button itself rather
  than an icon with a separate label).
- Add the two new cases to `barButtonItemInstances(for:on:)`'s switch at
  line 163.
- Update `updateUI()` (line 494) to refresh this item's `title`/label
  from `AppDefaults.shared.screenTimeMinutesUsedTodaySeconds` and the
  current weekday's limit, same pattern as however `.prevNext`'s
  `isEnabled` gets refreshed there today (read the existing `updateUI()`
  body to match).
- Subscribe to `.screenTimeUsageDidChange` (added in Section 1) inside
  `ArticleViewController`, calling into `allBarButtonItemInstances(for: .screenTimeRemaining)`
  (line 210) to update every live instance in one place — this is
  exactly the mechanism that comment already documents supporting.

Since this fires every second while foreground, confirm the label update
is cheap (string formatting only, no layout thrash) — a per-second
`setTitle` on a `UIBarButtonItem` is fine; a per-second Auto Layout pass
on a custom view is worth profiling once built.

## 6. Bedtime/limit settings screen

New pushed screen from `.articles` section or a new `.screenTime`
section in `SettingsViewController` (`iOS/Settings/`) — per
`docs/settings-screen.md`, adding a section means adding both the
`Section` enum case *and* the matching `Settings.storyboard` static
cell in lockstep, so this is a storyboard edit, not Swift-only. Given
this screen's own state (7 weekday limits, 2 bedtime times, 1 enable
toggle) is non-trivial, build the destination screen itself in SwiftUI
(matching `AO3AccountSettingsView`'s already-established precedent for
newer settings screens, per `docs/settings-screen.md`'s note that
`.ao3Account` "pushes `AO3AccountSettingsView` directly") rather than
another static-cell `UITableViewController` — a `Form` with a
`DatePicker(..., displayedComponents: .hourAndMinute)` pair for
bedtime and a `Stepper` or `Picker` per weekday for limits is
straightforward SwiftUI and avoids hand-building 9 storyboard cells.

**Decision, made this revision (was left open above):** use the existing
`.articles` section rather than a new `.screenTime` section — both this
row and the new Reading Stats row (Section 10) are two more rows in the
same "how you read" family as `.articles`' existing seven
(`ArticlesRow`: `theme`, `openLinksInNetNewsWire`, `disableArticleLinks`,
`showFeedNameInReaderView`, `fullScreenReading`, `annotations`,
`textReplacement` — `iOS/Settings/SettingsViewController.swift:78-86`,
confirmed), and two rows don't obviously earn a whole new top-level
section the way e.g. `.ao3Account` did (an entire authentication
subsystem). Add `case screenTime = 7` and `case readingStats = 8` to
`ArticlesRow`, each pushing its own SwiftUI screen the same way
`.ao3Account` pushes `AO3AccountSettingsView` — **both as their own
top-level rows in that switch, siblings of `theme`/`annotations`/etc.,
not a submenu where one pushes into the other.** If product feedback
later says these two deserve visual separation from the rest of
`.articles`, revisit as a section split then — cheaper to start flat and
split later than to build a section now on the strength of two rows.

Whichever section it's added under, **update `docs/settings-screen.md`'s
row inventory** in the same change — see "Docs to write/update" below
for the (corrected) citation on what actually requires this.

## 7. Weekly summary screen

SwiftUI `ScreenTimeSummaryView`, pushed from the settings screen above.
Reads `AppDefaults.shared.screenTimeDailyUsageHistory` (the
`[String: Int]` dictionary keyed by `"yyyy-MM-dd"`, Section 1), renders
last 7 entries as a simple `Chart` (Swift Charts, iOS 16+ — confirm
deployment target in the Xcode project settings before assuming this is
available; if the deployment target predates iOS 16, fall back to a
manual `HStack` of proportionally-sized bars) against each day's
configured limit for that weekday.

This is a **different screen from Reading Stats** (Section 10) — this
one is minutes-used-vs-limit, scoped under Screen Time and meaningless
if `screenTimeEnabled` is off; Reading Stats is words/pace/fandom/tag
activity, meaningful regardless of whether limits are on. Don't merge
them into one screen even though both are "a weekly chart" — they read
from different history dictionaries or (once Section 10 also links to
this one) from different concerns.

## 8. `ReadingStatsCalendar` (pure logic, in `Modules/Account`)

Sibling to `ScreenTimeCalendar` (Section 2), same file location and
testability reasoning, but a distinct type — this isn't reused code,
it's the same *pattern* applied to different data:

```swift
public enum ReadingStatsCalendar {

	/// Consecutive days (ending at `asOf`'s day, or the most recent day
	/// with any recorded activity if `asOf` itself has none yet) with
	/// `wordsRead > 0` in `history`. Derived on every call rather than
	/// stored as its own counter -- one fewer piece of state to keep in
	/// sync with the history dictionary, same reasoning
	/// ScreenTimeCalendar's pure-function design already established for
	/// this codebase. O(streak length), not O(history size): walks
	/// backward from `asOf` day-by-day and stops at the first gap.
	public static func currentStreak(
		history: [String: ReadingStatsDailyEntry],
		asOf: Date,
		calendar: Calendar = .current
	) -> Int { ... }

	/// Sums `history` entries whose date-key falls within `range`
	/// (inclusive), for the metric-card/chart values on ReadingStatsView.
	/// Returns zeros for an empty or non-overlapping range rather than
	/// optional -- callers already have to handle "no reading yet" as a
	/// zero state everywhere else (Section 10's mockup shows 0 for every
	/// metric on a fresh install, not a loading spinner or nil).
	public static func totals(
		history: [String: ReadingStatsDailyEntry],
		range: ClosedRange<Date>,
		calendar: Calendar = .current
	) -> ReadingStatsTotals { ... }
}

public struct ReadingStatsTotals: Sendable {
	public let wordsRead: Int
	public let secondsActive: Int
	public let worksCompleted: Int
	public let byFandom: [String: Int]   // words, not count -- a 200k-word fandom binge and four 500-word drabbles shouldn't look equal in the pie chart
	public let byTag: [String: Int]
	public var wordsPerHour: Double {
		secondsActive > 0 ? Double(wordsRead) / (Double(secondsActive) / 3600) : 0
	}
}
```

Test this the same way `ScreenTimeCalendarTests.swift` tests
`isSameUsageDay`/`isWithinBedtimeWindow` — an explicit non-`.current`
`Calendar` with a fixed `TimeZone` passed to every test call, not
`Calendar.current`, for the same determinism reason (see Section 2's own
tests and the "Tests" section below).

## 9. `ReadingStatsTracker` and the word/fandom/tag data model

### 9a. What's already there vs. what needs building

Checked directly against `Modules/Articles/Sources/Articles/Article.swift`
and `Modules/RSParser/Sources/RSParser/Feeds/ParsedItem.swift` before
assuming anything here, per this repo's own "don't guess APIs" rule:

- **Already persisted per-article, free to read:** `wordCount: Int?`,
  `fandoms: [String]?`, `additionalTags: [String]?`, `ratings`/
  `warnings`, `chapterCurrent`/`chapterTotal`, and `isComplete: Bool?`.
  `isComplete` is `chapterCurrent == chapterTotal` — **it means the fic
  itself is fully posted by its author, not that the reader has finished
  reading it.** Don't use it as the "did I finish this" signal for the
  works-completed count below; it answers a different question.
- **The actual reader-finished-this signal already exists**, just not
  under an obvious name: `WebViewController`'s scroll tracking already
  marks an article read at a 99%-of-scroll-height threshold
  (`docs/reading-progress.md`, "Reading-progress data flow" step 2),
  resolved through the article's `bookKey` when one exists so every
  feed's copy of the same book shares one read state
  (`docs/book-identity.md`). This is the hook Reading Stats needs for
  "a work was finished" — not a new completion mechanism.
- **Not there yet, needs building:** any per-day history of *how many*
  words were read, on which day, attributed to which fandom/tags. Article
  metadata is static per-article; nothing today logs "read N words of
  article X on date Y." That's the actual new instrumentation this
  feature needs — the rest of this section is about building that log
  economically, not about re-deriving data that secretly already exists.

### 9b. Data model

One rolling history dictionary, same date-keyed-`Data` shape as
`screenTimeDailyUsageHistory` (Section 1), but a richer value type since
one flat `Int` isn't enough to back the fandom/tag breakdowns:

```swift
static let readingStatsDailyHistory = "readingStatsDailyHistory"
static let readingStatsTrackingEnabled = "readingStatsTrackingEnabled"
```

```swift
struct ReadingStatsDailyEntry: Codable, Sendable {
	var wordsRead: Int = 0
	var secondsActive: Int = 0
	var wordsByFandom: [String: Int] = [:]
	var wordsByTag: [String: Int] = [:]
	var completedBookKeys: Set<String> = []
}
```

Pruned to the last 35 entries on every write (5 weeks) rather than
`screenTimeDailyUsageHistory`'s 14 — this supports both the "this week"
view and a "this month" toggle (mocked in Section 10) without a second
history key, and still leaves room for a clean "this week vs. last week"
comparison at any point in the window. Same `PropertyListEncoder`/`Data`
archiving approach as Section 1's instruction — confirm against
`articleThemeOverrides`'s actual implementation once, reuse the same
helper for both rather than writing it twice.

`readingStatsTrackingEnabled` defaults to `true` (unlike
`screenTimeEnabled`, which defaults `false` because it's an enforcement
feature) — Reading Stats has no enforcement action, so there's less
reason to hide it by default the way an opt-in limit is hidden. Still
exposed as an off switch (on `ReadingStatsView` itself, or a small toggle
row above it — see Section 10) for anyone who doesn't want local reading
activity tracked at all, matching the "flag it, don't decide it silently"
posture the rest of this plan already takes on similar calls. When off,
`ReadingStatsTracker` (below) becomes a no-op and the view shows zeros
rather than stale data.

### 9c. Tracker

`ReadingStatsTracker` is a **separate singleton from `ScreenTimeTracker`**,
not a shared one, for two reasons: it needs to keep working when
`screenTimeEnabled` is `false` (Scope recap, above), and it needs to know
*which article* is open — `ScreenTimeTracker` as sketched in Section 3 is
deliberately article-agnostic, just a foreground-seconds counter, and
that's a good, simple property to keep for the enforcement feature.
Bolting article-awareness onto it to serve Reading Stats would compromise
that simplicity for an unrelated feature. Reuses the same
foreground/active lifecycle notifications Section 3 already established
(`UIApplication.willResignActiveNotification`/`didBecomeActiveNotification`)
— that pattern is worth reusing; the tracker instance isn't.

Two hooks into it, both new:

1. **`WebViewController.setArticle(_:)`** tells the tracker which
   article is now open (`wordCount`/`fandoms`/`additionalTags`/`bookKey`
   — a small struct, not the whole `Article`, to keep the tracker's
   surface narrow). While that article is open and the app is
   foreground, `secondsActive` accumulates against today's entry the
   same per-second-`Timer` way `ScreenTimeTracker.tick()` already does
   (Section 3) — a second tracker firing its own per-second timer is
   wasteful; consider whether `ScreenTimeTracker.tick()` can notify a
   second observer instead of duplicating the timer, as an implementation
   detail once both trackers exist side by side.
2. **The existing 99%-scroll-height read-completion point**
   (`docs/reading-progress.md` step 2, inside `WebViewController`) also
   notifies the tracker: this article's `wordCount` is added to
   `wordsRead`/`wordsByFandom`/`wordsByTag` for today, and its `bookKey`
   (or `articleID` if no `bookKey`) is added to `completedBookKeys`.

**Open decisions, flagged rather than resolved here:**

- **Re-reads.** If a work's `bookKey` is already in some prior day's
  `completedBookKeys`, does hitting the 99% threshold again (rereading a
  favorite) count toward "works read" a second time? Recommend: no for
  the works-completed metric (count each `bookKey` once, ever, the first
  time it's seen — needs an all-time seen-set alongside the daily log,
  not just the 35-day rolling window), but yes for `wordsRead`/pace (a
  reread is still reading, and StoryGraph's own model counts rereads
  toward pace). This means `wordsRead` and "works completed" are not
  simply derivable from each other — worth stating explicitly so a future
  reader doesn't assume `completedBookKeys.count` and "words read this
  period" are two views of the same underlying event.
- **What counts as "words read" for a work abandoned partway.** The
  tracker as sketched only adds `wordCount` at the 99%-threshold moment —
  someone who reads 80% of a long fic and stops contributes 0 words that
  day, not 80% of `wordCount`. Attributing partial credit would need
  reading `readingProgress` at the moment the app backgrounds/the article
  closes rather than only at completion, which is a meaningfully bigger
  change (partial-word accounting, updated repeatedly as progress
  changes rather than written once). Recommend shipping the simpler
  complete-only version first and revisiting if undercounting turns out
  to matter in practice — flagging now so it's a deliberate choice, not a
  gap discovered later.
- **Fandom/tag attribution for multi-fandom crossover works.** `fandoms`/
  `additionalTags` are both arrays — a crossover fic's full `wordCount`
  would currently get added to *every* listed fandom's bucket in
  `wordsByFandom` (and every tag's bucket in `wordsByTag`), meaning the
  pie chart's percentages won't sum to 100% for anyone who reads
  crossovers. That's the same tradeoff StoryGraph's own multi-genre books
  make in its genre pie chart (checked during the mockup research above)
  and is probably fine to ship as-is, but state it as a known,
  accepted approximation rather than a bug someone reports later.

## 10. Reading Stats settings entry and screen

Per Section 6's decision, `Settings > Articles` gets a new
`readingStats` row (`ArticlesRow` case 8), pushing `ReadingStatsView`
directly — a sibling row next to the new `screenTime` row, **not**
reachable only via the Screen Time screen. Someone with
`screenTimeEnabled == false` still sees and can open this row.

`ReadingStatsView` (SwiftUI, `iOS/ReadingStats/`), built against
`ReadingStatsCalendar.totals(history:range:)` (Section 8):

- A "This week" / "This month" period picker (two segments) driving
  `range`.
- Four metric cards: words read, words/hour (`ReadingStatsTotals.wordsPerHour`),
  works read (`worksCompleted`), current streak
  (`ReadingStatsCalendar.currentStreak`, always computed for the actual
  current streak regardless of which period is selected in the picker
  above — a streak isn't "this week's streak," it's ongoing, so it
  shouldn't reset to some period-scoped number when someone taps "This
  month").
- A "N% more/fewer words than last week" comparison chip, comparing the
  selected period's total against the immediately preceding period of
  the same length.
- A bar chart of `wordsRead` per day across the selected range (Swift
  Charts if the deployment target allows it, per Section 7's same
  fallback note).
- A "By fandom" pie chart from `byFandom`, and a "Top tags" ranked bar
  list from `byTag` (top 5, by word count) — see Section 9c's flagged
  multi-fandom/tag caveat before treating either as an exact percentage
  breakdown in any copy shown near them (avoid text like "100% of your
  reading" anywhere nearby).
- A small "This week" detail list (average session, longest session,
  most-read fandom) and an "All time" detail list (total words read
  ever, longest streak ever) — both need their own all-time-scoped
  aggregation, separate from the 35-day rolling `readingStatsDailyHistory`
  (Section 9b already flags the all-time seen-set `completedBookKeys`
  needs for "works read"; "total words read ever" and "longest streak
  ever" need the same kind of never-pruned running counter, not a sum
  over the rolling window, which would silently shrink once entries age
  out past 35 days).
- The `readingStatsTrackingEnabled` off switch (Section 9b), shown as a
  small footer control or a separate row above the charts, not buried in
  a different settings screen — it's the thing this exact page depends
  on, so it should be visible from here.

`SceneCoordinator` needs no new method for the row itself
(`SettingsViewController`'s existing storyboard-segue-to-SwiftUI pattern,
Section 6, handles the push) — the new coordinator method below is only
for the toolbar shortcut.

## 11. Toolbar icon (Reading Stats)

A second, independent `ToolbarFunction` case, following Section 5's
exact pattern:

```swift
case readingStats
```

added to the enum at `iOS/AppDefaults.swift:763-780` (confirmed current
case list: `theme`, `tableOfContents`, `find`, `prevNext`, `lock`,
`annotations`, `settings`, `checkForUpdates`, `read`, `star`, `heart`,
`nextUnread`, `action`, `scrollBack`, `scrollToTop`, `scrollToBottom`).
`title`/`icon` added to the extension at line 789 onward:

```swift
case .readingStats:
	return NSLocalizedString("Reading Stats", comment: "Toolbar function: reading stats")
```
```swift
case .readingStats: return UIImage(systemName: "chart.bar")
```

An SF Symbol directly, not a new `Assets.Images` catalog entry — mirrors
`.lock`'s `UIImage(systemName: "lock.open")` (line 853, confirmed), the
one existing precedent in this same switch for skipping the asset
catalog.

Four new `Key` constants next to the `toolbarFnCheckForUpdates*` block
(`iOS/AppDefaults.swift:1018-1021`, confirmed):

```swift
static let toolbarFnReadingStatsTop = "toolbarFnReadingStatsTop"
static let toolbarFnReadingStatsTopOverflow = "toolbarFnReadingStatsTopOverflow"
static let toolbarFnReadingStatsBottom = "toolbarFnReadingStatsBottom"
static let toolbarFnReadingStatsBottomOverflow = "toolbarFnReadingStatsBottomOverflow"
```

— added to the `registerDefaults()` key list alongside the matching
`.checkForUpdates` line (`iOS/AppDefaults.swift:1215`, confirmed) and to
the `toolbarFunctionKeys` table (`iOS/AppDefaults.swift:1624-1641`,
confirmed) as its own `.readingStats: [...]` entry, same four-key shape
as every other row in that table.

**Not** added to `defaultToolbarFunctionOrder(for:)`'s `native` arrays
(`iOS/AppDefaults.swift:1714-1720`) — recommend it starts available via
the toolbar customizer but not inline by default on either bar, same as
every function not explicitly listed in `native`. An opt-in shortcut for
a stats page seems like the right default weight next to the
core-reading-controls that *are* native by default (`.theme`,
`.tableOfContents`, `.find`, `.prevNext`, `.lock`, `.annotations`,
`.settings`, `.checkForUpdates` on top; `.read`, `.star`, `.heart`,
`.nextUnread`, `.action` on bottom) — flagged as a recommendation, not a
hard requirement, same as everywhere else in this plan a UI-weight call
is made without a product decision on record.

In `ArticleViewController.swift`, mirroring the existing
`settingsBarButtonItem`/`settingsBottomBarButtonItem` pair
(lines 70/151, confirmed) and `showSettingsFromToolbar(_:)`
(line 1166, confirmed):

```swift
private lazy var readingStatsBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chart.bar"), style: .plain, target: self, action: #selector(showReadingStatsFromToolbar(_:)))
private lazy var readingStatsBottomBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chart.bar"), style: .plain, target: self, action: #selector(showReadingStatsFromToolbar(_:)))
```

added to `barButtonItemInstances(for:on:)`'s switch (same location as
Section 5's addition), and:

```swift
@objc private func showReadingStatsFromToolbar(_ sender: Any) {
	coordinator.showReadingStats()
}
```

**Deliberately not** `coordinator.showSettings(scrollToArticlesSection: true)`
— that opens the Settings list scrolled to the right section, still
requiring a tap on the row underneath it. The point of this button is
"get to this page faster" (the actual ask this revision started from),
so it should open `ReadingStatsView` directly. `SceneCoordinator` already
has exactly this shape of shortcut for a different screen —
`showCurrentActivity()` (`iOS/SceneCoordinator.swift:1653-1660`,
confirmed) presents `CurrentActivityView` directly as a sheet, bypassing
any list screen entirely. New method modeled on it directly:

```swift
func showReadingStats() {
	let hostingController = UIHostingController(rootView: NavigationStack { ReadingStatsView() })
	rootSplitViewController.present(hostingController, animated: true)
}
```

## 12. Fandom/tag visual design reference

Researched directly (not guessed) before sketching Section 10's layout:
The StoryGraph's own stats page uses a tappable pie chart per breakdown
category (genre, mood), each slice drilling into the underlying book
list, plus ranked bar-style lists for finer-grained categories with too
many distinct values to pie-chart usefully. That maps onto this app's
data cleanly — fandom (few large buckets per reader, like genre) as the
pie chart, tags (long-tail, like mood) as the ranked bar list — which is
the split Section 10 above already uses. Section 9c's flagged crossover-
work caveat is the one place this app's data doesn't map as cleanly as
it first appears; keep that caveat attached to the pie chart specifically
wherever this gets implemented, not just in this planning doc.

Drill-down (tapping a fandom slice or a tag bar to see the underlying
articles) is explicitly **not** scoped in this revision — Scope recap's
"explicitly out" list above. `wordsByFandom`/`wordsByTag` as designed
(Section 9b) only store aggregate word counts per day, not which
articles contributed to them, so drill-down would need a heavier per-
article event log, not just a richer dictionary value. Worth having in
mind if this gets revisited, not worth building against speculatively
now.

## Docs to write/update

**Correction from the original plan:** the original version of this plan
cited `docs/CLAUDE.md` (a routing table, "Keeping this current" table,
specific line numbers) several times in this section and in Section 6.
Checked directly against the tree: **no `docs/CLAUDE.md` exists.** The
only `CLAUDE.md` in this repository is the top-level one, and it's four
short "Approach" bullets (read-before-writing, concise output, no
guessing APIs, etc.) — no docs-routing content, no "Keeping this current"
table, nothing resembling what was being cited. Every `docs/*.md` file
checked (`settings-screen.md`, `reading-progress.md`, `book-identity.md`,
and others) instead cross-references other doc files directly inline
(e.g. `reading-progress.md`'s own "See `book-identity.md` for the
`bookKey`-sharing mechanism" at its top) rather than through a central
table. Either a `docs/CLAUDE.md` routing table existed in some other
version of this tree and was removed, or it was never real — this plan
can't tell which from the snapshot alone. Until confirmed one way or the
other, treat every "point X at docs/CLAUDE.md's table" instruction below
as "cross-reference the new doc directly from the relevant existing doc
files, the way `reading-progress.md`/`book-identity.md` already
cross-reference each other," not as an actual table edit.

- **New file `docs/screen-time.md`** covering the full system: the
  `AppDefaults` keys, `ScreenTimeCalendar`'s wraparound logic,
  `ScreenTimeTracker`'s active/deactivate lifecycle choice and the
  reasoning above, the enforcement-reason tracking (limit vs. bedtime),
  and the settings/summary screens. Write it in the same
  confirmed-vs-inferred voice as the rest of `docs/`.
- **New file `docs/reading-stats.md`**, same voice, covering: the
  `readingStatsDailyHistory` data model and the all-time counters that
  sit alongside it (Section 9b/10), `ReadingStatsCalendar`'s streak/range
  math, the `ReadingStatsTracker` hooks into `WebViewController` (both
  the per-second-active hook and the 99%-threshold completion hook —
  cross-reference `reading-progress.md`'s existing description of that
  threshold directly rather than re-explaining it), and the three flagged
  open decisions in Section 9c (re-reads, partial-credit abandonment,
  crossover-work attribution) so a future reader finds them here instead
  of only in this scratch plan. Add a line to `reading-progress.md`
  itself noting that its 99%-threshold read-completion point now has a
  second consumer (`ReadingStatsTracker`, in addition to marking the
  article read) — the kind of "this thing has more than one reason not to
  change casually" note `reading-progress.md`'s own scroll-position
  section already models for its other multi-consumer pieces.
- **Update `docs/settings-screen.md`**'s row inventory for both new
  `.articles` rows (`screenTime` and `readingStats`, Section 6's
  decision) in the same change that adds them.
- Do **not** cite a scratch planning file (e.g. this document's own
  filename) from any code comment. Point code comments at
  `docs/screen-time.md`/`docs/reading-stats.md` once they exist instead.

## Tests

Following the existing `Testing` framework convention (`import Testing`,
`@Suite`, `@Test`, `@testable import Nectar`) and the
reset-state-with-`defer`-cleanup pattern already used in
`Tests/NetNewsWire-iOSTests/UnifiedToolbarsMigrationTests.swift`:

**`ScreenTimeCalendarTests.swift`** (pure logic, highest-value tests,
no `AppDefaults` involved at all):

- `isWithinBedtimeWindow` — non-wraparound window (e.g. 13:00-14:00),
  time inside / before / after / exactly-at-start / exactly-at-end
  (confirm which edge is inclusive matches the implementation and pin it
  in the test, since off-by-one here is exactly how a one-minute gap or
  overlap at the boundary would slip through unnoticed).
- `isWithinBedtimeWindow` — wraparound window (22:00-07:00): time at
  23:00, time at 03:00, time at 12:00 (should be `false`), time exactly
  at 22:00 and exactly at 07:00.
- `isWithinBedtimeWindow` — `startMinutes == endMinutes` returns `false`
  (the "window disabled via zero width" case, if that's how
  `screenTimeBedtimeEnabled = false` is *not* how it's represented —
  confirm the settings UI actually uses the separate `Bool` and this
  zero-width case is unreachable in practice, or keep the test if it's
  a real reachable state).
- `isSameUsageDay` — same calendar day different times, day boundary
  crossing (23:59 vs 00:01 next day), explicit non-`.current` `Calendar`
  with a fixed `TimeZone` passed in so the test is deterministic
  regardless of the machine running it (do not rely on `Calendar.current`
  in the test itself even though the production default parameter does).

**`ScreenTimeAppDefaultsTests.swift`** (mirrors
`AppDefaultsBackupTests.swift`'s direct-`AppDefaults.store` manipulation
style):

- `resetState()`/`defer { resetState() }` pair, same shape as
  `UnifiedToolbarsMigrationTests.swift`'s, removing every new `Key.screenTime*`
  entry.
- Round-trip each new computed property (set then get).
- `screenTimeDailyLimitMinutes(for:)` returns the registered default for
  an untouched weekday and the just-set value after
  `setScreenTimeDailyLimitMinutes(_:for:)`, for at least two distinct
  weekdays confirmed independent of each other (setting Monday's limit
  must not change Tuesday's — this is exactly the kind of dictionary-key
  bug that's easy to introduce if the getter/setter round-trips through
  the wrong intermediate representation).
- `screenTimeDailyUsageHistory` pruning: write 20 entries, confirm only
  the most recent 14 (or whatever cap is chosen) survive, and confirm
  the *oldest* ones are the ones dropped, not an arbitrary subset.

**`ScreenTimeTrackerTests.swift`** — this one is the hardest to write
honestly, since `ScreenTimeTracker` as sketched reads `Date()` directly
and drives a real `Timer`. Two options, pick one rather than half-doing
both:

1. Inject a clock: add a `nonisolated(unsafe) static var now: () -> Date = { Date() }`
   test seam (same spirit as `AppDefaults.store` already being a
   directly-swappable `static let`) and drive `shouldEnforceNow()`/
   `rolloverIfNeeded()` by calling them directly in tests with
   `ScreenTimeTracker.now` overridden, rather than letting a real
   `Timer` fire. This is the more testable design and worth the small
   amount of production-code intrusion.
2. If a clock seam is rejected as unwanted production complexity, test
   only `shouldEnforceNow()`'s decision logic by factoring it out to take
   an explicit `Date` parameter (it already mostly does, via
   `ScreenTimeCalendar`) and accept that the `Timer`-driven `tick()`
   loop itself is exercised only by manual/UI testing, not unit tests.

Recommend option 1 — a silently-untested per-second enforcement loop is
the single most consequential piece of this whole feature to get wrong
(it's the thing that's supposed to have no bypass), and it's a small
production change to make it testable.

Specific cases once the seam exists:

- Crossing the daily limit exactly at the boundary (used == limit)
  triggers enforcement; one second before does not.
- Crossing into the bedtime window with the daily limit not yet reached
  still triggers enforcement (bedtime and limit are independent ORs, not
  one gating the other).
- `rolloverIfNeeded()` correctly writes the previous day's total into
  `screenTimeDailyUsageHistory` before resetting the counter, and does
  not fire an extra rollover on the very first call after a fresh
  install (`screenTimeUsageDate == nil` case).
- Enforcement-reason tracking (Section 3's flagged issue): a
  bedtime-triggered enforcement is not auto-lifted by
  `rolloverIfNeeded()` alone if the new day is still inside the bedtime
  window; a limit-triggered enforcement is lifted on rollover.

**Manual/UI test pass** (not automatable cheaply, call out explicitly
rather than silently skipping): multi-scene iPad behavior if
multi-window is supported (Section 3's flagged issue), the actual fade
animation timing/feel, VoiceOver behavior on the enforcement overlay
(does it announce anything, can a person navigate away from it with
VoiceOver gestures in a way that defeats "no bypass" — worth an explicit
accessibility pass given the no-bypass requirement), and Low Power Mode
throttling a repeating `Timer`'s actual firing cadence (a 1-second timer
is not guaranteed to fire exactly on time under system pressure; confirm
the drift is acceptable rather than assuming it away).

**`ReadingStatsCalendarTests.swift`** (pure logic, same shape as
`ScreenTimeCalendarTests.swift`, same fixed-`Calendar`/fixed-`TimeZone`
determinism requirement):

- `currentStreak` — no entries at all (0), a single day with
  `wordsRead > 0` as of that same day (1), a gap in the middle of an
  otherwise-continuous run (streak stops at the gap, doesn't count days
  on the far side of it), an entry present for a date but with
  `wordsRead == 0` (does not count as an active day — confirm this
  matches the intended semantics before assuming it, since "an entry
  exists" and "reading happened" aren't the same condition once
  `secondsActive`-only days are possible), and `asOf` itself having no
  entry yet (today, before any reading) falling back to the most recent
  active day rather than reporting 0 just because today hasn't logged
  anything yet.
- `totals(history:range:)` — a range with no matching entries returns all
  zeros (not a crash, not `nil`), a range partially overlapping the
  history's stored dates only sums the overlapping portion, and
  `wordsPerHour` specifically returns `0` rather than dividing by zero
  when `secondsActive == 0` for the range.
- `byFandom`/`byTag` summation across multiple days — confirm per-day
  dictionaries merge by summing matching keys rather than one day's
  entry overwriting another's for the same fandom/tag name.

**`ReadingStatsAppDefaultsTests.swift`** (mirrors
`ScreenTimeAppDefaultsTests.swift`'s shape):

- `resetState()`/`defer { resetState() }` pair removing every new
  `Key.readingStats*` entry.
- Round-trip `readingStatsTrackingEnabled` and the daily-history
  dictionary (set then get, including a `ReadingStatsDailyEntry` with
  non-empty `wordsByFandom`/`wordsByTag`/`completedBookKeys` to confirm
  the nested `Codable` fields survive the archive/unarchive round trip,
  not just the top-level `Int`s).
- `readingStatsDailyHistory` pruning: write 40 entries, confirm only the
  most recent 35 survive and the dropped ones are the oldest, mirroring
  the equivalent `screenTimeDailyUsageHistory` pruning test above.
- Confirm `readingStatsTrackingEnabled` defaults to `true` on a fresh
  `registerDefaults()` call — the one place this feature's default
  deliberately differs from `screenTimeEnabled`'s `false` default
  (Section 9b), worth a test precisely because it's an intentional
  exception to the pattern the rest of this plan otherwise follows.

## Build order

1. `ScreenTimeCalendar` + its tests — no dependencies, fully isolated,
   de-risks the trickiest logic first.
2. `AppDefaults` additions + their tests.
3. `ScreenTimeTracker` (with the clock seam) + its tests, wired to
   `AppDelegate.start()` but with `screenTimeEnabled` defaulting `false`
   so it's inert in the running app until Step 5's UI exists.
4. `ScreenTimeEnforcementOverlay`, manually triggered via a debug menu
   item or by temporarily flipping the default, to validate the fade
   and window-level behavior before any settings UI exists to reach it
   normally.
5. Settings screen (enable toggle, limits, bedtime) + storyboard/section
   wiring + `docs/settings-screen.md` update.
6. Toolbar icon wiring.
7. Weekly summary screen.
8. `docs/screen-time.md` + cross-references from/to the docs it touches
   (corrected per "Docs to write/update" above — no routing-table edit,
   direct cross-references instead).
9. `ReadingStatsCalendar` + its tests — same "pure logic first"
   reasoning as Step 1, and has zero dependency on anything in Steps
   1-8, so it can happen any time after Step 2 if the two features end
   up worked on in parallel.
10. `ReadingStats` `AppDefaults` additions + their tests.
11. `ReadingStatsTracker`'s two `WebViewController` hooks (Section 9c) —
    build and manually verify these before the view exists, the same
    "validate the mechanism before the UI can reach it" order Step 4
    already uses for the enforcement overlay. Confirm the re-read/
    partial-credit/crossover-attribution behaviors actually match
    Section 9c's flagged decisions once real data is flowing, not just
    once the code compiles.
12. `.articles` row wiring for `screenTime`/`readingStats` (Section 6) +
    `ReadingStatsView` itself (Section 10) + `docs/settings-screen.md`
    row-inventory update.
13. Reading Stats toolbar icon wiring (Section 11).
14. `docs/reading-stats.md` + the `reading-progress.md` cross-reference
    note (Section "Docs to write/update" above).
