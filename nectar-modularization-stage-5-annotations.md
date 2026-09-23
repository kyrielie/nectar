# Nectar modularization: Stage 5, Annotations — final plan

Companion to the Stage 0-4 plan (`nectar-modularization-stage-0-4.md`).
Everything in that doc's package template, `project.yml` wiring,
doc-update discipline, and "uniform `@testable import`" test rule
applies here unless this doc says otherwise.

Line numbers are from the snapshot this plan was written against.
Stages 0-4 edit `iOS/AppDefaults.swift`, `project.yml`,
`Nectar-CI.xctestplan`, and several files listed below. **Re-verify
every line number with `view` before cutting.** Where this doc gives a
symbol name and a line number, the symbol name is authoritative.

## Decisions already made (do not reopen)

| Question | Decision |
|---|---|
| Delete-revert bug (docs describe `revertOrUnwrapAnnotationDOM` / `revertAnnotationDOMIfCurrentlyOpen`; neither exists in code) | Fix it, as its own commit, before any extraction (5.1) |
| SwiftUI views | Deferred. Stage 5 is logic + bridge. Views are a later "5d" |
| `annotations.js`, `core.css` | Stay in `Shared/Article Rendering/`. Do not move or split |
| Backup allowlist gap (8 keys) | Add all 8, and fix the completeness test (5.2) |
| `migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()` / `migrateToolbarStyleDefaultIfNeeded()` | Dead code, removed deliberately. Delete the stale comments that cite them |
| JS tests in CI | Add a Node job first (5.0) |
| Package name | `Modules/AnnotationsKit` (avoids clashing with the JS global `Annotations`, the `Annotation` type, and `Account`'s `...Annotation...` API names) |
| `HighlightPalette` | Owned by Stage 1 (`Modules/AppChrome`), which depends on `Articles` for `Annotation.Color`. See "Dependency notes" below |

## Dependency notes

`Modules/AppChrome` (Stage 1) depends on `Articles`:
`HighlightPalette.HexSet` uses `Annotation.Color` (defined in
`Modules/Articles/Sources/Articles/Annotation.swift`) in
`subscript(_ color: Annotation.Color) -> String` and in `byColorKey`,
which builds its dictionary from `Annotation.Color.<case>.rawValue`.
This is a one-directional dependency — `Articles` depends only on
`RSCore` and must never depend on `AppChrome`. Callers that use the
`Annotation.Color`-typed API already import `Articles`, so this adds
no new import burden: `HighlightColorPopover.swift:95`,
`AccentColorTableViewController.swift:358-359`,
`HighlightPalettePreviewCell.swift:73-81`, and
`HighlightPaletteHexSetTests.swift`.

`Notification.Name.highlightPaletteDidChange` is declared in
`AppDefaults.swift`'s `extension Notification.Name` (~line 903), not
inside the `HighlightPalette` block itself. It stays in the app
target. Stage 5c's bridge needs it (see below), so the notification
name must remain reachable from app-target code.

**Sequencing:** 5a-5c do not need Stage 1 to have landed. 5b's
`AppDefaults+Annotations.swift` touches the same file Stage 1 cuts
from, so sequence the merges if both are in flight — but if Stage 1
hasn't landed when 5b starts, proceed anyway; the two edits are to
disjoint line ranges (Stage 1: enum blocks ~83-684; 5b: `Key` entries
~946, ~1060-1087 and accessors ~1469-1506, ~1834-1957).

## What Stage 5 is, and is not

**Is:** move the pure text-replacement / sentence-context logic into a
new package; extract the ~874 lines of annotation code from
`WebViewController` behind a bridge that lives in that package; move
annotation `AppDefaults` accessors into an `AppDefaults+Annotations.swift`;
and land three small preparatory fixes (JS CI, delete-revert, backup
allowlist).

**Is not:**
- Moving `AnnotationsTable` or the `Account` annotation API. They
  share a `DatabaseQueue` with `ArticlesTable`, are created in
  `ArticlesTable.init` (line 87), are joined by
  `ArticleSQLiteExportTable` (line 120), merged by
  `BackupSQLiteImportTable.mergeAnnotations` (line 339), and guard
  dedupe in `ArticlesTable.articleIDsWithAnnotations` (line 1734).
  Extracting the table is a schema/transaction refactor, not a package
  move.
- Moving `Annotation` / `Annotation.Color` / `Annotation.RowStyle`.
  They stay in `Modules/Articles`, below `ArticlesDatabase` and
  `Account`.
- Moving any SwiftUI view under `iOS/Article/Annotations/`.
- Moving `annotations.js`, `core.css`, or `WebViewConfiguration`'s
  script loading.
- Fixing the "revert does not re-run `shiftedAnchorsForRevert` for
  other rows" offset-drift gap. Log it in `docs/investigate-later.md`
  (5.1).

## Sub-stage order

```
5.0  JS tests in CI                 (no code moves)
5.1  Fix delete-revert bug          (behavior change, own commit)
5.2  Backup allowlist + real test   (behavior change, own commit)
5a   Move pure logic -> AnnotationsKit
5b   AppDefaults+Annotations.swift
5c   Extract bridge from WebViewController
     (5d views: deferred, not part of this plan)
```

Each sub-stage must build and pass the full test plan on its own. Do
not combine sub-stages into one commit.

---

## 5.0 Add the JS tests to CI

**Why first:** `grep -rniE 'node|npm|jsdom|Tests/JS' .github/` returns
nothing. The 1,262 lines under `Tests/JS/annotations/` (anchor
resolution, edit-shift math, DOM wrapping) run nowhere automatically,
though `Tests/JS/README.md` says they run "in CI without a simulator."
A green baseline is required before touching the code they cover.

**Steps:**

1. Run locally first and record the baseline:
   ```sh
   cd Tests/JS && npm install && npm test
   ```
   `package.json`'s script is `node --test annotations/*.test.js`, with
   `jsdom ^25.0.0` as its only dev dependency. There is no lockfile in
   the snapshot (`ls Tests/JS` shows only `README.md`, `annotations`,
   `package.json`). If `npm install` generates a `package-lock.json`,
   commit it so CI can use `npm ci`.
2. If any test already fails, **stop and report**. Do not fix or skip
   tests in this stage; a red baseline changes the plan.
3. Add a job to `.github/workflows/ci.yml` (existing jobs:
   `swiftlint`, an iOS test job, `ios-simulator-build`, all matching
   macOS runners for the last two). The JS job needs neither Xcode nor
   macOS; use `ubuntu-latest`, `actions/setup-node`, `npm ci` (or
   `npm install` if no lockfile), `npm test`, with
   `working-directory: Tests/JS`. Match the file's existing
   `actions/checkout@v5` usage and trigger conditions.
4. Update `Tests/JS/README.md`'s "Running" section if it claims CI
   behavior that is now (finally) true.

**Verify:** push to a branch; the new job runs and passes.

**Docs:** `docs/annotations.md` "Tests" section: one sentence noting
the JS suite runs in CI.

---

## 5.1 Fix the delete-revert bug

**The bug:** `docs/annotations.md` (UI section, "Note editor") and
comments in `iOS/Article/Annotations/AnnotationsListView.swift`
(lines ~143-160 and ~860-873) describe a fix that does not exist in
code.

- `AnnotationsListView.delete(_:)` (line 875) calls
  `onDeleteAnnotation?(annotation)` first, then removes the row and
  calls `account.deleteAnnotation`.
- `AnnotationsListView` has `var onDeleteAnnotation: ((Annotation) -> Void)?`
  (line 160) and an `init` parameter for it (line 189), and forwards
  it in the nested "All Highlights" link (line 467).
- **No call site passes it.** `ArticleViewController.showAnnotationsList`
  (line ~1189) and `showAllHighlights` (line ~1177) omit it.
- `revertOrUnwrapAnnotationDOM` and
  `ArticleViewController.revertAnnotationDOMIfCurrentlyOpen` do not
  exist anywhere (`grep -rn` returns only comments).

**Observable result:** open the list from the toolbar on an article,
swipe-delete a text-edit row, go back. The DB row is gone but the
replacement text stays in the live DOM until the next load.

**Fix:**

1. In `iOS/Article/WebViewController.swift`, the private method
   `deleteAnnotation(_ annotation:account:)` (line ~1792) has two
   halves: the DOM half (`Annotations.revertTextEdit` if
   `originalText != nil`, else `Annotations.removeAnnotationHighlight`)
   and the DB half (`account.deleteAnnotation` in a `Task`). Factor
   the DOM half into a new method,
   `func revertOrUnwrapAnnotationDOM(_ annotation: Annotation)`
   (internal, not private, so `ArticleViewController` can call it).
   Have `deleteAnnotation` call it, then do the DB half. **No behavior
   change for the existing note-editor delete path.**
2. In `iOS/Article/ArticleViewController.swift`, add
   `func revertAnnotationDOMIfCurrentlyOpen(_ annotation: Annotation)`:
   no-op unless `article?.articleID == annotation.articleID`,
   otherwise `currentWebViewController?.revertOrUnwrapAnnotationDOM(annotation)`.
   (`currentWebViewController` is already used in
   `navigateToAnnotation`.)
3. Pass `onDeleteAnnotation: { [weak self] in self?.revertAnnotationDOMIfCurrentlyOpen($0) }`
   at both `AnnotationsListView(` construction sites in this file
   (`showAllHighlights`, `showAnnotationsList`). Leave the two
   Settings sites
   (`AnnotationsSettingsView.swift:84`, `TextReplacementSettingsView.swift:116`)
   passing nothing; neither can have a `WebViewController` open
   behind it.
4. Correct the comments in `AnnotationsListView.swift` and the doc
   text so they describe reality.

**Do not fix (log instead):** deleting an edit row does not re-run
`TextReplacementOffsetShift.shiftedAnchorsForRevert` against other
rows whose offsets were shifted when the edit was saved. This is
documented in `docs/annotations.md` as "flagged, not fixed." Add an
entry to `docs/investigate-later.md` describing it. It is a deeper,
separate bug.

**Tests:** there is no `WebViewController`/`ArticleViewController`
test harness for this path (the app test target has no working
account fixture; see `AnnotationsListViewScopeTests.swift`'s header
comment). Add what is testable: a pure test that
`revertAnnotationDOMIfCurrentlyOpen`'s guard logic behaves (extract
the "same article?" predicate as a static function if needed, the way
`AnnotationsListView.resolvedBookKey(for:)` is static for the same
reason). **Manual verification is required and must be reported:**
with a text-edit row in an open article, swipe-delete it from the
toolbar list, return to the article, confirm the original wording is
restored without reopening.

