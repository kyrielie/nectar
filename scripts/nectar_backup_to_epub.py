#!/usr/bin/env python3
"""
nectar_backup_to_epub.py

Converts a Nectar backup (or ArticlesDatabase DB.sqlite3) into high-quality EPUB 3.3
ebooks conforming to the Standard Ebooks Manual of Style and Archive of Our Own (AO3)
specifications, sorted into a clean directory hierarchy:
    <output_dir>/<Fandom>/<Author>/[<Series>/]<Filename>.epub

Features & Standard Compliance:
- Strict EPUB 3.3 compliance with uncompressed `mimetype` at byte 0.
- EPUB 3 Navigation Document (`toc.xhtml`) with ToC and Landmark navigation, plus
  backward-compatible NCX (`toc.ncx`) for older e-readers.
- Author Workskin & Workstyle Fidelity: Extracts author `<style>` blocks into
  `css/workskin.css`, preserves `<div id="workskin" class="userstuff">` wrappers
  across all split chapters, and injects dark-mode contrast guards.
- Standard Ebooks Typography Engine: Intelligent conversion of straight quotes
  to curly quotes (“ ” / ‘ ’), true em-dashes (—), en-dashes (–), ellipses (…),
  and clean paragraph indentation without breaking HTML attributes.
- Decompresses Nectar's at-rest LZFSE + Base64 compressed contentHTML using macOS
  native libcompression (zero pip dependencies required).
- Preserves full AO3 stats: Published, Updated, Words, Chapters, Comments, Kudos,
  Bookmarks, Hits, Archive Lock status, and Collections directly in Dublin Core
  metadata refines and the preface.
- Preserves personal reader highlights and annotations from Nectar's annotations table,
  generating a dedicated "Reader Highlights & Notes" Back Matter chapter.
- Optional `--calibre-add` flag to automatically import generated EPUBs into Calibre.
- Optional polite rate-limited fetcher (`--fetch-missing`) adhering to Nectar's AO3
  scraping invariants (5s delay, session cookie support).
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
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from datetime import datetime, timezone
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
# Filesystem Sanitization & Language Helpers
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


def normalize_bcp47_language(lang_code: Optional[str]) -> str:
    """Normalize AO3 language codes to valid BCP 47 / ISO 639-1 tags."""
    if not lang_code:
        return "en"
    code = lang_code.strip().lower()
    mapping = {
        "english": "en",
        "espanol": "es",
        "francais": "fr",
        "deutsch": "de",
        "italiano": "it",
        "russian": "ru",
        "japanese": "ja",
        "chinese": "zh",
        "portugues": "pt",
        "en-us": "en-US",
        "en-gb": "en-GB",
        "zh-cn": "zh-CN",
        "zh-tw": "zh-TW",
    }
    return mapping.get(code, code if len(code) <= 8 else "en")


def ensure_xhtml(html_content: str) -> str:
    """Ensure HTML is well-formed XHTML5 for EPUB 3 conformance."""
    if not html_content:
        return ""

    # Ensure void elements are self-closing
    for tag in ["br", "hr", "img", "meta", "link", "col", "base", "input"]:
        html_content = re.sub(
            rf"<({tag}\b[^>/]*)(?<!/)>",
            r"<\1/>",
            html_content,
            flags=re.IGNORECASE
        )

    # Escape unescaped ampersands
    html_content = re.sub(
        r"&(?!(?:[a-zA-Z]+|#\d+|#x[0-9a-fA-F]+);)",
        "&amp;",
        html_content
    )
    return html_content


# ---------------------------------------------------------------------------
# Standard Ebooks Typography Engine
# ---------------------------------------------------------------------------

def apply_standard_ebooks_typography(text: str) -> str:
    """
    Applies Standard Ebooks typographic transformations to text:
    - Curly quotes (“ ” and ‘ ’)
    - Em-dashes (—) replacing typewriter '--'
    - En-dashes (–) for number ranges
    - True ellipses (…) replacing '...'
    Safely ignores HTML tags and attributes.
    """
    if not text:
        return ""

    tokens = re.split(r'(<[^>]+>)', text)
    transformed_tokens = []

    for token in tokens:
        if token.startswith('<') and token.endswith('>'):
            transformed_tokens.append(token)
            continue

        # Typography only on text nodes
        t = token

        # 1. Ellipses
        t = re.sub(r'\.{3,}', '…', t)
        t = re.sub(r'\.\s\.\s\.', '…', t)

        # 2. Dashes
        t = re.sub(r'---', '—', t)
        t = re.sub(r'--', '—', t)
        # En-dash for numeric ranges (e.g. 1990-1995 or pp. 10-15)
        t = re.sub(r'(\b\d+)-(\d+\b)', r'\1–\2', t)

        # 3. Smart Apostrophes & Single Quotes
        # Contractions and possessives
        t = re.sub(r"([a-zA-Z0-9])'([a-zA-Z0-9])", r"\1’\2", t)
        # Decades / leading apostrophes ('90s, 'cause)
        t = re.sub(r"\b'(\d{2}s?)\b", r"’\1", t)
        t = re.sub(r"\b'(em|cause|tis|twas)\b", r"’\1", t)
        # Single quotes around words: 'word' -> ‘word’
        t = re.sub(r"(^|[\s(\[{])'([^\s])", r"\1‘\2", t)
        t = re.sub(r"([^\s])'([\s)\]},.;:!?]|$)", r"\1’\2", t)

        # 4. Smart Double Quotes
        # Opening quotes: preceded by space, opening punctuation, or start of line
        t = re.sub(r'(^|[\s(\[{>])"([^\s])', r'\1“\2', t)
        # Closing quotes: followed by space, closing punctuation, or end of line
        t = re.sub(r'([^\s])"([\s)\]}<,.;:!?]|$)', r'\1”\2', t)
        # Fallback any remaining unmatched straight quotes
        t = t.replace('"', '”')

        transformed_tokens.append(t)

    return "".join(transformed_tokens)


# ---------------------------------------------------------------------------
# Standard Ebooks & Modern E-Reader Stylesheets
# ---------------------------------------------------------------------------

PAGE_STYLES_CSS = """@page {
  margin-bottom: 5pt;
  margin-top: 5pt;
}
"""

CORE_CSS = """/* Standard Ebooks Core CSS Reset */
html {
  font-family: serif;
}
body {
  margin: 0;
  padding: 0;
  color: #111;
  background-color: #fff;
  text-rendering: optimizeLegibility;
}
p {
  margin: 0;
  text-align: justify;
  text-justify: inter-word;
  hyphens: auto;
  -webkit-hyphens: auto;
}
p + p {
  text-indent: 1.5em;
}
h1, h2, h3, h4, h5, h6 {
  font-family: sans-serif;
  font-weight: 600;
  line-height: 1.25;
  text-align: center;
  text-indent: 0;
  break-after: avoid;
  page-break-after: avoid;
}
h1 + p, h2 + p, h3 + p, h4 + p {
  text-indent: 0;
}
blockquote {
  margin: 1.25em 2em;
  font-style: italic;
}
hr {
  border: 0;
  height: 1px;
  background: #ccc;
  margin: 2em auto;
  width: 40%;
}
a {
  color: inherit;
  text-decoration: underline;
}

