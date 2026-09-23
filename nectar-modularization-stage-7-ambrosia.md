# Nectar modularization: Stage 7, Ambrosia — final plan

Companion to the Stage 0-4 plan (`nectar-modularization-stage-0-4.md`),
the Stage 5 plan (`nectar-modularization-stage-5-annotations.md`), and
the Stage 6 plan (`nectar-modularization-stage-6-ao3kit.md`). This
stage does not touch `WebViewController`'s annotation handling,
AO3Kit's extractors, or the Stage 0-4 feature clusters directly, but it
shares file-grouping conventions with Stage 6 (see "Coordination with
Stage 6") and touches files Stage 5 also touches (see "Coordination
with Stage 5").

## Why this is the highest-risk, least-scoped stage

Every other stage moves files that already have clean edges: a folder
that's already self-contained (Stage 0), plain enums with a wide but
mechanical touch-count (Stage 1), or logic that's already split out of
its UI shell (Stages 2-4). Ambrosia is different on both axes:

1. **It requires editing shared core types in place, not adding
   siblings next to them.** `ParsedItem` (RSParser),
   `Article`/`ArticleStatus` (Articles), and `articles`/`bookState`
   (ArticlesDatabase's schema) all carry Ambrosia fields as first-class
   properties/columns, not an attachable extension. `bookKey` in
   particular is threaded through **111 lines of `ArticlesTable.swift`
   alone** (grep count) plus `BookStateTable`, `AnnotationsTable`,
   `AO3ChapterFetcher`, `AO3KudosManager`, `LocalAccountRefresher`,
   three `iOS/Article/Annotations/*` views, `SmartFeedArticleGrouping`,
   `ArticleFeedNaming`, and `ManageStorageViewModel` — this is a
   load-bearing identity concept for the whole read-state system, not
   a bolt-on.
2. **The one piece of real, acknowledged technical debt in the whole
   modularization backlog lives here**: a SQL `CASE` expression
   (`AmbrosiaSQLiteImportTable.bookKeySQLExpression`) that must stay in
   exact precedence sync with `ParsedItem.bookKey` (Swift), by
   convention, verified by one parity test (`BookKeySQLParityTests`). A
   mistake in either direction risks silent book-identity corruption on
   import — wrong read/starred/loved/scroll state applied to the wrong
   book, or two copies of the same book treated as different books (or
   vice versa). This is not a build-break risk like the other stages;
   it's a data-correctness risk that can go unnoticed for a long time.
3. **Two independent transfer routes** (ordinary JSON Feed parsing vs.
   the paginated `.sqlite` bulk-import route) duplicate real logic
   against each other by necessity — the SQLite path's
   `INSERT OR REPLACE ... SELECT` can't call into Swift per-row, so
   `bookKeySQLExpression`, the `content_html`/date TEXT-to-numeric
   conversions, and the "which columns are safe to bulk-copy vs. need
   one-row-at-a-time treatment" reasoning all live in SQL, mirrored
   from the Swift side by hand. Any package boundary drawn here has to
   decide which side of that duplication each piece belongs on without
   breaking the mirror.
4. Unlike AO3Kit (Stage 6, headless but spread across 3 modules),
   Ambrosia is *not* headless: `wordCount`/`fandoms`/`series`/etc. are
   read directly in `iOS/MainTimeline/Cell/MainTimelineCellData.swift`,
   `iOS/MainTimeline/Cell/BadgeColorTable.swift`,
   `Shared/Article Rendering/ArticleRenderer.swift`,
   `Shared/Exporters/ArticleCSVExporter.swift`,
   `Shared/Timeline/ArticleSorter.swift`, and
   `iOS/ReadingStats/ReadingStatsTracker.swift`. A package boundary
   here has real UI-facing consumers on day one, not just an internal
   refactor other code doesn't notice.

Given that, "modularize Ambrosia" is better read as **"introduce
boundaries around Ambrosia without moving the parts that would break
identity or duplicate the SQL mirror,"** not a single package
extraction the way Stages 0-4 were. This plan splits it into ordered
sub-stages so review and testing can happen incrementally, and so a
mistake in a later sub-stage doesn't put identity-critical code back
in scope.

## What's actually detangleable vs. what has to stay put

Confirmed by reading the code, not inferring from the docs:

- **Genuinely boundary-able, low risk:** the two independent
  transfer-route *helper* types that don't touch shared core types —
  `AmbrosiaFeedIdentity` (45 lines, pure `String -> String?`, zero
  dependents outside `LocalAccountDelegate`/`LocalAccountRefresher`),
  `AmbrosiaTransferFormatPreference` (a UserDefaults-backed enum,
  already isolated in its own file), `AmbrosiaSQLiteWireFormat` (a
  single `Int32` constant), and
  `AmbrosiaSQLiteTransferWalkState`/`WalkStateStore` (a Codable struct
  + UserDefaults persistence, no article/database dependency at all).
  None of these touch `ParsedItem`, `Article`, or the SQL schema.
  `AmbrosiaAO3NetworkPreference` was the same shape as these but
  already lives in `Modules/AO3Kit`, moved there by Stage 6 — see
  "Coordination with Stage 6."
- **Boundary-able with care:** `AmbrosiaSQLiteTransferFetcher` (the
  walk loop, retry/backoff, LZFSE decompress) depends only on
  `ArticlesDatabase`'s two public entry points
  (`importAmbrosiaSQLiteTransfer`, `readAmbrosiaSQLiteTransferManifest`)
  and `Articles` for `ArticleChanges` — it's a consumer of the
  database's public API, not an editor of shared types, so it can move
  without touching `ParsedItem`/`Article` at all.
- **Not boundary-able without touching shared core types (this is the
  real Stage 7 work):** `ParsedItem`'s Ambrosia fields + `bookKey`,
  `Article`'s mirrored fields + `bookKey`, `JSONFeedParser`'s
  `_ambrosia` parsing block, `Article+Database.swift`'s
  (de)serialization and `changesFrom` diff logic, the
  `articles`/`bookState` schema migrations in `ArticlesDatabase.swift`,
  and `AmbrosiaSQLiteImportTable`'s bulk-copy SQL (which computes
  `bookKey` server-side and must stay byte-for-byte in sync with
  `ParsedItem.bookKey`). These can be given a clearer internal
  structure (Sub-stage C) but cannot be *relocated out of*
  RSParser/Articles/ArticlesDatabase without breaking the "one shared
  identity concept" property `book-identity.md` describes — moving
  `bookKey` itself to a new module would mean three existing modules
  (RSParser, Articles, ArticlesDatabase) all depend on a fourth just
  for one `String`, which is worse coupling than today, not better.

## Coordination with Stage 6 (AO3Kit)

`AmbrosiaAO3NetworkPreference` lives in `Modules/AO3Kit`, moved there
by Stage 6's sub-stage 6b: it has zero code-level `Account` coupling
and `Account` already depends on `AO3Kit` for the RSParser-layer AO3
extraction types Stage 6 also moves, so this is not a new or backward
dependency edge. This stage does not move it and does not group it
with the sub-stage A files below.

The `bookKey`-prefix constants (`ao3-work:`, `ao3-series:`,
`calibre-series:` in `AO3ChapterFetcher.swift`) stay exactly where
they are: `AO3ChapterFetcher` itself stays in `Modules/Account` (Stage
6 defers moving it — see that plan's Sub-stage 6d), so its private
prefix constants stay with it. `ParsedItem.bookKey` (RSParser) keeps
its own independent copy of the same prefixes, as it always has. This
stage does not touch either copy or attempt to unify them — see "What
NOT to do" below.

`Article.isAmbrosiaItem` gates `AO3ChapterFetcher.isAO3NetworkRequestAllowed`
and the stats-merge branch in `rebuildParsedItem`. This field stays
visible to whatever module owns AO3 chapter-fetching logic, which is
why it stays a plain field on `Article` rather than becoming `internal`
to a hypothetical `Modules/Ambrosia` package — see "What NOT to do."

## Coordination with Stage 5 (Annotations)

`AnnotationsTable`/`Annotation` resolve `bookKey` at write time via the
same `bookKeysForArticleIDs` helper Sub-stage C documents (and does
not move). No code change is needed for coordination — Sub-stage C's
documentation-only pass must not turn into a behavior change in that
shared helper if Stage 5 is mid-flight on the same file area.

## What's already settled about the plan below

- **`BookKeySQLParityTests` is wired into CI.** `Nectar-CI.xctestplan`'s
  `testTargets` array lists `ArticlesDatabaseTests` by identifier, and
  `BookKeySQLParityTests.swift` is one file among that target's tests
  — there is no per-file selection in the test plan, so the whole
  target (and this test with it) already runs in CI. Sub-stage C's
  item 2 is unchanged by this: the test exists and runs, but nothing
  currently makes a *human* re-check the precedence match beyond
  trusting the test, which is the actual gap that sub-stage's review
  recommendation addresses.
- **`docs/database.md`'s migration table is missing three rows.**
  Every `ALTER TABLE`/`CREATE INDEX` statement in
  `ArticlesDatabase.performInitialSetup` was checked against the
  "Migrations of note" table in `docs/database.md`. The table stops
  documenting new columns partway through the migration sequence:
  `additionalTags` (articles), `dateBookmarked` (articles, added as
  "Schema version 4" per its own source comment), and
  `ao3ConfirmedMissingAt` (articles) are missing, plus the
  `articles_searchRowID` index. `additionalTags` and `dateBookmarked`
  are both Ambrosia/AO3 fields and are already described accurately
  elsewhere (`docs/ambrosia-feed.md`, `docs/module-layout.md`) — only
  `database.md`'s migration-history table has fallen behind.
  Sub-stage C's doc pass adds these three rows (and the index, for
  completeness, though it isn't Ambrosia-specific) rather than a
  wholesale rewrite — the table's shape and everything above the gap
  is accurate.
- **No test today exercises the cross-route identity guarantee
  Sub-stage D adds.** Every test file referencing
  `bookKey`/`calculatedArticleID`/cross-route language in
  `ArticlesDatabaseTests` and `AccountTests` was checked; the only
  related test is `AmbrosiaSQLiteImportAsymmetryTests` (read-state
  seeding asymmetry between the two routes), a different claim from
  "two different `articleID`s converge on the same `bookKey`."
  Sub-stage D is net-new coverage, not a duplicate.
- **Sub-stages A and B need no `Package.swift` or `project.yml`
  change.** `AmbrosiaSQLiteTransferFetcher.swift`'s own imports are
  exactly `Foundation`, `os`, `RSWeb`, `Articles`, `ArticlesDatabase` —
  no dependency on anything else in `Account`, confirming sub-stage
  B's file is a pure database-API consumer. `Modules/Account/Package.swift`'s
  target declaration has no `sources:`, `path:`, or `exclude:`
  restriction, so SwiftPM's default recursive file discovery already
  picks up every `.swift` file under `Sources/Account/` regardless of
  subfolder. Grouping the sub-stage A/B files into a
  `LocalAccount/Ambrosia/` subfolder is a filesystem-only move:
  nothing needs updating in either manifest, and there is no
  equivalent of Stage 5's "silently stops running in CI" risk — that
  risk is specific to introducing a *new package/target*, which
  sub-stages A/B do not do.
- **The two unscoped Ambrosia `UserDefaults` preferences are correct
  as-is.** `AmbrosiaTransferFormatPreference.current` (this stage) and
  `AmbrosiaAO3NetworkPreference.updatesEnabled` (Stage 6, now in
  AO3Kit) are both unscoped: one global key each, no `accountID` in
  the key. This would be a real identity-adjacent risk if the app
  could have more than one `.onMyMac` account.
  `AccountManager.init()` creates exactly one `defaultAccount` of type
  `.onMyMac` with a fixed identifier, `AddAccountViewController` only
  ever lists `.onMyMac` as an existing default rather than something
  the person creates another instance of, and
  `AccountManager.duplicateServiceAccount` explicitly exempts
  `.onMyMac` from its duplicate-detection logic
  (`guard type != .onMyMac else { return false }`) because it isn't
  something duplicated in the first place. There is exactly one local
  account per install, so an unscoped preference is correct — no
  scoping fix is part of this plan.

## Proposed sub-stages

### Sub-stage A — Extract the standalone Ambrosia preference/identity types (trivial, same shape as Stage 0)

Move, with no logic changes, into a new file grouping inside
`Modules/Account` (a subfolder, `LocalAccount/Ambrosia/`, not a new
package — see "What NOT to do" for why a new package here is a false
economy):

- `AmbrosiaFeedIdentity.swift`
- `AmbrosiaTransferFormatPreference.swift`
- `AmbrosiaSQLiteWireFormat.swift`
- `AmbrosiaSQLiteTransferWalkState.swift`

These have narrow, one-directional dependents
(`LocalAccountDelegate`, `LocalAccountRefresher`,
`AmbrosiaSQLiteTransferFetcher`) and zero dependency on
`ParsedItem`/`Article`/schema. This sub-stage is pure file
organization: confirm each file compiles standalone, group them, done.
It proves out where the line is for sub-stage B before touching
anything with real risk.

### Sub-stage B — Give `AmbrosiaSQLiteTransferFetcher` a narrower home

`AmbrosiaSQLiteTransferFetcher` depends on `ArticlesDatabase`'s public
`importAmbrosiaSQLiteTransfer`/`readAmbrosiaSQLiteTransferManifest` and
on `Articles` for `ArticleChanges` — nothing in `Account` proper
besides `NectarAppGroupUserDefaults` (already covered by sub-stage A's
grouping). Move it alongside the sub-stage A files. No public API
changes needed; `LocalAccountRefresher.fetchAndImportAmbrosiaSQLiteTransfer`
keeps calling it exactly as today. Low risk: this is a consumer of a
public database API, not an editor of shared core types, so this
sub-stage doesn't touch `bookKey` or the SQL mirror at all.

### Sub-stage C — Document, don't move, the identity-critical core

This is the sub-stage that actually earns Stage 7's "highest risk"
label, and the approach is **structural clarity without relocation**:

1. **Consolidate the `_ambrosia` JSON parsing block in
   `JSONFeedParser` into a private helper type**
   (`AmbrosiaExtensionParsing` or similar), still inside
   `RSParser/Feeds/JSON/`, so the ~40-argument `ParsedItem` call site
   in `parseItem` reads as "standard JSON Feed fields + call out to
   one well-named helper" instead of one 900-character line. This is a
   readability change with a clear test (existing
   `JSONFeedParserTests.ambrosiaExtension` must still pass
   byte-for-byte), not a module boundary — `_ambrosia` parsing is
   legitimately RSParser's job (it's feed-format work), and
   `module-layout.md` already says as much. Do **not** promote this to
   its own package: doing so would make `RSParser` depend on a new
   `Modules/Ambrosia` for something that's still, structurally, "one
   more JSON key this parser understands," and would put
   `ParsedSeriesEntry` (already RSParser-local) on the wrong side of a
   package boundary from the parser that constructs it.
2. **Add an explicit "bookKey parity" contract note, not just a
   comment, at both ends of the mirror** — `ParsedItem.bookKey` and
   `AmbrosiaSQLiteImportTable.bookKeySQLExpression` already
   cross-reference each other in prose; make `BookKeySQLParityTests`
   (already wired into CI via the `ArticlesDatabaseTests` entry in
   `Nectar-CI.xctestplan`) a named, non-skippable gate in
   documentation, not just in CI: add a code comment at the top of
   each side pointing at the exact test name, not just "see the other
   file's doc comment." The test already enforces the parity
   mechanically; what's missing is a human pointer from the code to
   the test, so a future reader editing one side knows exactly what to
   run before trusting a change, rather than rediscovering the test's
   existence by chance.
3. **Do not attempt to extract `bookKey` itself, or the Ambrosia
   fields on `ParsedItem`/`Article`, into a separate module.** As
   covered above, this would require three existing modules (RSParser,
   Articles, ArticlesDatabase) to each take on a new dependency for
   one property each already has direct, simple access to — trading
   zero actual coupling reduction for a real new compile-graph edge. A
   `Modules/Ambrosia` package that a naive read of the priority list
   might suggest is, on inspection, the wrong shape for this specific
   feature; unlike AO3Kit (genuinely several unrelated concerns glued
   together across modules with no shared identity concept),
   Ambrosia's fields are placed correctly today — they're just
   unusually central.
4. **Migration-comment consolidation only, no functional change**: the
   Ambrosia-related `ALTER TABLE`/one-time-fix blocks in
   `ArticlesDatabase.performInitialSetup` (the `isAmbrosiaItem`
   column, the `bookKey` column, the series-group `bookKey`-routing
   data fix) are already grouped and well-commented and need no code
   change. `docs/ambrosia-feed.md` and `docs/module-layout.md` are
   accurate; `docs/database.md`'s "Migrations of note" table is
   missing the three rows noted above. This sub-stage's doc work is to
   add those three rows in the same "Columns | Table | Purpose" shape
   as the existing entries — a small, mechanical addition, not a
   rewrite.

### Sub-stage D — Verify the cross-route identity guarantee explicitly

The JSON Feed route computes `articleID` via
`Article.calculatedArticleID(feedID:uniqueID:)` (an MD5 hash of
`feedID` and `uniqueID`), but the `.sqlite` transfer route's bulk
`INSERT ... SELECT` uses the wire row's own `id` directly as both
`articleID` and `uniqueID` (`AmbrosiaSQLiteImportTable.copyItems`'s
own comment confirms this is deliberate — the wire id is already
globally stable, so there's no per-feed guid to combine it with the
way `JSONFeedParser` does). This means the *same* Ambrosia-hosted
book, synced once via the JSON route and later via a `.sqlite`
transfer for the same feed (e.g. after a transfer-format preference
change), gets two different `articleID`s but converges on the same
`bookKey` — which is exactly what `bookKey` exists to paper over
(`book-identity.md`'s whole reason for being), so this is intentional,
not a bug. This sub-stage adds one focused test that pins this down
explicitly (no code change): import the same book via both routes for
the same `feedID` and assert both distinct `articleID`s resolve to the
same `bookKey` and share `BookStateTable` state. This is cheap
insurance given how much of this stage's risk is "silent identity
corruption," and is fully net-new coverage, not a gap in an existing
test's scope.

## What NOT to do

- **Do not create `Modules/Ambrosia`** as a top-level SPM package.
  Every piece of Ambrosia logic that could move there either (a) has
  to stay in RSParser/Articles/ArticlesDatabase because it edits
  shared core types (Sub-stage C's territory), or (b) is small enough
  and narrowly-enough consumed that it belongs as a subfolder of
  `Modules/Account` (Sub-stages A/B), not a fourth module three others
  would need to newly depend on. A package with only "the parts that
  don't have to stay elsewhere" left in it would be a grab-bag, not a
  concern boundary — the opposite of what the
  `AO3Kit`/`AnnotationsKit`/`ReadingStats` precedent is going for.
- **Do not touch `WebViewController.swift`'s `bookKey`-prefix check**
  (`article.bookKey.hasPrefix("ao3-work:")`, line 555) as part of this
  stage. It's one line, reads a value this stage isn't relocating, and
  Stage 5's Annotations work already has open surgery planned in this
  same file — two stages editing the same 3,000+-line file
  concurrently is exactly the kind of collision the whole
  modularization effort is trying to avoid causing more of.
- **Do not attempt to eliminate the Swift/SQL `bookKey` duplication**
  (e.g. by trying to make `AmbrosiaSQLiteImportTable` call into Swift
  per-row instead of using a SQL `CASE`) as part of this stage. That
  bulk `INSERT ... SELECT` is the entire reason the SQLite transfer
  route is fast enough to be worth having as a separate path at all;
  per-row Swift computation would undo its own performance rationale.
  The parity *test* (Sub-stage C, item 2) is the right mitigation for
  this stage; a rewrite of the import strategy is out of scope and
  should be its own, separately-justified piece of work if it's ever
  done at all.
- **Do not attempt to unify `ParsedItem.bookKey`'s prefix constants
  with `AO3ChapterFetcher`'s** (see "Coordination with Stage 6"). Both
  copies stay exactly where they are; this stage does not touch
  either.

## Suggested order and rough sizing

| Sub-stage | Size | Risk | Blocking? |
|---|---|---|---|
| A — extract standalone preference/identity types | small | none — file-move-only, no manifest changes | no |
| B — relocate `AmbrosiaSQLiteTransferFetcher` | small | none — no dependency on anything outside `ArticlesDatabase`/`Articles`/`RSWeb` | depends on A landing first (shared folder) |
| C — consolidate parsing helper, add parity-test cross-references, fix 3 missing rows in `docs/database.md` | medium | medium (touches `JSONFeedParser`, no behavior change intended but is the identity-critical file) | no, but should land before D |
| D — add the explicit cross-route identity test | small | none (test-only, net-new) | depends on C for context, not code |

A and B can proceed immediately and in either order. C should be
reviewed on its own, ideally by someone who can independently
re-verify the `bookKeySQLExpression`/`ParsedItem.bookKey` precedence
match rather than trusting the parity test alone, given what's at
stake if that match is wrong. D is cheap and should not be skipped
even if time is short elsewhere in this stage — it is the one piece of
net-new safety this stage adds beyond reorganization.
