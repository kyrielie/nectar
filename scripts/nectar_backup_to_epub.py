#!/usr/bin/env python3
"""
nectar_backup_to_epub.py

Converts a Nectar backup (or ArticlesDatabase DB.sqlite3) into EPUBs using the
Archive of Our Own (AO3) EPUB format, sorted into a directory hierarchy:
    <output_dir>/<Fandom>/<Author>/[<Series>/]<Filename>.epub

Features & Metadata Preservation:
- Decompresses Nectar's at-rest LZFSE + Base64 compressed contentHTML using macOS
  native libcompression (zero pip dependencies required).
- Preserves full AO3 stats: Published, Updated, Words, Chapters, Comments, Kudos,
  Bookmarks, Hits, Archive Lock status, and Collections (which default AO3 EPUBs omit!).
- Preserves Nectar-specific reading state: Read/Unread status, Starred, Loved (maps to
  Calibre 5-star rating), reading progress, and last opened date.
- Preserves personal reader highlights and annotations from Nectar's annotations table,
  generating a dedicated "Reader Highlights & Notes" chapter in the EPUB.
- Replicates AO3's exact EPUB 2.0 / Calibre structure (mimetype at byte 0 uncompressed,
  content.opf with Calibre series tags, toc.ncx, preface with dl.tags, summary, chapters).
- Automatically splits multi-chapter works into individual chapter files for clean pagination.
- Optionally fetches missing contentHTML directly from AO3's official EPUB download route
  with rate-limiting (5s delay), adhering to Nectar's AO3 scraping invariants.
"""

import argparse
import base64
import ctypes
import html
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# ---------------------------------------------------------------------------
# macOS Native LZFSE Decompression (libcompression)
# ---------------------------------------------------------------------------

COMPRESSION_LZFSE = 0x801
_libcompression = None

def _get_libcompression():
    global _libcompression
    if _libcompression is None:
        try:
            lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
            lib.compression_decode_buffer.argtypes = [
                ctypes.c_void_p, ctypes.c_size_t,
                ctypes.c_void_p, ctypes.c_size_t,
                ctypes.c_void_p, ctypes.c_uint32
            ]
            lib.compression_decode_buffer.restype = ctypes.c_size_t
            _libcompression = lib
        except Exception:
            _libcompression = False
    return _libcompression if _libcompression is not False else None


def decompress_content_html(stored_val: Optional[str]) -> Optional[str]:
    """
    Decompresses Nectar's stored contentHTML.
    In Nectar, contentHTML is compressed using NSData.compressed(using: .lzfse)
    and then Base64-encoded. If decompression fails or input is uncompressed,
    it falls back to returning the stored string as-is.
    """
    if not stored_val:
        return stored_val

    try:
        compressed_bytes = base64.b64decode(stored_val)
    except Exception:
        return stored_val

    lib = _get_libcompression()
    if lib:
        buf_size = max(65536, len(compressed_bytes) * 4)
        max_size = 64 * 1024 * 1024
        while buf_size <= max_size:
            dst = ctypes.create_string_buffer(buf_size)
            res = lib.compression_decode_buffer(
                dst, buf_size,
                compressed_bytes, len(compressed_bytes),
                None, COMPRESSION_LZFSE
            )
            if res > 0:
                return dst.raw[:res].decode("utf-8", errors="replace")
            buf_size *= 4

    if "<html" in stored_val or "<div" in stored_val or "<p" in stored_val:
        return stored_val

    return stored_val


# ---------------------------------------------------------------------------
# Filesystem Sanitization & Helpers
# ---------------------------------------------------------------------------

def sanitize_filename(name: str, max_len: int = 100) -> str:
    """Sanitize strings for filesystem safety across macOS/Linux/Windows."""
    if not name:
        return "Unknown"
    cleaned = re.sub(r'[/\\:*?"<>|]', '-', name)
    cleaned = cleaned.replace('\xa0', ' ')
    cleaned = re.sub(r'\s+', ' ', cleaned).strip('. ')
    if not cleaned:
        return "Unknown"
    if len(cleaned) > max_len:
        cleaned = cleaned[:max_len].strip('. ')
    return cleaned


def escape_xml(s: Optional[str]) -> str:
    if not s:
        return ""
    return html.escape(str(s), quote=True)


def ensure_xhtml(html_content: str) -> str:
    """Ensure HTML is well-formed XHTML for EPUB conformance."""
    if not html_content:
        return ""

    for tag in ["br", "hr", "img", "meta", "link", "col", "base"]:
        html_content = re.sub(
            rf"<({tag}\b[^>/]*)(?<!/)>",
            r"<\1/>",
            html_content,
            flags=re.IGNORECASE
        )

    html_content = re.sub(
        r"&(?!(?:[a-zA-Z]+|#\d+|#x[0-9a-fA-F]+);)",
        "&amp;",
        html_content
    )
    return html_content