@media (prefers-color-scheme: dark) {
  body {
    background-color: #121212;
    color: #e4e4e7;
  }
  hr {
    background: #444;
  }
}
"""

SE_CSS = """/* Standard Ebooks Semantic Layout & Section Patterns */
.byline {
  display: block;
  text-align: center;
  font-style: italic;
  margin: 0.5em 0 2em 0;
}
.title-header {
  margin-top: 2em;
  margin-bottom: 1em;
}
.fulltitle {
  font-size: 1.8em;
  margin-bottom: 0.25em;
}
.message {
  display: block;
  text-align: center;
  margin: 1.5em 0;
  font-style: italic;
}
.tags-dl {
  margin: 1.5em 0;
  padding: 0;
  font-size: 0.9em;
  line-height: 1.5;
}
.tags-dl dt {
  font-weight: bold;
  float: left;
  clear: left;
  width: 9em;
  margin-bottom: 0.5em;
}
.tags-dl dd {
  margin-left: 9.5em;
  margin-bottom: 0.5em;
}
.tags-dl dd:after {
  content: "";
  display: table;
  clear: both;
}
.stats-block {
  border-top: 1px solid #ccc;
  border-bottom: 1px solid #ccc;
  padding: 0.75em 0;
  margin: 1.5em 0;
  font-size: 0.85em;
  text-align: center;
  line-height: 1.6;
}
.meta-section {
  margin: 2em 0;
}
.meta-section h3 {
  font-size: 1.1em;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.5em;
  color: #555;
}
.chapter-header {
  margin: 2em 0 1.5em 0;
  text-align: center;
}
.chapter-title {
  font-size: 1.4em;
  margin: 0.25em 0;
}
.endnotes-section {
  margin-top: 3em;
  padding-top: 1.5em;
  border-top: 1px dashed #ccc;
}

@media (prefers-color-scheme: dark) {
  .stats-block {
    border-color: #333;
  }
  .tags-dl dt {
    color: #a1a1aa;
  }
  .meta-section h3 {
    color: #a1a1aa;
  }
  .endnotes-section {
    border-color: #333;
  }
}
"""

ANNOTATIONS_CSS = """/* Nectar Reader Highlights & Notes Styling */
.annotations-header {
  margin-top: 2em;
  margin-bottom: 1.5em;
}
.annotation-summary {
  font-size: 0.9em;
  text-align: center;
  color: #71717a;
  margin-bottom: 2em;
}
.annotation-card {
  margin: 1.5em 0;
  padding: 1em 1.25em;
  border-left: 4px solid #f59e0b;
  background-color: #fbfbfb;
  border-radius: 0 4px 4px 0;
}
.annotation-location {
  font-size: 0.8em;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #71717a;
  margin-bottom: 0.5em;
}
.annotation-quote {
  font-style: italic;
  margin: 0.5em 0;
  color: #27272a;
  text-align: left;
}
.annotation-note {
  font-weight: 500;
  margin: 0.5em 0;
  color: #18181b;
  text-align: left;
}
.annotation-date {
  display: block;
  font-size: 0.75em;
  color: #a1a1aa;
  margin-top: 0.5em;
}

@media (prefers-color-scheme: dark) {
  .annotation-card {
    background-color: #1f1f23;
  }
  .annotation-quote {
    color: #e4e4e7;
  }
  .annotation-note {
    color: #f4f4f5;
  }
  .annotation-summary, .annotation-location {
    color: #a1a1aa;
  }
}
"""

CONTAINER_XML = """<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


# ---------------------------------------------------------------------------
# Author Workskin & Chapter Extraction Engine
# ---------------------------------------------------------------------------

def has_story_content(html_str: Optional[str]) -> bool:
    """Checks if html_str contains actual story text."""
    if not html_str:
        return False
    text_only = re.sub(r'<[^>]+>', ' ', html_str)
    text_only = re.sub(r'\s+', ' ', text_only).strip()
    return len(text_only) >= 80


class ChapterInfo:
    def __init__(self, title: str, html_body: str, chapter_id: str = "chapter-1"):
        self.title = title
        self.html_body = html_body
        self.chapter_id = chapter_id


