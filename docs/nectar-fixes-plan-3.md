# Nectar fixes plan 3

Six issues reported after Fix #5 (scroll indicator / pinch-zoom lock, shipped
separately). Each entry below has a confirmed root cause, found by reading
the current code rather than guessing.

## 1. Collections should render wide, like Fandom/Relationships/Characters/Additional Tags

**Root cause confirmed.** `AO3ChapterHTMLExtractor.parseWorkHeader`'s
`collections` branch builds its row without `isWide: true`:

```swift
} else if classTokens.contains("collections") {
    let entries = tagEntries(fromLinksIn: dd)
    guard !entries.isEmpty else { continue }
    rows.append(AO3PrefaceRow(label: label, values: entries))
}
```

compared to the `tags` branch just above it, which computes
`isWide = classTokens.contains("fandom") || ... || classTokens.contains("freeform")`
and passes it through. `AO3PrefaceRow.isWide`'s doc comment already
describes exactly the symptom reported: a long comma-separated value list
"wraps its tag list inside a column that's only as wide as '1fr' of the
label column leaves free."

**Fix:** add `isWide: true` to the `collections` row, matching the freeform
row shape. One line, `AO3ChapterHTMLExtractor.swift:769`. No renderer change
needed — `AO3PrefaceRenderer.html(id:data:)` already branches on `isWide`
generically.

## 2. Don't request notification permission at launch

