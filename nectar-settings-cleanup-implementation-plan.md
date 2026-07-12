# Nectar: Settings Cleanup — Detailed Implementation Plan

Scope: items 3, 4, 12, 13, 14, 15 from the rough plan (Feeds section rename, remove
"Add NetNewsWire News Feed," hide Notifications, hide Accounts, trim Help, extend
About). Everything below is checked against the current `SettingsViewController.swift`
and `Settings.storyboard` source, with real element IDs, not placeholders.

Two corrections to the earlier rough plan, confirmed by rereading the source:

- **"Enable JavaScript" is already gone.** `ArticlesRow` today is only
  `.theme` / `.openLinksInNetNewsWire` / `.enableFullScreenArticles` — no JS toggle,
  no `enableJavaScriptSwitch` outlet, nothing to remove. `nectar-plan-v3.md` Phase E
  item 4 is stale on this point; skip it.
- **Feeds naming is "Import Feeds" / "Share Feeds"**, per your last answer — overrides
  `nectar-plan-v3.md`'s "Import Books Feed" / "Export Books Feed."

---

## 0. Two files move together, always

`SettingsViewController.swift` is a `UITableViewController` with `dataMode="static"` —
`Settings.storyboard` owns section/row structure and header titles; the Swift file only
overrides behavior for a few dynamic sections (`.accounts` row count, `.feeds` row
count) and all `didSelectRowAt` handling. There are **no** `numberOfSections`,
`titleForHeaderInSection`, or `heightForHeaderInSection` overrides in the Swift file —
the storyboard is the only place section count/order/titles live. Every section
removal below requires a matching storyboard edit; changing only the `Section` enum
will misalign every row lookup after the touched section without changing what's
actually on screen.

Current section order (`SettingsViewController.swift`, `Section: Int` enum) mapped to
storyboard section IDs (`Settings.storyboard`):

| # | Swift case | Storyboard `tableViewSection id` | Header text |
|---|---|---|---|
| 0 | `.notifications` | `Bmb-Oi-RZK` | "Notifications, Badge, Data, & More" |
| 1 | `.accounts` | `0ac-Ze-Dh4` | "Accounts" |
| 2 | `.feeds` | `hAC-uA-RbS` | "Feeds" |
| 3 | `.timeline` | *(not touched here)* | |
| 4 | `.articles` | *(not touched here)* | |
| 5 | `.appearance` | *(not touched here)* | |
| 6 | `.troubleshooting` | *(not touched here)* | |
| 7 | `.help` | `CS8-fJ-ghn` | "Help" |

After this pass, `.notifications` and `.accounts` are deleted outright (both sections
have exactly one functional row each, so removing that row empties the section — no
partial-section case to handle), and `.help` shrinks to one row instead of five.
`.feeds` keeps its shape, loses one row, gets two rows relabeled.

---

## 1. Remove `.notifications` section

**Storyboard.** Delete the whole `<tableViewSection headerTitle="Notifications, Badge,
Data, & More" id="Bmb-Oi-RZK">...</tableViewSection>` block — it has exactly one cell
(`id="zvg-7C-BlH"`, label `id="F9H-Kr-npj"` text "Open System Settings").

**Swift — `SettingsViewController.swift`:**
- Delete `case notifications = 0` from `Section`.
- In `didSelectRowAt`, delete the `case .notifications:` branch:
  ```swift
  case .notifications:
      UIApplication.shared.open(URL(string: "\(UIApplication.openSettingsURLString)")!)
      tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
  ```
  No corresponding `numberOfRowsInSection` or `cellForRowAt` case exists for
  `.notifications` today (it falls through to `default: super...`), so nothing else
  references it — confirm with a project-wide search for `Section.notifications`
  before deleting, in case something outside this file (e.g. a deep-link handler)
  scrolls to it the way `scrollToArticlesSection` does for `.articles`.

---

## 2. Remove `.accounts` section

**Storyboard.** Delete `<tableViewSection headerTitle="Accounts" id="0ac-Ze-Dh4">...
</tableViewSection>` — one static cell (`id="XHc-rQ-7FK"`, label `id="6sn-wY-hHH"` text
"Add Account", `accessoryType="disclosureIndicator"`). Note this section's *content* is
actually built dynamically in Swift (`AccountManager.shared.accounts.count + 1` rows,
one real account row per account plus the static "Add Account" row) — the storyboard
cell is really just a template `UITableViewController` static-cell machinery needs
present at index 0 of the section; removing the section removes the template along
with it.