def extract_workskin_and_chapters(
    content_html: str,
    work_title: str
) -> Tuple[List[ChapterInfo], str, Optional[str]]:
    """
    Parses content_html and extracts:
    1. Chapters list (ChapterInfo)
    2. Author workskin CSS (with dark-mode guard)
    3. Work-level afterword / endnotes if present
    """
    if not content_html or not has_story_content(content_html):
        return [], "", None

    # 1. Extract Author Workskin CSS (<style> blocks)
    workskin_rules = []
    style_matches = re.findall(r'<style[^>]*>(.*?)</style>', content_html, flags=re.DOTALL | re.IGNORECASE)
    for match in style_matches:
        cleaned_css = match.strip()
        if cleaned_css:
            workskin_rules.append(cleaned_css)

    workskin_css = ""
    if workskin_rules:
        raw_workskin = "\n\n".join(workskin_rules)
        # Inject dark-mode contrast guard for workskin
        workskin_css = f"""/* Author Workskin Stylesheet Preserved from AO3 */
{raw_workskin}

/* Workskin Dark-Mode & Viewport Contrast Guard */
@media (prefers-color-scheme: dark) {{
  #workskin {{
    color: #e4e4e7;
    background-color: transparent;
  }}
  #workskin [style*="color: #000"],
  #workskin [style*="color: black"],
  #workskin [style*="color:#000000"] {{
    color: #f4f4f5 !important;
  }}
}}
#workskin {{
  max-width: 100%;
  box-sizing: border-box;
  overflow-wrap: break-word;
}}
"""

    # 2. Extract Afterword / Work Endnotes if present
    afterword_html = None
    afterword_match = re.search(
        r'(<div[^>]*id=[\"\']afterword[\"\'][^>]*>.*?</div>\s*</body>|</div>\s*</div>\s*</body>\s*</html>)',
        content_html,
        flags=re.DOTALL | re.IGNORECASE
    )
    if not afterword_match:
        afterword_match = re.search(r'(<div[^>]*id=[\"\']afterword[\"\'][^>]*>.*)', content_html, flags=re.DOTALL | re.IGNORECASE)
    if afterword_match:
        afterword_html = afterword_match.group(1)

    # 3. Extract Multi-Chapter Works
    chapter_pattern = re.compile(
        r'<div[^>]*class=[\"\'][^\"\']*?\bchapter\b[^\"\']*?[\"\'][^>]*id=[\"\']chapter-(\d+)[\"\'][^>]*>(.*?)'
        r'(?=<div[^>]*class=[\"\'][^\"\']*?\bchapter\b[^\"\']*?[\"\'][^>]*id=[\"\']chapter-\d+[\"\']|<div[^>]*id=[\"\']afterword[\"\']|<!-- afterword -->|</body>|$)',
        flags=re.DOTALL | re.IGNORECASE
    )

    chapters: List[ChapterInfo] = []
    for match in chapter_pattern.finditer(content_html):
        ch_num = match.group(1)
        ch_inner = match.group(2)

        title_match = re.search(
            r'<h3[^>]*class=[\"\'][^\"\']*title[^\"\']*[\"\'][^>]*>(.*?)</h3>',
            ch_inner,
            flags=re.DOTALL | re.IGNORECASE
        )
        if title_match:
            ch_title = re.sub(r'<[^>]+>', '', title_match.group(1)).strip()
        else:
            ch_title = f"Chapter {ch_num}"

        # Strip redundant chapter header if already extracted
        ch_body_clean = re.sub(
            r'<h3[^>]*class=[\"\'][^\"\']*title[^\"\']*[\"\'][^>]*>.*?</h3>',
            '',
            ch_inner,
            flags=re.DOTALL | re.IGNORECASE
        )

        chapters.append(ChapterInfo(
            title=ch_title,
            html_body=ch_body_clean.strip(),
            chapter_id=f"chapter-{ch_num}"
        ))

    if chapters:
        return chapters, workskin_css, afterword_html

    # 4. Fallback Single-Chapter Work
    single_match = re.search(
        r'<div[^>]*id=[\"\']chapters[\"\'][^>]*>(.*?)(?:<div[^>]*id=[\"\']afterword[\"\']|</body>|$)',
        content_html,
        flags=re.DOTALL | re.IGNORECASE
    )
    if single_match:
        body = single_match.group(1)
    else:
        body = content_html

    # Strip author <style> blocks from body text as they are moved to workskin.css
    body = re.sub(r'<style[^>]*>.*?</style>', '', body, flags=re.DOTALL | re.IGNORECASE)

    return [ChapterInfo(title=work_title, html_body=body.strip(), chapter_id="chapter-1")], workskin_css, afterword_html


# ---------------------------------------------------------------------------
# Ambrosia Tag Synonym & Metatag Resolver
# ---------------------------------------------------------------------------

ENV_TAG_SEEDS_PATH = os.environ.get("AMBROSIA_TAG_SEEDS_DB")

