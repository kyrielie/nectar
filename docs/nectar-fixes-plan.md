# Nectar fixes: scroll position, feed titles, missing book

## 1. Scroll position — fix the viewDidLoad/setArticle race

**Root cause (traced in `iOS/Article/WebViewController.swift` and
`ArticleViewController.swift`):** `ArticleViewController.viewDidLoad` always
renders the article at `windowScrollY == 0` before `setArticle`'s async
`account.fetchScrollPosition(forArticleID:)` has resolved, then a second
render fires later with the correct value. The two renders' WKWebView
`contentOffset` reset events race against a single `suppressNextScrollSave`
boolean, so the *correct* load's reset can go unsuppressed, get read as a
genuine scroll to 0, and get written back into the database — overwriting
the real position with 0. This happens on every article open, not just
relaunch.

### Fix 1a — don't render at 0 before the fetch resolves (primary fix)

In `WebViewController`, stop calling `loadWebView(reason: "viewDidLoad")`
unconditionally from `viewDidLoad()` when a scroll-position fetch is already
in flight for this article.

- Add a private flag, e.g. `private var isAwaitingInitialScrollFetch = false`.
- In `setArticle`, when `updateView` is true and there's a valid
  `article`/`account`, set `isAwaitingInitialScrollFetch = true` *before*
  kicking off the `Task`, and clear it in the `Task` right before calling
  `self.loadWebView(reason: "setArticle(...) after scroll fetch")` (both on
  the success path and the "article changed, discard" early-return path —
  clear it there too, or the flag can get stuck true for the next article).
- In `viewDidLoad()`, change the unconditional call to:
  ```swift
  if !isAwaitingInitialScrollFetch {
      loadWebView(reason: "viewDidLoad")
  }
  ```
- Net effect: when `setArticle` already has a fetch in flight, `viewDidLoad`
  does nothing and the *first* render is the one with the correct
  `windowScrollY`. `loadWebViewGeneration`'s existing stale-completion guard
  still protects against any leftover races (e.g. `nil` article path, or
  `updateView: false` callers), so this is additive, not a replacement for
  it.
- This also removes the double `loadHTMLString` call (and its visible
  reload flash) in the common case, which is what `loadWebViewCallCount`'s
  diagnostic comment was tracking.

### Fix 1b — make the reset-suppression handle overlapping loads

Even with 1a, keep this as defense in depth for the remaining legitimate
double-load paths (theme change, `contentSizeCategoryDidChange`, the
`nil`-article path in `setArticle`, and the still-declared-but-currently-
unset `restoreState`/`currentState` pair in `ArticleViewController`, which
is dead code today but shouldn't become live and reintroduce this bug):

- Replace `private var suppressNextScrollSave = false` with a count:
  `private var pendingLoadResets = 0`.
- Increment it once per `renderPage` call (right where
  `suppressNextScrollSave = true` is set today).
- In `scrollPositionDidChange`, change the check to:
  ```swift
  if self.pendingLoadResets > 0 {
      self.pendingLoadResets -= 1
      ... return
  }
  ```
- This means N overlapping loads correctly suppress N reset events instead
  of only the first one, regardless of ordering.

### Fix 1c — clean up the dead `restoreState`/`currentState` pair

`ArticleViewController.restoreState` is declared, read once in
`viewDidLoad`, and never assigned anywhere in the codebase; `currentState`
is a computed property that's never read anywhere. This is vestigial —
looks like it was meant for preserving scroll position across
`ArticleViewController` recreation (rotation/split-view layout changes) but
was never wired up. Either:
- finish it (assign `restoreState` from the outgoing controller's
  `currentState` wherever `ArticleViewController` gets recreated), or
- remove both, so a future contributor doesn't wire it up incorrectly and
  reintroduce the single-shared-value bug Fix 1a/1b just closed (note the
  `updateView: false` branch skips `setArticle`'s own per-article fetch
  entirely, forcing whatever `state.windowScrollY` is passed in — the same
  shape of bug as the original `AppDefaults.shared.articleWindowScrollY`
  issue).

Recommend removal unless there's a known repro this was meant to fix —
confirm with whoever added it before deleting.

### Fix 1d — verification

- **Manual repro of the current bug:** open a long article, scroll partway,
  tap back to the timeline, reopen the same article. Before the fix this
  should intermittently show scroll position 0 despite scrolling earlier
  (most reliable if you reopen fast, right after tapping away).
- **After the fix:** reopening should consistently land at the last
  scrolled position, and the article's web view should only reload HTML
  once (check `loadWebViewCallCount`/`generation` debug logs — should see
  one `renderPage` call per article open, not two).
- Also re-verify the two already-fixed Phase A0 bugs (relaunch/Handoff
  restore, fast-exit flush) aren't affected by 1a/1b's changes — both
  should still pass their existing "done when" checks.

---

## 2. "cute" collection's book not showing — data doesn't point to a parser bug

Checked the "cute" collection's item against every hard-drop condition in
`JSONFeedParser.parseItem`:

- `version` has the JSON Feed 1.1 marker — present at the feed level.
- `items` array present.
- Feed-level `title` present.
- Item has `id: "ambrosia-book-8789"` — present, so `parseUniqueID` should
  succeed.
- Item has non-empty `content_html` — so the "dropped, neither content_html
  nor content_text present" path (flagged last time as the likely culprit
  for a metadata-only item) does **not** apply here; this item has content.
- `_ambrosia` fields are well-typed (`word_count`/`chapter_current`/
  `chapter_total` are numbers, `is_complete` a bool, arrays are string
  arrays) — nothing that would fail an `as? Int`/`as? Bool`/`as? [String]`
  cast and silently drop metadata.

So on parser logic alone, this item should parse into a `ParsedItem` fine.
That points away from `JSONFeedParser` and toward one of:

1. **It's being filtered from view, not dropped from storage** — e.g.
   already marked read with "hide read articles" on
   (`HidingReadArticlesState.swift`), or it's sorted below the fold in a
   very long timeline. Worth checking with "show read articles" temporarily
   toggled on before assuming it's missing entirely.
2. **The refresh log itself** — `JSONFeedParser`'s own diagnostic logging
   (`parseItem: ... dropped -- ...`) fires via `os.Logger` any time an item
   is actually dropped, with the item's title/url in the message. Pulling
   Console.app / `log stream` output filtered to subsystem
   `com.ranchero.NetNewsWire.RSParser` while refreshing this specific
   collection will say definitively whether the parser ever saw and dropped
   this item, which would immediately rule out (1)–(3) if a drop log
   appears, or rule out the parser entirely if it doesn't.