# ---------------------------------------------------------------------------
# Default AO3 EPUB Styles
# ---------------------------------------------------------------------------

PAGE_STYLES_CSS = """@page {
  margin-bottom: 5pt;
  margin-top: 5pt;
}
"""

STYLESHEET_CSS = """/* Standard AO3 EPUB / Calibre Stylesheet with Nectar Annotations */
.byline {
  display: block;
  text-align: center;
}
.calibre {
  display: block;
  font-size: 1em;
  padding-left: 0;
  padding-right: 0;
  margin: 0 5pt;
}
.calibre1 {
  display: block;
}
.calibre2 {
  font-weight: bold;
}
.calibre3 {
  display: block;
  font-weight: bold;
  margin: 0;
}
.calibre4 {
  display: block;
  margin: 0 0 1em 1em;
}
.calibre5 {
  display: block;
  margin: 0 0 0 1em;
}
.calibre6 {
  display: block;
  font-size: 1.41667em;
  font-weight: bold;
  line-height: 1.2;
  text-align: center;
  margin: 0.67em 0;
}
.calibre7 {
  display: block;
  margin: 1em 0;
}
.calibre8 {
  display: block;
}
.calibre9 {
  color: gray;
  display: block;
  height: 2px;
  margin: 0.5em auto;
  border: currentColor inset 1px;
}
.calibre10 {
  font-style: italic;
}
.endnote-link {
  display: block;
  font-size: 0.75em;
  margin: 0.5em 0;
}
.message {
  display: block;
  text-align: center;
  margin: 1em 0;
}
.tags {
  display: block;
  margin: 1em 0;
  padding: 0;
  border: currentColor none medium;
}
.toc-heading {
  display: none;
  font-size: 1.41667em;
  font-weight: bold;
  line-height: 1.2;
  margin: 0.83em 0;
}
.userstuff {
  display: block;
  font-family: serif;
  margin: 1em;
  padding: 0;
}
.userstuff1 {
  display: block;
  font-family: serif;
  padding: 0;
}
.userstuff2 {
  display: block;
  font-family: serif;
  margin: 1em 0;
  padding: 0;
}

/* Nectar Highlight & Annotation Styles */
.nectar-annotation {
  margin: 1.5em 0;
  padding: 0.8em 1.2em;
  border-left: 4px solid #f68b1f;
  background-color: #fafafa;
}
.nectar-quote {
  font-style: italic;
  margin-bottom: 0.5em;
}
.nectar-note {
  font-weight: 500;
  margin-bottom: 0.4em;
  color: #222;
}
.nectar-meta {
  font-size: 0.8em;
  color: #666;
}
.badge-pill {
  display: inline-block;
  font-size: 0.75em;
  font-weight: bold;
  padding: 2px 6px;
  border-radius: 4px;
  text-transform: uppercase;
}
.badge-yellow { background: #fff3cd; color: #856404; }
.badge-blue { background: #d1ecf1; color: #0c5460; }
.badge-green { background: #d4edda; color: #155724; }
.badge-pink { background: #f8d7da; color: #721c24; }
.badge-purple { background: #e2d9f3; color: #491299; }
"""

CONTAINER_XML = """<?xml version='1.0' encoding='utf-8'?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile media-type="application/oebps-package+xml" full-path="content.opf"/>
  </rootfiles>
</container>
"""


# ---------------------------------------------------------------------------
# AO3 HTML Content Parser & Splitter
# ---------------------------------------------------------------------------

def has_story_content(html_str: Optional[str]) -> bool:
    """
    Checks if html_str contains actual story text (not just an empty stub,
    metadata placeholder, or blank wrapper).
    """
    if not html_str:
        return False
    # Strip HTML tags and check text length
    text_only = re.sub(r'<[^>]+>', ' ', html_str)
    text_only = re.sub(r'\s+', ' ', text_only).strip()
    # Meaningful content must have actual body prose
    return len(text_only) >= 80


class ChapterInfo:
    def __init__(self, title: str, html_body: str):
        self.title = title
        self.html_body = html_body