**Docs:** `docs/annotations.md` (already describes the intended
behavior; confirm it now matches), `docs/investigate-later.md`.

---

## 5.2 Backup allowlist and a completeness test that actually checks

**The gap:** `AppDefaults.backupEligibleKeys` (`iOS/AppDefaults.swift`,
line ~1150) contains none of these 8 keys:
`textReplacementApplyAutomatically`, `textReplacementTypoFixesEnabled`,
`textReplacementQuoteConversionEnabled`, `textReplacementTypoTable`,
`textReplacementReaderInsertTable`, `textReplacementCustomTable`,
`textReplacementPerWorkOverride`, and `annotationsSortOrder`. None
appear in `AppDefaultsBackupTests`' excluded set either — nobody
decided. `BackupManager.exportBackup` (`iOS/Backup/BackupManager.swift`,
line ~149) and restore (~302) both iterate only `backupEligibleKeys`,
so a restored backup brings back highlights and edit rows but loses
the person's typo table, reader-insert names, custom rules, and
per-work overrides.

**The test is a false guarantee:** `everyExcludedKeyAboveIsExhaustive`
(`Tests/NetNewsWire-iOSTests/AppDefaultsBackupTests.swift`, ~line 116)
is described as catching "a new Key added without an explicit
decision" but its body only asserts (a) the excluded set and the
allowlist don't overlap and (b) the allowlist has no duplicates. It
cannot detect a forgotten key.

