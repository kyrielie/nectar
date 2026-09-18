# Screen Time

Screen Time is an opt-in, local-only reading limit. `ScreenTimeTracker` records foreground seconds while the app is active, using the device calendar for usage-day and bedtime calculations. Daily limits are stored independently for each weekday. A bedtime window may wrap midnight.

When a limit or enabled bedtime window is crossed, the tracker posts a limit notification. Each connected scene presents its scene-local black enforcement overlay; there is no dismiss, grace period, or extension path. Device-clock changes are an accepted limitation.

`ScreenTimeSettingsView`'s "Daily limits" and "Bedtime" sections are
editable regardless of whether "Enable Screen Time" is on — the toggle
only controls whether the tracker enforces the values, per
`ScreenTimeTracker.tick()`'s `screenTimeEnabled` guard, not whether they
can be set. They previously carried `.disabled(!enabled)` /
`.opacity(enabled ? 1 : 0.4)`, which is why they used to appear greyed out
and unreachable while Screen Time was off; both modifiers were removed
since nothing about setting a limit or bedtime window actually depends on
the feature being enabled.

`ScreenTimeSettingsView`'s in-settings lockout status line (SF Symbol +
message, above the "Enable Screen Time" toggle) and
`ScreenTimeEnforcementOverlay`'s full-screen message are both generated
by `ScreenTimeTracker.lockoutStatus(for:bedtimeEndMinutesFromMidnight:)`
— the overlay used to keep its own separate, differently-worded
`text(for:)` switch over the same cases, which let the two surfaces'
wording drift out of sync; that's now unified onto `lockoutStatus`, and
`ScreenTimeEnforcementOverlay.show(in:reasons:bedtimeEndMinutesFromMidnight:)`
takes the bedtime end time as a parameter so it can call `lockoutStatus`
the same way the settings screen does.

Usage history is retained for the most recent fourteen dates and powers the weekly summary. Settings and toolbar placement are independent of the tracker's enforcement state.

## Take a Break

Take a Break has three modes (`AppDefaults.screenTimeTakeABreakMode`,
`TakeABreakMode`: `.off` / `.reminder` / `.enforced`), not a bool. Both
non-off modes share one recurring trigger — every
`AppDefaults.screenTimeBreakReadingMinutes` of continuous reading,
tracked by `ScreenTimeTracker`'s `secondsSinceLastBreak` — but differ in
what happens when it fires:

- `.reminder` shows the dismissible `ScreenTimeBreakView` (posts
  `.screenTimeBreakReached`; `dismissBreak()` posts
  `.screenTimeBreakDidClear` and resets the countdown). This is the
  original, only mode that used to exist.
- `.enforced` blocks reading for `AppDefaults.screenTimeBreakEnforcedMinutes`
  the same way a daily limit or bedtime does, via a new
  `.recurringBreak` case on `ScreenTimeTracker.Reason`. It reuses the
  existing enforcement-overlay notifications (`.screenTimeLimitReached`
  / `.screenTimeEnforcementDidClear`) rather than a separate
  presentation path, since `SceneDelegate`'s overlay wiring already
  keys off `ScreenTimeTracker.activeReasons`, which now includes
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
`ScreenTimeSettingsView`'s "Take a Break" section. Upgraders with the old
`screenTimeTakeABreakEnabled` bool set to `true` are read as `.reminder`
on first access after upgrade (see `screenTimeTakeABreakMode`'s getter);
there's no reverse migration path back to the bool.