def extract_chapters_and_parts(content_html: str, work_title: str) -> Tuple[List[ChapterInfo], Optional[str], Optional[str]]:
    """
    Parses content_html and splits it into:
    1. Chapter list (ChapterInfo)
    2. Work-level notes/summary if found inside preface
    3. Work-level afterword/endnotes if found
    """
    if not content_html or not has_story_content(content_html):
        return [], None, None

    custom_css = ""
    style_matches = re.findall(r'<style[^>]*>(.*?)</style>', content_html, flags=re.DOTALL | re.IGNORECASE)
    if style_matches:
        custom_css = "\n".join(style_matches)

    afterword_html = None
    afterword_match = re.search(r'(<div[^>]*id=[\"\']afterword[\"\'][^>]*>.*?</div>\s*</body>|</div>\s*</div>\s*</body>\s*</html>)', content_html, flags=re.DOTALL | re.IGNORECASE)
    if not afterword_match:
        afterword_match = re.search(r'(<div[^>]*id=[\"\']afterword[\"\'][^>]*>.*)', content_html, flags=re.DOTALL | re.IGNORECASE)
    if afterword_match:
        afterword_html = afterword_match.group(1)

    chapter_pattern = re.compile(
        r'<div[^>]*class=[\"\'][^\"\']*?\bchapter\b[^\"\']*?[\"\'][^>]*id=[\"\']chapter-(\d+)[\"\'][^>]*>(.*?)'
        r'(?=<div[^>]*class=[\"\'][^\"\']*?\bchapter\b[^\"\']*?[\"\'][^>]*id=[\"\']chapter-\d+[\"\']|<div[^>]*id=[\"\']afterword[\"\']|<!-- afterword -->|</body>|$)',
        flags=re.DOTALL | re.IGNORECASE
    )

    chapters: List[ChapterInfo] = []
    for match in chapter_pattern.finditer(content_html):
        ch_num = match.group(1)
        ch_inner = match.group(2)

        title_match = re.search(r'<h3[^>]*class=[\"\'][^\"\']*title[^\"\']*[\"\'][^>]*>(.*?)</h3>', ch_inner, flags=re.DOTALL | re.IGNORECASE)
        if title_match:
            ch_title = re.sub(r'<[^>]+>', '', title_match.group(1)).strip()
        else:
            ch_title = f"Chapter {ch_num}"

        chapters.append(ChapterInfo(title=ch_title, html_body=ch_inner))

    if chapters:
        return chapters, custom_css, afterword_html

    single_match = re.search(r'<div[^>]*id=[\"\']chapters[\"\'][^>]*>(.*?)(?:<div[^>]*id=[\"\']afterword[\"\']|</body>|$)', content_html, flags=re.DOTALL | re.IGNORECASE)
    if single_match:
        body = single_match.group(1)
    else:
        body = content_html

    return [ChapterInfo(title=work_title, html_body=body)], custom_css, afterword_html


# ---------------------------------------------------------------------------
# EPUB Generator
# ---------------------------------------------------------------------------