class TagSynonymResolver:
    """
    Connects to Ambrosia's ao3_tag_seeds.db to provide:
    1. Inward canonicalization: Maps non-canonical author tags to official AO3 canonical tags.
    2. Colloquial ship names: Expands formal relationships into searchable portmanteau names (e.g. 'Stucky', 'Destiel').
    3. Metatag inheritance: Connects sub-fandoms to parent umbrella fandoms (e.g. 'Marvel Cinematic Universe').
    """
    def __init__(self, db_path: Optional[Path] = None):
        self.db_path = db_path
        self._conn = None
        self._canonical_cache: Dict[str, str] = {}
        self._ship_synonyms_cache: Dict[str, List[str]] = {}
        self._parent_fandoms_cache: Dict[str, List[str]] = {}

        if self.db_path and self.db_path.exists():
            try:
                self._conn = sqlite3.connect(f"file:{self.db_path.resolve()}?mode=ro", uri=True)
            except Exception:
                try:
                    self._conn = sqlite3.connect(str(self.db_path))
                except Exception:
                    self._conn = None

    @property
    def is_available(self) -> bool:
        return self._conn is not None

    def canonicalize_tag(self, term: str) -> str:
        """Resolves a raw tag to its official canonical AO3 tag name."""
        if not self._conn or not term:
            return term
        term_clean = term.strip()
        lower_term = term_clean.lower()
        if lower_term in self._canonical_cache:
            return self._canonical_cache[lower_term]

        cur = self._conn.cursor()
        # 1. Check if it's already a canonical tag
        cur.execute("SELECT name FROM canonical_tags WHERE LOWER(name) = ? LIMIT 1", (lower_term,))
        row = cur.fetchone()
        if row:
            self._canonical_cache[lower_term] = row[0]
            return row[0]

        # 2. Check if it's a synonym
        cur.execute("""
            SELECT c.name
            FROM tag_synonyms s
            JOIN canonical_tags c ON c.id = s.canonical_id
            WHERE LOWER(s.synonym) = ?
            LIMIT 1
        """, (lower_term,))
        row = cur.fetchone()
        if row:
            self._canonical_cache[lower_term] = row[0]
            return row[0]

        self._canonical_cache[lower_term] = term_clean
        return term_clean

    def colloquial_ship_names(self, relationship_tag: str) -> List[str]:
        """
        Finds popular colloquial ship names for a relationship.
        For example: 'Hermione Granger/Draco Malfoy' -> ['Dramione']
        'James "Bucky" Barnes/Steve Rogers' -> ['Stucky']
        """
        if not self._conn or not relationship_tag:
            return []
        lower_rel = relationship_tag.strip().lower()
        if lower_rel in self._ship_synonyms_cache:
            return self._ship_synonyms_cache[lower_rel]

        cur = self._conn.cursor()
        cur.execute("""
            SELECT s.synonym
            FROM tag_synonyms s
            JOIN canonical_tags c ON c.id = s.canonical_id
            WHERE LOWER(c.name) = ? AND c.tag_type = 'relationship'
        """, (lower_rel,))
        rows = cur.fetchall()

        ships = []
        for r in rows:
            syn = r[0].strip()
            syn_clean = re.sub(r'^[#@\s]+', '', syn)
            # Filter for short, punchy portmanteau ship names
            if syn_clean and len(syn_clean) <= 25 and '/' not in syn_clean and '&' not in syn_clean and not syn_clean.startswith('('):
                if syn_clean.islower():
                    syn_clean = syn_clean.capitalize()
                if syn_clean not in ships:
                    ships.append(syn_clean)

        self._ship_synonyms_cache[lower_rel] = ships[:3]
        return self._ship_synonyms_cache[lower_rel]

    def parent_fandoms(self, fandom_tag: str) -> List[str]:
        """
        Finds parent umbrella fandoms from tag_parent_links.
        For example: 'The Avengers (Marvel Movies)' -> 'Marvel Cinematic Universe'
        """
        if not self._conn or not fandom_tag:
            return []
        lower_fan = fandom_tag.strip().lower()
        if lower_fan in self._parent_fandoms_cache:
            return self._parent_fandoms_cache[lower_fan]

        cur = self._conn.cursor()
        cur.execute("""
            SELECT c2.name
            FROM tag_parent_links pl
            JOIN canonical_tags c1 ON pl.child_id = c1.id
            JOIN canonical_tags c2 ON pl.parent_id = c2.id
            WHERE LOWER(c1.name) = ? AND c1.tag_type = 'fandom'
              AND c2.name NOT IN ('No Fandom', 'Movies', 'Cartoons & Comics & Graphic Novels', 'Books & Literature')
        """, (lower_fan,))
        rows = cur.fetchall()
        parents = [r[0] for r in rows if r[0]]
        self._parent_fandoms_cache[lower_fan] = parents
        return parents


# ---------------------------------------------------------------------------
# EPUB 3.3 Assembler Engine
# ---------------------------------------------------------------------------

