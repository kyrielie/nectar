# Nectar (Companion App): NetNewsWire Fork Plan

Separate repo, forked from `Ranchero-Software/NetNewsWire` (MIT licensed, no
copyleft obligations). Goal: strip it down to a single-purpose reader for
Ambrosia's local feed server, not a general-purpose RSS client.

# Nectar (Companion App): NetNewsWire Fork Plan

Separate repo, forked from `Ranchero-Software/NetNewsWire` (MIT licensed, no
copyleft obligations). Goal: strip it down to a single-purpose reader for
Ambrosia's local feed server, not a general-purpose RSS client.

**This revision** checks the plan against a fresh repomix dump after
another engineer picked up work on Nectar, and switches the plan from a
parallel multi-engineer structure to a single sequential build — one
engineer, one phase at a time, in order. What changed:

1. **More is done than last revision.** Confirmed against current source:
   the build error fix is applied, and Phase 0.5.1 (display name), 0.5.2
   (first-run empty state), and 0.5.3 (KVS warnings) are all complete and
   match their "done when" criteria exactly. 0.5.4 is mostly done but has
   a new wrinkle — see below.
2. **A new small issue turned up in 0.5.4's cleanup.** The dead
   `Shared/ShareExtension/` and `Shared/Widget/` source folders are still
   on disk, and are now *no longer excluded* from the main app target's
   build (the `project.pbxproj` exception-set entries that used to exclude
   them were removed along with the ones that genuinely needed removing).
   They're almost certainly harmless — spot-checked one file
   (`ExtensionContainers.swift`) and it's self-contained, no
   extension-only APIs — but this means dead code is now silently compiling
   into the shipped app, which wasn't true before. Flagged as a real,
   if low-severity, item to close out.
3. **Phases 2 through 9 are all still unstarted** — none of the reading-
   behavior, starring-rename, pairing, heart, toolbar, sharing, immersive/
   swipe, or rename work has begun. Phase 1 (`_ambrosia` parsing) remains
   fully done, confirmed unchanged.
4. **Parallel work map removed.** The previous revision laid out a
   multi-engineer parallelization scheme (six phases startable at once,
   file-collision notes, a fan-in diagram). That's no longer the plan —
   this is now one engineer working phases in order, so all of that
   apparatus is gone in favor of a single suggested build order. Anything
   from that scheme worth keeping (e.g. which files a phase touches) is
   folded into that phase's own section instead of a separate table.

**Naming note**: the app is being renamed from NetNewsWire/"Ambrosia Reader"
to **Nectar**. The full internal rename (bundle ID, module name, target
name, source-level `NetNewsWire`/`AmbrosiaReader` references) stays the
**last** phase (Phase 9) — doing it early would force every other phase's
patch to carry rename-related diffs unrelated to its own feature.
`CFBundleDisplayName` (Phase 0.5.1) is now set to "Nectar" — done.

**Open questions, flagged inline below and collected at the end**: single-tap
vs. double-tap for the chrome-hide gesture, whether "starred" needs an
internal rename or just new UI copy, and whether the AO3 story/series share
links should both always be offered or should vary by context.

**Target device note**: development and testing target is a physical iPhone
on iOS 18.7.8, not the newest simulator/OS. Confirmed
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` in `xcconfig/NetNewsWire_project.xcconfig`
— 18.7.8 is comfortably within the supported range, no blocker. But files
have `#available(iOS 26, *)` branches with an older-OS fallback path, and a
real 18.7.8 device only ever executes that fallback — so any work touching
these files needs to be built and tested against the actual device, not
assumed correct from the iOS-26 branch alone:
`iOS/Account/AccountNotificationInspectorView.swift`,
`iOS/Article/ArticleViewController.swift` (Phase 6),
`iOS/Article/WebViewController.swift` (Phases 2, 6, 7, 8),
`iOS/CurrentActivity/CurrentActivityView.swift`,
`iOS/MainFeed/MainFeedCollectionViewController.swift`,
`iOS/MainTimeline/Cell/MainTimelineCell.swift`,
`iOS/MainTimeline/MainTimelineModernViewController.swift`,
`iOS/SceneCoordinator.swift` (Phases 2, 4, 5),
`iOS/Settings/TickMarkSlider.swift`, `iOS/Settings/TimelineCustomizerCell.swift`.

---

## Build error fix — done

`iOS/Article/ArticleViewController.swift` previously failed to build
because of a single-element labeled-tuple typealias
(`typealias State = (windowScrollY: Int)`, which Swift silently collapses
to bare `Int`, dropping the label). Confirmed fixed in current source —
`State` is now a real struct:

```swift
struct State {
    let windowScrollY: Int
}
```

Nothing further to do here.

---

## Git workflow: one commit (or tight series) per phase

