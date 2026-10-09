# Reading Time

Reading Time was previously called Screen Time. It was renamed to avoid a crashing conflict with the iOS system Screen Time framework. The type, property, file and UI names all use "Reading Time"; the persisted `UserDefaults` key strings (all prefixed `screenTime`, plus the `toolbarFnScreenTimeRemaining*` toolbar keys) and `ToolbarFunction.readingTimeRemaining`'s raw value `"screenTimeRemaining"` keep the old spelling on purpose so stored settings carry over. Do not "finish" the rename there without a migration.

Reading Time is an opt-in, local-only reading limit. `ReadingTimeTracker` records foreground seconds while the app is active, using the device calendar for usage-day and bedtime calculations. Daily limits are stored independently for each weekday. A bedtime window may wrap midnight.

## Active-time accounting

`ReadingTimeTracker` and `ReadingStatsTracker` both credit elapsed time
through their own `ActiveTimeAccumulator` instance (`iOS/Shared/
ActiveTimeAccumulator.swift`) rather than each maintaining its own
nullable-`lastTick` timestamp. The accumulator tracks an explicit
`isActive` flag (set by `becomeActive(now:)`/`resignActive()`, driven from
`didBecomeActive`/`willResignActive`) instead of inferring "currently
active" from whether a timestamp happens to be non-nil — the old pattern
made it easy for a stale `lastTick` to silently credit a suspend/resume
gap as active reading time. Each `tick(now:)` call caps what it credits at
5 seconds (`maxCreditPerTick`), bounding both a forward clock jump and any
gap between ticks, and carries a sub-second remainder across calls so
short resign/active cycles don't lose time to flooring. Both trackers
also own a `ForegroundTicker` (`iOS/Shared/ForegroundTicker.swift`), which
holds the one-time `start()` setup: register the resign/become-active
observers, run the tracker's own `prepare` step, then start the one-second
`Timer` in `.common` run-loop mode (`RunLoop.current.add(_: forMode:
.common)`) rather than `Timer.scheduledTimer`'s default `.default` mode, so
ticks keep firing while the person is actively scrolling (the default
mode suspends timers during scroll tracking). `ForegroundTicker` is
composition, not a base class, on purpose: it owns only that lifecycle. What
`tick()`, `willResignActive()`, and `didBecomeActive()` do stays in each
tracker, because they differ in ways that matter (`ReadingTimeTracker.tick()`
must run `evaluate(at:)` and `evaluateRecurringBreakExpiry(at:)` even on a
tick that credits no foreground time, so a bedtime window opening or an
enforced break expiring is caught on wall-clock time;
`ReadingStatsTracker.tick()` returns early in that case). `start()` is a
no-op once the ticker is running; `ReadingTimeTracker.resetForTesting()`
tears it down (`stopForTesting(target:)`) so tests can exercise `start()`'s
setup again, while `ReadingStatsTracker.resetForTesting()` does not, because
no test starts that tracker's ticker.

When a limit or enabled bedtime window is crossed, the tracker posts a limit notification. Each connected scene presents its scene-local black enforcement overlay; there is no dismiss, grace period, or extension path for a daily-limit or bedtime lockout specifically (Take a Break, below, has its own separate dismiss/timer paths). Bedtime and usage-day calculations consistently read the device's current `Calendar.current`/timezone (`ReadingTimeCalendar`'s helpers, `evaluate(at:)`), so a timezone change or DST transition is reflected the moment the next tick runs, not stuck on whatever zone was active when tracking started. What's still unhandled: the person manually moving the device clock backward mid-session. `tick()` clamps a negative `now.timeIntervalSince(previous)` to zero, so usage simply stops accruing rather than going negative, but the bedtime-window check re-evaluates against the rolled-back time on the very next tick — so winding the clock back out of a bedtime window ends the lockout immediately, and winding it back into one starts a new lockout immediately. There's no detection of the rollback itself, just a consistent (if manipulable) read of whatever the clock currently says.

### Lockout pause

