# Backup Size Optimization Plan

A roadmap for reducing the storage footprint and transfer duration of Nectar's full
device backup archives (`.zip`). 

> [!NOTE]
> **Status: Deferred (Future Planning).**
> This plan captures the design, findings, and migration steps for when backup file
> size becomes an operational concern (e.g. large libraries of 5,000+ works causing
> AirDrop or iCloud backup timeouts). It is not currently scheduled for immediate
> implementation.

---

## 1. Problem Analysis & Current Footprint

Comparative exports show that a Nectar full backup `.zip` is approximately
**$3\times$ larger** than the equivalent raw fic content exported as standard EPUBs.

Analysis of `DB.sqlite3` (`database.md`, `backup-restore.md`) reveals the primary
causes:

| Component | Mechanism | Estimated Storage Overhead |
|---|---|---|
| **FTS4 Search Table** | `search using fts4(title, body)` duplicates all article text into inverted index shadow tables (`search_content`, `search_segments`, `search_segdir`). | $\approx 40\text{–}50\%$ of `DB.sqlite3` |
| **Base64 Encoding** | `contentHTML` is LZFSE-compressed but Base64-encoded to fit SQLite `TEXT` (`ContentHTMLCompression.swift`). | $+33\%$ expansion on compressed bytes |
| **B-Tree Page Fragmentation** | Fixed 4096-byte page headers and secondary indexes (`bookKey`, `uniqueID`, `searchRowID`, `starred`). | $\approx 10\text{–}15\%$ of `DB.sqlite3` |
| **Feed Metadata Stubs** | Uncached feed subscriptions take up database rows in `articles`, `statuses`, and `search`. | Varies by feed volume |

---

## 2. Key Architectural Finding: `search` is Dead Weight in Backups

In [`BackupSQLiteImportTable.swift`](file:///Users/ethanchan/Documents/Applications/nectar/Modules/ArticlesDatabase/Sources/ArticlesDatabase/BackupSQLiteImportTable.swift#L98-L101), the restore flow merges:
1. `articles` (`INSERT OR IGNORE`)
2. `statuses` (OR of booleans, timestamp arbitrated)
3. `bookState` (OR of booleans, timestamp arbitrated)
4. `annotations` (later `updatedAt` wins)

**Restore never reads or merges the `search` virtual table.** 

When articles are imported during restore, Nectar's existing startup pass
(`SearchTable.indexUnindexedArticles()`) already indexes any unindexed articles
into the local device's live search table asynchronously. Persisting the entire FTS4
search index into the backup zip wastes space during export, compression, and transfer.

---

## 3. Phased Implementation Plan

### Phase 1: Strip FTS4 Search Index from Backup Snapshot
*(High ROI, Zero Schema Risk)*

Currently, [`ArticlesDatabaseFullSnapshotExportTable.swift`](file:///Users/ethanchan/Documents/Applications/nectar/Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesDatabaseFullSnapshotExport.swift)
creates the backup database via `VACUUM INTO destinationPath`.

#### Execution Steps:
1. **Export to temporary stage**: Run `VACUUM INTO tempDatabasePath` to obtain an atomic, consistent point-in-time snapshot.
2. **Drop search index on the copy**:
   ```sql
   DROP TABLE IF EXISTS search;
   VACUUM;
   ```
3. **Move to export bundle**: Package the compacted `DB.sqlite3` into `Accounts/<accountID>/DB.sqlite3` before zipping.
4. **Restore compatibility**: Zero changes required on restore (`BackupSQLiteImportTable.swift` already ignores `search`).
5. **Expected reduction**: **$\approx 40\text{–}50\%$ reduction in backup size**, cutting archive creation time and transfer bandwidth in half.

#### Test Updates:
- Update [`ArticlesDatabaseFullSnapshotExportTests.swift`](file:///Users/ethanchan/Documents/Applications/nectar/Modules/ArticlesDatabase/Tests/ArticlesDatabaseTests/ArticlesDatabaseFullSnapshotExportTests.swift)
  to separate testing of raw database vacuum from the backup-manager export pipeline.

---

### Phase 2: Migrate `contentHTML` from `TEXT` (Base64) to `BLOB` (Binary LZFSE)
*(Medium ROI, High Schema Risk — Recommended only if local device storage is constrained)*

#### Current State:
`articles.contentHTML` is defined as `TEXT NOT NULL` and stores Base64-encoded
LZFSE compressed bytes (`ContentHTMLCompression.swift`). Base64 adds a mandatory
33% storage tax and degrades zip compression.

#### Execution Steps:
1. Schema migration to change `contentHTML` column type or add `contentHTMLBlob BLOB`.
2. Update `FMResultSet` read accessors in `Article+Database.swift` to read `NSData` directly instead of `swiftString`.
3. Eliminate Base64 encoding/decoding cycles in `ContentHTMLCompression.swift`.
4. Run a background data migration pass converting stored strings to raw blobs.
5. **Expected reduction**: $\approx 33\%$ reduction in stored HTML size in both the active database and backup archives.

---

### Phase 3: Prune Stale Network Caches in `FeedSettings.db`
*(Low ROI, Low Risk)*

#### Execution Steps:
1. Prior to bundling `FeedSettings.db`, purge stale HTTP Conditional-GET headers (`etag`, `lastModified`) and cached favicon blobs for feeds deleted or inactive for $>90$ days.
2. Compact `FeedSettings.db` via `VACUUM`.

---

## 4. Verification & Benchmark Checklist

When this plan is activated, verify the following gates:

1. **Size Benchmark**:
   - Measure backup archive size on libraries of 100, 1,000, and 5,000 works.
   - Confirm $\ge 40\%$ reduction in total zip size after Phase 1.
2. **Restore Round-Trip**:
   - Restore a stripped backup onto a fresh device/simulator with an empty database.
   - Verify all articles, statuses, reading progress, and annotations restore completely.
3. **Search Index Backfill**:
   - Confirm `SearchTable.indexUnindexedArticles()` kicks off on first launch after restore.
   - Verify in-app full-text search returns correct results once indexing finishes.
4. **Backward Compatibility**:
   - Confirm a backup produced with the stripped search table can restore cleanly on older app builds (schema version remains compatible).
