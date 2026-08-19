# Backup / restore

Full device backup and non-destructive restore, driven from a new
**Backup** section in Settings (`settings-screen.md`). Implemented by
`BackupManager` (`iOS/Backup/BackupManager.swift`, app-target-only) and
`BackupRestoreCoordinator` (`iOS/Import/BackupRestoreCoordinator.swift`,
the restore-side document-picker → merge-options → import flow).

## File layout (inside the zip)

```
manifest.json                        schema version, app version/build, export date,
                                      account list, whether settings are included
Accounts/<type>_<accountID>/DB.sqlite3          one subfolder per account
Accounts/<type>_<accountID>/FeedSettings.db
Accounts/<type>_<accountID>/Subscriptions.opml
Settings.plist                       filtered UserDefaults dump — present only if
                                      the person opted in to including settings
Themes/<n>.nnwtheme               custom-installed themes only — always included,
                                      not gated by the settings toggle
```

Account subfolders are named exactly the way `account.dataFolder`'s last
path component already is (`AccountManager`'s own `<type>_<accountID>`
convention) — both export and import key off this name directly rather
than a separately-invented identifier.

`manifest.json` (`BackupManifest`) carries `schemaVersion` (currently
`1`), `appVersion`/`appBuild`, `exportDate`, `accountFolderNames`, and
`settingsIncluded: Bool`. `schemaVersion` is what makes a later additive
change (e.g. the blacklist/mute feature noted below) non-breaking — a
backup written before a field exists simply omits it, and any importer
reading an older backup already has to treat "field absent" as a normal
case. `settingsIncluded` is read by the restore UI (see
`BackupManager.peekSettingsIncluded(zipURL:)`) to decide whether to offer
the settings-replace toggle at all, rather than guessing from
`Settings.plist`'s mere presence.

No credential of any kind is ever written to the zip. `AO3SessionStore`
and `AO3ChallengeSessionStore` (Keychain-backed AO3 login/Cloudflare
cookies, see `ao3-authenticated-reading.md`) are never read by
`BackupManager` at all — restore always requires signing back in to AO3
by hand. The restore merge-options screen always shows a fixed,
non-toggleable notice to this effect, regardless of any other option
chosen.

## Export (`BackupManager.exportBackup(includeSettings:)`)

1. For each `AccountManager.shared.accounts`: copy `Subscriptions.opml`
   and `FeedSettings.db` as-is; write `DB.sqlite3` via
   `account.exportFullSnapshot(toPath:)` (`ArticlesDatabaseFullSnapshotExportTable`'s
   `VACUUM INTO`, see `database.md`) — atomic, consistent, and the only
   export path that includes `bookState` and the FTS `search` table.
2. Copy the custom-installed `Themes` folder
   (`ArticleThemesManager.shared.folderPath`) into `Themes/` —
   unconditional, not gated by `includeSettings`: a custom theme file is
   user content the same way a feed subscription is, not a preference.
   Only the installed-folder contents are copied, not the themes bundled
   inside the app itself (those ship with every install already).
3. If `includeSettings`, dump `Settings.plist` filtered through
   `AppDefaults.backupEligibleKeys` — an explicit, manually maintained
   allowlist (see "Settings scoping" below), not "every key minus known
   system prefixes."
4. Build and write `manifest.json`.
5. Zip the working directory's *contents* (not the directory itself) via
   `Zip.zipFiles` — the pinned `Zip` version always prefixes entries with
   the given path's own directory name, so zipping the contents
   individually is what keeps `manifest.json`/`Accounts`/`Themes`/
   `Settings.plist` at the zip's own root rather than nested one level
   down.
6. Hand back a `URL` for `SettingsViewController` to present via
   `UIDocumentPickerViewController(forExporting:)`, matching every other
   export action in this codebase (`exportArticlesCSV`,
   `exportArticlesSQLite`, `exportOPMLDocumentPicker`) rather than a
   share sheet.
7. Logged via `ActivityLog.shared.logActivity(owner: .app, kind: .exportBackup)`,
   the same way every other bulk operation shows up in the Activity Log.

## Settings scoping: `AppDefaults.backupEligibleKeys`

`AppDefaults.Key` is a plain `struct` of `static let` strings (not
`CaseIterable`), so there's no `allCases` to filter. `backupEligibleKeys`
(`iOS/AppDefaults.swift`) is a manually maintained `[String]` allowlist
of person-facing preferences — real, ongoing maintenance burden every
time a new `AppDefaults.Key` is added, called out in the doc comment on
that array so it doesn't silently drift.