`tick()` reads whether a limit or bedtime lockout is already active
*before* that tick's own `evaluate(at:)` call runs, and skips crediting
`readingTimeMinutesUsedTodaySeconds` (and skips `evaluateBreak`) for that
tick if so. Previously usage kept accruing every second the enforcement
overlay was on screen, which meant the moment a person somehow dismissed
or worked around the overlay, they were often already further past the
limit than the overlay implied.

### Break persistence

`recurringBreakEndDate`, `secondsSinceLastBreak`, and a
`readingTimeLastResignDate` timestamp are now mirrored into `AppDefaults`
(rather than living purely in memory on `ReadingTimeTracker`), closing a
force-quit loophole: previously, force-quitting the app during an
`.enforced` break cleared the lockout for free on relaunch, since
`recurringBreakEndDate` was in-memory-only. `start()` now reads a
persisted `recurringBreakEndDate` back in — restoring the lockout if it's
still in the future, or clearing it (and `secondsSinceLastBreak`) if it
already expired while the app was gone. `didBecomeActive()` also compares
`readingTimeLastResignDate` to now: if the app was away for at least
`readingTimeBreakEnforcedMinutes`, that counts as taking a break on its
own, and `secondsSinceLastBreak` resets (dismissing an active `.reminder`
overlay too) — reusing the same enforced-break duration as the away-time
threshold for both `.reminder` and `.enforced` modes.

### Indicator display mode

The Reading Time pie indicator shown during fullscreen reading has its own
toggle, `AppDefaults.readingTimeIndicatorDisplayMode`
(`ReadingTimeIndicatorDisplayMode`: `.off`/`.pie`), independent of
`pageCounterDisplayMode`. Previously `WebViewController` tied the
indicator's visibility directly to the page counter's own `isHidden`
state (`readingTimePieIndicatorView.isHidden = pageCounterLabel.isHidden`),
so there was no way to show the indicator without also turning on the
page counter, or vice versa. Both views are separate subviews of the
reader's own `view` (not nested inside `notchCoverView`, despite being
visually aligned with it), so each already has independent visibility —
the fix was gating `readingTimePieIndicatorView.isHidden` on
`readingTimeIndicatorDisplayMode` instead of on the label's state. Default
is `.pie`, preserving the previous always-shown-when-conditions-met
behavior for existing users; it's in `backupEligibleKeys`. Edited from
`ReadingTimeSettingsView`'s "Show indicator while reading" toggle.

`ReadingTimeSettingsView`'s "Daily limits" and "Bedtime" sections are
editable regardless of whether "Enable Reading Time" is on — the toggle
only controls whether the tracker enforces the values, per
`ReadingTimeTracker.tick()`'s `readingTimeEnabled` guard, not whether they
can be set. They previously carried `.disabled(!enabled)` /
`.opacity(enabled ? 1 : 0.4)`, which is why they used to appear greyed out
and unreachable while Reading Time was off; both modifiers were removed
since nothing about setting a limit or bedtime window actually depends on
the feature being enabled.

`readingTimeEnabled` is registered as `false`, so a fresh install has Screen
Time off. `ReadingTimeTrackerTests` run inside the Nectar.app host and write
to its real `UserDefaults`; they turn the feature on to drive the tracker,
so each test ends with `cleanupState()`, which removes the Reading Time keys
and lets the registered defaults apply again. Before that, the teardown
re-ran the setup and left Reading Time on in the simulator's app container
(inferred from reading the tests; not reproduced). A test that crashes
before its `defer` runs can still leave state behind; uninstalling the app
from the simulator clears it.

The "Daily limits" section has its own "Enable daily limit" toggle
(`AppDefaults.readingTimeDailyLimitEnabled`), independent of the per-weekday
minutes so the limit can be turned off without losing the configured values,
symmetric with `readingTimeBedtimeEnabled`. `ReadingTimeTracker.evaluate(at:)`
only computes `limitReached` when it is on. It defaults to `true` (registered
default) so upgraders keep the previous always-on behavior, and it is in
`backupEligibleKeys`.

