# Full-screen top clearance (retired rule and cleanup record)

**Status: the app now keeps the notch inset in full-screen reading** (`hideBars()` no longer
cancels the top safe area, matching upstream NetNewsWire), so the page starts below
`notchCoverView` and the 68px title-clearance rule is retired (`nnwtheme-format.md`,
"Full-screen reading"). Everything below describes the earlier behavior, when the page started
at the top edge of the screen and the cover (about 62pt on current Dynamic Island iPhones; 59pt
on earlier ones) hid anything the theme drew above that line. The measurements remain useful for
finding bundles whose leftover clearance padding now adds blank space. Not confirmed on a device.

## What was done

- **App change.** `hideBars()` stopped cancelling the top safe-area inset (matching upstream
  NetNewsWire), so every theme, imported ones included, starts below the cover with no padding.
  Not confirmed on a device.
- **Bundles cleaned (66).** Removed the trailing `html{padding-top:Npx}` "Full-screen
  clearance" rule from 32 bundles (30 in `gallery-themes/`, plus Midnight Blue and Duskbloom in
  `Themes/`); set `.t` top padding in the 29 spec-derived bundles from 76px to 28px
  (`generate_spec_themes.py` regenerates all 29 byte-identical to the committed files), in Upvote
  and Watch Later from 78px to 26px, and in Nectar from 66px back to its original 18px; removed
  the 68px `padding-top` rules from Reversi (`.rv`) and High Contrast (`.hc`). Each changed bundle
  got a `Version` bump. The 28px and 26px values are judgment calls, not measured.
- **Color table.** `iOS/Resources/ThemeColorTable.json` keys are `SHA-256` over the raw
  `stylesheet.css`, `template.html` and probe version (`ArticleTheme.cacheKey`). The committed
  table was stale for Nectar, Midnight Blue and Duskbloom; reverting their clearance edits made
  those three match again, which confirms the edits were restored to the original bytes. Only
  High Contrast and Reversi keys were rewritten (colors are unaffected by padding). The keys were
  computed with a Python reproduction of the hash, not by `scripts/regenerate-theme-colors.sh`;
  run that script on a Mac to confirm.
- **Upstream-pinned bundles.** Appanoose (title at 53px), Biblioteca (38), NewsFax (25), Sepia
  (55) and Tiqoe Dark (55) failed the old 68px rule. They needed no change: the app now supplies
  the clearance and the pins stay byte-identical to upstream.
- **Running heads.** About 155 bundles carry a running head (feed link, date, byline) that was
  partly or wholly under the cover and mostly served as a 68px spacer. They are untouched and
  now visible; remove a head only as a design decision.
- **Tooling.** `buildscripts/theme-audit/check_fullscreen_top.py` and `intentional-bleed.txt` are
  removed, since their premise (a cover hiding the page's first 62px) no longer holds.
  `gallery/build.py` now warns about a leftover clearance rule
  (`Full-screen clearance` or `html{padding-top:Npx}`), covered by `LeftoverClearanceWarning` in
  `gallery/test_build.py`.

## Device checks still open

Confirm on a Dynamic Island phone and a notch phone, with Page Counter on, that the title sits just
below the cover in full-screen reading for: stock Nectar, Midnight Blue, one spec-derived bundle,
Watch Later, and Sepia (upstream-pinned). Also check text selection right after entering full
screen (`annotations.md`).
