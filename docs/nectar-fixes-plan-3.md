# Nectar fixes plan 3 (rough)

Investigation done by reading code, not by running the app. Confidence noted per item.

**Status:** items 1, 2, 5, 6 implemented by a previous pass (merged). Item 4
implemented in this pass -- see its section below for what was actually
built vs. proposed. Item 3 (AO3-authenticated link opening) is not started:
it's the largest item, has open design questions the plan itself flags as
unresolved (data-store lifetime), and needs a new view controller plus a
build-and-look pass rather than a code-only read -- left for the next
person per the plan's own suggested order of work.

---

## 1. Top toolbar colors wrong when switching appearance in article view

**Confidence: high.** Root cause found by reading code; not yet confirmed on-device with logging, but the mechanism fits the reported symptom exactly (correct after re-entering, wrong on live switch).

### What's actually going on

Two independent, differently-reliable pipelines currently paint article-view chrome:

- **Bottom toolbar** (read/star/heart/nextUnread/action) has no explicit tint of
  its own. It cascades from `UIWindow.tintColor`, which `SceneDelegate` sets from
  `Assets.Colors.primaryAccent` in `handleAccentColorDidChange(_:)`, wired to the
  **synchronous** `.accentColorDidChange` notification. That path is reliable, so
  the bottom toolbar always looks right.

- **Top nav bar** (theme/TOC/find/next/prev buttons, title) is painted by
  `SurfacePaletteNavigationBarAware.applySurfacePaletteNavigationBarAppearance()`,
  which builds a `UINavigationBarAppearance` and sets explicit `tintColor` on
  each bar button item from `AppDefaults.shared.surfaceTint`. This needs to be
  re-run on every palette change while the screen is on screen.

`nectar-architecture.md`'s own "Live-update pipeline shape" section documents
the established pattern for this: every Surface-Palette-consuming screen
observes the **dedicated, synchronous** `.surfaceTintDidChange` notification
(posted directly inside the `surfaceTint` setter, same thread, before the
setter returns) and calls its repaint from that handler. The doc's own
observer list confirms who follows this pattern: `ArticleSearchBar`,
`MainFeedCollectionViewController`, `MainTimelineModernViewController`,
`ColorPaletteTableViewController`, `AccentColorTableViewController`,
`SettingsBackgroundPalette`/`SurfacePaletteAware`, `SettingsViewController`.

**`ArticleViewController` is not on that list.** It never registers for
`.surfaceTintDidChange` (or `.accentColorDidChange`) at all. Instead it
re-applies the nav bar appearance from a single catch-all handler:

```swift
// ArticleViewController.swift
NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
...
@objc nonisolated func userDefaultsDidChange(_ note: Notification) {
    Task { @MainActor in
        coordinator.applyArticleBackSwipeGating()
        navigationItem.rightBarButtonItems = rightBarButtonItems()
        applySurfacePaletteNavigationBarAppearance()
    }
}
```

`UserDefaults.didChangeNotification` is a generic, whole-store notification
with none of the guarantees the architecture doc calls out for the dedicated
notification (same-thread, synchronous, posted before the setter returns).
It's also routed through `Task { @MainActor in ... }`, adding a hop instead of
running inline. That's a plausible, self-consistent explanation for exactly
the reported symptom:

- **Exit and re-enter**: `viewDidLoad()` runs again and calls
  `applySurfacePaletteNavigationBarAppearance()` fresh → correct colors,
  every time.
- **Switch appearance while already in article view**: the nav bar repaint
  depends entirely on the generic notification firing, landing, and being
  processed before something else reads/uses the bar's current appearance —
  no ordering or timing guarantee vs. the reliable, synchronous pipeline the
  bottom toolbar rides on. This is consistent with "sometimes stale, always
  fixed by a fresh `viewDidLoad`."