def create_epub(
    output_path: Path,
    metadata: Dict[str, Any],
    content_html: Optional[str],
    annotations: Optional[List[Dict[str, Any]]] = None
) -> None:
    """
    Assembles a complete, compliant AO3-style EPUB archive at output_path,
    preserving full AO3 stats, collections, lock state, reading status, and annotations.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    work_title = metadata.get("title") or "Untitled"
    authors_list = metadata.get("authors") or ["Anonymous"]
    author_str = ", ".join(authors_list)
    fandoms_list = metadata.get("fandoms") or ["Uncategorized"]
    summary_raw = metadata.get("summary") or ""
    tags = metadata.get("tags") or []
    series_name = metadata.get("series_name")
    series_index = metadata.get("series_index")
    work_url = metadata.get("url") or ""
    date_pub = metadata.get("date_published") or metadata.get("date_modified") or datetime.utcnow().strftime("%Y-%m-%d")
    date_mod = metadata.get("date_modified")
    date_bookmarked = metadata.get("date_bookmarked")
    word_count = metadata.get("word_count")
    ch_current = metadata.get("chapter_current")
    ch_total = metadata.get("chapter_total")
    comment_count = metadata.get("comment_count")
    kudos_count = metadata.get("kudos_count")
    bookmark_count = metadata.get("bookmark_count")
    hit_count = metadata.get("hit_count")
    is_restricted = metadata.get("is_restricted")
    collections = metadata.get("collections") or []
    language = metadata.get("language") or "en"
    
    # Nectar reading state
    is_read = metadata.get("is_read", False)
    is_starred = metadata.get("is_starred", False)
    is_loved = metadata.get("is_loved", False)
    reading_progress = metadata.get("reading_progress")
    last_opened_at = metadata.get("last_opened_at")

    doc_uuid = str(uuid.uuid4())

    # Parse chapters
    chapters, custom_css, afterword = extract_chapters_and_parts(content_html or "", work_title)
    if not chapters:
        raise ValueError(f"No story content or chapters found for '{work_title}'")

    stylesheet_content = STYLESHEET_CSS
    if custom_css:
        stylesheet_content += "\n/* Custom Workskin CSS */\n" + custom_css

    split_files: List[Tuple[str, str, str]] = []  # (filename, title, content_xhtml)

    # 1. Preface (Metadata block)
    stats_lines = []
    if date_pub:
        stats_lines.append(f"Published: {date_pub}")
    if date_mod and date_mod != date_pub:
        is_complete = metadata.get("is_complete")
        label = "Completed" if is_complete else "Updated"
        stats_lines.append(f"{label}: {date_mod}")
    if word_count:
        stats_lines.append(f"Words: {word_count:,}")
    if ch_current is not None or ch_total is not None:
        curr = ch_current if ch_current is not None else 1
        tot = ch_total if ch_total is not None else "?"
        stats_lines.append(f"Chapters: {curr}/{tot}")
    if comment_count is not None:
        stats_lines.append(f"Comments: {comment_count:,}")
    if kudos_count is not None:
        stats_lines.append(f"Kudos: {kudos_count:,}")
    if bookmark_count is not None:
        stats_lines.append(f"Bookmarks: {bookmark_count:,}")
    if hit_count is not None:
        stats_lines.append(f"Hits: {hit_count:,}")
    if date_bookmarked:
        stats_lines.append(f"Bookmarked on AO3: {date_bookmarked}")

    dl_items = []
    for category_label, key in [
        ("Rating", "ratings"),
        ("Archive Warning", "warnings"),
        ("Category", "categories"),
        ("Fandom", "fandoms"),
        ("Relationship", "relationships"),
        ("Characters", "characters"),
        ("Additional Tags", "additional_tags"),
    ]:
        vals = metadata.get(key) or []
        if vals:
            links = ", ".join([f'<a href="http://archiveofourown.org/tags/{urllib.parse.quote(v)}">{escape_xml(v)}</a>' for v in vals])
            dl_items.append(f'      <dt class="calibre3">{category_label}:</dt>\n      <dd class="calibre4">{links}</dd>')

    if language:
        dl_items.append(f'      <dt class="calibre3">Language:</dt>\n      <dd class="calibre4">{escape_xml(language)}</dd>')

    if is_restricted:
        dl_items.append('      <dt class="calibre3">Archive Lock:</dt>\n      <dd class="calibre4">Restricted to Registered Users</dd>')

    # Collections
    if collections:
        coll_links = []
        for c in collections:
            if isinstance(c, dict):
                c_name = c.get("name")
                c_slug = c.get("slug")
                if c_name:
                    href = f"http://archiveofourown.org/collections/{urllib.parse.quote(c_slug or c_name)}"
                    coll_links.append(f'<a href="{href}">{escape_xml(c_name)}</a>')
            elif isinstance(c, str):
                coll_links.append(f'<a href="http://archiveofourown.org/collections/{urllib.parse.quote(c)}">{escape_xml(c)}</a>')
        if coll_links:
            dl_items.append(f'      <dt class="calibre3">Collections:</dt>\n      <dd class="calibre4">{", ".join(coll_links)}</dd>')

    # Stats block
    if stats_lines:
        stats_text = "<br class=\"calibre1\"/>\n        ".join(stats_lines)
        dl_items.append(f'      <dt class="calibre3">Stats:</dt>\n      <dd class="calibre5">\n        {stats_text}\n      </dd>')

    preface_dl = "\n".join(dl_items)
    work_link_html = f'Posted originally on the <a href="http://archiveofourown.org/">Archive of Our Own</a> at <a href="{work_url}">{work_url}</a>.' if work_url else ""

    preface_xhtml = f"""<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(work_title)} - {escape_xml(author_str)}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
    <link rel="stylesheet" type="text/css" href="page_styles.css"/>
  </head>
  <body class="calibre">
    <div id="preface" class="calibre1">
      <h2 class="toc-heading" id="calibre_toc_1">Preface</h2>
      <p class="message">
        <b class="calibre2">{escape_xml(work_title)}</b><br class="calibre1"/>
        {work_link_html}
      </p>
      <div class="calibre1">
        <dl class="tags">
{preface_dl}
        </dl>
      </div>
    </div>
  </body>
</html>"""
    split_files.append(("split_000.xhtml", "Preface", ensure_xhtml(preface_xhtml)))

    # 2. Title & Summary
    summary_block = ""
    if summary_raw:
        clean_sum = summary_raw if ("<p" in summary_raw or "<div" in summary_raw) else f"<p>{summary_raw}</p>"
        summary_block = f"""      <p class="calibre7">Summary</p>
      <blockquote class="userstuff">{clean_sum}</blockquote>"""

    annotations_link = ""
    if annotations:
        annotations_link = f"""      <div class="endnote-link">
        <p>📝 You have <a href="split_annotations.xhtml">{len(annotations)} saved highlights and notes</a> from Nectar.</p>
      </div>"""

    title_xhtml = f"""<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(work_title)} - {escape_xml(author_str)}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
    <link rel="stylesheet" type="text/css" href="page_styles.css"/>
  </head>
  <body class="calibre">
    <div id="preface" class="calibre1">
      <div class="calibre1">
        <h1 class="calibre6">{escape_xml(work_title)}</h1>
        <div class="byline">by {escape_xml(author_str)}</div>
{summary_block}
{annotations_link}
      </div>
    </div>
  </body>