def create_epub(
    output_path: Path,
    metadata: Dict[str, Any],
    content_html: Optional[str],
    annotations: Optional[List[Dict[str, Any]]] = None,
    resolver: Optional[TagSynonymResolver] = None
) -> None:
    """
    Assembles a complete, Standard Ebooks-compliant EPUB 3.3 archive at output_path,
    preserving full AO3 stats, workskins, reading status, and personal reader annotations.
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
    date_pub = metadata.get("date_published") or metadata.get("date_modified") or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    date_mod = metadata.get("date_modified")
    word_count = metadata.get("word_count")
    ch_current = metadata.get("chapter_current")
    ch_total = metadata.get("chapter_total")
    comment_count = metadata.get("comment_count")
    kudos_count = metadata.get("kudos_count")
    bookmark_count = metadata.get("bookmark_count")
    hit_count = metadata.get("hit_count")
    is_restricted = metadata.get("is_restricted", False)
    collections = metadata.get("collections") or []
    language = normalize_bcp47_language(metadata.get("language"))

    # Nectar reading state
    is_starred = metadata.get("is_starred", False)
    is_loved = metadata.get("is_loved", False)

    # Canonical Identifier
    if work_url and "archiveofourown.org/works/" in work_url:
        canonical_id = work_url.split("?")[0]
    else:
        canonical_id = f"urn:uuid:{uuid.uuid4()}"

    mod_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Parse chapters and workskin
    chapters, workskin_css, afterword = extract_workskin_and_chapters(content_html or "", work_title)
    if not chapters:
        raise ValueError(f"No story content or chapters found for '{work_title}'")

    has_workskin = bool(workskin_css.strip())
    has_annotations = bool(annotations and len(annotations) > 0)

    # Split files manifest: list of (rel_path, title, xhtml_content, properties)
    split_files: List[Tuple[str, str, str, Optional[str]]] = []

    # -----------------------------------------------------------------------
    # 1. Preface (Metadata block, Summary, Notes)
    # -----------------------------------------------------------------------
    tags_dl_items = []
    
    # Categorized metadata tags
    if metadata.get("ratings"):
        tags_dl_items.append(f"<dt>Rating:</dt><dd>{escape_xml(', '.join(metadata['ratings']))}</dd>")
    if metadata.get("warnings"):
        tags_dl_items.append(f"<dt>Archive Warning:</dt><dd>{escape_xml(', '.join(metadata['warnings']))}</dd>")
    if metadata.get("categories"):
        tags_dl_items.append(f"<dt>Category:</dt><dd>{escape_xml(', '.join(metadata['categories']))}</dd>")
    if metadata.get("fandoms"):
        tags_dl_items.append(f"<dt>Fandom:</dt><dd>{escape_xml(', '.join(metadata['fandoms']))}</dd>")
    if metadata.get("relationships"):
        tags_dl_items.append(f"<dt>Relationship:</dt><dd>{escape_xml(', '.join(metadata['relationships']))}</dd>")
    if metadata.get("characters"):
        tags_dl_items.append(f"<dt>Characters:</dt><dd>{escape_xml(', '.join(metadata['characters']))}</dd>")
    if metadata.get("additional_tags"):
        tags_dl_items.append(f"<dt>Additional Tags:</dt><dd>{escape_xml(', '.join(metadata['additional_tags']))}</dd>")
    if series_name:
        s_idx = f" #{series_index}" if series_index is not None else ""
        tags_dl_items.append(f"<dt>Series:</dt><dd>Part {s_idx} of {escape_xml(series_name)}</dd>")
    if collections:
        c_names = [c.get("name") if isinstance(c, dict) else str(c) for c in collections]
        tags_dl_items.append(f"<dt>Collections:</dt><dd>{escape_xml(', '.join(c_names))}</dd>")

    # Extended Stats Line
    stats_spans = []
    if date_pub:
        stats_spans.append(f"Published: {date_pub}")
    if date_mod and date_mod != date_pub:
        label = "Completed" if metadata.get("is_complete") else "Updated"
        stats_spans.append(f"{label}: {date_mod}")
    if word_count:
        stats_spans.append(f"Words: {word_count:,}")
    if ch_current is not None or ch_total is not None:
        curr = ch_current if ch_current is not None else len(chapters)
        tot = ch_total if ch_total is not None else len(chapters)
        stats_spans.append(f"Chapters: {curr}/{tot}")
    if kudos_count is not None:
        stats_spans.append(f"Kudos: {kudos_count:,}")
    if bookmark_count is not None:
        stats_spans.append(f"Bookmarks: {bookmark_count:,}")
    if hit_count is not None:
        stats_spans.append(f"Hits: {hit_count:,}")
    if is_restricted:
        stats_spans.append("🔒 Restricted")

    stats_block_html = f'<div class="stats-block">{" &nbsp;•&nbsp; ".join(stats_spans)}</div>' if stats_spans else ""
    tags_dl_html = f'<dl class="tags-dl">\n{"".join(tags_dl_items)}\n</dl>' if tags_dl_items else ""

    summary_html = ""
    if summary_raw.strip():
        clean_summary = apply_standard_ebooks_typography(ensure_xhtml(summary_raw))
        summary_html = f"""
      <div class="meta-section" epub:type="abstract">
        <h3>Summary</h3>
        <blockquote>{clean_summary}</blockquote>
      </div>"""

    workskin_link = '<link rel="stylesheet" type="text/css" href="../css/workskin.css"/>' if has_workskin else ""

    preface_xhtml = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(work_title)} - Preface</title>
    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
    {workskin_link}
  </head>
  <body epub:type="frontmatter">
    <section id="preface" epub:type="preface">
      <header class="title-header">
        <h1 class="fulltitle" epub:type="fulltitle">{escape_xml(work_title)}</h1>
        <p class="byline">by {escape_xml(author_str)}</p>
      </header>
      {stats_block_html}
      {tags_dl_html}
      {summary_html}
    </section>
  </body>
</html>"""

    split_files.append(("text/preface.xhtml", "Preface", preface_xhtml, None))

    # -----------------------------------------------------------------------
    # 2. Chapters (Multi-part XHTML5 with Workskin wrapper preserved)
    # -----------------------------------------------------------------------
    for idx, ch in enumerate(chapters, start=1):
        ch_filename = f"text/chapter-{idx}.xhtml"
        formatted_body = apply_standard_ebooks_typography(ensure_xhtml(ch.html_body))

        # CRITICAL: Retain <div id="workskin" class="userstuff"> so author CSS matches!
        ch_xhtml = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="{language}" xml:lang="{language}">
  <head>
    <title>{escape_xml(ch.title)} - {escape_xml(work_title)}</title>
    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
    {workskin_link}
  </head>
  <body epub:type="bodymatter">
    <section id="{ch.chapter_id}" epub:type="chapter" role="doc-chapter">
      <header class="chapter-header">
        <h2 class="chapter-title">{escape_xml(ch.title)}</h2>
      </header>
      <div id="workskin" class="userstuff">
        {formatted_body}
      </div>
    </section>
  </body>
