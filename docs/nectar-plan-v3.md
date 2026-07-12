# Nectar: Plan v3 — Post Phase-5 Cleanup and Remaining Work

Checked against the current repomix dump, not carried over from `netnewswire-fork-plan.md`
on trust. That file is stale in one important way (below) and doesn't cover any of the
new asks in this revision, so this replaces it rather than patching it.

---

## 0. Correction to the old plan

The old plan (§"This revision," point 3) says Phases 2–9 are all unstarted. That's wrong
for Phase 2. Confirmed in current source:

- `WebViewController.windowScrollY` now persists per-article, not just to the single
  global `AppDefaults.shared.articleWindowScrollY` the old plan describes. On every
  scroll-position update it also calls `account.saveScrollPosition(_:forArticleID:)`;
  on `setArticle`, it calls `account.fetchScrollPosition(forArticleID:)` and restores it
  before reloading the web view.
- This is backed by a real column in `StatusesTable` (via `ArticlesTable` /
  `ArticlesDatabase`), not a UserDefaults hack — confirmed by grepping
  `saveScrollPosition`/`fetchScrollPosition` through `Account.swift` down to
  `ArticlesDatabase.swift` and `StatusesTable.swift`.
- There's also scroll-percentage-gated read-marking already in `WebViewController`
  (99%-of-document-height triggers marking read) — this wasn't in the old plan's phase
  descriptions at all.

**Update:** per-article save/restore is solid for ordinary in-session reopening, but
two real bugs undercut "always respect the scroll position" for relaunch/Handoff and
for fast exits — traced and fixed in Phase A0 below, not left as a vague open item.

So: **per-article scroll position save/restore already exists.** What's actually
missing — confirmed by grepping the whole tree for `scrollProgress` and
`readingProgress` (zero hits either way) — is a **percentage read out and shown to the
user**. Nothing currently converts a saved scroll position into "34% read" or a progress
bar. That's the real remaining piece of your "save progress" ask, covered in Phase A
below, and it's smaller than a fresh implementation would have been.