`ReadingTimeSettingsView`'s in-settings lockout status line (SF Symbol +
message, above the "Enable Reading Time" toggle) and
`ReadingTimeEnforcementOverlay`'s full-screen message are both generated
by `ReadingTimeTracker.lockoutStatus(for:bedtimeEndMinutesFromMidnight:)`
— the overlay used to keep its own separate, differently-worded
`text(for:)` switch over the same cases, which let the two surfaces'
wording drift out of sync; that's now unified onto `lockoutStatus`, and
`ReadingTimeEnforcementOverlay.show(in:reasons:bedtimeEndMinutesFromMidnight:)`
takes the bedtime end time as a parameter so it can call `lockoutStatus`
the same way the settings screen does.

Usage history is retained for the most recent fourteen dates and powers the weekly summary. Settings and toolbar placement are independent of the tracker's enforcement state.

## Take a Break

Take a Break has three modes (`AppDefaults.readingTimeTakeABreakMode`,
`TakeABreakMode`: `.off` / `.reminder` / `.enforced`), not a bool. Both
non-off modes share one recurring trigger — every
`AppDefaults.readingTimeBreakReadingMinutes` of continuous reading,
tracked by `ReadingTimeTracker`'s `secondsSinceLastBreak` — but differ in
what happens when it fires:

- `.reminder` shows the dismissible `ReadingTimeBreakView` (posts
  `.readingTimeBreakReached`; `dismissBreak()` posts
  `.readingTimeBreakDidClear` and resets the countdown). This is the
  original, only mode that used to exist.
- `.enforced` blocks reading for `AppDefaults.readingTimeBreakEnforcedMinutes`
  the same way a daily limit or bedtime does, via a new
  `.recurringBreak` case on `ReadingTimeTracker.Reason`. It reuses the
  existing enforcement-overlay notifications (`.readingTimeLimitReached`
  / `.readingTimeEnforcementDidClear`) rather than a separate
  presentation path, since `SceneDelegate`'s overlay wiring already
  keys off `ReadingTimeTracker.activeReasons`, which now includes
  `.recurringBreak`. Unlike the limit/bedtime lockouts, which clear the
  instant their underlying condition stops being true,
  `.recurringBreak` ends on a fixed timer
  (`evaluateRecurringBreakExpiry(at:)`, checked every tick against a
  stored end date) since there's no external condition to watch.

A break of either kind won't start (or keep counting toward) while a
daily-limit or bedtime lockout is already active — `evaluateBreak` checks
`isLimitLockout`/`isBedtimeLockout` first — so the stricter lockout
always wins rather than the two competing for the enforcement overlay.

Both timer settings are edited via `CountDownTimerSettingView`, a
generic wrapper around the same `CountDownTimerPicker` wheel
`DailyLimitDetailView` uses for daily limits, pushed from
`ReadingTimeSettingsView`'s "Take a Break" section. Upgraders with the old
`readingTimeTakeABreakEnabled` bool set to `true` are read as `.reminder`
on first access after upgrade (see `readingTimeTakeABreakMode`'s getter);
there's no reverse migration path back to the bool.

## Persisted contract and test locations

Reading Time and Reading Stats keep their data in `UserDefaults` under the
key strings declared in `AppDefaults+ReadingTime.swift` (17 keys) and
`AppDefaults+ReadingStats.swift` (5 keys), with `TakeABreakMode` and
`ReadingTimeIndicatorDisplayMode` stored by raw value and
`ReadingStatsDailyEntry` stored as JSON, and the toolbar function stored as its
raw value `"screenTimeRemaining"` in the toolbar order arrays. `ReadingTimePersistedContractTests`
(`Tests/NetNewsWire-iOSTests`) pins all of those against literals and never
touches `UserDefaults`, so a renamed key or raw value fails a test instead
of silently orphaning stored data. Changing one needs a migration and an
update to that file in the same commit.

The pure calendar math is tested in the packages that own it:
`ReadingTimeCalendarTests` in `Modules/ReadingTime/Tests/ReadingTimeTests`
and `ReadingStatsCalendarTests` in
`Modules/ReadingStats/Tests/ReadingStatsTests`. Both package test targets
run in CI through `Nectar-CI.xctestplan` (see `module-layout.md`, "Test
plans"). The tracker tests (`ReadingTimeTrackerTests`,
`ReadingStatsTrackerAccountingTests`) stay in the app test target because
they use `AppDefaults` and the tracker singletons.