</html>"""
        split_files.append((ch_filename, ch.title, ch_xhtml, None))

    # -----------------------------------------------------------------------
    # 3. Afterword / Endnotes
    # -----------------------------------------------------------------------
    if afterword and has_story_content(afterword):
        formatted_afterword = apply_standard_ebooks_typography(ensure_xhtml(afterword))
        afterword_xhtml = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="{language}" xml:lang="{language}">
  <head>
    <title>Afterword - {escape_xml(work_title)}</title>
    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
    {workskin_link}
  </head>
  <body epub:type="backmatter">
    <section id="afterword" epub:type="afterword" role="doc-afterword" class="endnotes-section">
      <header class="chapter-header">
        <h2 class="chapter-title">Afterword</h2>
      </header>
      <div id="workskin" class="userstuff">
        {formatted_afterword}
      </div>
    </section>
  </body>
</html>"""
        split_files.append(("text/afterword.xhtml", "Afterword", afterword_xhtml, None))

    # -----------------------------------------------------------------------
    # 4. Reader Highlights & Notes Chapter
    # -----------------------------------------------------------------------
    if has_annotations:
        anno_cards = []
        for anno in annotations or []:
            quote = escape_xml(anno.get("quoteExact") or "")
            note = escape_xml(anno.get("note") or "")
            color_hex = anno.get("color") or "#f59e0b"
            created_at = anno.get("createdAt") or ""
            ch_loc = escape_xml(anno.get("chapterTitle") or "Chapter")

            quote_block = f'<blockquote class="annotation-quote">“{apply_standard_ebooks_typography(quote)}”</blockquote>' if quote else ""
            note_block = f'<p class="annotation-note"><strong>Note:</strong> {apply_standard_ebooks_typography(note)}</p>' if note else ""
            date_block = f'<span class="annotation-date">Saved on {created_at}</span>' if created_at else ""

            card = f"""
      <div class="annotation-card" style="border-left-color: {color_hex};">
        <div class="annotation-location">{ch_loc}</div>
        {quote_block}
        {note_block}
        {date_block}
      </div>"""
            anno_cards.append(card)

        annotations_xhtml = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="{language}" xml:lang="{language}">
  <head>
    <title>Reader Highlights &amp; Notes - {escape_xml(work_title)}</title>
    <link rel="stylesheet" type="text/css" href="../css/core.css"/>
    <link rel="stylesheet" type="text/css" href="../css/se.css"/>
    <link rel="stylesheet" type="text/css" href="../css/annotations.css"/>
    <link rel="stylesheet" type="text/css" href="../css/page_styles.css"/>
  </head>
  <body epub:type="backmatter">
    <section id="reader-notes" epub:type="annotation" role="doc-endnotes">
      <header class="annotations-header">
        <h2 class="chapter-title">Reader Highlights &amp; Notes</h2>
        <p class="annotation-summary">Preserved personal reader annotations from Nectar.</p>
      </header>
      {"".join(anno_cards)}
    </section>
  </body>
