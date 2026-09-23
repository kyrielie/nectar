#!/usr/bin/env python3
"""Builds the demo JSON Feed used for Nectar's screenshots.

    python3 demo-feeds/build.py [--out demo-feeds/dist] [--now 2026-09-23T12:00:00Z]

Reads demo-feeds/feed.template.json, replaces each item's "days_ago" with a
real RFC 3339 "date_published" relative to now, and writes feed.json.

Dates are computed at build time because the app ignores articles older than
its 90-day cutoff (ArticlesTable.articleCutoffDate). A feed with fixed dates
would silently stop populating the timeline once they age out.

The feed is deliberately a plain JSON Feed 1.1: no "_ambrosia" extension, so
Nectar never treats these items as AO3/Ambrosia works.
"""

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
JSON_FEED_MARKER = "://jsonfeed.org/version/"  # matches JSONFeedParser.jsonFeedVersionMarker


def parse_now(value):
    if value is None:
        return datetime.now(timezone.utc)
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def rfc3339(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def validate(feed):
    """Mirrors what Modules/RSParser JSONFeedParser requires, so a bad feed
    fails here instead of silently dropping items inside the app."""
    problems = []
    if JSON_FEED_MARKER not in str(feed.get("version", "")):
        problems.append("version must contain " + JSON_FEED_MARKER)
    if not isinstance(feed.get("title"), str):
        problems.append("feed title is required")
    items = feed.get("items")
    if not isinstance(items, list) or not items:
        problems.append("items must be a non-empty array")
        return problems
    seen = set()
    for index, item in enumerate(items):
        label = "item %d (%s)" % (index, item.get("title", "?"))
        item_id = item.get("id")
        if not isinstance(item_id, str) or not item_id:
            problems.append(label + ": id is required")
        elif item_id in seen:
            problems.append(label + ": duplicate id")
        else:
            seen.add(item_id)
        if "content_html" not in item and "content_text" not in item:
            problems.append(label + ": needs content_html or content_text (parser drops it otherwise)")
        if "_ambrosia" in item:
            problems.append(label + ": _ambrosia must not be present in the demo feed")
    return problems


def build(now):
    template = json.loads((HERE / "feed.template.json").read_text(encoding="utf-8"))
    for item in template["items"]:
        days_ago = item.pop("days_ago")
        item["date_published"] = rfc3339(now - timedelta(days=days_ago))
    return template


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(HERE / "dist"))
    parser.add_argument("--now", help="fixed UTC time, YYYY-MM-DDTHH:MM:SSZ (for reproducible output)")
    args = parser.parse_args()

    feed = build(parse_now(args.now))
    problems = validate(feed)
    if problems:
        for problem in problems:
            print("error:", problem, file=sys.stderr)
        return 1

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "feed.json").write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote %s (%d items)" % (out / "feed.json", len(feed["items"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