Also worth flagging since it touches this doc's own instructions: `feed-api.md` in this
project describes a per-library token requirement and lists `401` as a real, meaningful
failure mode (§2, §8). **Resolved as of this revision**: token auth has been removed
from the server. `feed-api.md`'s auth section is now stale documentation of a scheme
that no longer exists, not a live discrepancy to reconcile in Nectar's networking code.
The old plan's Phase 4 — "there is no authentication, drop `CredentialsType.ambrosiaToken`,
Keychain storage, and any `401` handling" — is the accurate direction going forward.
Practical effect on Phase 4: don't build or preserve any token/pairing/401-retry code on
the Nectar side, and treat `feed-api.md`'s auth section as needing an update on the
Ambrosia side (out of scope for Nectar's own plan, but worth a note back to whoever owns
that doc so the next person doesn't re-discover this same contradiction from scratch).
The rest of `feed-api.md` — routes, the `_ambrosia` JSON Feed extension schema,
pagination, ETag caching, OPML shape — is still the live contract and is what Phase 4's
OPML-rewrite work and Phase 1/7's field-reading work should keep building against.

---

## 1. Phase A — Reading/scroll progress, visible and durable

**Goal:** each timeline card shows how far into the article you are, and that position
survives app relaunch (it already does at the storage layer in the common case — this
phase both fixes the two confirmed bugs that break that guarantee and makes progress
visible).

### A0 — Two confirmed bugs in "respect the scroll position," fix first

Traced directly in `WebViewController.swift`, `ArticleViewController.swift`, and
`SceneCoordinator.swift` — not reproduced by guesswork, both are real code paths.

**Bug 1 — relaunch/Handoff restore reads the wrong value.** Ordinary in-session
reopening of an article is correct: `WebViewController.setArticle` does its own async
per-article DB fetch via `account.fetchScrollPosition(forArticleID:)`. But
`SceneCoordinator.restoreWindowState` / `selectSidebarItemAndArticle` — the paths used
on app relaunch and NSUserActivity/Handoff resume — instead read
`AppDefaults.shared.articleWindowScrollY`, a **single global slot that every article's
scroll updates overwrite** (see `WebViewController.windowScrollY`'s `didSet`, which
writes this same key on every scroll change regardless of which article is open). That
stale global gets passed into `selectArticle(_:articleWindowScrollY:)` →
`ArticleViewController.restoreScrollPosition` → `WebViewController.setScrollPosition`,
which synchronously forces `windowScrollY` to that value and reloads — overwriting
whatever correct position the per-article path would have restored. Net effect: on
relaunch, whichever article you're returned to gets the *last-scrolled article's*
offset, not its own. This only shows up when those two differ, which is exactly the
intermittent pattern described.

Fix: stop using `AppDefaults.shared.articleWindowScrollY` as a restore source entirely.
`restoreWindowState` and `handle(_ activity:)` should resolve the specific article's own
saved position the same way `setArticle` already does — an async
`account.fetchScrollPosition(forArticleID:)` call keyed to the article actually being
restored — rather than a single global last-write-wins value. The global `AppDefaults`
key can likely be deleted outright once this lands (confirm nothing else reads it before
removing the `Key.articleWindowScrollY` storage and the `StateRestorationInfo` field
that carries it).

**Bug 2 — quick exits lose the last moment of progress.** Scroll saves flow through
`scrollPositionQueue`, a `CoalescingQueue` with a 0.3s interval, then an async
`evaluateJavaScript` round trip to read `window.scrollY`, then an async DB write. There
is no flush-on-exit anywhere — `WebViewController.viewWillDisappear` only pauses media
and cancels image loads. Exit fast enough after your last scroll (well within a second
is enough) and that last position update never fires before the view tears down, so
reopening resumes from an earlier point than where you actually stopped.

Fix: force a synchronous flush when the article is about to go away. In
`WebViewController.viewWillDisappear` (or wherever the article is about to be replaced/
popped), cancel any pending coalesced call and immediately run the same
`evaluateJavaScript` read + `saveScrollPosition` write inline, awaited, rather than
relying on the next scheduled queue fire. This closes the gap without touching the
debounce behavior during active scrolling, which is fine as-is.

**Done when:** relaunching the app with two or more articles read in the same session
restores each one to its own saved position, not whichever was scrolled last anywhere
in the app; and rapidly opening, scrolling briefly, and exiting an article, then
reopening it, always resumes from the true last scroll position with no dropped tail.

### A1 — Visible progress on cards

1. **Expose a percentage, not just a raw scroll offset.** `windowScrollY` is a pixel
   offset with no denominator stored anywhere. Add a `readingProgress: Double?` (0...1)
   computed at the point `WebViewController` already reads `scrollHeight`/`innerHeight`
   for the 99% read-marking check — reuse that same JS bridge payload instead of adding
   a second one. Persist this alongside the existing scroll-position save call, in the
   same `StatusesTable` row (add a column rather than a second table, since it's
   1:1 with the existing scroll-position row and always written together).
2. **Card display.** Add a slim progress indicator to `MainTimelineCell` — a thin bar
   under the title or a partial-ring on the unread indicator, whichever reads better at
   the compact row height already used (do this as a quick visual comparison before
   picking, not a guess). Hide entirely when `readingProgress` is nil (never-opened
   article) or 0, and when the article is fully read — showing "100%" on something
   already marked read is noise, not information.
3. **Reset on unread.** If the user marks an article unread manually, decide whether
   progress resets to nil or is preserved as "you were here, but marked unread on
   purpose." Recommend preserving it — the position is still useful information — but
   flag this as a real product decision, not an implementation detail.

**Done when:** a partially-read article's card shows its progress, that progress
matches what's restored on reopening the article, and it survives an app relaunch.

---

## 2. Phase B — Card content: summary/description vs. body preview

**Confirmed problem, not a guess.** `MainTimelineCellData.summary` (used by
`ArticleStringFormatter.truncatedSummary`) is built from **`article.body`**, stripped to
300 characters — it's a body-text preview, not a feed-provided summary/description.
Ambrosia's JSON Feed items carry a real `summary` field per JSON Feed 1.1 (the
`_ambrosia` extension in `feed-api.md` rides alongside a normal JSON Feed item, which
already has `content_html`/`content_text` and, separately, `summary`) — those are two
different fields on the wire, and the card is currently reading the wrong one.

1. Confirm `Article.summary` (the JSON Feed `summary` field, separate from
   `contentHTML`/`contentText`/`body`) is actually populated by the parser for Ambrosia
   feeds — `TimelineCustomizerCollectionViewController`'s own preview article
   constructs `Article(... summary: nil ...)`, so at minimum the preview never exercises
   this path today.
2. Change `MainTimelineCellData.init` to prefer `article.summary` when present, falling
   back to the current truncated-body behavior only when `summary` is nil — so feeds
   without a `summary` field (or non-Ambrosia feeds, if any survive) don't regress to
   blank cards.
3. Everything else in the card (title, metadata line, tags) is unaffected by this
   change and doesn't need touching here.

**Done when:** a card shows the feed's actual summary/description text when the feed
provides one, and only falls back to a body-text snippet when it doesn't.

---

## 3. Phase C — Tag display: three selectable modes

**Decided:** build all three, user-selectable, rather than picking one. Single-line
stays the default (most condensed); expanded (full per-row) and the pill-badge middle
ground become alternative modes chosen via a new control in Timeline Layout — not a
replacement for the existing number-of-lines slider, which stays as-is and keeps
governing how many lines the summary/description text (Phase B) gets, a separate
concern from tag density.

