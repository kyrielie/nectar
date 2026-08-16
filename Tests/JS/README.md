# Headless JS tests

Nothing under `Modules/`, `Shared/`, or `iOS/` had a way to unit-test
cross-platform article-rendering JS outside a real `WKWebView` before this
directory existed (grep confirmed no `package.json`/JS test runner
anywhere in the repo as of the annotations feature). This directory is a
minimal, self-contained addition for that purpose — it is **not** part of
the Xcode build and does not touch any `.xcodeproj`/`Package.swift`
target. It exists purely so JS-only logic (like `annotations.js`'s anchor-
resolution algorithm, which has no Swift-side equivalent to test through)
can be verified headlessly and in CI without a simulator.

## Running

```sh
cd Tests/JS
npm install
npm test
```

## What's here

- `annotations/` — tests for `Shared/Article Rendering/annotations.js`,
  loaded directly (not copied) via a relative `require` from the real
  file, so these tests exercise the actual shipped source, not a
  duplicate. Fixture HTML follows the same "small, deliberately
  fragment-shaped" style as
  `Tests/NetNewsWire-iOSTests/ArticleRendererStripFakeParagraphIndentsTests.swift`'s
  Swift fixtures — one concern per test, not full rendered article
  documents.

## Adding more

If a future cross-platform `.js` file under `Shared/Article Rendering/`
needs the same treatment, add a sibling directory here rather than
growing `annotations/`, and update this README's list.
