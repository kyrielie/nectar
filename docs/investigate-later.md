# Investigate later

Open questions that had temporary diagnostic logging attached to them in
the code, where that logging was removed during a vibecoding-cleanup pass
(dead scaffolding, dangling citations to planning docs that don't exist
in the tree) before the underlying question was actually resolved.
Removing the logging did not answer the question — it just means the
question is now tracked here in prose instead of in code comments, and
whoever picks it back up should re-add equivalent instrumentation rather
than assume either "it must be fine" or "it must still be broken."

Each entry: what was being investigated, what the logging looked like
before removal, and the working theory, so it can be reconstructed
without archaeology.

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
