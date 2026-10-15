# Investigate later

Open questions that no longer have a home elsewhere in the docs, found
during a vibecoding-cleanup pass while resolving dangling citations to
planning docs that don't exist anywhere in the tree. Two kinds of entry:

- Questions that had temporary diagnostic logging attached to them in the
  code, where that logging was removed as dead scaffolding before the
  underlying question was actually resolved. Removing the logging did
  not answer the question — it just means the question is now tracked
  here in prose instead of in code comments, and whoever picks it back
  up should re-add equivalent instrumentation rather than assume either
  "it must be fine" or "it must still be broken."
- Open, unresolved questions that were attributed to a specific
  planning/audit document that turned out not to exist in the tree, with
  no indication the underlying question was ever actually answered
  elsewhere.

Each entry: what was being investigated, what evidence (logging or
otherwise) previously existed, and the working theory, so it can be
reconstructed without archaeology.

## Native UIKit colors possibly lagging WKWebView's `prefers-color-scheme` on live appearance switch

**Where:** `iOS/Article/WebViewController.swift` —
`registerForTraitChanges` handler and `applyResolvedBackgroundColors()`.

**Question:** when the person flips the in-app Appearance setting (or the
system auto-switches) while an article is open, does WKWebView's own
`@media prefers-color-scheme` CSS re-evaluate before, after, or
same-frame as the native trait-change handler that repaints
`webView.backgroundColor`/notch cover/page counter? If native colors
resolve before the CSS side has caught up, there could be a brief
one-frame mismatch between the native chrome and the article body.

**What the removed logging did:** on each `registerForTraitChanges` fire
with an actual style change, logged the previous/new
`userInterfaceStyle`, the webview's own trait snapshot, the current
in-app palette, and the article ID; then, via a `logCSSColorSchemeAgreement`
helper, ran a `evaluateJavaScript` round-trip asking the page directly
whether `window.matchMedia('(prefers-color-scheme: dark)').matches` and
what `getComputedStyle(document.body).backgroundColor` currently
reported, logging both sides so they could be diffed by eye.

**Reproduction path assumed:** an article already open (loaded document,
not mid-`renderPage()`), then toggling Settings → Appearance (or letting
the system auto-switch) while that article stays on screen.

**Status:** never confirmed on-device either way. See
`docs/article-color-pipeline.md` for the surrounding pipeline this sits
in.

**To resume:** reintroduce logging equivalent to the above (or use the
Xcode debugger / View Debugger's color inspector directly instead of
`os.Logger`), reproduce on-device with the path above, and if a real lag
is confirmed, fold the finding into `docs/article-color-pipeline.md`
directly rather than leaving it here.

## Whether nav bar / toolbar colors reliably repaint on a live in-app palette switch, across all three adopting screens

**Where:** `Shared/Extensions/SurfacePaletteNavigationBarAware.swift` —
`applySurfacePaletteNavigationBarAppearance()`.

**Question:** when the person changes Surface Palette or Accent Color
while `ArticleViewController`, `MainFeedCollectionViewController`, or
`MainTimelineModernViewController` is on screen, does the nav
bar/toolbar reliably repaint on all three, or does at least one lag/miss
a repaint depending on scroll position or which palette was previously
active? Working theory (unconfirmed) in `docs/app-chrome-palette.md`: this
may be the same class of observer-list gap described there for Accent
Color (a screen missing a dedicated `.surfaceTintDidChange`/
`.accentColorDidChange` observer), and/or may overlap with the
transparent-scroll-edge `toolbarStyle` bugfix documented in the same
file — but nothing here confirms either theory on-device.

**What the removed logging did:** a single `os.Logger` debug line in the
`.system` branch of `applySurfacePaletteNavigationBarAppearance()`,
logging the adopting screen's type whenever that branch ran and reset to
system appearance. On its own this only covered one of three branches
(`.system`, not `.tinted`/`.blend`) and didn't log per-screen repaint
timing relative to the palette-change notification firing — it was a
starting point, not complete coverage of the question.

**Status:** never confirmed on-device. See `docs/app-chrome-palette.md`
for the full toolbar-style/palette system this sits in.

**To resume:** logging that actually answers the question needs to cover
all three `toolbarStyle` branches (not just `.system`) and needs to be
timestamped relative to the `.surfaceTintDidChange`/`.accentColorDidChange`
notification firing, on all three adopting screens, not just one branch
on whichever screen happens to trigger it first. Reproduce by switching
Surface Palette while each of the three screens is on screen, at both
scroll-edge and mid-scroll positions. Fold the finding into
`docs/app-chrome-palette.md` once confirmed.