Migration/state-bookkeeping keys are deliberately excluded and must never
be replayed onto another device: `firstRunDate`,
`hasShownAO3Onboarding`, `hasMigratedNavigationBarTintingDefault`,
`hasMigratedToolbarStyleDefault`, `hasMigratedArticleToolbarToggles`,
`didMigrateLegacyStateRestorationInfo`, `lastImageCacheFlushDate`,
`useTintedNavigationBar` (dead migration-source-of-truth only — no
property backs this key), and state-restoration keys
(`selectedArticle`/`selectedSidebarItem`). `AppDefaultsBackupTests`
(`Tests/NetNewsWire-iOSTests/`) has a named test per excluded key, plus a
completeness check that every current `AppDefaults.Key` is accounted for
by exactly one of `backupEligibleKeys` or the test file's own excluded
set.

## Import (`BackupManager.importBackup(from:includeSettings:)`, non-destructive merge)

1. Unzip to a temp directory; read and validate `manifest.json` **before
   touching any live data** — a corrupt or missing manifest throws
   `BackupManagerError.manifestMissingOrUnreadable` at this point, with
   nothing else in the flow having run yet.
2. If `includeSettings && manifest.settingsIncluded`, overwrite
   `AppDefaults.store` for every key in the *current* app's
   `backupEligibleKeys` that the backup's `Settings.plist` actually has a
   value for. This is the one deliberate exception to "never
   delete/overwrite" in the whole restore flow (see "Merge guarantees"
   below) — scoped to `backupEligibleKeys` specifically so a backup
   written by an older app version can't smuggle in a key the current
   version doesn't recognize as eligible.
3. Install `.nnwtheme` files from the zip's `Themes/` folder —
   unconditional, not gated by `includeSettings`. A name collision with
   an already-installed theme (`ArticleThemesManager.themeExists(filename:)`)
   is skipped, keeping the local copy; this deliberately does not call
   `ArticleThemesManager.importTheme(filename:)` unconditionally, since
   that method's own contract is remove-then-copy (an overwrite), not
   skip-on-collision.
4. For each account folder in the zip, matched by
   `<type>_<accountID>` folder name against a local account:
   - Unmatched folders (no local account with that name) are recorded
     and reported back, not silently dropped — restore never creates a
     new account on the person's behalf.
   - **`FeedSettings.db`** — `Account.mergeFeedSettings(fromBackupAtPath:)`
     → `FeedSettingsDatabase.mergeFromBackup(atPath:)`: `INSERT OR
     IGNORE` keyed on `feedURL`, ATTACH/BEGIN/DETACH ordering mirroring
     `BackupSQLiteImportTable` (DETACH only after an explicit
     commit/rollback, since SQLite refuses to DETACH a database still
     part of an open transaction).
   - **`DB.sqlite3`** — `Account.importBackupSnapshot(backupDatabasePath:)`
     → `ArticlesDatabase.importBackupSnapshot(backupDatabasePath:)` →
     `BackupSQLiteImportTable.importBackup` (see "Merge guarantees" per
     table, below). `articlesTable.emptyCaches()` runs afterward, since
     this import bypasses `ArticlesTable`/`StatusesTable`'s normal save
     paths entirely via raw SQL against the attached backup file, and any
     cached `Article` for an articleID a conflict-merge just touched
     needs to be dropped rather than left stale.
   - **`Subscriptions.opml`** — `account.importOPML(_:completion:)`
     directly, reusing the existing add/reconcile logic (see
     "`reconcileRepairedFeeds` in a restore context" below) rather than a
     second diff-and-add-missing implementation.
5. Return a `BackupImportResult` (matched/unmatched account folder
   names, whether settings were applied, installed/skipped theme
   filenames) for the caller to summarize.
6. Logged via `ActivityLog.shared.logActivity(owner: .app, kind: .importBackup)`,
   wrapping the whole `importBackup` call the same way export wraps
   `exportBackup`.

The restore UI (`BackupRestoreCoordinator`) does a throwaway
`BackupManager.peekSettingsIncluded(zipURL:)` read right after the
document picker returns, purely to decide whether the merge-options
alert should offer the settings-replace choice at all — the real,
authoritative manifest read happens again inside `importBackup` itself
before anything is merged; a failure at the peek stage just hides the
toggle rather than blocking the flow, since `importBackup` will still
fail cleanly on a truly bad file.

## Merge guarantees — what restore actually does, per table

Every merge rule here is additive-only (`INSERT OR IGNORE`, an
OR-of-booleans, or a later-timestamp-wins `UPDATE` — never `DELETE` or
`INSERT OR REPLACE`), except the settings-replace step above, which is
opt-in and off by default specifically so it never happens by accident.

