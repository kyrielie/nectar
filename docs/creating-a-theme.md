# Creating a theme

The short, spec-only walk-through. For one table of every rule and who enforces it, see "Theme contract" in `nnwtheme-format.md`. The detail lives elsewhere: `nnwtheme-format.md` (bundle
format and authoring rules), `theme-system.md` (the Swift side), `article-color-pipeline.md`
(how the notch and webview color is read), `theme-mockups.md` (design previews and how the
older bundles were converted), and the skills in `.claude/skills/` (`nnwtheme-builder`,
`nnwtheme-header-design`, `nnwtheme-porter`).

## 1. Pick a route

| You want | Do this |
|---|---|
| The stock layout in a new palette (a port) | Add an entry to `buildscripts/theme-generation/generate_ported_themes.py` (shape A). See the porter skill. |
| A new design | Copy a shape B bundle (`nnwtheme-format.md`, "Which templates to add"), with or without the running head; leave it out unless the design uses it. The app keeps the page below the notch cover, so the theme adds no top spacing for it. A shape A template is also fine as the base for an original design (Beacon); the versal and divider opt-ins in section 2 work with any shape. |
| Custom markup for a real concept | Hand-build it (builder skill). Keep every name in section 2; no notch spacing is needed. |

## 2. Names that must be exact

**Bundle**

- Folder `<Name>.nnwtheme`. The app identifies the theme by this folder name without the
  suffix (selection, lookup and import-overwrite all use it).
- Files `Info.plist`, `template.html`, `stylesheet.css`. `License.md` is optional and nothing
  reads it. Only `Info.plist` is needed for the app to load a bundle (a missing template or
  stylesheet falls back to the default); the gallery build and the tests enforce the rest.

**Info.plist** (case-sensitive)

| Key | Type | Notes |
|---|---|---|
| `Name` | string | Required to decode. The gallery shows it; the app shows the folder name. Keep them equal. |
| `ThemeIdentifier` | string | Required. Convention `com.nectar.themes.<slug>`. App code never reads it; the gallery uses it as the id. |
| `CreatorHomePage` | string | Required. |
| `CreatorName` | string | Required. The creator's name only; the description goes in `License.md`. |
| `Version` | integer | Required. `1` for a new theme; raise it when `stylesheet.css` or `template.html` changes (`theme-gallery.md`). |
| `Family`, `FamilyVariant` | string | Optional. Only for two or more sibling bundles; checked by `ArticleThemePlistFamilyTests`. |

The gallery build fails on a missing required key. The app's loader is lenient and decodes a missing key to `""` or `0` (`ArticleThemePlist`).

**template.html**

- `#bodyContainer` must keep `id="bodyContainer"` and class `articleBody`.
- Tokens, written `[[name]]`: `title`, `preferred_link`, `byline`, `body`, `feed_link`,
  `feed_link_title`, `avatar_src`, `dateline_style`, `datetime_long|medium|short`,
  `date_long|medium|short`, `time_long|medium|short`, `external_link`,
  `external_link_label`, `external_link_stripped`. `text_size_class` is a legacy token that is
  never substituted. The header comment in `Shared/Article Rendering/template.html` is the
  authority.
- Optional avatar: `main.js` removes every `nnwimageicon:` image unless the `<img>` has
  `data-nnw-keep` (for example `<img src="[[avatar_src]]" data-nnw-keep width="48" height="48">`).
  Without the attribute nothing changes. Birdsite and Watch Later are the examples: they lay the
  image over a CSS placeholder disc, which shows when there is no image. See `nnwtheme-format.md`.
- Opt-in attributes on `#bodyContainer`: `data-versal-target`; `data-chapter-divider` together
  with both `data-chapter-divider-char` and `data-chapter-divider-class`.
- No inline `<script>`: the real reader blocks it.

**stylesheet.css**

- Generated markup you style but cannot rename: `.summary.module`, `.notes.module`,
  `.end.notes.module`, `h3.heading`, `blockquote.userstuff`, `h2.heading` and `h3.title`,
  `#ao3SyntheticPreface` and `#ao3Preface`, `dl.tags` (with `.wide` rows), `span.versalCap`,
  `mark.nnw-highlight`.
- Color contract: `--nnw-bg`, `--nnw-ink`, `--nnw-link` as literal values in `:root` and in
  the dark `:root`; page color written as `background-color` on `body` (never the `background`
  shorthand). See "Color tokens and the page color" in `nnwtheme-format.md`.
- Preface hooks `--ao3-preface-border-color`, `-background-color`, `-text-color`,
  `-label-color`, `-font-size` (all read by `core.css`, each with a fallback).
- `img, figure, video, div, object { max-width: 100%; }`, required by
  `ArticleThemeOverflowSafetyTests` and warned about by the gallery build.
- One `@media (prefers-color-scheme: dark)` block. The iOS and macOS `@supports` split,
  `--gx`, `--u`, and `--font-main`/`--font-body`/`--font-code` are conventions, not enforced.

## 3. Build it

1. Copy a shape B bundle, rename the folder, and replace its `tNN` class (in `template.html`
   and every selector) with a number no other bundle uses.
2. Keep the stylesheet order: font `@import` first, `:root` palette, structural base, `.rh`,
   notes, your rules, the dark block, then the iOS and macOS `@supports` blocks.
3. Fonts: use real Google Fonts families (confirm each on fonts.google.com), end every stack
   in a system fallback, and do not lead with an Apple-only face.
4. Ornaments are CSS only (`content:` or the shared divider), inside the page width.
5. Fill in `Info.plist` and `License.md`.

## 4. Place it and test it

- Put it in `gallery-themes/` (gallery only). Use `Themes/` only to ship it in the app
  (`project.yml` copies that folder; also see `BUNDLED` in `gallery/build.py`).
- Swift suites that scan both folders: `ArticleThemeOverflowSafetyTests`,
  `ArticleThemePlistFamilyTests`, `ArticleThemeColorExtractorTests`.
- Python, from `buildscripts/theme-generation`: `python3 -m unittest`.
  `gallery/build.py` fails on a missing plist key, a missing
  `#bodyContainer.articleBody`, a macro inside an HTML comment in `template.html`, a
  non-leading or unterminated `@import`, a `ThemeIdentifier` shared with another
  bundle, or a `Version` that is not an integer >= 1 (see `theme-gallery.md`,
  "Bundle checks"). Its tests: `python3 -m unittest discover -s gallery`.
- Counts of bundles and shapes: `theme_inventory.py` (the docs do not state them).

## 5. Check on a device

No test enforces these. In full-screen reading, confirm the first title line sits just
below the notch cover (no extra gap), the notch cover matches the page color in light and dark, and the
page counter is readable.

## 6. Share it

Zip the bundle folder and link it as `nectar://theme/add?url=<zip URL>` (`theme-gallery.md`).