**Steps:**

1. Add the 8 keys to `backupEligibleKeys`. All 7 `textReplacement*`
   values and the sort order are stored as `String` (the tables via
   `AppDefaults.encode`, which writes a JSON `String`; the sort order
   via `@AppStorage`), so they serialize into `Settings.plist` without
   change.
2. Update the allowlist's own doc comment: it hard-codes counts
   ("146 keys as of this writing; 119 included below, 27 excluded").
   Recount from the code after your edit and update, or remove the
   counts.
3. Make the completeness test real. `Key` is a plain struct of
   `static let` strings (not `CaseIterable`), so there is no
   `allCases`. Options, in order of preference: (a) have the test read
   `iOS/AppDefaults.swift` source, extract `static let <n> = "<value>"`
   entries inside `struct Key`, and assert every value is in exactly
   one of `backupEligibleKeys` or the test's excluded set; (b) add a
   `static let allKeys: [String]` to `Key` next to the definitions.
   Pick (a) unless the test target cannot read the source file at
   runtime, in which case (b). **Report which you chose and why.**
4. The test will now fail on any key with no decision, including keys
   other stages add. **Tell the Stage 0-4 engineer**: Stages 3 and 4
   add no keys in the 0-4 plan, but Stage 0b touches `currentThemeName`
   (already allowlisted) and any rebase will hit this test. Resolve
   failures by deciding, not by loosening the test.

**Verify:** the strengthened test fails if you temporarily remove one
of the 8 keys from the allowlist, then passes when restored. Record
that you did this check.

**Docs:** `docs/backup-restore.md` (note the settings allowlist now
covers text-replacement and annotation-list preferences),
`docs/settings-screen.md` if it describes the allowlist.

---

## 5a Move pure logic into `Modules/AnnotationsKit`

**What moves** (pure `Foundation`/`NaturalLanguage`, no `RSCore`, no
UIKit/SwiftUI, and nothing else in `Modules/Articles/Sources`
references them in code):

| From `Modules/Articles/Sources/Articles/` | LOC |
|---|---|
| `TextReplacementRuleTable.swift` | 196 |
| `TextReplacementQuoteConversion.swift` | 301 |
| `TextReplacementOffsetShift.swift` | 156 |
| `TextReplacementPerWorkOverride.swift` | 83 |
| `SentenceContext.swift` | 133 |

Five files, 869 lines.

Tests move with them, from `Modules/Articles/Tests/ArticlesTests/`:
`TextReplacementRuleTableTests.swift` (206),
`TextReplacementQuoteConversionTests.swift` (237),
`TextReplacementOffsetShiftTests.swift` (347),
`TextReplacementPerWorkOverrideTests.swift` (123),
`SentenceContextTests.swift` (131). About 1,044 lines.
**`AnnotationRowStyleTests.swift` (81) stays in `Articles`:** it tests
`Annotation.rowStyle`, which stays. All of these use
`@testable import Articles` today; the moved ones become
`@testable import AnnotationsKit`.

**Dependencies:** `TextReplacementOffsetShift.swift` uses `Annotation`
(`firstOverlap`, `shiftedAnchors`, `shiftedAnchorsForRevert`,
`descendingApplicationOrder`, lines 52, 87, 134, 153). So
`AnnotationsKit` depends on `Articles`. This is one-directional and
creates no cycle (`Articles` must not depend on `AnnotationsKit`). The
other four files need no dependencies.

**Public API:** already mostly `public`. Counts of `public` vs
declaration lines: RuleTable 19/27, QuoteConversion 2/32, OffsetShift
15/18, PerWorkOverride 6/6, SentenceContext 7/25. The app calls
`TextReplacementQuoteConversion.findMatches(in:)` (public, line 75),
`TextReplacementRuleEngine.findMatches`, `TextReplacementMatch`
(public struct with public init), and the `AppDefaults` accessors
reference `TextReplacementRuleTable` and
`TextReplacementPerWorkOverride`. Do a public-API pass: after the
move, build; every error "X is inaccessible due to internal
protection level" gets a `public` on exactly that member, and nothing
more. **Do not blanket-`public` the package.** Members the tests use
but the app doesn't stay internal and are reached through
`@testable`.

**Package files to create:**

`Modules/AnnotationsKit/Package.swift`: copy
`Modules/Articles/Package.swift`'s shape exactly (swift-tools-version
6.2, `.iOS(.v17)`, `type: .dynamic` library, both upcoming-feature
flags), with:
```swift
dependencies: [ .package(path: "../Articles") ],
targets: [
	.target(name: "AnnotationsKit", dependencies: ["Articles"], swiftSettings: [...same two flags...]),
	.testTarget(name: "AnnotationsKitTests", dependencies: ["AnnotationsKit"])
]
```
Note `Articles`'s own manifest lists `RSCore` as a dependency;
`AnnotationsKit` does not need it directly.

**Wiring (all required; a miss is a silent failure):**

1. `project.yml`: add under `packages:`
   ```yaml
   AnnotationsKit:
     path: Modules/AnnotationsKit
   ```
   and `- package: AnnotationsKit` with `embed: true` under
   `Nectar-iOS`'s `dependencies`. Also add `- package: AnnotationsKit`
   to `Nectar-iOSTests`'s dependencies (its list today is `Nectar-iOS`,
   `Articles`, `Account`, `RSCore`) because app-level tests will
   import it.
2. `Nectar-CI.xctestplan`: add a `testTargets` entry for
   `AnnotationsKitTests` with `containerPath: container:Modules/AnnotationsKit`,
   `identifier` and `name` both `AnnotationsKitTests`, matching the
   existing `ArticlesTests` entry's shape. **If you skip this, the
   1,044 moved test lines silently stop running in CI**, the same
   failure mode this project has hit before.
3. After `xcodegen generate`, confirm `NetNewsWire-iOS.xctestplan`
   needs no change (it lists only `Nectar-iOSTests`).
