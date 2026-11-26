# EPUB 3.3 Export (`EPUB3Generator`)

Nectar exports individual works as EPUB 3.3 archives directly to the iOS Share Sheet (`UIActivityViewController`) via [ShareEPUBActivity.swift](file:///Users/ethanchan/Documents/Applications/nectar/iOS/Article/ShareEPUBActivity.swift) and [EPUB3Generator.swift](file:///Users/ethanchan/Documents/Applications/nectar/iOS/Article/EPUB3Generator.swift).

For full-backup-to-EPUB conversion (`scripts/nectar_backup_to_epub.py`), see `backup-restore.md`.

## Entry Points

* `WebViewController.showActivityDialog()` (reader Share button)
* `MainTimelineModernViewController.shareEPUBAction()` (timeline context menu)

## Generation Pipeline (`EPUB3Generator.generateEPUB(for:account:)`)

1. **Decompress story HTML:** Calls `ContentHTMLCompression.decompress(_:)` on `article.contentHTML` and validates body text via `hasStoryContent(_:)` (`String.strippingHTML()`).
2. **Fetch annotations:** Queries `account.fetchAnnotations(forArticleID:)` to include a `text/reader-notes.xhtml` backmatter chapter when annotations exist.
3. **DOM extraction (`SwiftSoup`):** `extractWorkskinAndChapters(from:workTitle:)` parses the HTML once with `SwiftSoup.parse(_:)`:
   * Extracts `#ao3Preface, #ao3SyntheticPreface` for `<dl class="tags">` preservation.
   * Collects and removes `<style>` blocks into `css/workskin.css` (with dark-mode contrast guards).
   * Extracts `#afterword` for `text/afterword.xhtml`.
   * Splits `div.chapter[id^=chapter-]` elements, reading `h3.title` for chapter titles and stripping it from chapter bodies. Falls back to `#chapters` or `body` for single-chapter works.
4. **XHTML serialization (`SwiftSoup`):** `ensureXHTML(_:)` serializes HTML fragments using `.syntax(.xml)` and `.escapeMode(.xhtml)` so void tags and entities conform to XHTML/EPUB 3.3. XML text escaping delegates to `RSCore`'s `String.escapingSpecialXMLCharacters`.
5. **Canonical AO3 URLs:** Tag, series, collection, and author links use `AO3Link.canonicalHost` rather than hardcoded host strings.
6. **Container packaging (`ZIPFoundation`):** `packageEPUB(from:to:)` creates the archive with `Archive(url:accessMode: .create)` and writes `mimetype` **first** with `compressionMethod: .none` (required by EPUB 3.3 §3.3), followed by sorted `META-INF/` and `EPUB/` entries with `.deflate`.