## iPad support status

**Where:** referenced from `iOS/MainTimeline/MainTimelineModernViewController.swift`
(a popover-anchor comment), previously citing "the July audit" as the
place this was tracked.

**Question:** `xcconfig/common/NetNewsWire_ios_target_common.xcconfig` sets
`TARGETED_DEVICE_FAMILY = 1,2`, so the app still builds and installs on
iPad, but nothing in the tree suggests iPad has had deliberate layout
attention beyond scattered popover-anchor guards (like the one that
pointed here) needed just to avoid a crash on `UIAlertController`
presentation. Whether the app is meant to be a real supported iPad
experience, an iPhone-only experience that happens to still build for
iPad, or something in between, isn't stated anywhere in the current docs.

**Status:** the "July audit" this was attributed to is not present
anywhere in the current tree -- another dangling reference, found and
resolved during the vibecoding cleanup pass. Whatever findings that audit
had about iPad support, if any, weren't carried into any current doc.

**To resume:** decide (and document in `CLAUDE.md`'s routing table once
decided) whether iPad is in scope; if it is, audit `UISplitViewController`/
regular-vs-compact size-class handling across `SceneCoordinator.swift`
and the Settings/MainFeed/MainTimeline/Article view controllers, since
none of the current docs describe any iPad-specific layout path. If it's
explicitly out of scope, consider setting `TARGETED_DEVICE_FAMILY = 1`
so the build configuration matches reality.
## Annotation offset drift after deletion

Deleting an annotation reverts or unwraps its live DOM row before removing the
database record. Existing later rows can still have offsets captured against
the pre-deletion article text; re-rendering/re-anchoring handles many cases,
but offset drift after a sequence of edits and deletions remains an open
investigation. Do not treat the deletion callback as a complete offset-shift
solution.

## "More notes" pointer link may not scroll to the end notes

**Where:** the `p.jump` / `div.endnote-link` pointer ("See the end of the work
for more notes") inside `.notes.module`, and `WebViewController`'s
`decidePolicyFor navigationAction`.

**Question:** does the pointer link actually move the reader to the end notes?
Two cases, not yet verified on a device:

- **AO3-fetched works** (`href="#work_endnotes"`, target `div#work_endnotes`
  present in the `AO3KitTests` fixtures). The handler only intercepts
  `nectar-series:` links and http(s)/mailto/tel; a bare fragment falls through
  to `.allow`, so WebKit should scroll. Open points: the page loads with
  `loadHTMLString(_, baseURL:)` using the article's base URL, and where
  `Article.baseURL` comes from was not traced, so it is unconfirmed whether the
  fragment stays a same-document jump. With `disableArticleLinks` on, every link
  activation is cancelled, this one included. No test covers it.
- **Calibre/Ambrosia imports.** The Ambrosia fixture's pointer is
  `nudes_split_003.xhtml#endnotes`, an EPUB split-file link. Nothing in `Shared`
  or `iOS` rewrites `.xhtml` hrefs, so it likely resolves against the article's
  host and opens as a dead browser link. The target (`id="endnotes"`) is in the
  same HTML.

**Working theory / proposed fix:** rewrite `*.xhtml#frag` to `#frag` at render
time for the Calibre case, and add a test for the AO3 case.

**To resume:** reproduce on device for both shapes; add a JS or Swift test that
a fragment pointer resolves to an element in the article; decide whether the
rewrite belongs in `ArticleRenderer` or at import. Not implemented.

## Duplicate series blocks and the missing "Works inspired by" block

**Where:** `AO3ChapterHTMLExtractor.serializedContentHTML`,
`AO3PrefaceRenderer.seriesFooterHTML`, `Shared/Article Rendering/core.css`,
`docs/theme-anatomy.html` (blocks 15 to 17).

**Question:** should AO3's own afterword series module (`div#series.series.module`,
with plain `/works/ID` Previous/Next Work links) be removed in favor of Nectar's
footer (`#ao3SeriesFooter`, `nectar-series:` links), and should "Works inspired by
this one" get a Nectar-built block?

**Current state (read from code and fixtures, not run on device):**
- The extractor serializes the whole `#workskin` div, so AO3's series module is
  shipped in the body alongside the preface Series row and `#ao3SeriesFooter`.
  A work in a series can show three series blocks.
- AO3's links are ordinary http(s) hrefs, which `decidePolicyFor` should send to
  the browser or in-app AO3 browser. Nectar's links stay inside the reader, so
  the two Next buttons likely behave differently.