4. `Modules/Articles`: no `Package.swift` change (the moved files did
   not contribute dependencies). Confirm `swift test` in
   `Modules/Articles` still passes (`Article`, `AuthorCache`,
   `AnnotationRowStyleTests`, etc.).

**Import edits (verified consumers of these types in code):**

- `iOS/AppDefaults.swift`: `import AnnotationsKit` (uses
  `TextReplacementRuleTable`, `TextReplacementPerWorkOverride` in
  accessors)
- `iOS/Article/WebViewController.swift`: `import AnnotationsKit`
  (`TextReplacementRuleTable`, `TextReplacementRuleEngine`,
  `TextReplacementQuoteConversion`)
- `iOS/Article/Annotations/AnnotationsListView.swift`:
  `import AnnotationsKit` (`SentenceContext`)
- `iOS/Article/Annotations/TextReplacementPerWorkOverrideView.swift`,
  `TextReplacementSettingsView.swift`: `import AnnotationsKit`
- `iOS/Article/Annotations/TextReplacementSummaryBanner.swift`,
  `iOS/Article/ArticleViewController.swift`,
  `iOS/Settings/SettingsViewController.swift`: check each — add the
  import only where a moved symbol is used, not where the match is
  only a `TextReplacementSummaryBanner...`/`TextReplacementSettingsView`
  type that stays in the app target.
- `Modules/ArticlesDatabase/Sources/.../AnnotationsTable.swift` (lines
  181, 185) and `BackupSQLiteImportTableTests.swift` (lines 277, 313)
  match only in comments and test names. **No change**, and
  `ArticlesDatabase` must not gain a dependency on `AnnotationsKit`.

**Do not touch:** `Annotation.swift`, `AnnotationRowStyleTests.swift`.

**Verify:**
- Package tests: `swift test` in `Modules/AnnotationsKit` and
  `Modules/Articles`, both green, moved test count unchanged (record
  before/after counts).
- Full app test plan (`./test.sh`) green.
- CI's `fail_on_warnings.sh` step: no new first-party warnings.

**Docs:** `docs/annotations.md` (paths for `TextReplacementRuleTable`,
`TextReplacementQuoteConversion`, `TextReplacementOffsetShift`,
`TextReplacementPerWorkOverride`, `SentenceContext`: the doc cites
`Modules/Articles/...` in ~10 places), `docs/module-layout.md` (new
package bullet; also correct its statement that
`Modules/CloudKitSync`/`NewsBlur`/`Secrets` exist among "supporting
services" — verify against `ls Modules` first, none of those
directories are in the snapshot), `docs/settings-screen.md` if it
cites these paths.

---

## 5b `AppDefaults+Annotations.swift`

Follows the precedent `iOS/ReadingStats/AppDefaults+ReadingStats.swift`
and `iOS/ScreenTime/AppDefaults+ScreenTime.swift` already set
(`extension AppDefaults.Key { ... }` plus
`extension AppDefaults { ... }`, using the internal
`AppDefaults.decode`/`encode` helpers). A **pure move**: key strings,
property names, behavior unchanged, no `UserDefaults` migration.

**Create:** `iOS/Article/Annotations/AppDefaults+Annotations.swift`
(same folder as the feature).

**Move from `iOS/AppDefaults.swift`** (re-verify lines first):

Keys (inside `struct Key`):
- `// MARK: - Annotations`: `defaultAnnotationColor`,
  `annotationCreationMethod` (~lines 1060-1062)
- `annotationsSortOrder` (~line 946; not under an annotations banner
  today, find it by name)
- `// MARK: - Text replacement`: the 7 `textReplacement*` keys
  (~lines 1073-1087)

Accessors (inside `final class AppDefaults`):
- `// MARK: - Annotations`: `defaultAnnotationColor`,
  `annotationCreationMethod` (~lines 1469-1506)
- `// MARK: - Text replacement`: `textReplacementApplyAutomatically`,
  `textReplacementTypoFixesEnabled`,
  `textReplacementQuoteConversionEnabled`, `textReplacementTypoTable`,
  `textReplacementReaderInsertTable`, `textReplacementCustomTable`,
  `textReplacementPerWorkOverride` (~lines 1834-1957)

Types:
- `enum AnnotationCreationMethod` (~line 882): only consumers are the
  annotation views, `WebViewController`, `PreloadedWebView`, and this
  accessor. Move it here; it is app-target-only and needs no package.

**Stays in `AppDefaults.swift`, on purpose:**
- `registerDefaults()` entries for `textReplacementApplyAutomatically`
  (false) and `textReplacementTypoFixesEnabled` (true)
  (~lines 2273-2283). `registerDefaults()` is one dictionary literal;
  splitting it is out of scope. Leave a one-line comment pointing at
  the new file.
- `backupEligibleKeys` (updated in 5.2; its entries reference
  `Key.textReplacement*`, which still resolve because `Key` is
  extended).
- `Notification.Name.highlightPaletteDidChange` and
  `highlightPalette`'s accessor (Stage 1 territory).

**Delete, do not move:** the stale comments citing
`migrateTextReplacementApplyAutomaticallyDefaultIfNeeded()` (~lines
1840 and 2277) and `migrateToolbarStyleDefaultIfNeeded()` (~line
2067). These migrations were removed deliberately; a comment citing a
function that does not exist is another stale in-code claim of the
kind this repo already tracks. Rewrite the two
`textReplacementApplyAutomatically` comments to say plainly: registered
default is false; there is no upgrade migration. **Do not change the
registered default value.**

**Visibility:** `Key` and its members are internal today, and this
file is in the same module (the app target), so
`extension AppDefaults.Key` works with no visibility changes, exactly
as `AppDefaults+ReadingStats.swift` does.

**Verify:** app builds; `AppDefaultsBackupTests` (strengthened in 5.2)
still passes, which is the real proof no key was dropped or renamed;
`grep -n 'textReplacement' iOS/AppDefaults.swift` now shows only the
`registerDefaults` entries and the allowlist entries.

