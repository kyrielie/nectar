# AO3 direct feed ingestion (RSS/Atom route)

How Nectar subscribes directly to AO3's own RSS/Atom feeds, as a second
ingestion path alongside the Ambrosia JSON Feed route. This is the
subscription/wiring layer; the actual HTML-parsing extractors it calls
(`AO3SummaryExtractor` and friends) are documented separately in
`ao3-feeds.md` — read that one for extractor internals, this one for how
and where they get invoked. See `refresh-throttling.md` for the
pagination/refresh-skip behavior mentioned below.

Ambrosia JSON Feed is not the only way an article reaches Nectar. Nectar
also subscribes directly to AO3's own native tag/user RSS and Atom feeds
(`https://archiveofourown.org/tags/<tag>/feed.atom`, works search feeds,
etc.) — a public site, not the user's own Ambrosia server. This route goes
through the ordinary `RSSParser`/`AtomParser` path (not `JSONFeedParser`),
with three fork-specific additions layered on at the `parsedItems`
construction site in both parsers:

- **`AO3IgnoreList.shouldExclude(_:)`** filters out items from
  blocked works/authors before they're ever turned into a `ParsedItem` —
  one choke point that covers show/fetch/save at once, so a blocked
  work never reaches the database, the timeline, or search.
- **`AO3SummaryExtractor.extract(fromSummaryHTML:)`** (`RSSItem.toParsedItem`
  only — Atom items don't carry AO3's summary HTML in the same shape) tries
  to parse AO3's machine-generated summary HTML into structured fields
  (fandoms, relationships, ratings, word count, `ao3WorkID` from the
  permalink, etc.) and, on success, builds the `ParsedItem` from that
  structured result instead of falling through to the generic
  body/summary promotion every other feed uses.
- AO3 search-results/tag-listing pages get their own pagination and
  refresh-skip handling — see `refresh-throttling.md`.

None of this is present in `JSONFeedParser`'s article-construction path;
it only applies to feeds fetched as RSS/Atom. `RSSItem.swift`/
`RSSParser.swift`/`AtomParser.swift` are otherwise upstream NetNewsWire
code — these three additions are the only diff from upstream in any of
them. In-code comments reference this as "Task 7"/"Task 9" of a `docs/`
planning file; the planning file itself is out of scope, but the task
numbers confirm this is a deliberate, planned feature, not incidental.