</html>"""
        split_files.append(("text/reader-notes.xhtml", "Reader Highlights & Notes", annotations_xhtml, None))

    # -----------------------------------------------------------------------
    # 5. EPUB 3 Navigation Document (`toc.xhtml`)
    # -----------------------------------------------------------------------
    nav_ol_items = []
    for fn, t, _, _ in split_files:
        nav_ol_items.append(f'        <li><a href="{fn}">{escape_xml(t)}</a></li>')

    toc_xhtml = f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="{language}" xml:lang="{language}">
  <head>
    <title>Table of Contents</title>
    <link rel="stylesheet" type="text/css" href="css/core.css"/>
    <link rel="stylesheet" type="text/css" href="css/se.css"/>
  </head>
  <body epub:type="frontmatter">
    <nav id="toc" epub:type="toc" role="doc-toc">
      <h2>Table of Contents</h2>
      <ol>
{"".join(nav_ol_items)}
      </ol>
    </nav>
    <nav id="landmarks" epub:type="landmarks">
      <h2>Landmarks</h2>
      <ol>
        <li><a href="text/preface.xhtml" epub:type="preface">Preface</a></li>
        <li><a href="text/chapter-1.xhtml" epub:type="bodymatter">Start of Content</a></li>
      </ol>
    </nav>
  </body>
</html>"""

    # -----------------------------------------------------------------------
    # 6. EPUB 2 NCX Navigation (`toc.ncx`) for older device backwards-compat
    # -----------------------------------------------------------------------
    ncx_navpoints = []
    for order, (fn, t, _, _) in enumerate(split_files, start=1):
        ncx_navpoints.append(f"""    <navPoint id="np_{order}" playOrder="{order}">
      <navLabel><text>{escape_xml(t)}</text></navLabel>
      <content src="{fn}"/>
    </navPoint>""")

    toc_ncx = f"""<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="{language}">
  <head>
    <meta name="dtb:uid" content="{canonical_id}"/>
    <meta name="dtb:depth" content="2"/>
    <meta name="dtb:generator" content="nectar_backup_to_epub"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>{escape_xml(work_title)}</text>
  </docTitle>
  <navMap>
{"".join(ncx_navpoints)}
  </navMap>
</ncx>"""

    # -----------------------------------------------------------------------
    # 7. Package Manifest & Spine (`content.opf` - EPUB 3.3 Strict)
    # -----------------------------------------------------------------------
    manifest_items = [
        '    <item id="toc" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '    <item id="css-core" href="css/core.css" media-type="text/css"/>',
        '    <item id="css-se" href="css/se.css" media-type="text/css"/>',
        '    <item id="css-page" href="css/page_styles.css" media-type="text/css"/>',
    ]
    if has_workskin:
        manifest_items.append('    <item id="css-workskin" href="css/workskin.css" media-type="text/css"/>')
    if has_annotations:
        manifest_items.append('    <item id="css-annotations" href="css/annotations.css" media-type="text/css"/>')

    spine_items = []
    for fn, _, _, props in split_files:
        item_id = fn.replace("text/", "").replace(".xhtml", "")
        prop_attr = f' properties="{props}"' if props else ""
        manifest_items.append(f'    <item id="{item_id}" href="{fn}" media-type="application/xhtml+xml"{prop_attr}/>')
        spine_items.append(f'    <itemref idref="{item_id}"/>')

    manifest_xml = "\n".join(manifest_items)
    spine_xml = "\n".join(spine_items)

    # Dublin Core Subjects & Typed Categories (Enriched with Ambrosia Canonical Seeds)
    raw_subject_tags: List[str] = ['Fanworks']

    # Fandoms + Parent Umbrella Metatags
    for f_item in fandoms_list:
        if f_item:
            raw_subject_tags.append(f"Fandom -- {f_item}")
            if resolver and resolver.is_available:
                canon_fan = resolver.canonicalize_tag(f_item)
                if canon_fan != f_item:
                    raw_subject_tags.append(f"Fandom -- {canon_fan}")
                for parent_fan in resolver.parent_fandoms(canon_fan):
                    raw_subject_tags.append(f"Fandom -- {parent_fan}")

    for r_item in metadata.get("ratings") or []:
        raw_subject_tags.append(f"Rating -- {r_item}")
    for w_item in metadata.get("warnings") or []:
        raw_subject_tags.append(f"Warning -- {w_item}")
    for c_item in metadata.get("categories") or []:
        raw_subject_tags.append(f"Category -- {c_item}")

    # Relationships + Popular Colloquial Portmanteau Ships (e.g. Stucky, Dramione)
    for rel in metadata.get("relationships") or []:
        raw_subject_tags.append(f"Relationship -- {rel}")
        if resolver and resolver.is_available:
            canon_rel = resolver.canonicalize_tag(rel)
            if canon_rel != rel:
                raw_subject_tags.append(f"Relationship -- {canon_rel}")
            for ship_name in resolver.colloquial_ship_names(canon_rel):
                raw_subject_tags.append(f"Relationship -- {ship_name}")

    for char in metadata.get("characters") or []:
        raw_subject_tags.append(f"Character -- {char}")
        if resolver and resolver.is_available:
            canon_char = resolver.canonicalize_tag(char)
            if canon_char != char:
                raw_subject_tags.append(f"Character -- {canon_char}")

    # Additional Tags + Inward Canonicalization
    for tag_item in metadata.get("additional_tags") or []:
        raw_subject_tags.append(tag_item)
        if resolver and resolver.is_available:
            canon_tag = resolver.canonicalize_tag(tag_item)
            if canon_tag != tag_item:
                raw_subject_tags.append(f"Freeform -- {canon_tag}")

    for coll in collections:
        c_title = coll.get("name") if isinstance(coll, dict) else str(coll)
        if c_title:
            raw_subject_tags.append(f"Collection -- {c_title}")

    # Deduplicate while preserving order
    seen_tags: Set[str] = set()
    subject_tags = []
    for tag in raw_subject_tags:
        if tag and tag not in seen_tags:
            seen_tags.add(tag)
            subject_tags.append(f'    <dc:subject>{escape_xml(tag)}</dc:subject>')

    subject_xml = "\n".join(subject_tags)

    # Series & Calibre metadata
    series_meta = ""
    if series_name:
        series_meta = f"""    <meta name="calibre:series" content="{escape_xml(series_name)}"/>\n"""
        if series_index is not None:
            series_meta += f"""    <meta name="calibre:series_index" content="{series_index}"/>\n"""

    if is_loved or is_starred:
        series_meta += '    <meta name="calibre:rating" content="10"/>\n'

    # Extended Stats metadata
    stats_meta = []
    if kudos_count is not None:
        stats_meta.append(f'    <meta property="nectar:kudos">{kudos_count}</meta>')
    if bookmark_count is not None:
        stats_meta.append(f'    <meta property="nectar:bookmarks">{bookmark_count}</meta>')
    if comment_count is not None:
        stats_meta.append(f'    <meta property="nectar:comments">{comment_count}</meta>')
    if hit_count is not None:
        stats_meta.append(f'    <meta property="nectar:hits">{hit_count}</meta>')
    stats_xml = "\n".join(stats_meta)

    # Authors with MARC relator roles
    author_meta = []
    for i, a_name in enumerate(authors_list):
        a_id = f"author_{i+1}"
        author_meta.append(f'    <dc:creator id="{a_id}">{escape_xml(a_name)}</dc:creator>')
        author_meta.append(f'    <meta refines="#{a_id}" property="role" scheme="marc:relators">aut</meta>')
        author_meta.append(f'    <meta refines="#{a_id}" property="file-as">{escape_xml(a_name)}</meta>')
    author_xml = "\n".join(author_meta)

    clean_summary_text = escape_xml(re.sub(r'<[^>]+>', ' ', summary_raw).strip())

    content_opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" xml:lang="{language}" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">{canonical_id}</dc:identifier>
    <dc:title id="title">{escape_xml(work_title)}</dc:title>
{author_xml}
    <dc:publisher id="publisher">Archive of Our Own</dc:publisher>
    <link refines="#publisher" rel="record" href="https://archiveofourown.org/"/>
    <dc:language>{language}</dc:language>
    <dc:date>{date_pub}</dc:date>
    <meta property="dcterms:modified">{mod_timestamp}</meta>
    <dc:description>{clean_summary_text}</dc:description>
{subject_xml}
{series_meta}{stats_xml}
  </metadata>
  <manifest>
{manifest_xml}
  </manifest>
  <spine toc="ncx">
{spine_xml}
  </spine>