**Docs:** `docs/settings-screen.md` (its table already names
`AppDefaults+<Feature>.swift`; add this one and note it is no longer
among "the next candidates to move"), `docs/module-layout.md` (same
sentence, which lists "reader, toolbar, annotations, text
replacement" as still in the main file).

---

## 5c Extract the annotation bridge from `WebViewController`

This is the real decomposition work in the stage. Read it fully
before starting; do it in the smallest steps that build.

### What is in `WebViewController.swift` today

| Region | Lines | Contents |
|---|---|---|
| `MessageName` cases | 31-32 | `textWasSelected`, `annotationWasTapped` |
| Stored state | 78 | `private var currentSelectionRect: CGRect?` |
| Stored state | 85 | `private var nextPageLoadContinuations` (backs `awaitNextPageLoad`) |
| Stored state | 143 | `var onTextReplacementReplacementsApplied: ((Int) -> Void)?` |
| Observer | 246 | `highlightPaletteDidChange` registered in init |
| `didFinish` | 858-864 | `initAnnotations()`, `applyHighlightPaletteColors()`, then a `Task` running `applyTextReplacementRulesIfNeeded()` then `loadAndRenderAnnotations()`, then `resumeAwaitingPageLoads()` |
| Message dispatch | 1033-1036 | `case .textWasSelected`, `case .annotationWasTapped` |
| **Main extension** | **1044-1826** | `// MARK: Annotations`; all annotation logic |
| Popover delegate | 1828-1838 | `UIPopoverPresentationControllerDelegate` |
| Menu delegate | 1840-1852 | `PreloadedWebViewAnnotationDelegate` |
| Bridge structs | 1975-2035 | `AnnotationSelector`, `ReanchorReport`, `TextEditPlan` (all `private`, `Codable`) |
| Handler reg | 2147, 2156-2157, 2165-2166 | `annotationMenuDelegate = self`, `removeScriptMessageHandler`/`add` for both names |
| Reset | 2183 | `currentSelectionRect = nil` in `renderPage` |

The main extension contains (by name): `initAnnotations`,
`applyHighlightPaletteColors`, `highlightPaletteDidChange`,
`applyTextReplacementRulesIfNeeded`, `loadAndRenderAnnotations`,
`reconcile`, `scrollToAnnotation`, `awaitNextPageLoad`,
`resumeAwaitingPageLoads`, `textWasSelected`,
`presentHighlightColorPopover`, `saveHighlightFromSelection`,
`annotationWasTapped`, `nativeMenuHighlightWasTapped`,
`openNoteEditor`, `saveNoteEdit`, `saveTextEdit`,
`saveHasHighlightChange`, `presentTextEditOverlapAlert`,
`deleteAnnotation` (plus 5.1's `revertOrUnwrapAnnotationDOM`).

### What the extracted code needs from the outside

By reading lines 1044-1826, the annotation code touches exactly these
host capabilities:

1. **The web view:** `webView?.evaluateJavaScript(...)`,
   `webView.safeAreaInsets`, `webView.convert(_:to:)`.
2. **The current article/account:** `article`, `article.account`,
   `article.articleID`, `article.bookKey`.
3. **UIKit presentation:** `present(_:animated:)`,
   `dismiss(animated:)`, `UIAlertController`, `UIHostingController`
   with a popover or sheet presentation, `view` (as
   `sourceView`/`bounds`), `UIPopoverPresentationControllerDelegate`.
4. **Settings:** `AppDefaults.shared.*` (annotation creation method,
   default color, highlight palette, and the text-replacement
   tables/toggles).
5. **Scroll history:** `scrollJumpHistory.append(Double(windowScrollY))`
   inside `scrollToAnnotation` (line 1343).
6. **Persistence:** `account.saveAnnotation`, `deleteAnnotation`,
   `updateAnnotationNote`, `updateAnnotationColor`,
   `markAnnotationOrphaned`, `reanchorAnnotation`,
   `setAnnotationEditFields`, `fetchAnnotations(forArticleID:)`.
7. **UI types in the app target:** `HighlightColorPopover`,
   `AnnotationEditorView`, `Annotation.Color` (in `Articles`).
8. **Logging:** `Self.logger`.

Items 3, 4 (in part), and 7 are the reason the presenting half cannot
move into a package: `HighlightColorPopover` and `AnnotationEditorView`
are SwiftUI views that stay in the app target (deferred, "5d") and
read `AppDefaults`/`HighlightPalette` directly.

### Design: split by what can be package-owned

**Split the ~874 lines into two halves along the JS/native line.**

**Half 1, moves to `AnnotationsKit`: `AnnotationsWebBridge`** owns
everything that is a JS call or its `Codable` payload, and pure
decisions. It has no UIKit and no `AppDefaults`.

Moves in:
- The three `Codable` bridge structs (`AnnotationSelector`,
  `ReanchorReport`, `TextEditPlan`), made `public`/internal as needed.
- Building and sending every JS call and decoding every result:
  `initAnnotations` (mode string), `applyHighlightPaletteColors`
  (given the 10 hex strings, so the package never sees
  `HighlightPalette`), `renderAnnotationsEncoded`,
  `addHighlightFromSelection`, `computeTextEditPlanEncoded`,
  `updateAnnotationColor`, `revertTextEdit`,
  `removeAnnotationHighlight`, `scrollToAnnotation`, `getArticleText`.
- The base64-JSON encode/decode helpers those calls share.
- The **rule-driven replacement pass** as a pure function: given the
  text, the assembled `TextReplacementRuleTable`, the
  quote-conversion flag, and article identity, return the
  `[Annotation]` rows to save (the matching, overlap-dropping,
  descending-order, and prefix/suffix capture logic from
  `applyTextReplacementRulesIfNeeded`, lines 1198-1251). The `Task`,
  the `account.fetchAnnotations` "already ran" check, the
  `AppDefaults` reads, and `account.saveAnnotation` calls stay with
  the caller.
- The **edit-save orchestration** as pure logic where possible:
  building the `computeTextEditPlan` argument payload (lines
  1679-1700) and ordering the shifted rows for persistence (line
  1738).

The bridge talks to the web view through a narrow protocol defined in
the package:

```swift
public protocol AnnotationsJavaScriptEvaluating: AnyObject {
	@MainActor func evaluate(_ script: String) async throws -> Any?
}
```

`WebViewController` (or a tiny adapter) conforms by forwarding to
`webView?.evaluateJavaScript`. Use a single async method rather than
the callback form so the package's async code reads linearly; the
existing code already mixes
`Task { ... await evaluateJavaScript }` (line 1298, 1704) with
completion-handler calls (lines 1069, 1118, 1345, 1498, 1620, 1805,
1814). **Preserve the fire-and-forget behavior of the handler-style
calls** (`initAnnotations`, `applyHighlightPaletteColors`,
`scrollToAnnotation`, `updateAnnotationColor`, `revertTextEdit`,
`removeAnnotationHighlight`): they log an error on failure and return
nothing. Do not turn a fire-and-forget call into one that can throw
into UI code.

Persistence is a second small protocol in the package so the bridge
never imports `Account`:

```swift
@MainActor public protocol AnnotationPersisting: AnyObject {
	func saveAnnotation(_ annotation: Annotation) async
	func deleteAnnotation(annotationID: String) async
	func updateAnnotationNote(annotationID: String, note: String?) async
	func updateAnnotationColor(annotationID: String, color: Annotation.Color) async
	func markAnnotationOrphaned(annotationID: String, at date: Date) async
	func reanchorAnnotation(annotationID: String, startOffset: Int, endOffset: Int, quoteExact: String, quotePrefix: String, quoteSuffix: String, chapterTitle: String?) async
	func setAnnotationEditFields(annotationID: String, hasHighlight: Bool, originalText: String?, replacementText: String?) async
	func fetchAnnotations(forArticleID articleID: String) async -> [Annotation]
}
```
These signatures are copied from `Account.swift` lines 1211-1252.
`extension Account: AnnotationPersisting {}` lives in the app target.
`Account` is declared `@MainActor public final class Account`
(`Account.swift:74`), so every one of these methods is
main-actor-isolated. Declare the protocol `@MainActor` (and drop
`Sendable` from it, since a main-actor-isolated class is not usable as
an unconstrained `Sendable` existential); the conformance
`extension Account: AnnotationPersisting {}` then needs no bodies
because the signatures already match. Do not change `Account`.
`AnnotationsKit` must **not** depend on `Account`.

**Half 2, stays in the app target: `AnnotationsController`** (new
file, `iOS/Article/Annotations/AnnotationsController.swift`) owns
everything UIKit/SwiftUI/`AppDefaults`: presenting
`HighlightColorPopover`, presenting `AnnotationEditorView`, the
overlap alert, `currentSelectionRect` and `isSelectionHighlightable`,
the popover delegate, and reading `AppDefaults`. It holds the
`AnnotationsWebBridge` and calls it. `WebViewController` holds one
`AnnotationsController`.

`AnnotationsController` needs from its host (`WebViewController`), via
a small app-target protocol `AnnotationsControllerHost`: `article`,
`webView` (for `safeAreaInsets`/`convert`), `view`,
`present(_:animated:)`, `dismiss(animated:)`, `recordScrollJump()`
(wrapping `scrollJumpHistory.append`), and the
`onTextReplacementReplacementsApplied` closure. Keep the protocol to
exactly those; if you find yourself adding more, the split is wrong.

### What stays in `WebViewController` (deliberately)

- Stored properties that extensions cannot hold, only the ones still
  needed: `nextPageLoadContinuations` and
  `awaitNextPageLoad`/`resumeAwaitingPageLoads` are page-load plumbing
  used by `ArticleViewController.navigateToAnnotation` (line 1273) and
  `didFinish`, not annotation logic. **Leave them in
  `WebViewController`.** Removing `currentSelectionRect` from
  `WebViewController` is expected (it moves to
  `AnnotationsController`).
- `MessageName.textWasSelected` / `.annotationWasTapped` constants and
  the `add`/`removeScriptMessageHandler` calls (lines 2156-2166):
  message registration is per-`PreloadedWebView` and reasserted on
  every dequeue because web views are pooled (see the comment at
  ~line 2143). Keep them here, unchanged. The `switch` at 1033-1036
  forwards to `annotations.textWasSelected(body:)` /
  `annotations.annotationWasTapped(body:)`.
- `webView.annotationMenuDelegate = self` (line 2147):
  `PreloadedWebView` holds this delegate `weak` and it is reasserted
  on every dequeue. Point it at the `AnnotationsController` (which
  conforms to `PreloadedWebViewAnnotationDelegate`) **and still
  reassert it on every dequeue**, or the native-menu "Highlight"
  action silently stops working after a pooled web view is reused.
- The `didFinish` call order (858-864). Preserve this exact sequence:
  `initAnnotations()`, `applyHighlightPaletteColors()`, then in a
  `Task` `applyTextReplacementRulesIfNeeded()` **before**
  `loadAndRenderAnnotations()`, then `resumeAwaitingPageLoads()`
  (which is not inside the `Task`). Rule-driven replacements must be
  persisted before the render so they show on the first load.
- The `renderPage` reset (2183): now `annotations.resetSelection()`.
- The `highlightPaletteDidChange` observer (line 246): keep the
  observer in `WebViewController` (it is a `NotificationCenter`
  `@objc` selector) or move it into `AnnotationsController`, but it
  must remain registered for the controller's lifetime and removed on
  deinit like the others. `WebViewController` registers 12 observers
  in its initializer (lines 236-247) and has **no `deinit` and no
  `removeObserver` call anywhere in the file**. Block-less
  selector-based observers registered with `addObserver(_:selector:...)`
  are cleaned up automatically on iOS 9+, so this works today. Follow
  the same convention if you move the palette observer into
  `AnnotationsController` (same automatic cleanup), and do not add a
  `deinit` just for this.

### Steps (each must build and pass tests)

1. **Introduce the two protocols and the bridge with no behavior
   change.** In `AnnotationsKit`, add
   `AnnotationsJavaScriptEvaluating`, `AnnotationPersisting`, and the
   three payload structs. Add
   `extension Account: AnnotationPersisting {}` in the app target.
   Nothing calls them yet. Builds.
2. **Move the payload structs and JS-call builders.** Move the three
   `Codable` structs and the base64 helpers; have `WebViewController`'s
   existing methods call the package versions. Behavior identical.
3. **Move the rule-driven replacement pass** as a pure function. Add a
   unit test in `AnnotationsKitTests` (new coverage; see checklist).
   `applyTextReplacementRulesIfNeeded` in `WebViewController` now
   assembles the table from `AppDefaults`, fetches existing rows,
   calls the pure function, and saves the results.
4. **Create `AnnotationsController` and move the presenting half**
   (popover, editor sheet, alert, selection tracking).
   `WebViewController` forwards to it. Conform it to
   `PreloadedWebViewAnnotationDelegate` and
   `UIPopoverPresentationControllerDelegate`, and delete those two
   conformances from `WebViewController`.
5. **Delete the emptied extension** (`// MARK: Annotations`, lines
   1044-1826) and the two delegate extensions.
   `WebViewController` should land near 2,300 lines (3,138 minus about
   874, plus a few dozen lines of forwarding and host-protocol glue).
   **Measure** the final size; do not assume this number.
6. **Ratchet `.swiftlint.yml`.** `file_length: 3200` was set just
   above `WebViewController.swift`; it is no longer the worst
   offender. `AppDefaults.swift` (Stage 1 shrinks it to ~1,830 first)
   and `SceneCoordinator.swift` (2,786 per the yml comment;
   **measure**) are next. Do not tighten past the real current
   maximum: `swiftlint lint --strict` runs in CI and turns any warning
   into a failure. Set it to just above the measured largest file.
   Update the yml comment and `docs/module-layout.md`'s "Lint size
   ratchet" section (which hard-codes "3,135 lines").

### Risks specific to 5c

- **Pooled web views.** Both `annotationMenuDelegate` and the
  script-message handlers must be reasserted on every dequeue
  (existing comments at ~2141-2156 explain why). Moving the delegate
  to a new object is exactly the change that breaks this silently:
  nothing crashes, the native "Highlight" menu item just never
  appears after web view reuse. **Manual test required:** switch
  between two articles several times in `.nativeMenu` mode;
  "Highlight" must still appear.
- **Stringly-typed JS bridge.** The JS function names
  (`Annotations.renderAnnotationsEncoded`, `addHighlightFromSelection`,
  `computeTextEditPlanEncoded`, `revertTextEdit`,
  `removeAnnotationHighlight`, `updateAnnotationColor`,
  `scrollToAnnotation`, `getArticleText`, `initAnnotations`) are
  strings in Swift and properties on the JS `Annotations` object.
  Moving the Swift half to a package cannot be checked by the compiler
  against the JS half. **Add the guard test described under "New
  tests," below.**
- **`@MainActor` and `Sendable`.** The package is compiled with
  `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`.
  The existing extension mixes
  `@MainActor func applyTextReplacementRulesIfNeeded` with
  un-annotated methods on a `UIViewController` subclass (implicitly
  main-actor). Expect real isolation compile errors when this crosses
  a package boundary; resolve them by annotating the protocols, not by
  `@unchecked Sendable` or `nonisolated(unsafe)`. **Do not use
  `@preconcurrency` to silence them without reporting each use.**
- **Stale-result guard.** `loadAndRenderAnnotations` (line 1289)
  checks `self.article?.articleID == articleID` after its fetch and
  discards the result if the person navigated away. That guard
  depends on host state. Preserve it, and keep the check on the host
  side of the protocol.
- **Do not change `annotations.js`.** If you find a JS/Swift
  mismatch, report it; do not edit the JS in this stage.

---

## New tests (required; things that do not exist today)

1. **JS bridge contract test** (`Tests/NetNewsWire-iOSTests/` or
   `AnnotationsKitTests`): read
   `Shared/Article Rendering/annotations.js` from the repo and assert
   that each function name the bridge calls appears as a key on the
   exported `Annotations` object literal (`var Annotations = {` at
   `annotations.js:1148`, assigned to `global.Annotations` at line
   1190). All nine names the Swift side calls are present in that
   literal: `renderAnnotationsEncoded`, `addHighlightFromSelection`,
   `computeTextEditPlanEncoded`, `revertTextEdit`,
   `removeAnnotationHighlight`, `updateAnnotationColor`,
   `scrollToAnnotation`, `getArticleText`, `initAnnotations`. Note the
   literal is `var`, not `const`, so a regex for `const Annotations`
   will match nothing. Have the bridge expose its called names as a
   `static let` array so the test and the code cannot drift apart.
2. **Rule-driven replacement pure function** (5c step 3): cover a rule
   match, a quote-conversion match, a quote-conversion candidate
   dropped for overlapping a rule match, descending-offset order,
   prefix/suffix capture at the 200-char window (including near the
   start and end of the text), and the "empty table and conversion
   off" early return. Before moving the logic, characterize the
   **current** behavior with a test against the extracted function
   using the same inputs the `TextReplacement*` tests use, so a
   mismatch is caught as a refactor regression and not a logic change.
3. **Payload decoding:** `TextEditPlan` has a custom `init(from:)`
   (defaults `shifted` to `[]`); test that a plan with only
   `{"status":"overlap","conflictingAnnotationID":"x"}` decodes.
4. **5.1's predicate** (above) and **5.2's strengthened completeness
   test** (above).

**Existing tests that must keep passing unchanged:**
`Modules/ArticlesDatabase` `AnnotationsTableTests`,
`ArticleSQLiteExportTableTests`, `BackupSQLiteImportTableTests`; the
`Tests/JS/annotations/*` suite; app-level `AnnotationCSVExporterTests`,
`AnnotationsListViewScopeTests`, `CopyHighlightTextTests`,
`HighlightPaletteHexSetTests`, `AlphabetIndexViewLetterExtractionTests`
(these need no change because the views and exporter do not move).

**Known unverifiable gaps to report, not paper over:** no
`WebViewController`/`ArticleViewController` test harness exists, and
the app test target has no working `Account` fixture (see
`AnnotationsListViewScopeTests.swift`'s header). The presenting half
of 5c and the 5.1 revert are therefore covered by **manual
verification only.** The implementer must list the manual checks
performed and their results in the PR description:

- [ ] Create a highlight via popup; tap it; add a note; change color;
      delete
- [ ] Same in `.nativeMenu` mode, after switching between articles
      several times
- [ ] `.off` mode: selecting text does nothing; existing highlights
      still tap
- [ ] Edit a highlight's text with "keep highlight" on and off; delete
      each
- [ ] Trigger the overlap alert (edit text inside an existing
      highlight)
- [ ] With "Apply Automatically on Open" on, open an article containing
      a typo-table word; confirm the replacement appears on first load
      and the summary banner shows
- [ ] Navigate to an annotation from the list, both same-article and
      cross-article
- [ ] Rotate / change appearance: highlight colors update live
- [ ] Fullscreen mode: highlight popover still presents for a short
      selection

---

## Out of scope, flagged for later

- The five views (`AnnotationsListView` 1,072 lines,
  `AnnotationEditorView`, `AnnotationsSettingsView`,
  `HighlightColorPopover`, and the text-replacement settings/banner
  views): coupled to `@AppStorage(AppDefaults.Key.…)`,
  `HighlightPalette`, and `AccountManager.shared` in 6 of 8 files.
  `AnnotationsListView` needs its own decomposition (row model,
  grouping, view) before a move. `AlphabetIndexView` (195 lines,
  imports only Foundation and SwiftUI) is the one leaf that could
  move first as a proof.
- `AnnotationCSVExporter` (`Shared/Exporters/`): depends on `Article`
  and `CSVFormatting`, which stay. Not a Stage 5 candidate.
- The three annotation seams in `SettingsViewController` (CSV export,
  `navigateToAnnotationFromSettings`,
  `currentWorkForTextReplacementOverride`): annotation-owned logic
  living in a settings VC. Note for a later stage.
- Duplicated palette hex in `core.css` fallbacks vs. `HighlightPalette`
  (documented as "kept in sync manually"). Flag, do not fix.
- `UIColor.cssHex` and friends: covered by the 0-4 plan's Stage 0a.
- Moving `ReadingStatsTracker` / `ScreenTimeTracker`: sequence this
  after Stage 5, using the same protocol-seam pattern
  (`AnnotationsJavaScriptEvaluating` / `AnnotationPersisting` /
  `AnnotationsControllerHost`) as precedent, once that pattern has
  landed and proven out here.

## Docs to update (consolidated)

| Doc | Update |
|---|---|
| `docs/annotations.md` | Paths for the moved files; "Tests" section (JS CI, new tests); delete-revert now real; new "Package layout" note; `AnnotationsController`/bridge description under "Message bridge" |
| `docs/module-layout.md` | `Modules/AnnotationsKit` bullet; `AppDefaults` extension-file list; lint ratchet numbers; check the CloudKitSync/NewsBlur/Secrets mention |
| `docs/settings-screen.md` | `AppDefaults+Annotations.swift`; backup allowlist |
| `docs/backup-restore.md` | Allowlist now covers text-replacement and sort order |
| `docs/investigate-later.md` | Revert does not re-shift other rows' offsets |
| `Tests/JS/README.md` | CI now runs these |
| `CLAUDE.md` (repo root) | Add `AnnotationsKit` to the routing table row for `AnnotationsTable`/`Annotation`/`annotations.js`; add the row for the new package |

Per that doc's rule against dangling citations, do not cite this plan
file in code comments. Fold decisions into the nearest topic doc
instead.

## Summary

| Sub-stage | Change | Behavior change | Risk |
|---|---|---|---|
| 5.0 | Node job in CI | None | Very low (but stop if baseline is red) |
| 5.1 | Wire delete-revert | Yes, fixes a bug | Low |
| 5.2 | Allowlist + real completeness test | Yes, more settings backed up | Low |
| 5a | 5 files (869 LOC) + 5 test files (~1,044 LOC) to `AnnotationsKit` | None | Low, mostly mechanical; the silent-CI-loss wiring step is the risk |
| 5b | Annotation keys/accessors to `AppDefaults+Annotations.swift`; delete dead comments | None | Low |
| 5c | ~874 lines out of `WebViewController` behind bridge + controller | None intended | **Medium-high**: pooled web views, isolation across a package boundary, unverifiable-by-test presenting half |

## Not yet verified — confirm during implementation

Stated so the implementer checks them rather than trusting them:

- No build or run was performed (no Xcode/simulator available while
  writing this plan). All symbol, line, and dependency claims are
  from reading source. `npm test`'s baseline is unknown.
- Selector-based `NotificationCenter` observers registered in an
  initializer being safe to leave without a `deinit` is standard
  iOS 9+ behavior and matches what `WebViewController` already does
  for 12 others, but was not run-tested here.
- `docs/settings-screen.md` (line ~343) references
  `migrateUnifiedToolbarsIfNeeded()` and
  `migrateArticleToolbarTogglesIfNeeded()`. Neither name appears in
  any `.swift` file in this snapshot, and the owner has confirmed the
  migrations were all removed, so those doc references are stale too.
  Fix them when editing that file.
- `docs/module-layout.md` lists `CloudKitSync`, `NewsBlur`, and
  `Secrets` among `Modules/` packages. `ls Modules` in this snapshot
  shows 14 directories and none of those three. Correct that sentence
  when you edit the file.
- `.swiftlint.yml`'s comment gives `SceneCoordinator.swift` as 2,786
  lines; `wc -l` on this snapshot confirms 2,786.
