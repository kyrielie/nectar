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
		let delegate = AO3SummaryScannerDelegate()
		let scanner = HTMLScanner(delegate: delegate)
		scanner.parse(Array(html.utf8))
		let blocks = delegate.topLevelBlocks

		let statsBlocks = blocks.filter { $0.tag == "p" && flattenedText($0).hasPrefix("Words:") }
		guard statsBlocks.count == 1, let statsBlock = statsBlocks.first else {
			return nil
		}

		let (wordCount, chapterCurrent, chapterTotal, isComplete) = parseStats(flattenedText(statsBlock))

		var fandoms: [String]?
		var ratings: [String]?
		var warnings: [String]?
		var categories: [String]?
		var characters: [String]?
		var relationships: [String]?
		var additionalTags: [String]?
		var series: [ParsedSeriesEntry] = []
		var passthroughBlocks: [AO3Node] = []

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

		let cleaned = serialize(passthroughBlocks)
		let cleanedSummaryHTML = cleaned.isEmpty ? nil : cleaned

		return AO3ExtractionResult(
			cleanedSummaryHTML: cleanedSummaryHTML,
			wordCount: wordCount,
			chapterCurrent: chapterCurrent,
			chapterTotal: chapterTotal,
			isComplete: isComplete,
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

	static func parseStats(_ text: String) -> (wordCount: Int?, chapterCurrent: Int?, chapterTotal: Int?, isComplete: Bool?) {
		var wordCount: Int?
		var chapterCurrent: Int?
		var chapterTotal: Int?
		var isComplete: Bool?

		let fields = text.components(separatedBy: ",")
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

		return (wordCount, chapterCurrent, chapterTotal, isComplete)
	}
}

// MARK: - Byline

private extension AO3SummaryExtractor {

	static func isBylineBlock(_ block: AO3Element, text: String) -> Bool {
		if text == "by Anonymous" && !containsElement(block, tag: "a") {
			return true
		}
		return containsAuthorLink(block)
	}

	static func containsAuthorLink(_ node: AO3Element) -> Bool {
		for child in node.children {
			guard case .element(let element) = child else {
				continue
			}
			if element.tag == "a" && element.attributes["rel"] == "author" {
				return true
			}
			if containsAuthorLink(element) {
				return true
			}
		}
		return false
	}

	static func containsElement(_ node: AO3Element, tag: String) -> Bool {
		for child in node.children {
			guard case .element(let element) = child else {
				continue
			}
			if element.tag == tag {
				return true
			}
			if containsElement(element, tag: tag) {
				return true
			}
		}
		return false
	}
}

// MARK: - Series paragraph

private extension AO3SummaryExtractor {