Comments already in `SurfacePaletteNavigationBarAware.swift` describe a
previous, related bug in the same area ("dark-on-dark/light-on-light toolbar
icons after toggling appearance ... while the screen was already visible")
that was partially fixed by setting bar-button `tintColor` explicitly. That
fix addressed *how* the color is applied once the handler runs; it didn't
address *whether/when* the handler runs, which is this bug.

### Proposed fix

Bring `ArticleViewController` in line with the documented, established
pattern instead of inventing a new one:

1. Add explicit observers for `.surfaceTintDidChange` (and, if instrumentation
   below shows the theme/TOC/find icon tints also drift, `.accentColorDidChange`)
   in `ArticleViewController.viewDidLoad()`, calling
   `applySurfacePaletteNavigationBarAppearance()` directly from the handler —
   same shape as `MainFeedCollectionViewController`/
   `MainTimelineModernViewController`.
2. Decide what to do with the existing `userDefaultsDidChange(_:)` catch-all:
   - `coordinator.applyArticleBackSwipeGating()` and
     `navigationItem.rightBarButtonItems = rightBarButtonItems()` react to
     *other* settings (back-swipe toggle, TOC/find vs. prev/next toggle) that
     don't have their own dedicated notifications today — those two calls
     likely need to stay on the generic path, or gain their own dedicated
     notifications too (bigger change, probably out of scope here).
   - `applySurfacePaletteNavigationBarAppearance()` should move to the new
     dedicated observer and can likely be removed from
     `userDefaultsDidChange(_:)` once the dedicated observer covers it — but
     leaving it in both places is also safe (idempotent re-apply) if we'd
     rather not touch the catch-all in the same patch.
3. Add `ArticleViewController` to the observer list documented in
   `nectar-architecture.md`'s "Live-update pipeline shape" section — the doc
   says explicitly this list should be kept current for the next person.

### Before writing this fix: instrument, per your suggestion

Two small, temporary logging additions to confirm the mechanism rather than
just trusting the static-analysis theory:

- A one-line `os_log`/`Logger.debug` at the top of
  `applySurfacePaletteNavigationBarAppearance()` printing the resolved
  `hexSet`/`tintColor` and a timestamp, so we can see *whether and when* it
  runs relative to an in-app palette switch.
- A one-line log in `userDefaultsDidChange(_:)` itself (it has none today) to
  see how late — or whether at all, in a given run — the generic notification
  arrives after tapping a new palette in Settings.
- For comparison, temporarily add the same style of log to
  `MainFeedCollectionViewController.surfaceTintDidChange(_:)` to see the gap
  in timing between the two paths side by side in the console during one
  palette switch while Article view is on screen.

This should make the race (or non-fire) directly visible in the console
before we touch the observer wiring, and gives us a concrete "before" trace
to compare against once the dedicated-notification fix is in.

### Also worth a quick check while in there

- Confirm whether `themeBarButtonItem`/`tableOfContentsBarButtonItem`/
  `findInArticleBarButtonItem`/`nextArticleBarButtonItem`/
  `prevArticleBarButtonItem` icon *tint* (as opposed to the bar's own
  background/title tint) is affected by the same staleness, or only the bar
  chrome itself — the existing `applySurfacePaletteNavigationBarAppearance()`
  does set `tintColor` on all of `rightBarButtonItems`, so it should be
  covered by the same fix, but worth confirming with the logging above since
  that's the actual user-visible complaint ("toolbar colors").

---

## 2. Series nav buttons in preface should wrap to their own line

**Confidence: high**, this is a small, contained CSS fix.

### Where it renders

`AO3PrefaceRenderer.seriesNavigationRowsHTML(_:)` builds:

```html
<dd class='wide'>
  <span class='ao3SeriesPrefaceEntry'>Part 1 of Series</span>
  <span class='ao3SeriesPrefaceLinks'>First · Previous · Next</span>
</dd>
```

Both are inline `<span>`s with nothing forcing a line break between them, so
they lay out side by side: `Part 1 of Series First Previous Next`.
`core.css` has rules for `.ao3SeriesPrefaceEntry` (`margin-right: 0.5em`) and
`.ao3SeriesPrefaceLinks` (`font-size: 0.95em`) but neither is `display:
block`.

### Proposed fix

Add `display: block;` to `.ao3SeriesPrefaceLinks` in `core.css` (small
addition next to the existing rule at ~line 241), which pushes it onto its
own line below `.ao3SeriesPrefaceEntry` without changing either element's
HTML. A small top margin (e.g. `margin-top: 0.2em`) will likely be wanted so
the wrapped links don't sit flush against the "Part N of Series" line —
should be checked visually once changed, not guessed at here.

Don't touch `.ao3SeriesFooterLinks`/`.ao3SeriesFooterEntry` — the footer
("This work is part of a series:" block after the article body) already uses
a `flex`/`flex-wrap` container and isn't part of what was reported.

This is CSS-only; no Swift or template changes needed. Should be checked
against a work in >1 series (multiple stacked `<dt>/<dd>` rows) and against
a first/last-in-series work (the disabled-link `.ao3SeriesNavDisabled`
styling) to make sure the block-level change doesn't introduce awkward
spacing in those variants.

---

## 3. Open AO3 links using the AO3 user's Nectar login, if signed in

**Confidence: medium-high** on the root cause; the fix is more involved than
the other items and needs a build-and-look pass, not just a code read.

### What's actually going on

Links opened in-app (`AppDefaults.shared.useSystemBrowser == false`, i.e.
"Open Links in NetNewsWire" is on — see item 5 for its rename) go through
`WebViewController.openURLInSafariViewController(_:)`, which presents an
`SFSafariViewController`. `SFSafariViewController` always uses the system's
shared Safari browsing context/cookie jar — there is no API to hand it a
custom cookie store. So even when someone is signed in to AO3 inside Nectar
(`AO3SessionStore.isSignedIn`), a link opened this way lands in an
entirely separate, Safari-owned session that knows nothing about that login.

The signed-in session itself is stored by `AO3SessionStore` as a single
Keychain-backed **raw Cookie header string** (`"name=value; name2=value2"`),
captured once in `AO3LoginViewController` by reading every
`archiveofourown.org` cookie out of that screen's own non-persistent
`WKWebView` cookie store after a successful login. It's designed to be
replayed as a manually-attached `Cookie:` header on `URLRequest`s
(`AO3AuthenticatedFetcher`), not to be dropped into another browsing
context's cookie store directly.

### Proposed fix

`SFSafariViewController` can't carry the session, so AO3 links (when signed
in) need to go through a different, in-app presentation instead:

1. Add a small helper — likely on `AO3SessionStore` — that turns the stored
   `cookieHeaderValue` back into individual `HTTPCookie`/`HTTPCookiePropertyKey`
   dictionaries (`domain: ".archiveofourown.org"`, `path: "/"`, `secure: true`,
   one per `name=value` pair split out of the stored header). This is lossy
   versus the original captured cookies (expiry/httpOnly flags aren't kept
   today), which should be fine for "browse while signed in" but is worth
   flagging as a known limitation in the doc comment.
2. Add a small dedicated view controller (new file, e.g.
   `AO3AuthenticatedWebViewController` — name TBD) that wraps a plain
   `WKWebView` with its own persistent-enough `WKWebsiteDataStore`, sets those
   cookies on `configuration.websiteDataStore.httpCookieStore` before
   `load(_:)`, and presents basic chrome (title, Done button; "Open in
   Safari" as an escape hatch is probably worth keeping, mirroring what
   `SFSafariViewController` gave for free). This does not need to be
   anywhere near as feature-rich as `WebViewController` — it's a bare
   authenticated browser, not the article reader.
3. In `WebViewController.openURL(_:)` / `openURLInSafariViewController(_:)`
   (and the `decidePolicyFor:` link-tap path that calls it), branch: if the
   URL's host is an AO3 domain (reuse the domain list already centralized in
   `AO3LinkListImporter`, e.g. `archiveofourown.org`/`.com`/`.net`/`.gay` and
   their `www.`/`download.`/`secure.`/`insecure.` variants — don't
   re-derive a second, possibly-drifting list) **and** `AO3SessionStore.isSignedIn`,
   present the new authenticated web view controller instead of
   `SFSafariViewController`. Otherwise, keep today's behavior unchanged
   (signed out, or a non-AO3 link) — no regression for the common case.