Sequential build, one phase at a time, each on its own branch off the
previous phase's tip — a straight stack, not the fan-in/fan-out structure
from the last revision:

```
main (build error fix already applied)
 └─ phase-0.5.4-cleanup (remaining item only, see below)
     └─ phase-2-reading-behavior
         └─ phase-3-starring
             └─ phase-4-pairing
                 └─ phase-5-heart
                     └─ phase-6-toolbar
                         └─ phase-7-sharing
                             └─ phase-8-immersive-swipe
                                 └─ phase-9-full-rename
```

Rules:

1. **Branch each phase off the previous phase's tip**, not off `main` —
   `git checkout -b phase-N-name phase-N-minus-1-name`.
2. **Rebase forward, don't merge, when an earlier phase needs a fix.** If
   Phase 3 needs a correction after Phase 5 has already branched from it,
   fix it on `phase-3-starring`, then rebase each downstream branch in
   stack order.
3. **Generate the patch for review/handoff with:**
   `git format-patch main..phase-N-name --stdout > phase-N-name.patch`
   (or `<previous-phase>..<this-phase>` for just that phase's own diff).
4. **A phase's "Done when" criterion doubles as its patch's acceptance
   test** — don't finalize a phase's patch until its own "Done when" line
   is verifiably true on device, since the next phase assumes this one is
   fully in.
5. **Merge each phase to `main` before starting the next**, rather than
   stacking unmerged branches indefinitely — keeps the working branch
   always one phase's diff away from `main`, and means there's only ever
   one thing in flight to worry about.

---

## Current state (confirmed against repo, not re-listed as pending)

Verified directly against the current source, not carried over from the
previous plan draft on trust:

- **Widget, Intents, and Share extension *targets* are gone.**
  `project.pbxproj`'s `PBXNativeTarget` section now has exactly two
  targets, `NetNewsWire-iOS` and `NetNewsWire-iOSTests` — no extension
  targets remain.
- **Extension *source folders* are not gone, and are excluded from the
  main target by design, not by accident.** `iOS/IntentsExtension/`,
  `iOS/ShareExtension/`, and `Shared/ShareExtension/` still exist on disk
  with real files in them (`IntentHandler.swift`, `ShareViewController.swift`,
  etc.). `project.pbxproj`'s `PBXFileSystemSynchronizedBuildFileExceptionSet`
  blocks correctly exclude these paths from the `NetNewsWire-iOS` target's
  membership — so the build is fine — but the dead source is still sitting
  in the tree. This replaces the old Phase 0.5.4, which assumed the cleanup
  needed was dangling references to *deleted target IDs*; that's not what's
  there. The exception sets all correctly target the surviving main-app
  target ID. **The actual remaining cleanup is deleting the dead
  `IntentsExtension/`, `ShareExtension/`, and `Shared/ShareExtension/`
  folders from disk** (or keeping them intentionally with a comment, if
  there's a reason) and then removing the now-empty exception-set entries
  that reference them. `Shared/Widget/*.swift` (`WidgetData.swift`, etc.)
  is similarly dead and unreferenced by any surviving target.
- **`fix_articlesorter.py` is a leftover one-shot patch script sitting at
  the repo root**, used to apply the `sortedByTitle`/`sortedByAuthor`
  implicit-return fix mentioned below. It already ran (the fix is present
  in `ArticleSorter.swift`) — delete the script itself as part of whichever
  phase's cleanup pass touches this file next; it's dead weight, not
  functional.
- **`project.pbxproj` bug fixed**: the file-system-synchronized membership
  exception sets for the (now-removed) Intents and Share extension targets
  were missing their own `Info.plist` from their exclusion list, causing
  "Multiple commands produce Info.plist." Fixed before the targets were
  removed outright; moot now, but worth knowing about if any extension
  target is ever added back.
- **`Shared/Timeline/ArticleSorter.swift` logic bug fixed**: `sortedByTitle`
  and `sortedByAuthor` had a `switch` as the last statement in a
  multi-statement closure body, so Swift's implicit-return-from-switch
  didn't apply — every case's `Bool` was silently discarded instead of
  being returned from `.sorted { }`. Fixed with an explicit `return` before
  each `switch`. Predates the fork; worth an upstream PR to NetNewsWire
  independently of this plan.

---

## Phase 0 — Strip down and restrict to local-only — **done**

All five items confirmed complete against the current source:

1. **Default feeds removed.** No reference to `DefaultFeeds.opml` or
   `DefaultFeedsImporter` anywhere in the tree.
2. **Accounts restricted to local-only.** `AddAccountViewController.swift`'s
   `AddAccountSections` enum now has exactly one case, `.local`, whose
   `sectionContent` is `[.onMyMac]`. The iCloud/web/self-hosted sections
   are gone, not just hidden.
3. **`.opml` registered as a document type.** `iOS/Resources/Info.plist`'s
   `CFBundleDocumentTypes` now has both the original `.nnwtheme` entry and
   a new `.opml` entry (`org.opml.opml`, role `Editor`).
4. **Reader view (article extraction) removed at the source level.**
   `ArticleViewController.swift`'s toolbar array has no
   `articleExtractorBarButtonItem` reference left, and no symbol named
   `articleExtractor`/`ArticleExtractorButton`/`toggleArticleExtractor`
   appears anywhere in current source. **One thing worth a quick
   double-check, not a re-do**: a stale `index.txt` file-listing at the
   repo root still lists `iOS/Article/ArticleExtractorButton.swift`,
   `Shared/Article Extractor/ArticleExtractor.swift`, and
   `Shared/Article Extractor/ExtractedArticle.swift` as if present — these
   have no actual file content in the repo and no code references them, so
   this is almost certainly just a stale listing (regenerate or delete
   `index.txt`), not evidence the files are still there. Confirm with
   `git status`/`ls` on a real checkout before assuming either way.
5. **Extension targets removed.** See "Current state" above for the
   nuance: targets are gone, but dead source folders remain — tracked as
   an open cleanup item there, not re-listed as a Phase 0 task.

**Still open, not resolved by this plan**: Handoff/Activity, notifications,
account stats, MarsEdit/micro.blog send-to (`Shared/ExtensionPoints/
SendToMarsEditCommand.swift`, `SendToMicroBlogCommand.swift` — confirmed
still present in `Shared/`), and the Dinosaurs Easter egg. Each needs an
explicit per-item keep/cut decision; nothing above implicitly resolves any
of them.

---

## Phase 0.5 — Build health fixes

### 0.5.1 — Home screen caption: "Nectar" — **still open**

Confirmed: `iOS/Resources/Info.plist` has no `CFBundleDisplayName` key.
`CFBundleName` is still the only name-bearing key, resolving to
`$(PRODUCT_NAME)` via `xcconfig/NetNewsWire_iOSapp_target.xcconfig` — this
part of the previous plan's analysis is unchanged and still accurate.
`Info.plist`'s `PRODUCT_BUNDLE_IDENTIFIER`-backed values already reference
an `ambrosia`/`AmbrosiaReader` namespace (e.g.
`com.ambrosia.AmbrosiaReader.FeedRefresh` in `BGTaskSchedulerPermittedIdentifiers`),
so some renaming has happened outside this plan's Phase 9 — worth
confirming that's intentional and consistent before Phase 9 starts, since
Phase 9's "done when" assumes a single controlled rename pass, not two.

1. Add `CFBundleDisplayName` = `Nectar` to `iOS/Resources/Info.plist`.
2. Leave `PRODUCT_NAME`, `PRODUCT_MODULE_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`,
   and every `NetNewsWire.<ClassName>`-qualified string exactly as they are.

**Done when:** home screen shows "Nectar," app launches and runs exactly as
before.

### 0.5.2 — First-run empty state — **still open**

Confirmed still reproducible: no "No library connected" (or equivalent)
string, and no `accounts.isEmpty` branch, appears anywhere in the current
source. The bug as originally diagnosed is still accurate and unfixed.

1. Locate the root-content view construction (likely `SceneCoordinator.swift`
   — confirm exact type before editing).
2. Add a conditional on `AccountManager.shared.accounts.isEmpty` (confirm
   exact API against `Modules/Account/Sources/Account/AccountManager.swift`):
   show a short message plus the existing OPML import button; a
   non-functional server-URL stub is fine here since Phase 4 replaces it.
3. Once any account exists, normal timeline UI takes over unchanged.

**Done when:** fresh install shows a message and an actionable button
instead of a black/blank screen.

### 0.5.3 — Spurious KVS/iCloud entitlement warnings — **still open**

Confirmed still present: `NSUbiquitousKeyValueStore.default` is still
called unconditionally in several places (sync-content-preference get/set
and change-notification handling), independent of whether an iCloud
account exists — this is what throws the "Unable to find entitlement for
KVS store" warning on launch.

1. Find and gate (or remove, if genuinely unreachable post-Phase-0) the
   unconditional `NSUbiquitousKeyValueStore` call sites.
2. Confirm no remaining code path can construct a non-`.onMyMac` account
   before deleting outright.

**Done when:** fresh launch log has no KVS/entitlement warnings.

### 0.5.4 — Clean up dead extension source and stale pbxproj exceptions — **rescoped**

Original framing (search for exception sets referencing *deleted target
IDs*) doesn't match what's actually in the file — see "Current state"
above. Rescoped to what's actually there:

1. Delete `iOS/IntentsExtension/`, `iOS/ShareExtension/`,
   `Shared/ShareExtension/`, and `Shared/Widget/` from disk (or keep
   intentionally with a comment explaining why).
2. Remove the now-pointless `PBXFileSystemSynchronizedBuildFileExceptionSet`
   entries that reference those paths (`iOS` group's exception set lists
   `IntentsExtension/Info.plist`, `IntentsExtension/IntentHandler.swift`,
   `ShareExtension/*`; `Shared` group's exception set lists
   `ShareExtension/SafariExt.js`, `ShareExtension/ShareDefaultContainer.swift`
   — the `MarsEdit`/`MicroBlog`/`SmartFeedPasteboardWriter`/
   `AccountRefreshTimer` entries in that same `Shared` exception set are
   unrelated to extensions and should stay, pending the separate
   MarsEdit/micro.blog keep-or-cut decision noted in Phase 0).
3. Delete `fix_articlesorter.py` from the repo root (see "Current state").

**Done when:** no `IntentsExtension`/`ShareExtension`/`Widget` path or
object reference remains in `project.pbxproj` or on disk, and
`fix_articlesorter.py` is gone.

**Suggested order within this phase:** no real dependency between the four
sub-items now that 0.5.4 no longer gates on target-ID lookups — any
engineer can take any subset. 0.5.1 and 0.5.2 are worth doing before
someone else starts device-testing Phase 2/4/5/8, purely so they're not
fighting a black screen or a mislabeled icon while testing unrelated work.

---

## Phase 1 — JSON Feed parsing: the `_ambrosia` extension — **done**

Confirmed complete end to end, via a different implementation shape than
originally proposed — worth knowing about since it changes what Phase 7
can assume:

- **Parser**: `Modules/RSParser/Sources/RSParser/Feeds/JSON/JSONFeedParser.swift`
  decodes `_ambrosia` (word count, chapters, completion, fandoms,
  relationships, characters, ratings, warnings, categories, series,
  `dateModified`) into `ParsedItem`. Comment in the parser notes there's no
  `_ambrosia_schema_version` field on the wire today — confirm this is
  still true on the Ambrosia side, since the original plan assumed
  gating on a version field.
- **Persistence**: **not** the single `ambrosiaMetadata TEXT` JSON column
  the previous plan proposed. Instead, `Article`
  (`Modules/Articles/Sources/Articles/ArticleUtilities.swift` or wherever
  `Article`'s full initializer lives) now carries each `_ambrosia` field as
  its own typed, optional property (`wordCount: Int?`, `chapterCurrent:
  Int?`, `fandoms: [String]?`, `series: [ArticleSeriesEntry]?`, etc.), with
  a new `ArticleSeriesEntry` struct (`name`, `index`, `ao3ID`) replacing the
  plan's proposed `ParsedSeriesEntry`-mirroring approach. There is no
  `Article.ambrosiaMetadata` computed accessor — anything downstream (Phase
  7 included) should read the individual fields directly off `Article`,
  not expect a metadata blob.
- **Timeline row**: `MainTimelineCellData.swift` has `wordCountString`,
  `fandomString`, and a combined `metadataString` (word count + completion
  + fandom + ratings/warnings), all absent-safe (empty string when the
  underlying field is `nil`, not a "confirmed none" default) — matches the
  correctness requirement from the original plan.
- **Sorting**: `ArticleSorter.swift` has `sortedByWordCount`,
  `sortedByTitle`, and `sortedByAuthor`, wired into `sortedByDate`'s
  dispatch alongside the pre-existing date/feed-name sorts.

**Nothing left to do here.** If a gap turns up later (e.g. the schema-
version gating question above), treat it as a small follow-up patch on
this phase's existing branch, not a re-implementation.

---

## Phase 4 — Add server and reachability

**Rewritten from the ground up in this revision.** The original draft
described a token-based pairing flow (QR-scan or OPML-import a base URL
plus an auth token, Keychain-store it, treat `401` as "token needs
refreshing"). Checked directly against `Ambrosia/Networking/LocalFeedServer.swift`
and `ambrosia_architecture.md`, none of that matches what the server
actually does:

- **There is no authentication.** `LocalFeedServer` binds `.inet(port:)`
  on all interfaces with no login, no token, no header check of any kind
  — confirmed both in the route handlers and in the architecture doc's
  invariant 24, which explicitly says a network-scope toggle with no auth
  behind it is deliberate for now, and that *if* auth is ever added it
  would be "a shared token checked in the route handlers" — future work,
  not present. There is nothing to pair, store, or expire. Drop
  `CredentialsType.ambrosiaToken`, Keychain storage, and any `401` handling
  from this phase entirely — building it now would be work against an API
  that doesn't exist, and would need throwing away or reworking whenever
  real auth eventually lands.
- **The exported OPML points at the wrong route for this fork's purposes.**
  `handleOPML()`/`generateOPML(baseURL:)` builds `<outline>` entries with
  `xmlUrl="…/feed/collection/<id>.xml"` — the hand-rolled RSS 2.0 route.
  The JSON Feed route that actually carries `_ambrosia` (word count,
  fandoms, series, etc. — everything Phase 1 parses) is the sibling
  `…/feed/collection/<id>.json` path; RSS gets a prose "stats line" folded
  into `<description>` instead, with no structured data. **Importing
  Ambrosia's OPML as-is would silently give Nectar feeds with none of
  Phase 1's data** — a real bug, not a hypothetical one, since OPML import
  was the "already free, no extra work" path in the original plan.
  Nectar-side fix: when importing an OPML file whose `xmlUrl` matches
  Ambrosia's `/feed/collection/<id>.xml` (or `/feed/search.xml` or
  `/feed/random-daily.xml`) shape, rewrite the extension to `.json` before
  subscribing. This is a small, local fix and doesn't require an
  Ambrosia-side change, but flag it to the Ambrosia side too — an
  Ambrosia-side JSON-flavored OPML export would be more robust than
  Nectar guessing at URL rewriting, and is a small change on that side
  (swap `.xml` for `.json` in `generateOPML`, or emit both).
- **There's no "opt-in auto-restart" feature.** The original plan's Phase 4
  item 3 claimed the feed server "has an opt-in auto-restart (not on by
  default)" — no such setting exists anywhere in the Ambrosia source; the
  server is a plain manual on/off toggle in Preferences
  (`rp.feedServerEnableDailyStory` and friends are unrelated per-feed
  settings, not a restart policy). Drop that claim. The real failure modes
  worth designing for are: the toggle is off, the Mac is asleep/closed, or
  — per `generateOPML`'s own generated warning comment — **the Mac's LAN
  IP address changed**, which silently breaks every previously-saved feed
  URL with no error code to distinguish it from "just unreachable right
  now." There is no way for the client to tell "IP changed" apart from
  "temporarily asleep" other than a prolonged string of failures, so don't
  build a specific "IP changed" UI state — just treat sustained
  unreachability as reason to prompt "check your library's address."
- **JSON Feed pagination needs handling.** Confirmed:
  `buildJSONFeed(...)` paginates at `jsonFeedDefaultPerPage = 100` /
  `jsonFeedMaxPerPage = 500`, and sets standard JSON Feed 1.1 `next_url`
  when more pages remain. Any Ambrosia collection over 100 items will
  silently truncate on first fetch unless Nectar's polling follows
  `next_url` to fetch subsequent pages. Confirm whether
  `Modules/RSParser`'s JSON Feed parser (or whatever drives account
  refresh) already follows `next_url` — if not, this is new work
  belonging to this phase, not an edge case to defer.

**Goal, rescoped:** get a base URL onto the phone with minimal typing (no
credential of any kind to enter), and treat "can't reach the library right
now" — for any reason — as a normal, expected state.

Not blocked on Phase 1 (it's done) — can start immediately.

1. **Add-server flow**: builds on `LocalAccountViewController.swift`
   (unchanged: 66 lines, takes a name, calls
   `AccountManager.shared.createAccount(type: .onMyMac)`), replacing the
   Phase 0.5.2 placeholder's stub URL-entry button with real behavior.
   Two entry points, neither needing a credential step:
   - **Manual entry / paste**: base URL only (e.g. `http://192.168.1.23:8765`,
     matching `LocalFeedServer.Config.port = 8765` and
     `localNetworkURLSync`'s format). This alone is enough to be useful and
     should ship even if QR scanning slips.
   - **Scan QR code**: still worth building, but the scope is now "decode a
     URL," not "decode a URL plus a secret" — meaningfully simpler than the
     original plan assumed. **This requires a small Ambrosia-side addition
     that doesn't exist today**: nothing in `LocalFeedServer`,
     `PreferencesWindowController`, or anywhere else in the Mac app renders
     a QR code. The natural place is wherever `localNetworkURLSync` is
     already surfaced to the user (the "started server" alert, referenced
     around the `feedServer.localNetworkURLSync` call sites in
     `LibraryWindowController.swift`/`ReaderViewController.swift`) — encode
     that string as a QR code there (`CIFilter.qrCodeGenerator` is enough,
     no new dependency needed) and show it in the alert. This is a
     cross-repo dependency: track it against the Ambrosia-side prep plan,
     not as something Nectar can finish alone.
   - **Import OPML** (via AirDrop, now that `.opml` is a registered
     document type, or the existing manual picker): apply the `.xml` →
     `.json` URL rewrite described above when constructing the subscribed
     feed URL(s), so imported feeds actually carry `_ambrosia` data.
2. **No credential storage needed.** Set the account's `endpointURL`
   (already on `Account` — `Modules/Account/Sources/Account/Account.swift`)
   to the entered/scanned/imported base URL and stop there. Leave
   `Modules/Secrets/Sources/Secrets/Credentials.swift`'s `CredentialsType`
   enum untouched — there is nothing to add a case for.
3. **Design a real "unreachable" state**: show last-cached content, retry
   with backoff, surface a clear "can't reach your library right now"
   indicator rather than an error dialog. No `401`/re-pair flow — with no
   auth, connection failures are always transport-level (timeout,
   connection refused, DNS/host unreachable), never an auth rejection, so
   there's exactly one failure UI to build, not two.
4. **Respect `ETag`/`If-None-Match`** on every poll — confirmed
   `LocalFeedServer` computes and returns a real `ETag` on both the RSS and
   JSON Feed routes (`computeFeedETag`, keyed on collection membership plus
   each item's `ao3.updatedDate`) and honors `If-None-Match` with a genuine
   `304`. This part of the original plan was accurate as written.
5. **Handle pagination** per the `next_url` note above — part of this
   phase's polling logic, not a follow-up.

**Done when:** adding a library takes one manual URL entry, one QR scan
(once Ambrosia renders one), or one OPML import (with the `.json` rewrite
applied), a collection over 100 items is fully fetched across pages, and
sustained unreachability (asleep Mac, toggled-off server, or changed LAN
IP — client can't tell which) shows a clear "can't reach your library"
state instead of a silent failure or an error dialog.

---

## Phase 2 — Reading behavior: scroll-gated read marking, real per-article progress

**Goal:** don't mark read on open, never lose scroll position per article.

Confirmed still fully unimplemented — `SceneCoordinator`'s article-selection
path still calls `markArticlesWithUndo([article], statusKey: .read, flag:
true)` immediately on selection (three call sites in this area total, not
just the one this phase targets — confirm which one fires on plain
selection vs. explicit read/unread toggling before removing anything), and
`WebViewController.swift`'s `scrollPositionDidChange()` still only reads
raw `window.scrollY` into a single global `windowScrollY` property with no
percentage calculation.

1. **Don't mark read on open.** Remove the immediate
   `markArticlesWithUndo(..., flag: true)` call in the selection path;
   replace with the scroll-gated version below.
2. **Scroll-percentage-gated marking.** Extend `scrollPositionDidChange()`'s
   JS evaluation to also read `document.body.scrollHeight`/viewport height,
   compute a percentage, and call `markArticlesWithUndo(..., flag: true)`
   once it crosses 99%.
3. **Real per-article scroll position.** `windowScrollY`'s `didSet` still
   writes straight to the single global `AppDefaults.shared.articleWindowScrollY`.
   Add `scrollPosition REAL DEFAULT 0` to the existing per-article
   `statuses` table in `ArticlesDatabase.swift` and change that `didSet` to
   write there instead. Update every read/restore call site accordingly.

**Done when:** opening an article doesn't flip its read state until
actually scrolled through, and switching between articles never discards
either one's scroll position.

---

## Phase 3 — Starring / read-later, one-directional

Unchanged from original plan and still accurate: `ArticleStatus.Key` today
has exactly `.read`/`.starred` — confirmed no `.loved` case yet (that's
Phase 5's job), so this phase's premise still holds. This becomes the
"read later" concept via UI label/icon only.

**Open question, still unresolved**: does "starred" need an internal
rename (`ArticleStatus.Key.starred`, the `statuses.starred` column,
`StarredFeedDelegate`/smart-feed label), or is this purely UI-copy/icon?
Recommend the latter — smaller diff, no behavior change, less regression
risk.

**Done when:** the star icon/label reads as "read later," no change to
underlying behavior.

---

## Phase 5 — Heart (loved) as a second, independent status

Confirmed fully unimplemented — `ArticleStatus.Key` has no `.loved` case,
and no `LovedFeedDelegate`/`toggleLoved` exists anywhere in the tree.
Original plan's design still matches the current code shape exactly
(`ArticleStatus`'s private `State` struct + `OSAllocatedUnfairLock` pattern
is unchanged from what the plan describes), so proceed as written:

1. **Schema**: add `case loved` to `ArticleStatus.Key`, `loved: Bool` to
   its private `State` struct, and a `loved BOOLEAN DEFAULT 0` column on
   `statuses` in `ArticlesDatabase.swift` — additive, same pattern as
   Phase 2's `scrollPosition` column (different column, same table; land
   as separate migrations, see "Parallel work map").
2. **Smart feed**: add `Shared/SmartFeeds/LovedFeedDelegate.swift`,
   mirroring `StarredFeedDelegate.swift`, registered in
   `SmartFeedsController.swift` alongside Today/Unread/Starred.
3. **UI wiring**: mirror the `toggleStarred`/`StarredFeedDelegate` touch
   points — `ArticleViewController.swift`, `WebViewController.swift`,
   `KeyboardManager.swift`, `RootSplitViewController.swift`,
   `SceneCoordinator.swift` — for a new `toggleLoved` action. Add a
   `heartBarButtonItem` in `ArticleViewController.swift` without touching
   the toolbar array itself — Phase 6 does that, and branches off this
   phase specifically so the two diffs don't collide.

**Done when:** an article can be independently starred and loved, each
with its own toggle and smart feed — toolbar placement is Phase 6's job.

---

## Phase 6 — Article view toolbar: heart and theme buttons

Branches off Phase 5 (needs `heartBarButtonItem` to exist). Rescoped from
the original plan: confirmed current toolbar array (the `#unavailable(iOS
26)` branch in `viewDidLoad`) is already just

```swift
toolbarItems = [
    readBarButtonItem, flex(),
    starBarButtonItem, flex(),
    nextUnreadBarButtonItem, flex(),
    actionBarButtonItem
]
```

— no `articleExtractorBarButtonItem` in it (Phase 0 already removed that).
So this phase is purely additive now, not "remove one, add two":

1. Add `heartBarButtonItem` (from Phase 5) and a new `themeBarButtonItem`
   to the array. `themeBarButtonItem`'s action pushes directly to
   `iOS/Settings/ArticleThemesTableViewController.swift` — confirmed still
   only reachable via the general Settings screen today.
2. Resulting array, ordering open: something like
   `[read, star, heart, nextUnread, theme, action]`.
3. Check whether the `#available(iOS 26, *)` branch of this same method
   needs the equivalent insertion — confirmed it currently only inserts
   `articleExtractorBarButtonItem` at index 5 on iOS 26+ (dead code now
   that the symbol is gone — this branch itself may need its own small fix
   independent of this phase's actual goal, worth a quick look since it
   won't be exercised on the iOS 18.7.8 test device anyway).

**Done when:** a heart button exists next to the star button, and a theme
button opens the theme picker directly from the article view, on the iOS
18.7.8 test device.

---

## Phase 7 — Sharing: AO3 story and series links

**Goal:** share sheet offers the real AO3 links.

No longer gated on Phase 1 landing — it's landed. Confirmed
`showActivityDialog` in `WebViewController.swift` already shares
`article?.preferredURL` via `UIActivityViewController`, with
`OpenInSafariActivity.swift` and `FindInArticleActivity.swift` as the
existing pattern to follow for a new custom `UIActivity`.

1. **Story link**: per Phase 1's confirmed implementation, Ambrosia's AO3
   story URL flows through the standard JSON Feed `url` field into
   `Article.url`/`preferredURL` with no extra parsing needed — confirmed
   directly in `buildJSONFeedItem`: `url: ao3?.storyURL`. This should
   already work — verify on a real feed before assuming it's fully done
   (and verify against the `.json` route specifically, not `.xml` — see
   Phase 4's note on Ambrosia's OPML export pointing at RSS by default),
   but expect no code change here.
2. **Series link needs building.** Per Phase 1's actual (not originally
   planned) shape, series data lives on `Article.series:
   [ArticleSeriesEntry]?` directly (not behind an `ambrosiaMetadata`
   accessor — that accessor doesn't exist). Add a computed property (on
   `Article` or as a free function) that builds
   `https://archiveofourown.org/series/<ao3ID>` from the first series
   entry's `ao3ID`, when present.
3. **Offer both as separate share actions.** Add a new `UIActivity`
   subclass, "Share AO3 Series Link," following `OpenInSafariActivity.swift`'s
   shape.

**Open question, still unresolved**: always offer both links when both
exist, or make the series link conditional on context? Plan assumes
"always offer both" — flag if different behavior is wanted.

**Done when:** the share sheet offers the AO3 story link (confirmed
working) and, when the work is part of a series, a separate "Share AO3
Series Link" action.

---

## Phase 8 — Immersive reading and swipe navigation

**Immersive reading is already fully built** — confirmed unchanged from
original plan: a tap on `fullScreenTapZone` calls `didTapNavigationBar()` →
`hideBars()`, which sets `AppDefaults.shared.articleFullscreenEnabled =
true`, hides status/nav/toolbar; dedicated tap zones restore via
`showBars(_:)`; state persists across relaunch.

**Open question, still unresolved**: single-tap-on-edge-zones (current
behavior) vs. a literal double-tap for the restore gesture? One-line change
either way (`UITapGestureRecognizer.numberOfTapsRequired = 2`) — need the
answer before touching it.

**Swipe to next/previous article, enable/disable** — not yet built.
Confirmed `ArticleViewController.swift`'s `UIPageViewController`
data-source methods (`pageViewController(_:viewControllerBefore:)` /
`...viewControllerAfter:)`) have no feature-flag guard today.

1. Add `AppDefaults.shared.articleSwipeNavigationEnabled: Bool` (default
   `true`, same pattern as `articleFullscreenEnabled`).
2. Guard the top of both data-source methods with
   `guard AppDefaults.shared.articleSwipeNavigationEnabled else { return nil }`.
3. Leave the separate pinch-to-pop gesture handling untouched — there's an
   existing comment noting the two were deliberately kept from conflicting.
4. Surface the toggle in Settings.

**Done when:** immersive reading behaves as confirmed above (or with the
double-tap change if requested), and swipe-between-articles can be turned
off without affecting back-navigation.

---

## Phase 9 — Full rename: NetNewsWire/Ambrosia Reader → Nectar

**Goal:** every remaining `NetNewsWire`/`AmbrosiaReader` reference becomes
`Nectar`. Last, so no earlier phase's patch carries incidental rename
diffs. Unchanged from the original plan, except: confirm before starting
that the partial `com.ambrosia.AmbrosiaReader` bundle-ID-adjacent renaming
already visible in `Info.plist` (see Phase 0.5.1) is accounted for and
doesn't conflict with this phase's intended end state.

1. **Target/module/product name**: `PRODUCT_NAME`, `PRODUCT_MODULE_NAME`,
   `PRODUCT_BUNDLE_IDENTIFIER` in `xcconfig/NetNewsWire_iOSapp_target.xcconfig`
   and sibling xcconfigs.
2. **Every `Info.plist`** referencing `NetNewsWire.SceneDelegate`,
   `NetNewsWire.AppDelegate`, or any other fully-qualified
   `<OldModuleName>.<ClassName>` string — mismatches here fail silently
   into a black screen (already hit once during initial setup, hence this
   being its own isolated phase rather than a blind find-replace).
3. **Xcode scheme names, target names** — rename via Xcode UI, not manual
   `.xcscheme`/`.pbxproj` editing.
4. **App icon, launch screen, display name strings** beyond the
   `CFBundleDisplayName` from Phase 0.5.1.
5. **Source-level occurrences of `NetNewsWire`/`AmbrosiaReader`** — the
   fully-qualified-class-name pattern (`NetNewsWire.`, trailing dot) is the
   dangerous subset worth isolating first.

**Done when:** no `NetNewsWire`/`AmbrosiaReader` string remains anywhere in
the project except intentional ones (e.g. a credit comment), and the app
builds, launches, and runs identically to before the rename.

---

## Suggested build order

Apply the build error fix first, on `main`, before anyone branches.

Then: **Phase 0.5, Phase 2, Phase 3, Phase 4, Phase 5, Phase 7, and Phase 8
can all start in parallel today** — none of them depend on each other or on
any unfinished phase (Phase 0 and Phase 1 are done). Phase 6 starts once
Phase 5 lands. Phase 9 starts once everything else has landed on `main`.

This replaces the previous fully-linear suggested order — that ordering
was written before Phase 1 was confirmed done, and Phase 1 being the long
pole was the main thing forcing everything after it to wait.

---

## Questions before implementation starts

1. **Chrome-hide gesture** (Phase 8): keep the existing single-tap-on-edge-
   zones behavior, or change the restore gesture to a real double-tap?
2. **Starred rename** (Phase 3): UI copy/icon only, or a full internal
   rename of `starred` throughout the codebase?
3. **Share sheet** (Phase 7): always offer both AO3 story and series links
   when both exist, or should the series link be conditional on something
   more specific?
4. **Still-open feature survey items** (Phase 0): Handoff/Activity,
   notifications, account stats, MarsEdit/micro.blog send-to, Dinosaurs
   Easter egg — keep or cut, per item?
5. **New, from the prior revision**: is the `com.ambrosia.AmbrosiaReader`-style
   naming already visible in `Info.plist` intentional partial rename work
   done outside this plan, or drift that Phase 9 needs to reconcile with?
   Worth answering before Phase 9 starts, not urgent now.
6. **New, from this revision (Phase 4)**: who owns adding QR-code
   rendering to Ambrosia — is that tracked in the Ambrosia-side prep plan
   already, or does it need to be added there? Nectar's scanner half is
   pointless without it.
7. **New, from this revision (Phase 4)**: should Nectar's OPML-import
   rewrite `.xml` → `.json` client-side (no Ambrosia change needed, but
   fragile if Ambrosia ever changes its route naming), or should the
   Ambrosia side add a JSON-flavored OPML export instead (more robust,
   needs a small change on that side)? Recommend raising with whoever owns
   the Ambrosia-side prep plan before building either.
8. **New, from this revision (Phase 4)**: confirm whether Nectar's JSON
   Feed parsing already follows `next_url` for pagination — this couldn't
   be verified from the Nectar-side source alone without a matching
   multi-page test feed, and Ambrosia will paginate at 100 items by
   default for any collection larger than that.
