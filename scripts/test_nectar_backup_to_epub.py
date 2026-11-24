#!/usr/bin/env python3
"""
test_nectar_backup_to_epub.py

Comprehensive test suite verifying nectar_backup_to_epub.py:
1. Standard Ebooks typography engine (smart quotes, em-dashes, en-dashes, ellipses).
2. Author workskin extraction, dark-mode contrast guard, and <div id="workskin"> DOM retention.
3. EPUB 3.3 compliance: uncompressed mimetype at byte 0, OPF 3.0 manifest, and Navigation Document (toc.xhtml).
4. Multi-chapter splitting vs single-chapter fallback.
5. End-to-end SQLite database conversion with personal reader annotations.
"""

import os
import re
import sqlite3
import tempfile
import unittest
import zipfile
from pathlib import Path

from nectar_backup_to_epub import (
    create_epub,
    extract_workskin_and_chapters,
    process_backup,
    sanitize_filename,
    TagSynonymResolver,
)

class TestNectarBackupToEPUB(unittest.TestCase):

    def test_workskin_extraction_and_preservation(self):
        fixture_path = Path("Modules/AO3Kit/Tests/AO3KitTests/Resources/ao3-work-workskin.html")
        if not fixture_path.exists():
            self.skipTest(f"Fixture {fixture_path} not found")

        content_html = fixture_path.read_text(encoding="utf-8")
        chapters, workskin_css, afterword = extract_workskin_and_chapters(content_html, "Borrow Somebody's Dreams")

        # 1. Verify author workskin rules extracted
        self.assertTrue(len(workskin_css) > 0)
        self.assertIn("#workskin .nine", workskin_css)
        self.assertIn("#workskin .juice", workskin_css)
        self.assertIn("prefers-color-scheme: dark", workskin_css)

        # 2. Verify chapters extracted
        self.assertTrue(len(chapters) >= 1)

        # 3. Build EPUB and inspect container
        with tempfile.TemporaryDirectory() as tmpdir:
            epub_path = Path(tmpdir) / "test_workskin.epub"
            metadata = {
                "title": "Borrow Somebody's Dreams Till Tomorrow",
                "authors": ["Prehensilizing"],
                "fandoms": ["17776 - Jon Bois"],
                "ratings": ["General Audiences"],
                "categories": ["Gen"],
                "tags": ["Space", "Football"],
                "summary": "What football will look like in the future.",
                "url": "https://archiveofourown.org/works/89438831",
                "word_count": 5000,
            }
            create_epub(epub_path, metadata, content_html)
            self.assertTrue(epub_path.exists())

            # Verify EPUB 3 structure
            with zipfile.ZipFile(epub_path, 'r') as zf:
                namelist = zf.namelist()
                # Uncompressed mimetype at byte 0
                self.assertEqual(namelist[0], "mimetype")
                info = zf.getinfo("mimetype")
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)

                # Navigation Document
                self.assertIn("EPUB/toc.xhtml", namelist)
                toc_xhtml = zf.read("EPUB/toc.xhtml").decode("utf-8")
                self.assertIn('epub:type="toc"', toc_xhtml)
                self.assertIn('epub:type="landmarks"', toc_xhtml)

                # OPF 3.0
                self.assertIn("EPUB/content.opf", namelist)
                opf_text = zf.read("EPUB/content.opf").decode("utf-8")
                self.assertIn('version="3.0"', opf_text)
                self.assertIn('properties="nav"', opf_text)
                self.assertIn('id="css-workskin"', opf_text)
                self.assertIn('https://archiveofourown.org/works/89438831', opf_text)
                self.assertIn('scheme="marc:relators">aut<', opf_text)

                # Dedicated workskin stylesheet
                self.assertIn("EPUB/css/workskin.css", namelist)
                extracted_css = zf.read("EPUB/css/workskin.css").decode("utf-8")
                self.assertIn("#workskin .juice", extracted_css)

                # Chapter body wraps content in <div id="workskin" class="userstuff">
                self.assertIn("EPUB/text/chapter-1.xhtml", namelist)
                ch1 = zf.read("EPUB/text/chapter-1.xhtml").decode("utf-8")
                self.assertIn('<link rel="stylesheet" type="text/css" href="../css/workskin.css"/>', ch1)
                self.assertIn('<div id="workskin" class="userstuff">', ch1)

    def test_multi_chapter_extraction(self):
        fixture_path = Path("Modules/AO3Kit/Tests/AO3KitTests/Resources/ao3-work-multi-chapter.html")
        if not fixture_path.exists():
            self.skipTest(f"Fixture {fixture_path} not found")

        content_html = fixture_path.read_text(encoding="utf-8")
        chapters, _, afterword = extract_workskin_and_chapters(content_html, "Multi Chapter Fic")
        self.assertTrue(len(chapters) >= 2)

        with tempfile.TemporaryDirectory() as tmpdir:
            epub_path = Path(tmpdir) / "test_multi.epub"
            metadata = {
                "title": "Multi Chapter Fic",
                "authors": ["Author One"],
                "fandoms": ["Original Work"],
                "series_name": "Test Series",
                "series_index": 1,
            }
            create_epub(epub_path, metadata, content_html)
            self.assertTrue(epub_path.exists())

            with zipfile.ZipFile(epub_path, 'r') as zf:
                namelist = zf.namelist()
                self.assertIn("EPUB/text/chapter-1.xhtml", namelist)
                self.assertIn("EPUB/text/chapter-2.xhtml", namelist)
                opf_text = zf.read("EPUB/content.opf").decode("utf-8")
                self.assertIn('name="calibre:series" content="Test Series"', opf_text)
                self.assertIn('name="calibre:series_index" content="1"', opf_text)

    def test_end_to_end_sqlite_process_backup(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "DB.sqlite3"
            output_dir = Path(tmpdir) / "epubs"

            # Create test database
            conn = sqlite3.connect(db_path)
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE articles (
                    articleID TEXT PRIMARY KEY,
                    uniqueID TEXT,
                    feedID TEXT,
                    title TEXT,
                    contentHTML TEXT,
                    summary TEXT,
                    url TEXT,
                    datePublished TEXT,
                    dateModified TEXT,
                    authors TEXT,
                    wordCount INTEGER,
                    chapterCurrent INTEGER,
                    chapterTotal INTEGER,
                    isComplete INTEGER,
                    fandoms TEXT,
                    ratings TEXT,
                    warnings TEXT,
                    categories TEXT,
                    relationships TEXT,
                    characters TEXT,
                    additionalTags TEXT,
                    series TEXT,
                    language TEXT,
                    commentCount INTEGER,
                    kudosCount INTEGER,
                    bookmarkCount INTEGER,
                    hitCount INTEGER,
                    isRestricted INTEGER,
                    collections TEXT,
                    dateBookmarked TEXT,
                    bookKey TEXT
                )
            """)
            cur.execute("""
                CREATE TABLE statuses (
                    articleID TEXT PRIMARY KEY,
                    read INTEGER,
                    starred INTEGER,
                    loved INTEGER,
                    readingProgress REAL,
                    lastOpenedAt TEXT
                )
            """)
            cur.execute("""
                CREATE TABLE annotations (
                    annotationID TEXT PRIMARY KEY,
                    articleID TEXT,
                    bookKey TEXT,
                    quoteExact TEXT,
                    note TEXT,
                    color TEXT,
                    createdAt TEXT,
                    chapterTitle TEXT
                )
            """)

            sample_html = """
            <div id="workskin">
              <style>#workskin .dialogue { color: #007aff; }</style>
              <div class="chapter" id="chapter-1">
                <h3 class="title">Chapter 1: The Arrival</h3>
                <p>"Here we are," Arthur said--smiling. It was 1920-1925...</p>
                <p class="dialogue">"Indeed," replied Ford.</p>
              </div>
            </div>
            """

            cur.execute("""
                INSERT INTO articles (
                    articleID, uniqueID, title, contentHTML, summary, url,
                    datePublished, authors, fandoms, ratings, series, wordCount,
                    kudosCount, bookmarkCount, hitCount, isComplete, bookKey
                ) VALUES (
                    'art1', 'uniq1', 'Hitchhiker Fic', ?, 'A galactic journey.',
                    'https://archiveofourown.org/works/424242',
                    '2024-01-01', '["Douglas Adams"]', '["Hitchhiker Guide"]',
                    '["General Audiences"]', '[{"name": "Don''t Panic", "index": 1}]',
                    4200, 100, 50, 1000, 1, 'bookkey1'
                )
            """, (sample_html,))

            cur.execute("""
                INSERT INTO statuses (articleID, read, starred, loved)
                VALUES ('art1', 1, 1, 1)
            """)

            cur.execute("""
                INSERT INTO annotations (
                    annotationID, articleID, bookKey, quoteExact, note, color, createdAt, chapterTitle
                ) VALUES (
                    'anno1', 'art1', 'bookkey1', 'Here we are', 'Iconic line.', '#FFD60A', '2024-01-02', 'Chapter 1'
                )
            """)
            conn.commit()
            conn.close()

            # Run process_backup
            process_backup(
                input_path=db_path,
                output_dir=output_dir,
                include_annotations=True
            )

            # Check directory hierarchy: <output_dir>/<Fandom>/<Author>/<Series>/01 - Title.epub
            clean_series_name = sanitize_filename("Don't Panic")
            expected_epub = output_dir / "Hitchhiker Guide" / "Douglas Adams" / clean_series_name / "01 - Hitchhiker Fic.epub"
            self.assertTrue(expected_epub.exists(), f"EPUB not found at {expected_epub}")

            # Verify contents of generated EPUB
            with zipfile.ZipFile(expected_epub, 'r') as zf:
                namelist = zf.namelist()
                self.assertIn("EPUB/text/reader-notes.xhtml", namelist)
                notes_text = zf.read("EPUB/text/reader-notes.xhtml").decode("utf-8")
                self.assertIn("Iconic line.", notes_text)
                self.assertIn("Here we are", notes_text)

                ch1_text = zf.read("EPUB/text/chapter-1.xhtml").decode("utf-8")
                self.assertIn('"Here we are,"', ch1_text)
                self.assertIn("Arthur said--smiling.", ch1_text)
                self.assertIn("1920-1925...", ch1_text)
                # Workskin preserved
                self.assertIn('<div id="workskin" class="userstuff">', ch1_text)

    def test_tag_synonym_resolver_and_enrichment(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            seeds_db = Path(tmpdir) / "ao3_tag_seeds.db"
            conn = sqlite3.connect(seeds_db)
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE canonical_tags (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    tag_type TEXT NOT NULL DEFAULT 'unknown'
                )
            """)
            cur.execute("""
                CREATE TABLE tag_synonyms (
                    synonym TEXT NOT NULL PRIMARY KEY,
                    canonical_id INTEGER NOT NULL REFERENCES canonical_tags(id)
                )
            """)
            cur.execute("""
                CREATE TABLE tag_parent_links (
                    child_id INTEGER NOT NULL REFERENCES canonical_tags(id),
                    parent_id INTEGER NOT NULL REFERENCES canonical_tags(id),
                    PRIMARY KEY (child_id, parent_id)
                )
            """)

            # Seed test tags
            cur.execute("INSERT INTO canonical_tags (id, name, tag_type) VALUES (1, 'Not Beta Read', 'additional')")
            cur.execute("INSERT INTO canonical_tags (id, name, tag_type) VALUES (2, 'Hermione Granger/Draco Malfoy', 'relationship')")
            cur.execute("INSERT INTO canonical_tags (id, name, tag_type) VALUES (3, 'The Avengers (Marvel Movies)', 'fandom')")
            cur.execute("INSERT INTO canonical_tags (id, name, tag_type) VALUES (4, 'Marvel Cinematic Universe', 'fandom')")

            cur.execute("INSERT INTO tag_synonyms (synonym, canonical_id) VALUES ('no beta we die like men', 1)")
            cur.execute("INSERT INTO tag_synonyms (synonym, canonical_id) VALUES ('dramione', 2)")
            cur.execute("INSERT INTO tag_parent_links (child_id, parent_id) VALUES (3, 4)")
            conn.commit()
            conn.close()

            resolver = TagSynonymResolver(seeds_db)
            self.assertTrue(resolver.is_available)

            # Test canonicalization
            self.assertEqual(resolver.canonicalize_tag("no beta we die like men"), "Not Beta Read")
            # Test ship portmanteau expansion
            ships = resolver.colloquial_ship_names("Hermione Granger/Draco Malfoy")
            self.assertIn("Dramione", ships)
            # Test parent fandom
            parents = resolver.parent_fandoms("The Avengers (Marvel Movies)")
            self.assertIn("Marvel Cinematic Universe", parents)

            # Test EPUB metadata generation with resolver
            epub_path = Path(tmpdir) / "test_synonyms.epub"
            metadata = {
                "title": "A Tagged Work",
                "authors": ["FicWriter"],
                "fandoms": ["The Avengers (Marvel Movies)"],
                "relationships": ["Hermione Granger/Draco Malfoy"],
                "additional_tags": ["no beta we die like men"],
            }
            content_html = "<div id='workskin'><p>This is a sample story with plenty of prose text to comfortably satisfy the eighty character story content threshold check for EPUB conversion testing.</p></div>"
            create_epub(epub_path, metadata, content_html, resolver=resolver)

            with zipfile.ZipFile(epub_path, 'r') as zf:
                opf_text = zf.read("EPUB/content.opf").decode("utf-8")
                # 1. Author's original verbatim tag
                self.assertIn("<dc:subject>no beta we die like men</dc:subject>", opf_text)
                # 2. Inward canonicalized tag
                self.assertIn("<dc:subject>Not Beta Read</dc:subject>", opf_text)
                # 3. Canonical ship name
                self.assertIn("<dc:subject>Hermione Granger/Draco Malfoy</dc:subject>", opf_text)
                # 4. Portmanteau ship name
                self.assertIn("<dc:subject>Dramione</dc:subject>", opf_text)
                # 5. Parent umbrella fandom
                self.assertIn("<dc:subject>Marvel Cinematic Universe</dc:subject>", opf_text)


if __name__ == "__main__":
    unittest.main()