1. **Add a `TagDisplayMode` enum**: `.compact` (today's single truncating
   `metadataString` line), `.expanded` (each of word count / completion / fandom /
   rating / warnings on its own row), `.badges` (word count/completion/date-ish stays
   on one line; fandom + rating + warnings wrap as small pill badges below it — the
   middle-ground option from the prior revision). Back it with a new
   `AppDefaults.shared.timelineTagDisplayMode`, same persistence pattern as
   `timelineNumberOfLines`/`timelineIconSize`.
2. **`MainTimelineCellData`**: stop precomputing a single `metadataString`. Keep the
   individual fields (`wordCountString`, `fandomString`, `isComplete`, `ratings`,
   `warnings`) as already-present properties, and let the layout/cell pick which
   rendering to build based on the active `TagDisplayMode` — precomputing one fixed
   string was fine when there was only one display option, but now the cell needs the
   raw fields to build any of the three.
3. **`MainTimelineCellLayout`**: add a layout path per mode. `.compact` reuses today's
   `rectForMetadata`. `.expanded` needs a new rect-per-field layout (stack of short
   single-line rects, one per non-nil field, each hidden/zero-height when its field is
   absent — same "hidden when zero, not confirmed-none" rule already used for `title`/
   `summary`). `.badges` needs a wrapping-row layout for the fandom/rating/warnings
   pills (a flow layout, not a fixed-height rect, since the pill count varies).
4. **Settings UI**: add a control to `TimelineCustomizerCollectionViewController` — a
   3-way segmented control or a second `TimelineCustomizerCell` slider-style selector
   (whichever matches the existing icon-size/number-of-lines slider's visual language
   more closely; check `TickMarkSlider.swift` before deciding whether a 3-position tick
   slider or a `UISegmentedControl` fits better) — wired to
   `AppDefaults.shared.timelineTagDisplayMode`, with the live preview cell (sections 2/3
   of that view controller) updating immediately on change, same as the existing
   sliders already do via the `UserDefaults.didChangeNotification` observer.

**Done when:** Timeline Layout settings has a working 3-way tag-display control, the
live preview reflects each mode immediately, and the actual timeline renders all three
modes correctly for articles with full metadata, partial metadata (some fields nil),
and no metadata at all.

---

## 4. Phase D — Card cleanup: icon sizing (keep the lines slider)

Confirmed: `showIcon` is already `false` everywhere it's constructed in the timeline
(`MainTimelineCellData` call sites, including the Timeline Layout customizer's own
preview cells) — icons are already not shown. But the **icon size slider itself** is
still live: `TimelineCustomizerCollectionViewController`'s section 0 is a
`TimelineCustomizerCell` with `sliderConfiguration = .iconSize`, bound to
`AppDefaults.shared.timelineIconSize`, sitting in Settings → Timeline Layout above the
number-of-lines slider and the live preview.

**Only the icon-size slider goes.** The existing number-of-lines slider
(`AppDefaults.shared.timelineNumberOfLines`, section 1) stays exactly as-is — it now
does double duty as the control for how many lines the Phase B summary/description text
gets, which is a real, still-needed setting, not a leftover.

1. Remove the icon-size section (section 0) from
   `TimelineCustomizerCollectionViewController` — drop it from `numberOfSections`/
   `cellForItemAt`/header wiring, and remove `IconSizeSelector`'s cell registration if
   nothing else uses it.
2. Leave `AppDefaults.shared.timelineIconSize` and `IconSize` alone at the model level
   unless nothing else reads them (quick grep before deleting the type itself — don't
   assume).
3. Confirm no other UI (Mac timeline, if shared) reads this same setting before ripping
   it out at the `AppDefaults` layer — if it's shared cross-platform, only remove the
   iOS Settings entry point, not the underlying default.
4. Renumber the remaining sections in `TimelineCustomizerCollectionViewController`
   (lines slider, tag-display-mode control from Phase C, live preview) once section 0 is
   gone — the view controller currently indexes sections positionally
   (`numberOfSections` returns a fixed `4`), so removing one section without adjusting
   the rest will misalign every section after it.

**Done when:** Settings → Timeline Layout shows the number-of-lines slider (now
documented as governing summary length), the Phase C tag-display-mode control, and the
preview — with no icon-size control anywhere.

---

## 5. Phase E — Settings cleanup

All confirmed live in `SettingsViewController.swift`'s current section/row enums —
nothing here is guesswork about what's still there.

1. **Rename Feeds section rows.** `FeedsRow.importSubscriptions` /
   `.exportSubscriptions` — change the row titles (wherever they're set, likely
   `Settings.storyboard` static-cell text or a title lookup keyed by row) from "Import
   Subscriptions"/"Export Subscriptions" to "Import Books Feed"/"Export Books Feed."
   Don't rename the underlying `importOPML`/`exportOPML` methods or notification names
   — just the user-facing strings — since Phase 9 of the old plan already has a
   dedicated full-rename pass and duplicating that work here risks drift.