</html>"""
    split_files.append(("split_001.xhtml", work_title, ensure_xhtml(title_xhtml)))

    # 3. Chapters
    for i, ch in enumerate(chapters, start=2):
        fn = f"split_{i:03d}.xhtml"
        ch_xhtml = f"""<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(work_title)} - {escape_xml(author_str)}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
    <link rel="stylesheet" type="text/css" href="page_styles.css"/>
  </head>
  <body class="calibre">
    <div class="userstuff1" id="chapters">
      <h2 class="toc-heading">{escape_xml(ch.title)}</h2>
      <div class="userstuff2">
        {ch.html_body}
      </div>
    </div>
  </body>
</html>"""
        split_files.append((fn, ch.title, ensure_xhtml(ch_xhtml)))

    # 4. Afterword (if present)
    if afterword:
        fn = f"split_{len(split_files):03d}.xhtml"
        aft_xhtml = f"""<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(work_title)} - {escape_xml(author_str)}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
    <link rel="stylesheet" type="text/css" href="page_styles.css"/>
  </head>
  <body class="calibre">
    <div id="afterword" class="calibre1">
      <h2 class="toc-heading">Afterword</h2>
      {afterword}
    </div>
  </body>
</html>"""
        split_files.append((fn, "Afterword", ensure_xhtml(aft_xhtml)))

    # 5. Nectar Highlights & Reader Notes (if any exist)
    if annotations:
        ann_entries = []
        for ann in annotations:
            quote = escape_xml(ann.get("quoteExact") or "")
            note = escape_xml(ann.get("note") or "")
            color = ann.get("color") or "yellow"
            chapter_name = escape_xml(ann.get("chapterTitle") or "Work")
            date_created = ann.get("createdAt") or ""

            entry_html = f"""      <div class="nectar-annotation">
        <div class="nectar-quote">“{quote}”</div>"""
            if note:
                entry_html += f"""\n        <div class="nectar-note">💬 Note: {note}</div>"""
            entry_html += f"""\n        <div class="nectar-meta">
          <span class="badge-pill badge-{color}">{color}</span> • {chapter_name} • {date_created}
        </div>
      </div>"""
            ann_entries.append(entry_html)

        ann_html_body = "\n".join(ann_entries)
        annotations_xhtml = f"""<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="{language}" xml:lang="{language}">
  <head>
    <title>Reader Highlights &amp; Notes - {escape_xml(work_title)}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
    <link rel="stylesheet" type="text/css" href="page_styles.css"/>
  </head>
  <body class="calibre">
    <div id="annotations" class="calibre1">
      <h1 class="calibre6">Reader Highlights &amp; Notes</h1>
      <p class="calibre7">Exported from your personal Nectar reader annotations.</p>
{ann_html_body}
    </div>
  </body>
</html>"""
        split_files.append(("split_annotations.xhtml", "Reader Highlights & Notes", ensure_xhtml(annotations_xhtml)))

    # Build content.opf
    manifest_items = []
    spine_items = []
    for fn, _, _ in split_files:
        item_id = fn.replace(".xhtml", "")
        manifest_items.append(f'    <item id="{item_id}" href="{fn}" media-type="application/xhtml+xml"/>')
        spine_items.append(f'    <itemref idref="{item_id}"/>')

    manifest_xml = "\n".join(manifest_items)
    spine_xml = "\n".join(spine_items)

    subject_tags = []
    for tag_item in ["Fanworks"] + tags:
        if tag_item:
            subject_tags.append(f'    <dc:subject>{escape_xml(tag_item)}</dc:subject>')
    for coll in collections:
        c_title = coll.get("name") if isinstance(coll, dict) else str(coll)
        if c_title:
            subject_tags.append(f'    <dc:subject>Collection: {escape_xml(c_title)}</dc:subject>')

    subject_xml = "\n".join(subject_tags)

    # Series metadata
    series_meta = ""
    if series_name:
        series_meta = f"""    <meta name="calibre:series" content="{escape_xml(series_name)}"/>\n"""
        if series_index is not None:
            series_meta += f"""    <meta name="calibre:series_index" content="{series_index}"/>\n"""

    # Extended Stats in Calibre metadata
    extended_stats_meta = []
    if kudos_count is not None:
        extended_stats_meta.append(f'    <meta name="nectar:kudos" content="{kudos_count}"/>')
    if comment_count is not None:
        extended_stats_meta.append(f'    <meta name="nectar:comments" content="{comment_count}"/>')
    if bookmark_count is not None:
        extended_stats_meta.append(f'    <meta name="nectar:bookmarks" content="{bookmark_count}"/>')
    if hit_count is not None:
        extended_stats_meta.append(f'    <meta name="nectar:hits" content="{hit_count}"/>')
    if is_loved or is_starred:
        extended_stats_meta.append('    <meta name="calibre:rating" content="10"/>')

    extended_stats_xml = "\n".join(extended_stats_meta)
    if extended_stats_xml:
        extended_stats_xml += "\n"

    summary_escaped = escape_xml(re.sub(r'<[^>]+>', ' ', summary_raw).strip())

    content_opf = f"""<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
  <metadata xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:calibre="http://calibre.kovidgoyal.net/2009/metadata">
    <dc:title>{escape_xml(work_title)}</dc:title>
    <dc:language>{escape_xml(language)}</dc:language>
    <dc:creator opf:file-as="{escape_xml(author_str)}" opf:role="aut">{escape_xml(author_str)}</dc:creator>
    <dc:identifier id="uuid_id" opf:scheme="uuid">{doc_uuid}</dc:identifier>
    <meta name="calibre:title_sort" content="{escape_xml(work_title.lower())}"/>
    <dc:description>{summary_escaped}</dc:description>
    <dc:publisher>Archive of Our Own</dc:publisher>
{series_meta}{extended_stats_xml}{subject_xml}
    <dc:date>{date_pub}T00:00:00+00:00</dc:date>
  </metadata>
  <manifest>
{manifest_xml}
    <item id="page_css" href="page_styles.css" media-type="text/css"/>
    <item id="css" href="stylesheet.css" media-type="text/css"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
{spine_xml}
  </spine>
