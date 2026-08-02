//
//  AO3ChapterHTMLExtractor.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

/// One posted chapter found in a fetched AO3 work page, in document order.
/// Used only to drive the table-of-contents UI -- the chapter's actual
/// rendered content lives in `AO3ChapterExtractionResult.contentHTML`, not
/// here (see that type's doc comment).
public struct AO3ExtractedChapter: Sendable {
	public let id: String       // e.g. "chapter-1", from the source div's own id
	public let title: String    // flattened text of the chapter's h3.title, e.g. "Chapter 2: Livermore, California"
}

public struct AO3ChapterExtractionResult: Sendable {

	/// The `#workskin` wrapper (plus its preceding `<style>` block, when the
	/// work has a custom skin), re-serialized as a single unit. This is what
	/// actually gets rendered -- title, work-level summary, and every posted
	/// chapter concatenated, exactly as the live page groups them. Splitting
	/// this into per-chapter HTML and discarding the wrapper would break the
	/// workskin's styling, since every one of its rules is scoped under
	/// `#workskin` (see `AO3ChapterHTMLExtractor`'s header comment).
	public let contentHTML: String

	/// Per-chapter boundaries/titles, in document order, for the TOC only.
	public let chapters: [AO3ExtractedChapter]
}

/// Extracts storable article content from a fetched AO3 work page
/// (`GET .../works/<id>?view_full_work=true`).
///
/// AO3 wraps a work's title, its own summary, and every concatenated posted
/// chapter in a single `<div id="workskin">`, unconditionally -- present and
/// non-empty even for works with no custom skin. Immediately before it, still
/// outside `#workskin`, sits the work's own `<style>` block when (and only
/// when) the work has a custom skin; every one of that stylesheet's rules is
/// scoped `#workskin .classname { ... }`, so it and the wrapper have to be
/// captured and stored together as one unit -- neither means anything to a
/// renderer without the other.
public enum AO3ChapterHTMLExtractor {

	/// Returns `nil` when no `<div class="chapter" id="chapter-...">` is
	/// found -- a gated/restricted work (logged out) and a deleted/moved
	/// work currently look identical by this signal (see the plan's "Still
	/// open" list); callers should treat both as "couldn't fetch", leaving
	/// the article's existing `contentHTML` (nil, on first fetch) alone
	/// rather than treating this as an error worth retrying aggressively.
	public static func extract(fromWorkPageHTML html: String) -> AO3ChapterExtractionResult? {
		let root = parseHTMLLiteTree(html)

		guard let (workSkinParent, workSkinIndex, workSkinDiv) = firstDescendantWithParent(of: root, where: {
			$0.tag == "div" && $0.attributes["id"] == "workskin"
		}) else {
			return nil
		}

		let chapterDivs = descendants(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "chapter" && ($0.attributes["id"]?.hasPrefix("chapter-") ?? false)
		})
		guard !chapterDivs.isEmpty else {
			return nil
		}

		stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)

		let chapters = chapterDivs.compactMap(extractedChapter)

		var contentHTML = ""
		if let styleElement = precedingStyleElement(parent: workSkinParent, beforeIndex: workSkinIndex) {
			contentHTML += serializeHTMLLiteNodes([.element(styleElement)])
		}
		contentHTML += serializeHTMLLiteNodes([.element(workSkinDiv)])

		return AO3ChapterExtractionResult(contentHTML: contentHTML, chapters: chapters)
	}
}

// MARK: - Per-chapter extraction

private extension AO3ChapterHTMLExtractor {

	/// Mutates `chapterDiv` in place (title heading rewrite, landmark strip)
	/// and returns the TOC-facing summary of it. `nil` only for a
	/// structurally malformed chapter div (missing title), which shouldn't
	/// happen against real AO3 output but shouldn't crash if it did.
	static func extractedChapter(_ chapterDiv: HTMLLiteElement) -> AO3ExtractedChapter? {
		guard let id = chapterDiv.attributes["id"] else {
			return nil
		}

		guard let prefaceGroup = firstDescendant(of: chapterDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "chapter preface group"
		}) else {
			return nil
		}
		guard let titleHeading = firstDescendant(of: prefaceGroup, where: {
			$0.tag == "h3" && $0.attributes["class"] == "title"
		}) else {
			return nil
		}

		// Flattened text of the whole heading, not just its <a> child --
		// a chapter with its own title (e.g. "Chapter 2: Livermore,
		// California", confirmed in workskinentire.html) has that title as
		// a text node trailing the anchor, sibling to it inside the same
		// h3. Reading only the anchor's text would silently drop it.
		let title = flattenedText(titleHeading).trimmingCharacters(in: .whitespacesAndNewlines)

		// `iOS/Resources/main_ios.js`'s tocNodes() only collects
		// `h1, h2.heading, h2.toc-heading` -- invisible to h3. Rewrite so
		// this chapter lands on the existing flat TOC branch with no
		// Swift/JS changes on that side.
		titleHeading.tag = "h2"
		titleHeading.attributes["class"] = "heading"

		if let body = firstDescendant(of: chapterDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "userstuff module" && $0.attributes["role"] == "article"
		}) {
			// Strip the "Chapter Text" landmark heading -- matched by
			// id="work", not by its English text, so a locale variant
			// isn't silently missed (untested against a non-English work).
			body.children.removeAll {
				if case .element(let el) = $0, el.attributes["id"] == "work" {
					return true
				}
				return false
			}
		}

		return AO3ExtractedChapter(id: id, title: title)
	}
}

// MARK: - Phantom TOC entry from the work title

private extension AO3ChapterHTMLExtractor {

	/// The work's own title -- `<h2 class="title heading">`, first h2 inside
	/// the work-level `div.preface.group` (distinct from each chapter's own
	/// `div.chapter.preface.group`), before the byline h3 -- carries the
	/// class `heading` and so matches `tocNodes()`'s `h2.heading` selector
	/// exactly like a rewritten chapter title does. Left alone, every AO3
	/// article's TOC would show this as a phantom entry above "Chapter 1".
	/// Confirmed harmless against the one workskin sample in hand, whose
	/// rules target paragraph-level classes, not `.title`/`.heading` --
	/// flagged as unverified against a workskin that does style that chrome.
	static func stripPhantomTitleHeadingClass(inWorkSkin workSkinDiv: HTMLLiteElement) {
		guard let workPreface = firstDescendant(of: workSkinDiv, where: {
			$0.tag == "div" && $0.attributes["class"] == "preface group"
		}) else {
			return
		}
		guard let titleHeading = firstDescendant(of: workPreface, where: { $0.tag == "h2" }) else {
			return
		}
		titleHeading.attributes["class"] = "title"
	}
}

// MARK: - Preceding <style> block

private extension AO3ChapterHTMLExtractor {

	/// The workskin `<style>` block, when present, sits immediately before
	/// `#workskin` in document order (separated only by whitespace text --
	/// the comments AO3 emits in between are silently consumed by
	/// `HTMLScanner`, never reaching this tree as nodes). Anything else
	/// found while walking backward past whitespace means there's no skin,
	/// same as `entire.html`'s no-skin sample.
	static func precedingStyleElement(parent: HTMLLiteElement, beforeIndex index: Int) -> HTMLLiteElement? {
		var i = index - 1
		while i >= 0 {
			switch parent.children[i] {
			case .text(let text):
				guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
					return nil
				}
				i -= 1
			case .element(let element):
				return element.tag == "style" ? element : nil
			}
		}
		return nil
	}
}