**Swift — `SettingsViewController.swift`:**
- Delete `case accounts = 1` from `Section`.
- In `numberOfRowsInSection`, delete:
  ```swift
  case .accounts:
      return AccountManager.shared.accounts.count + 1
  ```
- In `cellForRowAt`, delete the entire `case .accounts:` branch (the
  `SettingsComboTableViewCell` / "Add Account" cell construction, ~15 lines).
- In `didSelectRowAt`, delete the `case .accounts:` branch (pushes
  `AccountInspectorViewController` or `AddAccountViewController`).
- `tableView(_:indentationLevelForRowAt:)` currently does:
  ```swift
  override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
      return super.tableView(tableView, indentationLevelForRowAt: IndexPath(row: 0, section: Section.accounts.rawValue))
  }
  ```
  This hardcodes `Section.accounts.rawValue` as a reference point for *all* rows'
  indentation, not just the accounts section's own rows — it's a workaround for a
  static-table/dynamic-type indentation bug, not accounts-specific logic. Once
  `.accounts` is deleted, this needs to reference a different still-live section
  (e.g. `.feeds`, or whichever section this bug was originally scoped to) rather than
  being deleted outright — **check the git blame / original NetNewsWire commit that
  added this hack before choosing a replacement section**, since picking the wrong
  section here could silently reintroduce the dynamic-type bug it was working around.
- `AccountManager.shared.hasiCloudAccount` (used in `.troubleshooting`'s
  `numberOfRowsInSection` to conditionally show `cloudKitZoneStats`) is unaffected —
  it doesn't depend on the Accounts *section* existing, only on account data, which is
  untouched.

**Not in scope but flagged:** `.troubleshooting` still has an `accountStats` row
(`TroubleshootingRow.accountStats`) that pushes `AccountStatsView()`. With the Accounts
section itself gone, having per-account stats reachable from Troubleshooting is a bit
orphaned conceptually (stats for an account you can no longer see/manage in Settings)
but still functions correctly against the one local account — leaving as-is per your
scoped list, just noting it reads a little oddly post-change.

---

## 3. `.feeds` section: rename + remove "Add NetNewsWire News Feed"

**Storyboard — label text only, two edits, no structural cell changes:**
- Cell `id="glf-Pg-s3P"`, label `id="4Hg-B3-zAE"`: `text="Import Subscriptions"` →
  `text="Import Feeds"`.
- Cell `id="qke-Ha-PXl"`, label `id="25J-iX-3at"`: `text="Export Subscriptions"` →
  `text="Share Feeds"`.