- The footer shows "Part N of Series" as plain text, so no link to the series page
  remains if AO3's module is removed.
- "Works inspired by this one" is only confirmed in the Ambrosia/Calibre fixture (a
  `dl` in the afterword). No real AO3 page with that block is in the repo, so its
  class names and its position relative to the series module are unverified.

**Proposed changes:**
1. Remove `div#series` from the serialized afterword in the extractor (preferred over
   `display: none` in `core.css`, which also covers already-fetched works but leaves
   hidden text in the DOM). Fetched works only update on open or "Check for
   updates", so already-stored content keeps the block until then; decide whether a
   CSS fallback is worth carrying meanwhile.
2. Make the footer's series name a link to the series page, using the series URL
   the extractor already parses.
3. Check annotation offsets: `annotations.js` indexes text nodes under
   `.articleBody`. The series module sits after the prose, so earlier highlights
   should not shift, but verify, and check highlights that touch the end notes.
4. Capture a real AO3 page with "Works inspired by" as a fixture. Then add parsing
   to `AO3WorkPageMetadata` and a Nectar-rendered block, with links routed into the
   app's fetch flow like `nectar-series:`. Until then, leave AO3's block as is.
5. Update docs in the same change: `ao3-preface-rendering.md`, `ao3-feeds.md`,
   `nnwtheme-format.md` (styleable blocks table), and `theme-anatomy.html` (hide or
   remove block 15, add the new block, renumber).

**Not decided:** the order of the inspired-by block relative to the series footer.

## Allowing `[[avatar_src]]` to render in custom themes

**Where:** `Shared/Article Rendering/main.js` (`removeArticleIconAvatar`),
`iOS/Article/ArticleIconSchemeHandler.swift`, the Settings preview script in
`ArticleThemePreviewWebView`, `Shared/Extensions/SmallIconProvider.swift`,
`Shared/IconImageCache.swift`.

**Background:** `main.js` deletes every `img[src^="nnwimageicon:"]` at load. The
original reason was to avoid editing the stock templates, because the image was
the generic fallback icon. Now that fully custom themes exist, a theme may want it.
37 of the 168 bundled and gallery templates contain `[[avatar_src]]`, mostly the
stock-style header avatar cell, so lifting the strip globally would change them.

**What the code shows (read, not run on device):**
- The AO3 image is the bundled vector `archiveOfOurOwnFeedIcon.svg` (600x415,
  `preserves-vector-representation`, loaded with `isBackgroundSuppressed: true`). It
  is the AO3 site mark, not a per-author avatar.
- `article.iconImage()` resolves `imageForAuthors` first, then `imageForFeed`. AO3
  extractors set `avatarURL: nil` for authors, so the author branch finds nothing
  and AO3-feed articles get the bundled mark through `archiveOfOurOwnBundledIcon`.
- The handler draws that icon into a fixed 48x48 point `IconView`. `asImage()` uses
  `UIGraphicsImageRenderer`, which should default to the screen scale (about 144 px
  on a 3x phone).
- The bundled icon only applies when the feed's `homePageURL` or `url` is a
  recognized AO3 host (`AO3Link.isAO3Host`).

**Proposed changes:**
1. Make avatar rendering opt-in with an attribute (for example `data-show-avatar` on
   `#bodyContainer`), so existing and user-installed themes keep today's behavior.
   `removeArticleIconAvatar()` skips images when it is present.
2. Mirror the same check in the Settings preview script, which has its own removal.
3. Add a size parameter to the `nnwImageIcon:` URL and render the `IconView` at the
   requested size, instead of the fixed 48 points.
4. Decide fallback behavior for non-AO3 feeds (downloaded favicon or generated
   letter icon) and whether a theme can detect "no real avatar" to hide the slot.
5. Check Ambrosia-served articles: their feed URL may not be an AO3 host, so they
   would get a favicon or generated icon instead of the AO3 mark. Check what
   Ambrosia sets for `homePageURL` and consider an AO3 match on the article URL.
6. Look for tests that depend on the strip or the 48x48 size before changing either.
7. Update docs in the same change: `nnwtheme-format.md` (lines about
   `[[avatar_src]]` and the header block), `theme-system.md`, `creating-a-theme.md`,
   and `theme-anatomy.html` (note 2, the variables card row saying the image never
   renders, and an avatar in the mock header).

**To resume:** confirm on device what an AO3 feed article's `avatar_src` returns today
and at what pixel size, before deciding on the size parameter.
