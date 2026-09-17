# Screen Time

Screen Time is an opt-in, local-only reading limit. `ScreenTimeTracker` records foreground seconds while the app is active, using the device calendar for usage-day and bedtime calculations. Daily limits are stored independently for each weekday. A bedtime window may wrap midnight.

When a limit or enabled bedtime window is crossed, the tracker posts a limit notification. Each connected scene presents its scene-local black enforcement overlay; there is no dismiss, grace period, or extension path. Device-clock changes are an accepted limitation.

Usage history is retained for the most recent fourteen dates and powers the weekly summary. Settings and toolbar placement are independent of the tracker’s enforcement state.