	/// `Series: Part <N> of <a href=".../series/<id>">Name</a>`
	static func parseSeriesEntry(_ block: AO3Element, text: String) -> ParsedSeriesEntry? {
		guard let anchor = firstAnchor(block) else {
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

	static func firstAnchor(_ node: AO3Element) -> AO3Element? {
		for child in node.children {
			guard case .element(let element) = child else {
				continue
			}
			if element.tag == "a" {
				return element
			}
			if let found = firstAnchor(element) {
				return found
			}
		}
		return nil
	}

	static func seriesID(fromHref href: String?) -> String? {
		guard let href, let range = href.range(of: "/series/") else {
			return nil
		}
		let rest = href[range.upperBound...]
		let digits = rest.prefix { $0.isNumber }
		return digits.isEmpty ? nil : String(digits)
	}
}

// MARK: - Tag list

private extension AO3SummaryExtractor {

	static func parseTagList(_ ul: AO3Element,
	                          fandoms: inout [String]?,
	                          ratings: inout [String]?,
	                          warnings: inout [String]?,
	                          categories: inout [String]?,
	                          characters: inout [String]?,
	                          relationships: inout [String]?,
	                          additionalTags: inout [String]?) {
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

// MARK: - Node tree

private final class AO3Element {
	let tag: String
	let attributes: [String: String]
	let selfClosing: Bool
	var children: [AO3Node] = []

	init(tag: String, attributes: [String: String], selfClosing: Bool) {
		self.tag = tag
		self.attributes = attributes
		self.selfClosing = selfClosing
	}
}

private enum AO3Node {
	case element(AO3Element)
	case text(String)
}

private func flattenedText(_ element: AO3Element) -> String {
	var s = ""
	for child in element.children {
		switch child {
		case .text(let text):
			s += text
		case .element(let el):
			s += flattenedText(el)
		}
	}
	return s
}

// MARK: - Scanner delegate

/// Builds a lightweight tree of top-level `<p>`/`<ul>`/etc. blocks (and their
/// descendants) out of `HTMLScanner`'s flat event stream. AO3's generated
/// summary HTML never nests one top-level block inside another, so a simple
/// depth-tracked stack is sufficient -- no general-purpose HTML tree needed.
private final class AO3SummaryScannerDelegate: HTMLScannerDelegate {

	// AO3's generated summary HTML emits void elements like <br> and <hr>
	// without a trailing slash (e.g. "...Adult<br>Your flight..."). HTMLScanner
	// does no void-element tracking of its own -- by design, see its header
	// comment -- and only reports `selfClosing == true` for a literal "/>",
	// so a bare <br> arrives as an ordinary start tag. Without this list, it
	// gets pushed onto `stack` and is never popped (no matching </br> exists
	// in the source), which silently swallows every subsequent top-level
	// block -- including the `Words:` stats paragraph -- as a descendant of
	// the still-open element. `extract` then finds zero top-level stats
	// paragraphs instead of one and returns nil for an entry that's
	// otherwise a perfectly ordinary AO3 summary, with no error and no
	// crash -- the item just silently loses all AO3 metadata.
	private static let voidElements: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr"
	]

	private(set) var topLevelBlocks: [AO3Element] = []
	private var stack: [AO3Element] = []

	func htmlScanner(_ scanner: HTMLScanner,
	                 didStartTag name: ArraySlice<UInt8>,
	                 attributes: HTMLAttributes,
	                 selfClosing: Bool) {
		let tagName = String(decoding: name, as: UTF8.self).lowercased()
		let effectiveSelfClosing = selfClosing || Self.voidElements.contains(tagName)
		let element = AO3Element(tag: tagName, attributes: attributes.dictionary(), selfClosing: effectiveSelfClosing)

		if let parent = stack.last {
			parent.children.append(.element(element))
		}

		if !effectiveSelfClosing {
			stack.append(element)
		} else if stack.isEmpty {
			topLevelBlocks.append(element)
		}
	}

	func htmlScanner(_ scanner: HTMLScanner, didEndTag name: ArraySlice<UInt8>) {
		guard !stack.isEmpty else {
			return
		}
		let element = stack.removeLast()
		if stack.isEmpty {
			topLevelBlocks.append(element)
		}
	}

	func htmlScanner(_ scanner: HTMLScanner, didFindCharacters bytes: ArraySlice<UInt8>) {
		guard let parent = stack.last else {
			// Text between top-level blocks (whitespace) -- discarded.
			return
		}
		let text = String(decoding: bytes, as: UTF8.self)
		parent.children.append(.text(text))
	}
}

// MARK: - Re-serialization for pass-through content

private func serialize(_ nodes: [AO3Node]) -> String {
	var s = ""
	for node in nodes {
		serialize(node, into: &s)
	}
	return s
}

private func serialize(_ node: AO3Node, into s: inout String) {
	switch node {
	case .text(let text):
		s += escapeText(text)
	case .element(let element):
		s += "<\(element.tag)"
		for (name, value) in element.attributes {
			s += " \(name)=\"\(escapeAttribute(value))\""
		}
		if element.selfClosing {
			s += "/>"
			return
		}
		s += ">"
		for child in element.children {
			serialize(child, into: &s)
		}
		s += "</\(element.tag)>"
	}
}

private func escapeText(_ s: String) -> String {
	s.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
}

private func escapeAttribute(_ s: String) -> String {
	s.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "\"", with: "&quot;")
}
