# Nectar roadmap

This roadmap is the shared summary of project direction. It records the current
app state, the proposal inventory, and the currently approved planning work. Detailed
specifications live in the gitignored `plans/` directory; the index there must
agree with this roadmap. A specification's own status (for example, “Final
Specification”) means the design is written, not that the work is approved or
implemented.

## Current project

Nectar is an iOS reading and library app forked from NetNewsWire. Its current
implemented foundations include JSON Feed/Ambrosia ingestion, SQLite-backed
storage and search, AO3 feed and on-demand work fetching, reading progress and
statistics, annotations, theme customization, backup/restore, and EPUB export.
Use `CLAUDE.md` to route changes to the relevant technical documentation.

## Next initiative

AO3 request coordination is approved for further planning. Existing page and
work requests are generally user-triggered and use current pacing/gates. AO3
HTML listing pages are skipped during routine refresh; native AO3 RSS/Atom
subscriptions still refresh as ordinary metadata feeds. They bypass the
coordinator, but additional pacing is only an open policy question, not an
approved implementation requirement. The kudos POST also bypasses the
coordinator while honoring the shared cooldown. This approval is for planning
only; implementation is not approved. The working plan is indexed in the
local proposal index.

The faceted AO3 search builder remains an open proposal; no decision is needed
now.

## Proposal inventory

This is the authoritative classification of the proposals indexed in
`plans/README.md`. “Unverified” means source inspection found no implementation
or docs reference; it is not a claim that no partial work exists.

- **Approved for planning, partially implemented:** AO3 request coordination.
  The approved scope is to audit and plan coverage and correctness; it does not
  authorize implementation. See the plan status above and
  `docs/ao3-integration.md`.
- **Open proposal; not prioritized:** Faceted AO3 search builder. Existing
  app search results and pagination are in place; the plan's query builder,
  native filter UI, and saved-search behavior are not evidenced in current
  source.
- **Exploratory proposal; no implementation approved:** Settings redesign.
  The next proposed step is a reviewable SwiftUI root/navigation spike using
  existing settings behavior, then a product decision on information
  architecture and migration scope. The former implementation-ready proposal
  had stale assumptions and must not be treated as an implementation spec.
- **Unverified proposals:** WIP update checker; mature-content privacy gate;
  native AO3 comments viewer, author profiles, and account hub; native fandom
  catalog; reading queues/collections; recently deleted recovery; user EPUB
  import; custom font import; iCloud folder sync; manual theme presets.
- **Theme process/design proposals:** theme quality review, theme provenance
  and unification, and theme-management UI mockup. These should be handled as
  discrete design or maintenance projects, not presumed app features.
- **Completed in current app:** backup-to-EPUB proposal. Both the desktop
  converter and native per-work EPUB export exist; see `docs/backup-restore.md`.

Manual theme presets are still indexed as a draft proposal, not in the finished
archive; the former roadmap statement that it was archived was incorrect.

## Roadmap maintenance

Before marking work active or complete, compare its acceptance criteria with
current source and tests, check relevant topic docs, and record verified scope
here. Keep the inventory and order in `plans/README.md` aligned with this file.
Move completed plans into `plans/finished/`; keep lasting behavior documented
in tracked topic docs. Do not link this roadmap to individual gitignored plan
files.