### Open questions to settle before/while implementing

- Should "Open Links in NetNewsWire" being **off** (system browser / actual
  Safari.app) also get the authenticated-session treatment, or is this only
  for the in-app case? Handing cookies to the *system* Safari app isn't
  really possible/desirable the same way — recommend scoping this fix to the
  in-app case only, which is what was actually asked for ("opened in
  netnewswire").
- Whether to reuse one `WKWebsiteDataStore` across repeated authenticated-link
  opens (so cookies/session persist across taps within one app run) or create
  a fresh one per presentation and re-seed cookies each time from
  `AO3SessionStore` — the latter is simpler and keeps a single source of
  truth (the Keychain-backed store), recommend starting there.
- Confirm `AO3SessionStore`'s stored cookie value is still fresh enough to be
  useful for browsing (it's read/validated lazily elsewhere via
  `AO3ChapterFetcher.retryAuthenticated(url:)` clearing it on rejection) —
  an expired session would just silently look logged-out in the new browser
  view, which is an acceptable degrade, not a crash risk.

---

## 4. Preface flash while content is being fetched -- IMPLEMENTED

Built as proposed below, with the idempotency question resolved: all of
`processPage()`'s steps (`main.js`) address elements fresh by selector on
each call and don't stash cross-call state at the document/window level, so
re-running it against a freshly-swapped `#bodyContainer` is safe -- the old
subtree is simply gone, replaced by unprocessed nodes, the same shape as a
first pass on initial load.

Changes:
- `main_ios.js`: new `updateArticleBody(html)` (`withEncodedArg`-wrapped,
  matching `updateNectarSeriesLink`'s pattern) replaces `#bodyContainer`'s
  `innerHTML` and re-runs `processPage()`.
- `WebViewController.swift`: new `updateArticleBodyInPlace(reason:)` re-runs
  `ArticleRenderer.articleHTML` for the current article and evaluates
  `updateArticleBody(...)` instead of calling `loadWebView(reason:)`. Wired
  into both `ao3ChapterFetchDidComplete(_:)` and `ao3ChapterFetchDidFail(_:)`,
  matching the plan's note that the failure path should get the same
  treatment. Falls back to a full `loadWebView(reason:)` reload if there's no
  existing web view to update in place, or if encoding the body HTML fails.

Not yet confirmed on-device: scroll position preservation across the swap
(the plan's item 4 point 4) and whether `#bodyContainer`'s height change
shifts the current scroll offset. Worth checking against a real
AO3-chapter-fetch-completes case before considering this fully done.

### Original proposal (for reference)

**Confidence: medium.** Mechanism is well-supported by what the code already
does elsewhere for exactly this class of problem, but I ran out of budget to
verify one piece (whether `main.js`'s `processPage()` pipeline is safe to
re-run) before writing this section, so flagging that explicitly below
rather than asserting it.

### What's actually going on

`WebViewController.setArticle(_:)` renders synthetic preface content
immediately (built from already-parsed feed fields via
`ArticleRenderer.articleHTML`), then fires
`AO3ChapterFetcher.shared.fetchIfNeeded(for: article)` in the background. On
completion, `ao3ChapterFetchDidComplete(_:)` re-fetches the now-updated
`Article` and calls:

```swift
self.loadWebView(reason: "ao3ChapterFetchDidComplete(\(fetchedArticleID))")
```

Since the existing `webView` is non-nil and `replaceExistingWebView` defaults
to `false`, this takes `loadWebView`'s fast path straight into
`renderPage(webView)`, which re-renders the **entire** page via WebKit's
normal HTML-loading path (not a targeted DOM update) — same document,
same `WKWebView` instance, but a full reload of `[[body]]` (preface +
article content + series footer all together, per `template.html`), which is
what produces the visible flash: the whole content area blanks and repaints,
rather than just the piece that actually changed.

This is architecturally the same shape of problem the codebase has already
solved once, for series-nav link taps: `main_ios.js`'s
`updateNectarSeriesLink()` repaints just the tapped link's text/state "in
place, without a full page reload/scroll-position loss" (its own doc
comment), instead of doing a `loadWebView` round-trip.

### Proposed fix (no preloading, as requested)

Do the same kind of targeted, in-place DOM update for the chapter-fetch-
complete case instead of a full reload:

1. Add a JS function to `main_ios.js`, e.g. `updateArticleBody(html)`
   (mirroring `updateNectarSeriesLink`'s `withEncodedArg` pattern), that
   replaces `#bodyContainer`'s contents with the newly-rendered body HTML.
   `template.html` already funnels preface + content + series footer through
   one `[[body]]` substitution into `<div id="bodyContainer">`, so one
   targeted swap covers all three without needing to special-case the
   preface separately.
2. In `WebViewController.ao3ChapterFetchDidComplete(_:)`, replace the
   `self.loadWebView(...)` call with a new method that re-runs
   `ArticleRenderer.articleHTML(article:theme:timelineFeed:)` against the
   refetched article and calls
   `webView.evaluateJavaScript("updateArticleBody(\"<base64>\");")` instead
   of reloading the page. This keeps today's synthetic-preface-first
   behavior (no preloading, nothing changes about *when* the fetch starts)
   and only changes *how* the result is applied once it lands.
3. **Needs verification, not yet done:** `main.js` only runs its
   post-processing pipeline (`flattenPreElements`, `styleLocalFootnotes`,
   `removeWpSmiley`, `applyVersalCaps`, `applyChapterDividers`,
   `postRenderProcessing` — all inside `processPage()`) on
   `DOMContentLoaded`, which won't fire again after an `innerHTML` swap.
   `updateArticleBody` will need to call `processPage()` (or the relevant
   subset) again after swapping in the new HTML, or those steps silently
   stop applying to the fetched content (broken footnote styling, no versal
   caps, no chapter dividers, etc. on the enriched version of the page).
   Before writing this, check whether each of those steps is safe to run
   twice against the same document (idempotent), since the *old* DOM nodes
   are gone but anything that mutated document-level state (not just
   in-`bodyContainer` nodes) could double-apply. This is the one piece of
   this fix I'd want to actually trace through `main.js` line by line before
   writing code, rather than assume.
4. Scroll position: a full `loadWebView` already has its own scroll-restore
   handshake (`scrollRestoreComplete` message, `windowScrollY`) for the
   normal "opening an article" case. An in-place swap should naturally
   preserve scroll position (native browser behavior for a DOM mutation, not
   a navigation) — worth confirming empirically rather than asserting, since
   `#bodyContainer`'s height changing (synthetic preface → real, likely
   longer, preface/content) could shift what's under the current scroll
   offset even without WebKit resetting it outright.
5. `ao3ChapterFetchDidFail(_:)` has the same "unlike the success path... just
   re-render in place" comment and calls the same `loadWebView(...)`
   full-reload path today — worth applying the identical fix there too,
   since a failure message appearing is presumably a smaller, equally
   flash-prone update.

---

## 5. Default settings changes

**Confidence: high**, all confirmed against `AppDefaults.swift`'s
`registerDefaults()` and the relevant enum definitions. This is the
mechanical/low-risk item — only affects fresh installs (or anyone who resets
defaults), never overrides an existing choice, since `register(defaults:)`
only supplies fallbacks for keys with no stored value.

All changes are in `iOS/AppDefaults.swift`, `registerDefaults()`
(`~line 1066`), plus one storyboard label (item 6, folded in below since it's
in the same settings screen).

| Setting | Key | Current default | New default |
| --- | --- | --- | --- |
| Default theme | `Key.currentThemeName` | `Self.defaultThemeName` ("Default" sentinel → built-in fallback theme) | literal `"Promenade"` (matches `Promenade.nnwtheme`) |
| Badge colors | `Key.badgeColorMode` | `BadgeColorPalette.monochrome` (1) | `BadgeColorPalette.default` (2) |
| Hide Notch in Full Screen | `Key.hideNotchInFullScreen` | not registered → `false` | `true` — **new dict entry** |
| Show Previous/Next Article Buttons | `Key.showPrevNextArticleButtons` | `true` | `false` |
| Enable Swipe Back | `Key.articleBackSwipeEnabled` | `true` | `false` |
| Enable Full Screen Articles | `Key.articleFullscreenEnabled` | `false` | `true` |
| Show Table of Contents/Find Buttons | `Key.showTableOfContentsAndFind` | not registered → `false` | `true` — **new dict entry** |
| Page Counter | `Key.pageCounterDisplayMode` | not registered → `.off` | `PageCounterDisplayMode.percentage.rawValue` — **new dict entry** |
| Timeline, number of lines | `Key.timelineNumberOfLines` | `2` | `3` |
| Timeline, tag display | `Key.timelineTagDisplayMode` | `TagDisplayMode.compact` (1) | `TagDisplayMode.badges` (3) — "bubbles" |
| Show Last Updated Label | `Key.showLastUpdatedLabel` | `true` | `false` |

Notes:

- **Do not** change `AppDefaults.defaultThemeName`/`ArticleTheme`'s own
  "Default" sentinel constant — it's reused as a fallback throughout
  `ArticleThemesManager` (e.g. when a saved theme name no longer resolves)
  and isn't the same concept as "what a fresh install starts with." Only the
  `registerDefaults()` dictionary entry for `Key.currentThemeName` should
  change, to the plain string `"Promenade"`.
- `Key.articleFullscreenAvailable` should **not** be touched — it's a
  device-capability flag set at runtime by `SettingsViewController` (notch/
  Dynamic Island detection), not a user-facing default; only
  `articleFullscreenEnabled` is the "Enable Full Screen Articles" toggle
  proper (`logicalArticleFullscreenEnabled` is the AND of both).
- `hideNotchInFullScreen`, `showTableOfContentsAndFind`, and
  `pageCounterDisplayMode` currently have **no entry at all** in the
  `registerDefaults()` dictionary, so they silently fall back to
  `UserDefaults`' own zero-value (`false` / empty string → `.off`) today.
  Adding explicit entries is required, not just changing an existing value.
- Should confirm intent on `pageCounterDisplayMode`: its own doc comment
  notes turning it on "implies hiding the notch regardless of
  `hideNotchInFullScreen`'s own value" — since both are being defaulted on
  together here, that's consistent (no conflicting state), just noting it's
  understood, not accidental.

---

## 6. Rename "Open Links in NetNewsWire" → "Nectar"

**Confidence: high**, trivial. `iOS/Settings/Settings.storyboard` (~line 340)
has the row's `<label>` with `text="Open Links in NetNewsWire"`. Change the
`text` attribute to `"Open Links in Nectar"`. The `userLabel` on the
neighboring `<switch>` (line 346, `userLabel="Open Links in NetNewsWire"`) is
an Interface Builder editor-only annotation, not user-facing text — leave it
alone unless we want to keep IB's outline readable, in which case it can be
updated too for consistency, but it has no functional or visible effect
either way.

Should also grep for any other user-visible string that says "NetNewsWire"
in a Nectar-branded context before considering this done — this task only
asked about this one setting label, so scope is deliberately limited to that
unless you want a broader sweep.

---

## Suggested order of work

1. Item 5 (defaults) and item 6 (rename) — mechanical, no design decisions,
   do together.
2. Item 2 (series nav CSS) — small, isolated, no design decisions.
3. Item 1 (toolbar colors) — add the logging first, confirm the race/timing
   on-device, then wire the dedicated-notification fix.
4. Item 4 (preface flash) — needs the `main.js` idempotency check before
   writing the Swift/JS change.
5. Item 3 (AO3-authenticated link opening) — largest item, new view
   controller, needs a design decision on data-store lifetime (see open
   questions) before starting.
