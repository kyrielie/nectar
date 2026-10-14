# Theme testing

How the theme color probe, store and bundled color table are tested, and what
to do when a guard test fails. Cross-references: `article-color-pipeline.md`
(what the probe, store and gate do), `theme-system.md`, `nnwtheme-format.md`.

The probe's own fixture themes (`Tests/NetNewsWire-iOSTests/Fixtures/ThemeColorProbe/`)
are not described here yet; the check matrix, the article fixtures and the lldb
capture command are below.

## Where tests live

- Anything that needs a `WKWebView` or `Bundle.main` resources (`core.css`,
  the bundled themes, `ThemeColorTable.json`) is in `Tests/NetNewsWire-iOSTests`.
  The package test target cannot see `Bundle.main`.
- Pure logic (cache key hashing, store lookup order, the persisted file,
  staleness, probe sanity math) is in
  `Modules/ArticleTheming/Tests/ArticleThemingTests`.
- Suites use Swift Testing. Suites in the app target were written without being
  run in Xcode; treat a first failure as possibly a test problem as well as a
  code problem.

Relevant suites: `ArticleThemeColorProbeTests` (rendering),
`ArticleThemeColorStoreAppTests` and the package's `ArticleThemeColorStoreTests`
(store), `ArticleThemesManagerGateTests` (gate and prewarm),
`ThemeColorTableGeneratorTests` and `ThemeColorTableGuardTests` (bundled table),
`ArticleThemeCheckMatrixTests` (render checks over every theme).

## The bundled color table

`iOS/Resources/ThemeColorTable.json` is the cold-start color source for every
theme that ships in the app: each `Themes/*.nnwtheme` plus the Default theme
(stored under the key `Default`). Gallery themes are not tabulated. Shape:
`{ probeVersion, coreCSSHash, themes: { name: { key, measurement } } }`, where
`key` is `ArticleTheme.colorCacheKey`. The store reads it last before the
scanner (`ThemeColorStoreCore.loadBundledFromMainBundle`).

The Default theme's key hashes the raw `Shared/Article Rendering/template.html`
(and the default `stylesheet.css`), so editing that file, even only its header
comment, changes the key and needs a regeneration of the table (the colors do not
change, only the key).

`ThemeColorTableGuardTests` always runs and fails when:

- the table is not in the app bundle or does not decode;
- its `probeVersion` differs from `ArticleThemeColorProbe.version`;
- its `coreCSSHash` differs from the SHA-256 of the bundled `core.css`;
- a shipped theme has no entry, or its entry's `key` no longer matches the
  theme's stylesheet and template, or the table names a theme that no longer ships;
- an entry holds a color the store cannot parse.

The failure message says what to do. Editing `core.css`, any bundled theme's
`stylesheet.css` or `template.html`, or the Default theme's files means
regenerating the table in the same change.

### Regenerating

`ThemeColorTableGeneratorTests.regenerateTable` measures every shipped theme with
the probe and rewrites the file in the repo checkout (located through
`#filePath`, so run it from the simulator against this checkout). It is skipped
unless `REGENERATE_THEME_COLOR_TABLE=1` reaches the test process. With
`xcodebuild`, variables prefixed `TEST_RUNNER_` are passed to the test runner, so:

```sh
TEST_RUNNER_REGENERATE_THEME_COLOR_TABLE=1 xcodebuild \
  -project NetNewsWire.xcodeproj -scheme Nectar-iOS \
  -only-testing:Nectar-iOSTests/ThemeColorTableGeneratorTests \
  -xcconfig .github/ios-ci-no-signing.xcconfig \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

(Scheme, xcconfig and destination are the ones `test.sh` uses.) If any theme
fails the probe's sanity check the test fails and writes nothing; investigate
the theme or the probe, do not lower the floor. After it writes the file, run
the normal tests once more so the app is rebuilt with the new table, then commit
the JSON. A new file under `iOS/` is bundled by the next project generation
(`project.yml` bundles everything under `iOS`); `tableIsBundledAndDecodes` is the
check that this actually happened.

### When to bump `ArticleThemeColorProbe.version`

Only when the probe's own logic changes (what it reads, how it normalizes, the
sanity rules), so that every cached and tabulated measurement becomes invalid.
Do not bump it for a `core.css` change (the cache tracks that through its own
hash) or for theme edits (the cache key tracks content). Bumping it changes
every `colorCacheKey`, so regenerate the table in the same change.

## Smoke test over all themes

`ArticleThemeColorProbeTests.everyShippedThemePassesTheSanityCheck` probes every
`Themes/` and `gallery-themes/` bundle, stores nothing, fails if any measurement
is rejected, and prints cold and warm timings.

## Article fixtures

`Tests/NetNewsWire-iOSTests/Fixtures/ThemeCheck/` holds the article content the
check matrix renders:

- `article.json` and `kitchen-sink.json` are converted verbatim from `nnw-theme`'s
  `assets/fixtures/article.toml` and `kitchen-sink.toml` (every value is a string,
  so the conversion is lossless). Their keys are the macros
  `ArticleRenderer.articleSubstitutions()` fills, minus `dateline_style`, which the
  test loader adds (`articleDatelineTitle`). `upstreamFixturesCarryTheReaderMacroKeys`
  fails if the keys drift from `ArticleThemeSampleContent.substitutions()`.
- The third fixture, `ao3-preface`, is not a file: it is the app's own sample
  (`ArticleThemeSampleContent`), so the AO3 preface markup stays covered.
- `upstream-core.css` is NetNewsWire's `core.css` at the pin `mac-7.2b4`
  (`b7f4d8c7d273e4247c5d033ee47014805072297b`), SHA-256
  `d67552259cb45261e1aacf0c1af6bc39b560b084c7b9e3943191907e0977cd4d`, used only by
  the render-diff report. The test checks the hash. Refresh it only when moving
  the pin, together with the divergence list in `nnwtheme-format.md`.

To add a fixture, convert a captured `.toml` the same way and add a case to
`ThemeCheckFixture`.

## Check matrix (`ArticleThemeCheckMatrixTests`)

Renders each bundle in `Themes/` and `gallery-themes/` through
`ArticlePageComposer` with the reader's page preferences (content JavaScript
off), for each fixture, light and dark, at the default and the largest
accessibility body size (`.accessibilityExtraExtraExtraLarge`, fed to the
theme's `font-size` macro the way the reader feeds it). The page reports back
through a `WKUserScript` and a message handler, as the color probe does; nothing
uses `evaluateJavaScript`. That is about 2,000 page loads, so the test prints a
timing line.

- `noOverflowAndNoBrokenImagesAcrossMatrix` (one run per folder) fails on
  horizontal document overflow (`scrollWidth` or the body's `scrollWidth` above
  `clientWidth`, no tolerance) and on any `.articleBody img` that failed to load
  or renders at zero size (images with an empty `src` or `display: none` are
  skipped). It also fails if a page did not get the requested
  `prefers-color-scheme`, which would make the dark column meaningless; the
  remedy is `ArticleThemeColorProbe.useVisibleHostFallback`.
- `footnoteMarkersAreLegibleForThemesThatStyleThem` ports the numeral checks of
  `nnw-theme`'s `assets/footnotes.js` for themes whose own stylesheet mentions
  `footnote` (37 bundles when this was written): each marker resolves to a
  non-empty note, the numeral differs from its flattened backdrop by more than 60
  summed channel units (white when nothing is painted), it stays inside its
  marker, and all markers share height, baseline seat and font size. Not ported:
  the popover click (newsfoot is an app script and never runs here) and
  `keep_with_word` (opt-in upstream). Because `main.js` adds `a.footnote` at
  runtime, the selector also accepts `sup > a[href*="#fn"]`.
- `renderDiffAgainstUpstreamCoreCSS` is a report, not a gate. It renders the
  starter-style fixture theme and the six bundles that pass the upstream
  validator (Biblioteca, NewsFax, Promenade, Sepia, Tiqoe Dark, Verdana Revival)
  once with Nectar's `core.css` and once with `upstream-core.css`, and prints
  `RenderDiff ...` lines where overflow or image sizes differ. It asserts only
  that the upstream copy is the pinned file and that every page rendered. The
  upstream variant is `upstream-core.css` plus the theme's `ownStylesheet`.

There is no "scripts on" column: the reader never runs theme scripts.

## Capturing a real article (`nnwdump`)

`nnw-theme`'s `lldb/nnwdump.py` writes the substitution dictionary of the
selected article as a TOML fixture. It expects to be stopped at the final
`return d` of `ArticleRenderer.articleSubstitutions()`
(`Shared/Article Rendering/ArticleRenderer.swift`). In this repo that function
declares `var d = [String: String]()`, takes the article from
`guard let article = article`, and ends with `return d`, so the command's
defaults (`--var d`, `--article article`) match. The icon option relies on
`article.iconImage()?.image.dataRepresentation()`, which exists
(`Shared/Extensions/ArticleUtilities.swift`, `RSImage.dataRepresentation()`).
These names were confirmed by reading; the command itself has not been run
against Nectar.

1. Set a breakpoint on the final `return d` and select the article in the
   running app.
2. `command script import <path>/nnw-theme/lldb/nnwdump.py` (`npx nnw-theme@2
   capture` prints the exact path and an absolute output path; Xcode's lldb
   working directory is `/`).
3. At the breakpoint: `nnwdump /absolute/path/captured.toml` (`--no-icon` keeps
   the generated avatar).
4. Convert the TOML to JSON as above if it should join the matrix.