**Root cause confirmed.** `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
calls

```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { granted, _ in
    if granted { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
}
```

unconditionally, every launch (the OS only actually prompts once, but the
call — and the badge/remote-notification registration that follows — still
runs every time). This is a reading app with no push/remote-notification
account backend (`AccountType` has exactly one live case, `.onMyMac`, so
`registerForRemoteNotifications()` has nothing to register with), so this
prompt has no purpose at launch.

There's already a **correct** lazy request site:
`FeedInspectorViewController.newArticleNotificationsEnabledChanged(_:)` only
calls `requestAuthorization` when the person explicitly turns on
per-feed "new article" notifications, and reverts the switch if they decline.
That's the only place notifications should ever be requested.

**Fix:** delete the `requestAuthorization`/`registerForRemoteNotifications`
call from `AppDelegate`. Leave `UNUserNotificationCenter.current().delegate = self`
and `UserNotificationManager.shared.start()` in place — those just wire up
delivery/handling for notifications a feed has already opted into, they
don't prompt anyone.

## 3. Full-screen context-menu icons are backwards; menu should stay open after a tap

**Root cause confirmed — all three toggle icons, not just the heart.**
`WebViewController`'s press-and-hold context menu
(`contextMenuInteraction(_:configurationForMenuAtLocation:)`) builds its
loved/starred/read actions with the boolean test inverted relative to the
convention `ArticleViewController`'s own toolbar already establishes
(`updateUI()`, where filled = "this is the current state"):

| Action | `ArticleViewController` (correct) | `WebViewController` context menu (current) |
|---|---|---|
| Loved | `loved ? heartClosed (filled) : heartOpen` | `loved ? heartOpen : heartClosed` |
| Starred | `starred ? starClosed (filled) : starOpen` | `starred ? starOpen : starClosed` |
| Read | `read ? circleOpen : circleClosed (filled)` | `read ? circleClosed : circleOpen` |

(Read's own convention is intentionally the *opposite* sense of
loved/starred — filled circle means "unread, needs attention," matching the
system unread-dot idiom — but `WebViewController` has it backwards from
*its own* `ArticleViewController` counterpart either way.)

**Fix:** in `WebViewController.toggleLovedAction()`, `toggleStarredAction()`,
and `toggleReadAction()`, swap each ternary to match `ArticleViewController`'s
`updateUI()`. Three one-line changes.

**Menu staying open:** confirmed the deployment target is iOS 17
(`IPHONEOS_DEPLOYMENT_TARGET = 17.0`), so `UIAction.keepsMenuPresented`
(iOS 16+) is available. Setting `keepsMenuPresented: true` on the loved/
starred/read `UIAction`s keeps the menu open after a tap; the menu also
needs its `UIMenu` rebuilt with fresh titles/images afterward (the action
closures currently just call `coordinator.toggleX...`, with no menu
refresh), otherwise a second tap shows a stale label. Simplest approach:
have each action's handler call `interaction.updateVisibleMenu { _ in
self.buildContextMenu() }` (or equivalent) after toggling, rather than
rebuilding ad hoc — needs a small refactor to pull the menu-building code
in `configurationForMenuAtLocation` into a reusable method first.

## 4. Hide-from-feed (soft-delete) — new feature, not a bug

No existing plumbing for this. `ArticleStatus.Key` is a fixed three-case
enum (`read`, `starred`, `loved`); there's no "hidden" concept anywhere in
`ArticlesTable`/`StatusesTable`/`BookStateTable`, and the timeline's fetch
methods (`fetchUnsortedArticlesAsync`) have no filter for it.

**Shape of the fix**, following the precedent `loved` set (Phase 5 in the
schema migration, per `nectar-architecture.md`):

1. Add `case hidden` to `ArticleStatus.Key`, a `hidden: Bool` field on
   `ArticleStatus.State`, and the matching `statuses.hidden` column via the
   same `containsColumn`-guarded `ALTER TABLE` pattern used for `loved`.
   (See issue #5 below before adding another one of these unconditionally.)
2. Decide propagation scope: `loved`/`starred`/`read` propagate to every
   sibling `articleID` sharing a `bookKey` via `BookStateTable`. Hiding
   probably wants the same treatment (hide the book everywhere it appears),
   which means a `bookState.hidden` column too, and the same
   read/write/propagate path `ArticlesTable`/`Account` already have for
   loved.
3. Add a toggle action (context menu, swipe action, or both) and a
   `nectar-` filter step in the timeline fetch so hidden articles are
   excluded from the normal feed view without being deleted — mirrors how
   `read`/`starred`/`loved` already have dedicated smart feeds
   (`SmartFeeds/`); hidden probably wants the opposite, a *filter*, not a
   smart feed, plus maybe a "Show Hidden" toggle somewhere in Settings or a
   feed's own menu to reverse it per-work.
4. Needs a decision from you: does hiding a work also mean skipping it on
   future refreshes (so it doesn't silently reappear when the feed
   re-syncs), or does every refresh re-show it until hidden again? The
   `read`/`starred`/`loved` precedent doesn't answer this since none of
   those affect whether a row is fetched at all, only how it displays.

This is a multi-file feature addition, not a quick fix — flagging for
scoping/priority rather than estimating further here.

## 5. Relaunch stall — root cause confirmed

**Confirmed:** `Account.init` (called synchronously from
`AccountManager.init()`, called from `AppDelegate.override init()` — all on
the main thread, before the window is even shown) calls
`ArticlesDatabase.init`, which does:

```swift
queue.runInDatabaseSync { database in
    // ~25 sequential `containsColumn` checks (each its own
    // `SELECT * FROM table LIMIT 1` round trip), each guarding its own
    // conditional `ALTER TABLE ... ADD COLUMN`
    ...
    // then, unconditionally, every single launch:
    database.executeStatements("""
        INSERT OR IGNORE INTO bookState (...) SELECT ... FROM articles a JOIN bookState b ON b.bookKey = a.uniqueID WHERE ...;
        DELETE FROM bookState WHERE bookKey IN (SELECT a.uniqueID FROM articles a WHERE ...);
        UPDATE articles SET bookKey = ... WHERE ...;
        """)
    database.executeStatements("CREATE INDEX if not EXISTS ...")  // x3
    database.executeStatements("DROP TABLE if EXISTS ...")        // x1, multiple drops
}
```

`runInDatabaseSync` is a genuine `serialDispatchQueue.sync` — it blocks the
calling thread (main thread here) until every one of those statements has
run. Every `containsColumn` call is its own query+parse round trip, and
after the very first launch post-migration, **every one of these checks is
guaranteed to return "already exists"** — they're re-verified from scratch
on every single relaunch forever, not gated by any schema-version sentinel.
The `bookKey` series-migration block (the `INSERT OR IGNORE`/`DELETE`/
`UPDATE` three-statement block) is worse: it's not gated by a
`containsColumn`-style check at all, so it does a real `JOIN`/scan across
`articles`/`bookState` on every launch even though the comment describing
it explicitly calls it "self-limiting/idempotent" (true for correctness,
not for cost) — on a library that's grown over months of AO3/Ambrosia use,
this is exactly the kind of blocking-main-thread cost that would show up as
"a couple seconds unresponsive," and would get slower over time as the
library grows, matching what you're seeing.

**Fix, in order of impact:**
1. Add a schema-version sentinel (a `PRAGMA user_version` bump, or a
   dedicated one-row `schemaMigrations` table) so this whole block —
   `containsColumn` checks and the bookKey backfill alike — runs at most
   once per new column/migration ever added, not on every launch. This is
   the real fix.
2. Short of a full sentinel system, at minimum gate the bookKey
   series-migration block behind its own one-shot check (e.g. a stored
   `AppDefaults`/`AccountSettings` flag, since it has no `containsColumn`
   equivalent to key off), since it's the most expensive of the group and
   has no reason to run more than once.
3. Leave `runCreateStatements`/the column-existence checks as
   `runInDatabaseSync` (they need to complete before any read can safely
   run), but once gated by (1)/(2) they'll be a no-op on every launch after
   the first, so the synchronous-ness stops mattering in practice.

I have not made this change yet — wanted to confirm the diagnosis with you
before touching schema-migration code, since a mistake here risks a much
worse bug (skipped migration) than the stall itself.

## 6. Always use the login cookie for restricted works — root cause confirmed

**Confirmed:** `AO3ChapterFetcher.download(workID:...)` always makes an
**anonymous** request first —

```swift
let downloadResponse = try await Downloader.shared.download(url)
...
switch AO3ChapterHTMLExtractor.extract(fromWorkPageHTML: html) {
case .registrationRequired:
    switch await retryAuthenticated(url: url) { ... }
```

— and only falls back to `AO3AuthenticatedFetcher.fetch(url)` (which
attaches the stored session's Cookie header) *after* the anonymous fetch
comes back and gets parsed as `.registrationRequired`. Two problems with
this being fallback-only, matching what you flagged:

- Every restricted-work fetch pays for two full round trips (anonymous,
  then authenticated) instead of one, every time — no caching benefit either,
  since `AO3AuthenticatedFetcher` is deliberately cache-free and bypasses
  `Downloader` entirely (see its own header comment on why).
- More importantly: this only recovers a restricted work if
  `AO3ChapterHTMLExtractor.extract` correctly recognizes the anonymous
  response's HTML shape as `.registrationRequired`. Any restricted-content
  shape that isn't cleanly detected as that specific outcome (returns
  `.notFound`, or a technically-`.success` parse of a stripped/limited page)
  never reaches the authenticated retry at all — it silently shows wrong or
  missing content instead of the real thing, even though a valid session is
  sitting right there in the Keychain.

**Fix:** when `AO3SessionStore.isSignedIn`, use `AO3AuthenticatedFetcher.fetch(url)`
as the *primary* fetch, not a fallback, and only use the anonymous
`Downloader.shared.download(url)` path when signed out. This removes the
double round trip for the common signed-in case and closes the "silently
wrong content" gap for any restricted-page shape the extractor doesn't
recognize as `.registrationRequired`. Concretely, in `download(workID:...)`:
branch on `AO3SessionStore.isSignedIn` before the first fetch, call
whichever fetcher is appropriate, and feed the result into the same
`AO3ChapterHTMLExtractor.extract`/regression-guard/`rebuildParsedItem` path
already there — the `.registrationRequired` case for a signed-in fetch then
means "session is genuinely rejected," which is exactly
`retryAuthenticated`'s existing `.signedOut` handling (clear the session,
surface "Signed out of AO3"), just reached directly instead of after a
wasted anonymous attempt first.

Worth checking (not yet done) whether `AO3SearchResultsFetcher` and any
other AO3-page fetch sites have the same anonymous-first pattern — this
plan only traced `AO3ChapterFetcher.download`, since that's the one named
("work contents").

## Suggested order

#1 and #2 are one-line, zero-risk, ship immediately. #3 is small but
touches three call sites plus a menu-refresh mechanism — worth its own
patch. #5 and #6 both need your sign-off before I touch them (schema
migrations and network-auth paths are exactly the kind of thing where a
subtle mistake is worse than the bug). #4 needs a scoping decision (question
in that section) before it's buildable.
