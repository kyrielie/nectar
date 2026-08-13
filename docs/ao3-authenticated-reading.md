# AO3 authenticated reading (login, kudos, in-app browser)

New since the original architecture-doc split described in `CLAUDE.md`:
optional AO3 sign-in and the features it unlocks. This doc exists because
the code does, not because an existing section was split out of the
retired monolithic doc. See `ao3-preface-rendering.md` for the anonymous
chapter-fetch path this builds on, and `refresh-throttling.md` for the
general AO3 request gating this cluster adds its own layer on top of.

In-code comments attribute this work to "Workstream 3" (login), "Task 6"
(kudos-on-like), and "Task 8" (an audit that fixed a gating leak — see
below), citing `docs/ao3-merged-plan-nectar.md`,
`docs/ao3-merged-plan.md`, and `nectar-ao3-features-plan-FINAL.md`
respectively. **None of those three files exist anywhere in the current
tree.** This is the same dangling-reference pattern flagged in
`sqlite-transfer.md`, `refresh-throttling.md`, and `ao3-preface-rendering.md`
— now five confirmed missing planning docs across the codebase (a sixth,
`docs/nectar-fixes-plan-3.md`, is cited by `AO3AuthenticatedWebViewController.swift`
below and *did* exist in an earlier snapshot of this repo, but is absent
from the current one — worth confirming with whoever has the canonical
history whether this was an intentional cleanup or an accidental loss).

## Three separate, deliberately unshared credential mechanisms

Easy to conflate; each exists for a different reason and none reuse the
others' storage or transport:

