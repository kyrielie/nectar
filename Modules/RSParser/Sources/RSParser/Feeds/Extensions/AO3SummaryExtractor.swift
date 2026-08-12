//
//  AO3SummaryExtractor.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

/// Extracted from an AO3 tag/user Atom feed entry's `<summary>` HTML.
///
/// AO3 tag/user feeds render each work's byline, stats, series membership,
/// and tag list as machine-generated HTML inside the entry summary. This is
/// a second, independent metadata source from Ambrosia's `_ambrosia` JSON
/// Feed extension -- same `ParsedItem` fields, different wire format.
public struct AO3ExtractionResult: Sendable {
	public let cleanedSummaryHTML: String?
	public let wordCount: Int?
	public let chapterCurrent: Int?
	public let chapterTotal: Int?            // nil when AO3 shows "?"
	public let isComplete: Bool?             // nil when chapterTotal is nil
	public let language: String?
	public let fandoms: [String]?
	public let ratings: [String]?
	public let warnings: [String]?
	public let categories: [String]?
	public let characters: [String]?
	public let relationships: [String]?
	public let additionalTags: [String]?
	public let series: [ParsedSeriesEntry]?
	public let ao3WorkID: String?
}

public enum AO3SummaryExtractor {

	/// Returns `nil` when `html` doesn't look like an AO3-generated summary --
	/// specifically, when there isn't exactly one top-level `<p>` whose text
	/// starts with the literal `Words:` (AO3's machine-generated stats
	/// paragraph, unique to its export). Callers should fall back to their
	/// existing generic summary handling in that case.
	public static func extract(fromSummaryHTML html: String) -> AO3ExtractionResult? {
		let root = parseHTMLLiteTree(html)
		let blocks: [HTMLLiteElement] = root.children.compactMap {
			guard case .element(let element) = $0 else {
				return nil
			}
			return element
		}

		let statsBlocks = blocks.filter { $0.tag == "p" && flattenedText($0).hasPrefix("Words:") }
		guard statsBlocks.count == 1, let statsBlock = statsBlocks.first else {
			return nil
		}

		let (wordCount, chapterCurrent, chapterTotal, isComplete, language) = parseStats(flattenedText(statsBlock))

		var fandoms: [String]?
		var ratings: [String]?
		var warnings: [String]?
		var categories: [String]?
		var characters: [String]?
		var relationships: [String]?
		var additionalTags: [String]?
		var series: [ParsedSeriesEntry] = []
		var passthroughBlocks: [HTMLLiteNode] = []

		for block in blocks {
			if block === statsBlock {
				continue
			}

			if block.tag == "p" {
				let text = flattenedText(block).trimmingCharacters(in: .whitespacesAndNewlines)

				if isBylineBlock(block, text: text) {
					continue
				}

				if text.hasPrefix("Series: Part"), let entry = parseSeriesEntry(block, text: text) {
					series.append(entry)
					continue
				}
			}

			if block.tag == "ul" {
				parseTagList(block,
				             fandoms: &fandoms,
				             ratings: &ratings,
				             warnings: &warnings,
				             categories: &categories,
				             characters: &characters,
				             relationships: &relationships,
				             additionalTags: &additionalTags)
				continue
			}

			passthroughBlocks.append(.element(block))
		}

		let cleaned = serializeHTMLLiteNodes(passthroughBlocks)
		let cleanedSummaryHTML = cleaned.isEmpty ? nil : cleaned

		return AO3ExtractionResult(
			cleanedSummaryHTML: cleanedSummaryHTML,
			wordCount: wordCount,
			chapterCurrent: chapterCurrent,
			chapterTotal: chapterTotal,
			isComplete: isComplete,
			language: language,
			fandoms: fandoms,
			ratings: ratings,
			warnings: warnings,
			categories: categories,
			characters: characters,
			relationships: relationships,
			additionalTags: additionalTags,
			series: series.isEmpty ? nil : series,
			ao3WorkID: nil
		)
	}

	/// Parses the AO3 work ID out of a permalink like
	/// `https://archiveofourown.org/works/12345678`. Kept separate from
	/// `extract(fromSummaryHTML:)` since the work ID lives in the entry's
	/// `<link>`, not its `<summary>`.
	public static func ao3WorkID(fromPermalink permalink: String?) -> String? {
		guard let permalink, let range = permalink.range(of: "/works/") else {
			return nil
		}
		let rest = permalink[range.upperBound...]
		let digits = rest.prefix { $0.isNumber }
		return digits.isEmpty ? nil : String(digits)
	}
}

// MARK: - Stats paragraph

private extension AO3SummaryExtractor {