</package>
"""

    # -----------------------------------------------------------------------
    # 8. Write ZIP Container (Uncompressed mimetype at byte 0)
    # -----------------------------------------------------------------------
    with zipfile.ZipFile(output_path, "w") as zf:
        # Byte 0 uncompressed mimetype
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)

        # Standard container
        zf.writestr("META-INF/container.xml", CONTAINER_XML.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("EPUB/content.opf", content_opf.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("EPUB/toc.xhtml", toc_xhtml.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("EPUB/toc.ncx", toc_ncx.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

        # Stylesheets
        zf.writestr("EPUB/css/core.css", CORE_CSS.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("EPUB/css/se.css", SE_CSS.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("EPUB/css/page_styles.css", PAGE_STYLES_CSS.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

        if has_workskin:
            zf.writestr("EPUB/css/workskin.css", workskin_css.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)
        if has_annotations:
            zf.writestr("EPUB/css/annotations.css", ANNOTATIONS_CSS.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)

        # Text files
        for fn, _, xhtml_data, _ in split_files:
            zf.writestr(f"EPUB/{fn}", xhtml_data.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)


# ---------------------------------------------------------------------------
# Calibre Library Ingestion (`calibredb add`)
# ---------------------------------------------------------------------------

def import_into_calibre(epub_path: Path, library_path: Optional[str] = None) -> bool:
    """Adds an EPUB into Calibre's library if calibredb is available."""
    calibre_bin = shutil.which("calibredb")
    if not calibre_bin:
        mac_calibre = Path("/Applications/calibre.app/Contents/MacOS/calibredb")
        if mac_calibre.exists():
            calibre_bin = str(mac_calibre)

    if not calibre_bin:
        return False

    cmd = [calibre_bin, "add"]
    if library_path:
        cmd.extend(["--with-library", library_path])
    cmd.append(str(epub_path))

    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )
        return res.returncode == 0
    except Exception:
        return False


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
            "User-Agent": "NectarEPUBExport/2.0 (AppleWebKit; compatible)"
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
    include_annotations: bool = True,
    calibre_add: bool = False,
    calibre_library: Optional[str] = None,
    tag_seeds_db: Optional[Path] = None
) -> None:
    # Initialize TagSynonymResolver only when explicitly supplied or set in environment
    resolver = None
    target_seeds_db = tag_seeds_db or (Path(ENV_TAG_SEEDS_PATH) if ENV_TAG_SEEDS_PATH else None)
    if target_seeds_db and target_seeds_db.exists():
        resolver = TagSynonymResolver(target_seeds_db)
        if resolver.is_available:
            print(f"[*] Enabled tag synonym & canonicalization database: {target_seeds_db.name}")

    db_paths = find_sqlite_databases(input_path)
    if not db_paths:
        print(f"[!] No SQLite databases found in {input_path}")
        return

    print(f"[*] Found {len(db_paths)} database(s) to process.")

    total_articles = 0
    generated_count = 0
    downloaded_count = 0
    calibre_added_count = 0
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
                    create_epub(epub_path, metadata, decompressed_html, annotations=annotations_for_work, resolver=resolver)
                    generated_count += 1
                    note_info = f" (+{len(annotations_for_work)} notes)" if annotations_for_work else ""
                    print(f"  [+] Generated EPUB 3: {primary_fandom} / {primary_author} / {epub_filename}{note_info}")

                    if calibre_add:
                        if import_into_calibre(epub_path, library_path=calibre_library):
                            calibre_added_count += 1
                            print(f"      [Calibre] Added to library.")

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
                            if calibre_add and import_into_calibre(epub_path, library_path=calibre_library):
                                calibre_added_count += 1
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
    print("Nectar EPUB 3 Export Summary:")
    print(f"  Total Articles Examined: {total_articles}")
    print(f"  EPUBs Generated Locally: {generated_count}")
    print(f"  EPUBs Downloaded (AO3):  {downloaded_count}")
    if calibre_add:
        print(f"  Imported to Calibre:     {calibre_added_count}")
    print(f"  Skipped (No Content):    {skipped_count}")
    print(f"  Errors:                  {error_count}")
    print(f"  Output Directory:        {output_dir.resolve()}")
    print("=" * 60)


# ---------------------------------------------------------------------------
# CLI Entrypoint
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Convert a Nectar backup into Standard Ebooks-compliant EPUB 3.3 books with author workskin fidelity and full metadata preservation."
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
    parser.add_argument(
        "--calibre-add",
        action="store_true",
        help="Automatically import generated EPUBs into Calibre via calibredb"
    )
    parser.add_argument(
        "--calibre-library",
        type=str,
        default=None,
        help="Path or URL to a specific Calibre library (passed to calibredb --with-library). Implies --calibre-add"
    )
    parser.add_argument(
        "--tag-seeds-db",
        type=Path,
        default=None,
        help="Optional path to ao3_tag_seeds.db for tag canonicalization, ship portmanteau expansion, and fandom metatags (or set AMBROSIA_TAG_SEEDS_DB env var)"
    )

    args = parser.parse_args()

    if not args.input.exists():
        print(f"[!] Input path does not exist: {args.input}", file=sys.stderr)
        sys.exit(1)

    calibre_add_enabled = args.calibre_add or (args.calibre_library is not None)

    process_backup(
        input_path=args.input,
        output_dir=args.output,
        fetch_missing=args.fetch_missing,
        ao3_cookie=args.ao3_cookie,
        rate_limit_delay=args.rate_limit_delay,
        include_annotations=not args.no_annotations,
        calibre_add=calibre_add_enabled,
        calibre_library=args.calibre_library,
        tag_seeds_db=args.tag_seeds_db
    )


if __name__ == "__main__":
    main()