- Delete cell `id="F0L-Ut-reX"` (label `id="dXN-Mw-yf2"`, text "Add NetNewsWire News
  Feed") from the `Feeds` section's `<cells>` entirely — third and last cell in that
  section.

**Swift — `SettingsViewController.swift`:**
- `FeedsRow` enum: delete `case addNetNewsWireNewsFeed = 2`, leaving:
  ```swift
  private enum FeedsRow: Int {
      case importSubscriptions = 0
      case exportSubscriptions = 1
  }
  ```
  (Leave the case *names* `importSubscriptions`/`exportSubscriptions` alone — only the
  storyboard label text changes. Renaming the enum cases too is a pure-refactor nice-
  to-have, not required, and touching it risks an unrelated merge conflict with
  whatever else references `FeedsRow` — skip unless you're doing a dedicated rename
  pass.)
- In `numberOfRowsInSection`, the `.feeds` case currently is:
  ```swift
  case .feeds:
      let defaultNumberOfRows = super.tableView(tableView, numberOfRowsInSection: section)
      if AccountManager.shared.activeAccounts.isEmpty || AccountManager.shared.anyAccountHasNetNewsWireNewsSubscription() {
          return defaultNumberOfRows - 1
      }
      return defaultNumberOfRows
  ```
  This conditional exists *only* to hide the (now-deleted) "Add NetNewsWire News Feed"
  row when there's no account to add it to, or it's already subscribed. With that row
  gone from the storyboard, `defaultNumberOfRows` (from the static table) is now
  correct as-is — delete this whole `case .feeds:` branch so it falls through to
  `default: return super.tableView(...)`.
- In `didSelectRowAt`, delete the `case .addNetNewsWireNewsFeed:` branch inside the
  `.feeds` switch:
  ```swift
  case .addNetNewsWireNewsFeed:
      addFeed()
      tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
  ```
- **Dead code to remove in the same pass**, now that nothing calls it from here:
  `AccountManager.shared.anyAccountHasNetNewsWireNewsSubscription()`. Grep the whole
  tree for `anyAccountHasNetNewsWireNewsSubscription` before deleting the method
  itself — confirm this was its only call site (it's declared on `AccountManager`,
  likely in `Modules/Account/Sources/Account/AccountManager.swift` or an extension;
  not yet located in this pass, do that check as step one of implementation, not
  after).
- `addFeed()` itself (whatever it calls — likely instantiates
  `AddFeedViewController`) may still be used elsewhere (the main Feeds screen's "+"
  button almost certainly calls the same or a sibling method) — **do not delete
  `addFeed()`**, only the Settings call site and the dead subscription-check helper.

**Verification that this doesn't touch the underlying export mechanism:**
`exportOPML(sourceView:sourceRect:)` already short-circuits based on account count:
```swift
func exportOPML(sourceView: UIView, sourceRect: CGRect) {
    if AccountManager.shared.accounts.count == 1 {
        opmlAccount = AccountManager.shared.accounts.first!
        exportOPMLDocumentPicker()
    } else {
        exportOPMLAccountPicker(sourceView: sourceView, sourceRect: sourceRect)
    }
}
```
Since Nectar always has exactly one account, this already skips the account-picker
alert and goes straight to the document picker — renaming the row label has zero
effect on this method, and hiding the Accounts section (item 2 above) doesn't either.
`importOPML`/`exportOPML` method names, notification names, and this logic all stay
untouched — only the two storyboard label strings change.

---

## 4. Trim `.help` to a single "About Nectar" row

**Storyboard.** In `<tableViewSection headerTitle="Help" id="CS8-fJ-ghn">`, delete four
of the five cells, keeping only the last:
- Delete `id="Tle-IV-D40"` (label `uGk-2d-oFc`, "NetNewsWire Help")
- Delete `id="rFJ-wv-qYV"` (label `MLJ-rt-2zt`, "NetNewsWire Forum")
- Delete `id="TIX-yK-rC6"` (label `NeD-y8-KrM`, "Release Notes")
- Delete `id="taJ-sg-wnU"` (label `DsV-Qv-X4K`, "Bug Tracker")
- **Keep** `id="jK8-tv-hBD"` (label `76A-Ng-kfs`, "About NetNewsWire",
  `accessoryType="disclosureIndicator"`) — change its label text to
  `"About Nectar"`.
- Consider renaming the section's own `headerTitle="Help"` too, or removing the header
  text altogether, now that it contains only an About row — your call, not strictly
  required.

**Swift — `SettingsViewController.swift`:**
- `HelpRow` enum: delete `.help`, `.forum`, `.releaseNotes`, `.bugTracker`, leaving:
  ```swift
  private enum HelpRow: Int {
      case about = 0
  }
  ```
- In `didSelectRowAt`, the `.help` switch currently has five cases; delete all but
  `.about`:
  ```swift
  case .help:
      switch HelpRow(rawValue: indexPath.row) {
      case .about:
          let hosting = UIHostingController(rootView: AboutView())
          self.navigationController?.pushViewController(hosting, animated: true)
      default:
          break
      }
  ```
  (the `default: break` can stay as a harmless guard, or collapse to a single
  unconditional push since there's only one row now — either is fine.)
- **Do not delete `HelpURL`** (`iOS/Settings/HelpURL.swift` or wherever it's declared
  — `enum HelpURL: String { case helpHome, website, releaseNotes,
  howToSupportNetNewsWire, githubRepo, bugTracker, discourse, technotes,
  privacyPolicy }`). This type is `#if os(macOS)`-guarded for some members and is very
  likely still used by the Mac target's own Help menu — only the four `didSelectRowAt`
  call sites that referenced `HelpURL.helpHome`/`.discourse`/`.releaseNotes`/
  `.bugTracker` on iOS are going away with the rows above; the enum itself is
  out of scope for an iOS Settings-only pass. Confirm with a grep across the Mac target
  before touching `HelpURL` itself.
- `openURL(_ urlString: String)` (the GitHub-app-aware helper right below
  `didSelectRowAt`) becomes unused *from Settings* once these four rows are gone —
  check whether anything else in `SettingsViewController.swift` still calls it
  (skim for other `openURL(` call sites in the file) before deleting; if nothing else
  calls it, remove it in the same pass rather than leaving a dead private method.

---

## 5. Extend `AboutView.swift` with Nectar-specific content

Current `AboutView.swift` is a single `ScrollView` → `VStack` with: app icon
(`Image("nnwFeedIcon")`), title `Text(verbatim: "NetNewsWire")`, byline, website link,
a `Credits` block (`AboutCreditView` rows), a `Thanks` block, a `Dedication` block, and
a copyright line. `.navigationTitle` is currently `"About NetNewsWire"`.

Recommended approach — **add a Nectar section, don't replace NetNewsWire's**, since
Nectar is a fork and the existing credits are real attribution that shouldn't
disappear:

1. Change `.navigationTitle(Text(verbatim: "About NetNewsWire"))` to something like
   `"About Nectar"`.
2. Above or below the existing content (above reads better — Nectar-specific info
   first, upstream credits after), add a new block in the same `VStack(spacing: 6)` +
   bold secondary-style header pattern already used for Credits/Thanks/Dedication:
   ```swift
   VStack(spacing: 6) {
       Text(verbatim: "Nectar")
           .bold()
           .foregroundStyle(.secondary)
           .padding(.top, 16)
       Text(verbatim: "Nectar is a private fork of NetNewsWire for reading Ambrosia JSON feeds.")
       // README.md's own description is a good source for the exact wording here —
       // "nectar is not a feed reader. it is a json feed receiver for json feeds
       // produced by ambrosia" — worth quoting or paraphrasing consistently with that.
   }
   ```
3. Optionally swap `Image("nnwFeedIcon")` for a Nectar-specific app icon asset if one
   exists (check the asset catalog — out of visibility in this text-only dump, so
   confirm the asset name before wiring it in; if none exists yet, leave
   `nnwFeedIcon` as a placeholder and flag that a Nectar icon asset is needed).
4. Leave `AboutCreditView`/`AboutContributor` (`iOS/Settings/AboutCreditView.swift`,
   `AboutContributor.swift`) untouched — they're generic, reusable views, not
   NetNewsWire-specific, and Nectar's own credit (whoever forked/maintains it) can be
   added as a new `AboutCreditView(contributorType: "Nectar", contributors: [...])`
   row using the same pattern once `AboutContributor` has a case for the relevant
   people — check that enum's existing cases before adding a new one.

---

## Section-by-section "done when"

- **Notifications:** section no longer appears in Settings at all; no crash from a
  stale `Section.notifications.rawValue` reference anywhere else in the app.
- **Accounts:** section no longer appears; Import Feeds / Share Feeds still work
  correctly against the single local account with no picker UI; indentation-level
  hack repointed to a still-live section, not deleted blind.
- **Feeds:** section shows "Import Feeds" and "Share Feeds" (no third row); tapping
  each still triggers the existing `importOPML`/`exportOPML` flows unchanged;
  `anyAccountHasNetNewsWireNewsSubscription()` confirmed dead and removed, or confirmed
  still-used-elsewhere and left alone.
- **Help:** section (or its remnant) shows one row, "About Nectar," pushing the
  extended `AboutView`; the four removed rows produce no dead `HelpRow` cases, no dead
  storyboard cells, and `HelpURL` itself is untouched.
- **About:** screen title reads "About Nectar," a new Nectar-specific block is visible
  above/below the existing NetNewsWire credits (which remain intact), and nothing in
  `AboutCreditView`/`AboutContributor` broke.

## Suggested implementation order

1. `AccountManager.anyAccountHasNetNewsWireNewsSubscription()` grep (informs whether
   step 3 can fully delete it) — do this first since it's a five-minute check that
   de-risks the Feeds section work.
2. Feeds section (rename + remove row) — smallest, most self-contained change.
3. Notifications section removal — second smallest, no dynamic-row logic to unwind.
4. Accounts section removal — largest of the three removals (dynamic cell
   construction, three `didSelectRowAt`/`cellForRowAt`/`numberOfRowsInSection`
   branches, plus the indentation-hack repoint).
5. Help section trim + `openURL`/dead-code check.
6. About view extension — do last since it's additive/content work, not structural,
   and easiest to iterate on visually once the row that reaches it is already final.

Each step is independently buildable and testable — no step depends on a later one,
so this can land as five or six small PRs instead of one large one if that's
preferable for review.