2. **Remove "Add NetNewsWire News Feed."** Delete the
   `FeedsRow.addNetNewsWireNewsFeed` case, its row in `numberOfRowsInSection`'s
   `.feeds` branch (the `defaultNumberOfRows - 1` logic already conditionally hides this
   row when there's no active account or an existing subscription — once the row is
   gone entirely, that conditional and the `anyAccountHasNetNewsWireNewsSubscription()`
   check become dead code worth removing in the same pass, not left half-wired), and its
   `didSelectRowAt` case and `addFeed()` call site.
3. **Remove "Notifications → open system settings" row.** That's `Section.notifications`
   in `didSelectRowAt`, which calls
   `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`.
   Confirm whether the whole `.notifications` section becomes empty once this is gone —
   if so, remove the section, not just the row, so Settings doesn't show an empty
   header.
4. **Remove "Enable JavaScript."** `ArticlesRow.enableJavaScript`, its
   `enableJavaScriptSwitch` outlet and the `AppDefaults.shared.isArticleContentJavascriptEnabled`
   read in `viewWillAppear`. Also check `ArticleRenderer`/`WebViewController` for any
   place that branches on this default — if removing the toggle just leaves the
   underlying behavior always-on or always-off, confirm which one is intended (the
   task description implies "there's no JavaScript" — meaning either the toggle is
   already inert, or removing it needs to also confirm JS truly never runs; worth a
   quick check rather than assuming the toggle was already a no-op).
5. **Trim the Help section down to About + a new Nectar-specific About.**
   `HelpRow` currently has `.help`, `.forum`, `.releaseNotes`, `.bugTracker`, `.about`.
   Remove the first four rows (and whatever URLs/handlers back them —
   likely NetNewsWire.com/forum links that don't apply to a private fork anyway).
   Keep `.about`, and add Nectar-specific content to it — `AboutView.swift` /
   `AboutContributor.swift` / `AboutCreditView.swift` already exist as the SwiftUI
   views backing this; extend or add a section there rather than building a new screen,
   since the existing About screen is already the right entry point once the fork is
   the only thing being shipped.

**Done when:** Settings shows renamed Feeds buttons, no add-feed row, no
open-system-settings row, no JavaScript toggle, and a Help section reduced to a single
About entry with Nectar-specific content.

---

## 6. Phase F — Export liked/saved-for-later as CSV

Not yet scoped against source — starring the "liked/saved for later" concept needs
mapping to whatever the fork's actual starred-articles query is (the old plan's
open question 2 — "does `starred` get an internal rename or just new UI copy" — is
still unresolved and matters here: if the rename lands first, this phase's query
should use the new name).

1. Confirm the query for "all starred articles across accounts" — likely something on
   `AccountManager`/`Account` parallel to existing smart-feed queries; check
   `SmartFeedsController`/`SearchTimelineFeedDelegate`'s pattern for how an existing
   smart feed (e.g. Starred) is already fetched, and reuse that rather than writing a
   new query from scratch.
2. Define the CSV columns: at minimum title, AO3 story URL (per Phase 7's confirmed
   `article.url`/`preferredURL`), feed/collection name, date starred (confirm this is
   actually stored somewhere — `ArticleStatus` may only have `starred: Bool` with no
   timestamp; if there's no starred-date column, the CSV either omits that column or
   this phase needs a small schema addition first — check before promising the column).
3. Add an export entry point — Settings (a new row, or folded into the existing
   export-subscriptions area) or a share-sheet action from the Starred smart feed view,
   whichever fits the existing navigation better; recommend Settings since it's a
   one-shot bulk export rather than a per-article share action.
4. Write via `UIActivityViewController` with a temp file, matching the existing
   `exportOPML` pattern already in `SettingsViewController` for file-producing exports,
   rather than inventing new file-handling code.

**Done when:** an export action produces a CSV of every starred/liked article with
title, URL, feed name, and (if available) starred date, shareable via the standard
share sheet.

---

## Open items needing your decision before work starts

1. **Segmented control vs. tick-slider for tag-display mode** (Phase C, item 4) — check
   `TickMarkSlider.swift`'s visual language before picking which control style to add.
2. **Progress-on-unread** (Phase A, item 3) — reset or preserve reading progress when an
   article is manually marked unread.
3. **Starred date for CSV** (Phase F, item 2) — confirm whether a starred-date column
   exists; if not, decide whether it's worth adding before the export ships without it.
4. Everything already flagged as open in the old plan (chrome-hide gesture, starred
   rename scope, AO3 share-link conditionality, Handoff/notifications/MarsEdit keep-or-
   cut) is unaffected by this revision and still needs answers on its own timeline.