| Data | Rule | Why |
|---|---|---|
| `articles` | Keep both; new-only rows added, existing rows untouched | An article's content is immutable once fetched. |
| `statuses` (read, starred, loved) | OR the booleans | A real action should never un-happen because the other copy hadn't caught up. |
| `statuses` (scrollPosition, readingProgress) | Later `lastOpenedAt` wins (the only real per-row timestamp `statuses` has) | Genuinely has one "correct current value." |
| `bookState` (read, starred, loved) | OR the booleans | Same reasoning as `statuses`. |
| `bookState` (scrollPosition, readingProgress) | Later `updatedAt` wins (stamped by every upsert path — setRead/setStarred/setLoved/setScrollPosition/setReadingProgress/setLastOpenedAt/setKudosAttempted) | Same reasoning as `statuses`, different available timestamp column. |
| `bookState` (kudosAttemptedAt/kudosAttemptedAuthenticated) | Prefer whichever side already attempted (`kudosAttemptedAt IS NOT NULL`) | Gates a network side-effect, not reading state — "attempted" only ever skips a future attempt, never triggers a re-post, so this can't cause a duplicate kudos. |
| Annotations (highlights/notes) | New-only entries inserted by ID; on a conflicting `annotationID`, the row with the later `updatedAt` wins in full | Not a plain union — `save`/`updateNote`/`updateColor`/`markOrphaned`/`reanchor` all mutate an existing row in place and all stamp `updatedAt` (confirmed against `AnnotationsTable.swift`), so the same ID genuinely can hold diverged values on two devices; a full-row overwrite matches how `AnnotationsTable.save` itself upserts. |
| Feeds/folders (OPML) | Keep both; missing-locally feeds/folders added, existing untouched, plus `reconcileRepairedFeeds`'s existing re-pointing for a changed feed URL | Reuses `account.importOPML`'s existing behavior rather than a new rule. |
| `FeedSettings.db` | `INSERT OR IGNORE` keyed on `feedURL` — existing local row always wins; backup's row only fills in a feed missing locally | No per-row timestamp exists on this table to arbitrate a genuine conflict — this isn't "prefer newer," it's the only mechanically sound rule available. `editedName`/`newArticleNotificationsEnabled` are real user customization, not disposable cache, but the same no-timestamp reasoning still applies. |
| Settings (`AppDefaults`) | Off by default; if opted in, backup's values overwrite the current device's, scoped to `backupEligibleKeys` | The one deliberate exception — restoring settings is explicitly asking to replace preferences, which is different from merging data. |
| Custom themes | Keep both; a theme missing locally gets installed, a same-filename theme already installed is left alone | Same additive/keep-local-on-conflict shape as everything else. |
| Nothing present locally but absent from the backup | Never touched | No merge rule here issues a delete against local data, ever. |

## `reconcileRepairedFeeds` in a restore context

`account.importOPML` (used directly by restore's OPML step, see Import
step 4 above) already runs `LocalAccountDelegate.reconcileRepairedFeeds`
as part of its normal add/reconcile pass — it re-points a feed whose URL
changed (e.g. an Ambrosia LAN IP change) onto the pre-existing feed
instead of creating a duplicate, preserving that feed's `feedID` and
therefore all its articles/statuses/bookState.

This pass was originally written for "re-import a refreshed OPML on the
same device"; restore feeds it a possibly-stale OPML from a *different*
device, which is a new calling context. Read against that question
specifically: `reconcileRepairedFeeds` matches purely by Ambrosia
collection key (`AmbrosiaFeedIdentity.collectionKey(for:)`) against
`account.flattenedFeeds()` — the account's own current local feed list —
and the incoming OPML's URLs. Nothing in its matching or repointing logic
reads or assumes anything about *which device* produced the incoming
OPML; it only ever compares "does a feed with this collection key already
exist locally" against "what URL does the incoming OPML say that
collection key is at now." That comparison is exactly as valid when the
incoming OPML came from another device's backup as when it came from a
same-device re-import. No same-device assumption is baked into the logic
itself — the earlier "needs verification" flag on this (Correction 7 in
the original plan) is resolved: the code is correct as written for the
restore case without modification.

## Blacklist / mute feature — flagged for later, not built now

There is currently no muted-tag, blocked-feed, or content-filter concept
anywhere in the app, and it isn't part of this feature's scope. No
schema or table is reserved for it now. `manifest.json`'s
`schemaVersion` field is what makes a later addition like this additive
rather than a breaking change — whoever specs that feature should decide
its own storage shape and merge rule (union-merge like annotations if
it's a set of independent entries, replace-if-different if it's closer
to a single setting) and loop in whoever owns this backup feature before
finalizing it, rather than reverse-engineering it from wherever the
feature happened to land.