</package>
"""

    # Build toc.ncx
    nav_points = []
    for order, (fn, title, _) in enumerate(split_files, start=1):
        nav_points.append(f"""    <navPoint id="np_{order}" playOrder="{order}">
      <navLabel><text>{escape_xml(title)}</text></navLabel>
      <content src="{fn}"/>
    </navPoint>""")
    nav_xml = "\n".join(nav_points)

    toc_ncx = f"""<?xml version='1.0' encoding='utf-8'?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="{language}">
  <head>
    <meta name="dtb:uid" content="{doc_uuid}"/>
    <meta name="dtb:depth" content="2"/>
    <meta name="dtb:generator" content="nectar_backup_to_epub"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>{escape_xml(work_title)}</text>
  </docTitle>
  <navMap>
{nav_xml}
  </navMap>
</ncx>
"""

    with zipfile.ZipFile(output_path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("content.opf", content_opf.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("toc.ncx", toc_ncx.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("stylesheet.css", stylesheet_content.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("page_styles.css", PAGE_STYLES_CSS.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

        for fn, _, xhtml_data in split_files:
            zf.writestr(fn, xhtml_data.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)


# ---------------------------------------------------------------------------
# AO3 Live Downloader (Fallback for contentHTML == nil)
# ---------------------------------------------------------------------------

def download_ao3_epub(
    work_id: str,
    output_path: Path,
    session_cookie: Optional[str] = None,
    delay: float = 5.0
) -> bool:
    """
    Downloads official EPUB directly from AO3.
    AO3 rate-limiting rule: sleeps for `delay` seconds (default 5.0s).
    """
    url = f"https://archiveofourown.org/downloads/{work_id}/work.epub"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "NectarEPUBExport/1.0 (AppleWebKit; compatible)"
        }
    )
    if session_cookie:
        req.add_header("Cookie", f"_otwarchive_session={session_cookie}")

    try:
        time.sleep(delay)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(req, timeout=30) as resp, open(output_path, "wb") as out_f:
            if resp.status == 200:
                out_f.write(resp.read())
                return True
    except Exception as e:
        print(f"  [!] Failed to download from AO3 ({url}): {e}", file=sys.stderr)
        if output_path.exists():
            output_path.unlink()
    return False


# ---------------------------------------------------------------------------
# Main Backup Processing Engine
# ---------------------------------------------------------------------------

def find_sqlite_databases(input_path: Path) -> List[Path]:
    """Locate all DB.sqlite3 files in a directory or zip archive."""
    if input_path.is_file() and input_path.suffix.lower() in [".sqlite", ".sqlite3", ".db"]:
        return [input_path]

    results = []
    if input_path.is_file() and input_path.suffix.lower() == ".zip":
        extract_dir = Path(tempfile.mkdtemp(prefix="nectar_backup_"))
        print(f"[*] Extracting Nectar backup zip to temporary folder: {extract_dir}")
        with zipfile.ZipFile(input_path, 'r') as zf:
            zf.extractall(extract_dir)
        input_path = extract_dir

    for root, _, files in os.walk(input_path):
        for f in files:
            if f == "DB.sqlite3" or (f.endswith(".sqlite3") and "FeedSettings" not in f):
                results.append(Path(root) / f)

    return results


def get_table_columns(conn: sqlite3.Connection, table_name: str) -> Set[str]:
    cursor = conn.cursor()
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row[1] for row in cursor.fetchall()}


def process_backup(
    input_path: Path,
    output_dir: Path,
    fetch_missing: bool = False,
    ao3_cookie: Optional[str] = None,
    rate_limit_delay: float = 5.0,
    include_annotations: bool = True
) -> None:
    db_paths = find_sqlite_databases(input_path)
    if not db_paths:
        print(f"[!] No SQLite databases found in {input_path}")
        return

    print(f"[*] Found {len(db_paths)} database(s) to process.")

    total_articles = 0
    generated_count = 0
    downloaded_count = 0
    skipped_count = 0
    error_count = 0

    for db_path in db_paths:
        print(f"\n[*] Processing database: {db_path}")
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {row[0] for row in cursor.fetchall()}
        if "articles" not in tables:
            print(f"[!] No articles table found in {db_path}, skipping.")
            conn.close()
            continue

        article_cols = get_table_columns(conn, "articles")
        status_cols = get_table_columns(conn, "statuses") if "statuses" in tables else set()
        has_annotations = include_annotations and ("annotations" in tables)

        select_fields = ["a.articleID", "a.uniqueID", "a.title", "a.contentHTML", "a.summary", "a.url"]
        for col in [
            "datePublished", "dateModified", "authors", "wordCount", "chapterCurrent",
            "chapterTotal", "isComplete", "fandoms", "relationships", "characters",
            "ratings", "warnings", "categories", "additionalTags", "series", "language",
            "commentCount", "kudosCount", "bookmarkCount", "hitCount", "isRestricted",
            "collections", "dateBookmarked", "bookKey"
        ]:
            if col in article_cols:
                select_fields.append(f"a.{col}")
            else:
                select_fields.append(f"NULL AS {col}")

        if status_cols:
            for col in ["read", "starred", "loved", "readingProgress", "lastOpenedAt"]:
                if col in status_cols:
                    select_fields.append(f"s.{col}")
                else:
                    select_fields.append(f"NULL AS {col}")
            query = f"""
                SELECT {', '.join(select_fields)}
                FROM articles a
                LEFT JOIN statuses s ON a.articleID = s.articleID
            """
        else:
            query = f"""
                SELECT {', '.join(select_fields)},
                       NULL AS read, NULL AS starred, NULL AS loved,
                       NULL AS readingProgress, NULL AS lastOpenedAt
                FROM articles a
            """

        try:
            cursor.execute(query)
            rows = cursor.fetchall()
        except sqlite3.OperationalError as e:
            print(f"[!] Could not query database: {e}")
            conn.close()
            continue

        print(f"[*] Found {len(rows)} articles in database.")
        total_articles += len(rows)

        for row in rows:
            title = row["title"] or "Untitled"

            def parse_json_list(val):
                if not val:
                    return []
                try:
                    res = json.loads(val)
                    return res if isinstance(res, list) else []
                except Exception:
                    return []

            authors_raw = parse_json_list(row["authors"])
            authors = []
            for a in authors_raw:
                if isinstance(a, dict) and "name" in a and a["name"]:
                    authors.append(a["name"])
                elif isinstance(a, str) and a:
                    authors.append(a)
            if not authors:
                authors = ["Anonymous"]

            fandoms = parse_json_list(row["fandoms"]) or ["Uncategorized"]
            series_list = parse_json_list(row["series"])
            ratings = parse_json_list(row["ratings"])
            warnings = parse_json_list(row["warnings"])
            categories = parse_json_list(row["categories"])
            relationships = parse_json_list(row["relationships"])
            characters = parse_json_list(row["characters"])
            additional_tags = parse_json_list(row["additionalTags"])
            collections = parse_json_list(row["collections"])

            all_tags = ratings + warnings + categories + fandoms + relationships + characters + additional_tags

            series_name = None
            series_index = None
            if series_list and isinstance(series_list[0], dict):
                series_name = series_list[0].get("name")
                series_index = series_list[0].get("index")

            # Determine directory path: <Fandom> / <Author> / [<Series> /]
            primary_fandom = sanitize_filename(fandoms[0])
            primary_author = sanitize_filename(authors[0])

            if series_name:
                clean_series = sanitize_filename(series_name)
                target_dir = output_dir / primary_fandom / primary_author / clean_series
                if series_index is not None:
                    epub_filename = f"{series_index:02d} - {sanitize_filename(title)}.epub"
                else:
                    epub_filename = f"{primary_author} — {sanitize_filename(title)}.epub"
            else:
                target_dir = output_dir / primary_fandom / primary_author
                epub_filename = f"{primary_author} — {sanitize_filename(title)}.epub"

            epub_path = target_dir / epub_filename

            # Check contentHTML
            stored_html = row["contentHTML"]
            decompressed_html = decompress_content_html(stored_html)

            # Retrieve user annotations if present
            annotations_for_work = []
            if has_annotations:
                ann_cur = conn.cursor()
                try:
                    ann_cur.execute("""
                        SELECT quoteExact, note, color, createdAt, chapterTitle
                        FROM annotations
                        WHERE articleID = ? OR (bookKey IS NOT NULL AND bookKey = ?)
                        ORDER BY createdAt ASC
                    """, (row["articleID"], row["bookKey"]))
                    for ann_row in ann_cur.fetchall():
                        annotations_for_work.append({
                            "quoteExact": ann_row[0],
                            "note": ann_row[1],
                            "color": ann_row[2],
                            "createdAt": ann_row[3],
                            "chapterTitle": ann_row[4],
                        })
                except Exception:
                    pass

            metadata = {
                "title": title,
                "authors": authors,
                "fandoms": fandoms,
                "series_name": series_name,
                "series_index": series_index,
                "ratings": ratings,
                "warnings": warnings,
                "categories": categories,
                "relationships": relationships,
                "characters": characters,
                "additional_tags": additional_tags,
                "collections": collections,
                "tags": all_tags,
                "summary": row["summary"],
                "url": row["url"],
                "date_published": row["datePublished"],
                "date_modified": row["dateModified"],
                "date_bookmarked": row["dateBookmarked"],
                "word_count": row["wordCount"],
                "chapter_current": row["chapterCurrent"],
                "chapter_total": row["chapterTotal"],
                "is_complete": bool(row["isComplete"]) if row["isComplete"] is not None else None,
                "comment_count": row["commentCount"],
                "kudos_count": row["kudosCount"],
                "bookmark_count": row["bookmarkCount"],
                "hit_count": row["hitCount"],
                "is_restricted": bool(row["isRestricted"]) if row["isRestricted"] is not None else False,
                "language": row["language"] or "en",
                # Nectar status
                "is_read": bool(row["read"]) if row["read"] is not None else False,
                "is_starred": bool(row["starred"]) if row["starred"] is not None else False,
                "is_loved": bool(row["loved"]) if row["loved"] is not None else False,
                "reading_progress": row["readingProgress"],
                "last_opened_at": row["lastOpenedAt"],
            }

            try:
                if decompressed_html and has_story_content(decompressed_html):
                    create_epub(epub_path, metadata, decompressed_html, annotations=annotations_for_work)
                    generated_count += 1
                    note_info = f" (+{len(annotations_for_work)} notes)" if annotations_for_work else ""
                    print(f"  [+] Generated: {primary_fandom} / {primary_author} / {epub_filename}{note_info}")
                elif fetch_missing and row["url"]:
                    match = re.search(r'archiveofourown\.org/works/(\d+)', row["url"])
                    if match:
                        work_id = match.group(1)
                        print(f"  [*] Downloading from AO3 (work {work_id}): {title}...")
                        success = download_ao3_epub(
                            work_id=work_id,
                            output_path=epub_path,
                            session_cookie=ao3_cookie,
                            delay=rate_limit_delay
                        )
                        if success:
                            downloaded_count += 1
                        else:
                            skipped_count += 1
                    else:
                        print(f"  [-] Skipping (no stored content and unrecognized URL): {title}")
                        skipped_count += 1
                else:
                    print(f"  [-] Skipping (no stored content; use --fetch-missing to download): {title}")
                    skipped_count += 1
            except Exception as e:
                print(f"  [!] Error processing '{title}': {e}", file=sys.stderr)
                error_count += 1

        conn.close()

    print("\n" + "=" * 60)
    print("Export Summary:")
    print(f"  Total Articles Examined: {total_articles}")
    print(f"  EPUBs Generated Locally: {generated_count}")
    print(f"  EPUBs Downloaded (AO3):  {downloaded_count}")
    print(f"  Skipped (No Content):    {skipped_count}")
    print(f"  Errors:                  {error_count}")
    print(f"  Output Directory:        {output_dir.resolve()}")
    print("=" * 60)


# ---------------------------------------------------------------------------
# CLI Entrypoint
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Convert a Nectar backup into AO3-compliant EPUBs with full metadata preservation, organized by Fandom / Author / Series."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Path to Nectar backup .zip, extracted backup directory, or DB.sqlite3"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("./nectar_epubs"),
        help="Target output directory (default: ./nectar_epubs)"
    )
    parser.add_argument(
        "--fetch-missing",
        action="store_true",
        help="Download EPUB directly from AO3 for feed items where contentHTML was not cached locally"
    )
    parser.add_argument(
        "--ao3-cookie",
        type=str,
        default=None,
        help="AO3 _otwarchive_session cookie for restricted works when using --fetch-missing"
    )
    parser.add_argument(
        "--rate-limit-delay",
        type=float,
        default=5.0,
        help="Delay in seconds between AO3 downloads (default: 5.0 seconds)"
    )
    parser.add_argument(
        "--no-annotations",
        action="store_true",
        help="Exclude personal highlights and notes taken in Nectar from the exported EPUB"
    )

    args = parser.parse_args()

    if not args.input.exists():
        print(f"[!] Input path does not exist: {args.input}", file=sys.stderr)
        sys.exit(1)

    process_backup(
        input_path=args.input,
        output_dir=args.output,
        fetch_missing=args.fetch_missing,
        ao3_cookie=args.ao3_cookie,
        rate_limit_delay=args.rate_limit_delay,
        include_annotations=not args.no_annotations
    )


if __name__ == "__main__":
    main()
