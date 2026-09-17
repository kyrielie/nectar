# Reading Stats

Reading Stats is independent of Screen Time and is enabled by default. `ReadingStatsTracker` observes the active article and reading-progress updates from `WebViewController`. Words are credited from newly observed progress using a per-work high-water mark, so repeated progress samples are not double-counted. A work is counted as completed once progress reaches the existing 99% completion threshold.

Daily entries contain words, active seconds, completed work keys, and overlapping fandom/tag word totals. The rolling history retains thirty-five dates. Per-work progress and all-time word totals are stored separately so the display history can be pruned without losing accounting state.

Fandoms and tags intentionally receive the full credited word count for a work when multiple values are present; their totals are attribution buckets, not mutually exclusive percentages.