	static func parseStats(_ text: String) -> (wordCount: Int?, chapterCurrent: Int?, chapterTotal: Int?, isComplete: Bool?, language: String?) {
		var wordCount: Int?
		var chapterCurrent: Int?
		var chapterTotal: Int?
		var isComplete: Bool?
		var language: String?

		// "Language:" is handled separately, taking everything from its
		// own colon to the end of the stats text, rather than through the
		// comma-split loop below -- a language name can itself contain a
		// comma (AO3 lists several multi-part names, e.g. "Chinese-
		// simplified"'s siblings), and Language is always the stats
		// paragraph's last field, so this can't clip a field that comes
		// after it.
		let statsWithoutLanguage: String
		if let languageRange = text.range(of: "Language:") {
			let rawLanguage = text[languageRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
			language = rawLanguage.isEmpty ? nil : rawLanguage
			statsWithoutLanguage = String(text[text.startIndex..<languageRange.lowerBound])
		} else {
			statsWithoutLanguage = text
		}

		let fields = statsWithoutLanguage.components(separatedBy: ",")
		for field in fields {
			guard let colonIndex = field.firstIndex(of: ":") else {
				continue
			}
			let label = field[field.startIndex..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
			let value = field[field.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)

			if label == "Words" {
				let digitsOnly = value.filter { $0.isNumber }
				wordCount = digitsOnly.isEmpty ? nil : Int(digitsOnly)
			} else if label == "Chapters" {
				let parts = value.components(separatedBy: "/")
				guard parts.count == 2 else {
					continue
				}
				chapterCurrent = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
				let totalString = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
				if totalString == "?" {
					chapterTotal = nil
					isComplete = nil
				} else if let total = Int(totalString) {
					chapterTotal = total
					if let current = chapterCurrent {
						isComplete = current == total
					}
				}
			}
		}

		return (wordCount, chapterCurrent, chapterTotal, isComplete, language)
	}
}

// MARK: - Byline

private extension AO3SummaryExtractor {

	static func isBylineBlock(_ block: HTMLLiteElement, text: String) -> Bool {
		if text == "by Anonymous" && firstDescendant(of: block, where: { $0.tag == "a" }) == nil {
			return true
		}
		return firstDescendant(of: block, where: { $0.tag == "a" && $0.attributes["rel"] == "author" }) != nil
	}
}

// MARK: - Series paragraph

private extension AO3SummaryExtractor {

	/// `Series: Part <N> of <a href=".../series/<id>">Name</a>`
	static func parseSeriesEntry(_ block: HTMLLiteElement, text: String) -> ParsedSeriesEntry? {
		guard let anchor = firstDescendant(of: block, where: { $0.tag == "a" }) else {
			return nil
		}
		guard let ofRange = text.range(of: " of ") else {
			return nil
		}
		let indexString = text[text.index(text.startIndex, offsetBy: "Series: Part".count)..<ofRange.lowerBound]
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let index = Int(indexString) else {
			return nil
		}
		let name = flattenedText(anchor).trimmingCharacters(in: .whitespacesAndNewlines)
		let ao3ID = seriesID(fromHref: anchor.attributes["href"])
		return ParsedSeriesEntry(name: name, index: index, ao3ID: ao3ID)
	}

	/// Shared with `AO3SearchResultsExtractor`/`AO3ChapterHTMLExtractor`
	/// via `AO3HTMLHelpers.seriesID(fromHref:)`.
	static func seriesID(fromHref href: String?) -> String? {
		AO3HTMLHelpers.seriesID(fromHref: href)
	}
}

// MARK: - Tag list

private extension AO3SummaryExtractor {

	static func parseTagList(
		_ ul: HTMLLiteElement,
		fandoms: inout [String]?,
		ratings: inout [String]?,
		warnings: inout [String]?,
		categories: inout [String]?,
		characters: inout [String]?,
		relationships: inout [String]?,
		additionalTags: inout [String]?
	) {
		for child in ul.children {
			guard case .element(let li) = child, li.tag == "li" else {
				continue
			}

			// Label: leading text up to the first ":".
			var label: String?
			for liChild in li.children {
				if case .text(let s) = liChild, let colonIndex = s.firstIndex(of: ":") {
					label = s[s.startIndex..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
					break
				}
			}
			guard let label else {
				continue
			}

			// Values: text of each `<a>` inside, in order.
			var values: [String] = []
			for liChild in li.children {
				guard case .element(let element) = liChild, element.tag == "a" else {
					continue
				}
				values.append(flattenedText(element).trimmingCharacters(in: .whitespacesAndNewlines))
			}
			guard !values.isEmpty else {
				continue
			}

			switch label {
			case "Fandoms":
				fandoms = values
			case "Rating":
				ratings = values
			case "Warnings":
				warnings = values
			case "Categories":
				categories = values
			case "Characters":
				characters = values
			case "Relationships":
				relationships = values
			case "Additional Tags":
				additionalTags = values
			default:
				break
			}
		}
	}
}