1. **`AO3SessionStore`** (Keychain-backed, `Modules/Account`) — a signed-in
   AO3 session captured by `AO3LoginViewController` (an in-app WKWebView
   against AO3's real login page; Nectar never sees the password, only
   reads every `archiveofourown.org` cookie back out of the WKWebView's
   own non-persistent cookie store once login succeeds, and stores them as
   a single Cookie-header string). Used exactly once per retry, by
   `AO3AuthenticatedFetcher`, which manually attaches that Cookie header
   to a one-off `URLSession` request — specifically
   `AO3ChapterFetcher.retryAuthenticated(url:)`, fired only when an
   anonymous chapter fetch comes back `.registrationRequired` (a
   login-gated work). Deliberately bypasses `Downloader.shared`: the
   anonymous fetch that produced `.registrationRequired` for that exact
   URL is already cached in `Downloader`'s response cache, so routing the
   authenticated retry through it would silently hand back the stale,
   unauthenticated response. A `.registrationRequired` retry result clears
   the stored session (it's treated as expired/revoked).
2. **`AO3AuthenticatedWebViewController`** (iOS app target) — a small
   dedicated WKWebView-based in-app browser, scoped only to AO3 links
   *tapped* in-app (`WebViewController.openURLInAppBrowser(_:)` routes to
   it instead of `SFSafariViewController` when `AO3LinkListImporter.isAO3Host(_:)`
   matches; every other URL still goes to Safari). Exists because
   `SFSafariViewController` always uses the system's shared Safari cookie
   jar with no API to hand it a custom store, so an `AO3SessionStore`
   session could never follow a link tap into it. **Deliberately not
   wired to `AO3SessionStore`** — it uses its own persistent
   `WKWebsiteDataStore` (a fixed, non-default identifier, isolated from
   the article-reading webview's own data store so arbitrary rendered
   feed/article content can't reach a signed-in AO3 session's cookies by
   sharing a store) and lets WebKit handle all Set-Cookie/session
   persistence natively, including a "remember me" login performed
   directly inside this browser. No cookie reading/writing code needed
   here — genuinely a different mechanism from (1), not a refactor of it.
3. **`AO3ChallengeSessionStore`** (Keychain-backed, `Modules/Account`) —
   an anonymous Cloudflare-clearance cookie, captured the same way (1) is,
   by a separate `AO3ChallengeSolverViewController`, but kept in its own
   store because it represents something different: proof of "a real
   browser," not "a signed-in person," and is short-lived by Cloudflare's
   own design. Tracks a captured-at date and `cookieHeaderValueIfFresh`
   refuses to hand back a stale one — check this file before assuming a
   captured challenge cookie is still usable.

## Kudos-on-like (`AO3KudosManager`, off by default)

`AO3KudosOnLikePreference.isEnabled` (`NectarAppGroupUserDefaults`-backed,
default `false`) gates whether loving an AO3-sourced article also POSTs a
kudos on the person's behalf. Two entry points funnel into one shared
eligibility gate (toggle on, book loved, a CSRF token available, no
already-authenticated attempt already on record for that `bookKey`) and
one re-attempt policy (a prior *guest* kudos attempt is retried once
signed in — a guest and authenticated kudos are AO3-side distinct
identities — but an authenticated attempt, successful or not, is never
retried automatically):

- **Piggyback path** (`attemptKudosIfNeeded`, called from
  `AO3ChapterFetcher.download`'s success handler) — reuses the CSRF token
  that fetch's own page load already scraped, no dedicated request.
- **List-view path** (`attemptImmediateKudosIfNeeded`, called from
  `SceneCoordinator` when an article is loved via swipe/context menu
  rather than by opening it) — dispatches its own dedicated,
  token-only fetch, since there's no accompanying page load to piggyback
  on and the person is expecting near-immediate kudos-on-like behavior,
  not "whenever this article's chapter next happens to refetch."

**Known gotcha, already fixed once, worth re-checking on any future
change here:** the list-view path originally fired its dedicated AO3
request without checking `AO3ChapterFetcher.isAO3NetworkRequestAllowed(for:)`
— the same local-only-reader gate (`AmbrosiaAO3NetworkPreference`, below)
that the piggyback/chapter-fetch paths already respected. That let a
swipe-love on an Ambrosia-sourced work reach AO3 even with the
local-only-reader toggle on. Fixed by adding the same gate check to the
list-view path explicitly — any *new* AO3-request path added to this
manager needs the same gate, since it's not automatically inherited.

Both entry points are fire-and-forget: neither returns a value or throws,
and failures surface only in the Activity Log
(`ActivityOwner.ao3KudosManager`), same as `AO3ChapterFetcher`'s own
failures.

## Related preferences (all `NectarAppGroupUserDefaults`-backed, not `AppDefaults`)

Live in the `Account` module rather than `AppDefaults`/iOS app target for
the same reason: the code that actually reads them (`AO3ChapterFetcher`)
shouldn't need to depend on the iOS app target, and the Settings UI reads/
writes the same underlying key through these types rather than a second,
possibly-drifting `UserDefaults` suite. All three are exposed from the
same **Settings → Archive of Our Own** screen (`AO3AccountSettingsView`,
pushed from a new row in `SettingsViewController`, following the same
`UIHostingController`-push pattern as `AboutView`/`AccountStatsView`):

- **`AmbrosiaAO3NetworkPreference.updatesEnabled`** — "Fetch AO3 Updates
  for Library Works." The one on/off switch for keeping Nectar off AO3
  servers entirely when used purely as a local Ambrosia/Calibre archive
  reader; native (non-Ambrosia) AO3-RSS-sourced articles are unaffected
  and always fetch, since they have no other content source. Originally
  two separate flags (content updates / stats updates), collapsed to one
  since both come off the same HTTP fetch.
- **`AO3PrefaceRefetchPreference`** — a refetch-cadence picker. Once a
  work's chapter count matches `chapterCurrent`, `AO3ChapterFetcher.isStale`
  goes false *permanently*, so nothing re-checks a "settled" work for new
  comments/kudos/hit-count changes or formatting fixes. This preference
  adds a second, independent staleness trigger: refetch if the last
  successful preface fetch is older than the chosen interval, regardless
  of chapter count.
- **`AO3KudosOnLikePreference.isEnabled`** — described above.

`AO3AccountSettingsView` also surfaces sign-in state
(`AO3SessionStore.isSignedIn`) and a captured-challenge timestamp
(`AO3ChallengeSessionStore.capturedAt`) as plain read state, not
independent preferences.

## Settings-screen inventory note

This entire screen (and everything it exposes) is invisible to
`docs/settings-screen.md`'s coverage of the main `SettingsViewController`
storyboard list, since it's a SwiftUI screen pushed from one row there
rather than a row itself. Anyone auditing "what settings exist" needs to
check both places.
