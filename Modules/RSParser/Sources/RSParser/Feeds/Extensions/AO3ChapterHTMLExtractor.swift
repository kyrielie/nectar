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

/// The four ways a fetched AO3 work page can come back, distinguished by
/// document shape alone -- there is no HTTP-status-level signal for any of
/// the three failure cases; AO3 returns 200 for all of them.
public enum AO3ChapterExtractionOutcome: Sendable {
	/// `#workskin` plus at least one `.chapter` div were found -- the normal
	/// case.
	case success(AO3ChapterExtractionResult)
	/// The Adult Content Warning interstitial -- expected to be unreachable
	/// now that every fetch sends `view_adult=true` unconditionally, so
	/// seeing this outcome in practice means that parameter didn't do its
	/// job (redirect stripping it, an AO3 behavior change, or a gate this
	/// hasn't been sampled against yet).
	case adultContentGate
	/// AO3's "restricted to registered users" login wall
	/// (`div#signin`, "This work is only available to registered users of
	/// the Archive."). Distinct from `.notFound` -- Workstream 3's
	/// authenticated retry fires specifically on this outcome.
	case registrationRequired
	/// Neither `#workskin`+`.chapter` divs, nor either known gate page, was
	/// found. Catch-all for a genuinely deleted/moved work, or any other
	/// shape not yet sampled (a collection- or series-level gate, for
	/// instance).
	case notFound
}

/// Extracts storable article content from a fetched AO3 work page
/// (`GET .../works/<id>?view_full_work=true&view_adult=true`).
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

	/// See `AO3ChapterExtractionOutcome` for what each case means and when
	/// callers should treat it as retryable (`.registrationRequired`, via
	/// Workstream 3) versus not (`.adultContentGate`, `.notFound`).
	public static func extract(fromWorkPageHTML html: String) -> AO3ChapterExtractionOutcome {
		let root = parseHTMLLiteTree(html)

		if let (workSkinParent, workSkinIndex, workSkinDiv) = firstDescendantWithParent(of: root, where: {
			$0.tag == "div" && $0.attributes["id"] == "workskin"
		}) {
			let chapterDivs = descendants(of: workSkinDiv, where: {
				$0.tag == "div" && $0.attributes["class"] == "chapter" && ($0.attributes["id"]?.hasPrefix("chapter-") ?? false)
			})
			if !chapterDivs.isEmpty {
				stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)

				let chapters = chapterDivs.compactMap(extractedChapter)

				var contentHTML = ""
				if let styleElement = precedingStyleElement(parent: workSkinParent, beforeIndex: workSkinIndex) {
					contentHTML += serializeHTMLLiteNodes([.element(styleElement)])
				}
				contentHTML += serializeHTMLLiteNodes([.element(workSkinDiv)])

				return .success(AO3ChapterExtractionResult(contentHTML: contentHTML, chapters: chapters))
			}

			// Single-chapter works carry no per-chapter <div class="chapter">
			// wrapper at all -- confirmed against a real work (87955346,
			// "Chapters: 1/1"): the body sits directly inside
			// <div id="chapters" role="article">, with no h3.title chapter
			// heading either, since there's only ever one implicit chapter.
			// Without this branch, every single-chapter AO3 work was
			// misreported as gated/removed.
			if let chaptersDiv = firstDescendant(of: workSkinDiv, where: {
				$0.tag == "div" && $0.attributes["id"] == "chapters"
			}) {
				stripPhantomTitleHeadingClass(inWorkSkin: workSkinDiv)
				stripLandmarkHeading(from: chaptersDiv)

				let chapters = [AO3ExtractedChapter(id: "chapter-1", title: "Chapter 1")]

				var contentHTML = ""
				if let styleElement = precedingStyleElement(parent: workSkinParent, beforeIndex: workSkinIndex) {
					contentHTML += serializeHTMLLiteNodes([.element(styleElement)])
				}
				contentHTML += serializeHTMLLiteNodes([.element(workSkinDiv)])

				return .success(AO3ChapterExtractionResult(contentHTML: contentHTML, chapters: chapters))
			}
		}

		if isAdultContentGate(root) {
			return .adultContentGate
		}
		if isRegistrationRequired(root) {
			return .registrationRequired
		}
		return .notFound
	}
}

// MARK: - Gate page detection

private extension AO3ChapterHTMLExtractor {

	/// Adult Content Warning interstitial: anchored on the heading text --
	/// the simplest reliable signal, and it doesn't depend on the per-work
	/// "Yes, Continue" link's exact `view_adult=true`-suffixed href.
	static func isAdultContentGate(_ root: HTMLLiteElement) -> Bool {
		firstDescendant(of: root, where: {
			$0.tag == "h2" && $0.attributes["class"] == "landmark heading" && flattenedText($0).trimmingCharacters(in: .whitespacesAndNewlines) == "Adult Content Warning"
		}) != nil
	}

	/// Registration-required login wall: matched on `div#signin`'s
	/// presence -- an id, so cheaper and more specific than matching the
	/// "Sorry! This work is only available to registered users of the
	/// Archive." prose.
	static func isRegistrationRequired(_ root: HTMLLiteElement) -> Bool {
		firstDescendant(of: root, where: {
			$0.tag == "div" && $0.attributes["id"] == "signin"
		}) != nil
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
			stripLandmarkHeading(from: body)
		}

		return AO3ExtractedChapter(id: id, title: title)
	}
}

// MARK: - Landmark heading strip

private extension AO3ChapterHTMLExtractor {

	/// Strips the "Chapter Text" / "Work Text:" landmark heading -- matched
	/// by id="work", not by its English text, so a locale variant isn't
	/// silently missed (untested against a non-English work). Shared by
	/// both the multi-chapter body (`div.userstuff.module[role="article"]`)
	/// and the single-chapter body (`div#chapters[role="article"]`
	/// directly) -- the heading's id is the same either way.
	static func stripLandmarkHeading(from body: HTMLLiteElement) {
		body.children.removeAll {
			if case .element(let el) = $0, el.attributes["id"] == "work" {
				return true
			}
			return false
		}
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
