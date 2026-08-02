//
//  HTMLLiteTree.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation

// A minimal DOM-like tree over `HTMLScanner`'s flat event stream, for
// consumers that need to walk nested elements/text rather than handle a
// flat token stream directly. Factored out of `AO3SummaryExtractor` once a
// second consumer (`AO3ChapterHTMLExtractor`) needed the same tree-building.
//
// AO3's generated markup -- both feed summaries and work pages -- never
// depends on anything a real HTML5 tree constructor would add (implicit tag
// closing, foster parenting, etc.), so this stack-based builder is
// sufficient; pulling in a general-purpose HTML tree constructor isn't
// warranted.

final class HTMLLiteElement {
	let tag: String
	let attributes: [String: String]
	let selfClosing: Bool
	var children: [HTMLLiteNode] = []

	init(tag: String, attributes: [String: String], selfClosing: Bool) {
		self.tag = tag
		self.attributes = attributes
		self.selfClosing = selfClosing
	}
}

enum HTMLLiteNode {
	case element(HTMLLiteElement)
	case text(String)
}

/// Parses `html` into a tree rooted at a synthetic `#root` element (never
/// itself meaningful to callers -- its `children` are the document's
/// top-level nodes). AO3's generated markup fits comfortably in memory for
/// both use cases (a feed entry summary, or one work's full page), so
/// building the whole tree up front -- rather than a streaming/lazy walk --
/// keeps both extractors' logic simple.
func parseHTMLLiteTree(_ html: String) -> HTMLLiteElement {
	let builder = HTMLLiteTreeBuilder()
	let scanner = HTMLScanner(delegate: builder)
	scanner.parse(Array(html.utf8))
	return builder.root
}

func flattenedText(_ element: HTMLLiteElement) -> String {
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

/// Depth-first search for the first descendant (not including `element`
/// itself) matching `predicate`.
func firstDescendant(of element: HTMLLiteElement, where predicate: (HTMLLiteElement) -> Bool) -> HTMLLiteElement? {
	for child in element.children {
		guard case .element(let el) = child else {
			continue
		}
		if predicate(el) {
			return el
		}
		if let found = firstDescendant(of: el, where: predicate) {
			return found
		}
	}
	return nil
}

/// All descendants (not including `element` itself) matching `predicate`,
/// in document order.
func descendants(of element: HTMLLiteElement, where predicate: (HTMLLiteElement) -> Bool) -> [HTMLLiteElement] {
	var result: [HTMLLiteElement] = []
	for child in element.children {
		guard case .element(let el) = child else {
			continue
		}
		if predicate(el) {
			result.append(el)
		}
		result.append(contentsOf: descendants(of: el, where: predicate))
	}
	return result
}

/// Re-serializes a node list back to HTML. Not byte-identical to any
/// original source (attribute order/quoting/entity choices aren't
/// preserved), but semantically equivalent -- sufficient for content that's
/// headed into a `WKWebView`, not for a round-trip diff.
func serializeHTMLLiteNodes(_ nodes: [HTMLLiteNode]) -> String {
	var s = ""
	for node in nodes {
		serializeHTMLLiteNode(node, into: &s)
	}
	return s
}

private func serializeHTMLLiteNode(_ node: HTMLLiteNode, into s: inout String) {
	switch node {
	case .text(let text):
		s += escapeHTMLLiteText(text)
	case .element(let element):
		s += "<\(element.tag)"
		for (name, value) in element.attributes {
			s += " \(name)=\"\(escapeHTMLLiteAttribute(value))\""
		}
		if element.selfClosing {
			s += "/>"
			return
		}
		s += ">"
		for child in element.children {
			serializeHTMLLiteNode(child, into: &s)
		}
		s += "</\(element.tag)>"
	}
}

private func escapeHTMLLiteText(_ s: String) -> String {
	s.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
}

private func escapeHTMLLiteAttribute(_ s: String) -> String {
	s.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Tree builder

private final class HTMLLiteTreeBuilder: HTMLScannerDelegate {

	// AO3's generated markup emits void elements like <br> and <hr> without
	// a trailing slash. HTMLScanner does no void-element tracking of its
	// own -- by design, see its header comment -- and only reports
	// selfClosing == true for a literal "/>". Without this list, a bare
	// <br>/<hr> is pushed onto `stack` and never popped (no matching close
	// tag exists in the source), which silently swallows every subsequent
	// sibling as a descendant of the still-open element instead of at its
	// intended level.
	private static let voidElements: Set<String> = [
		"area", "base", "br", "col", "embed", "hr", "img", "input",
		"link", "meta", "param", "source", "track", "wbr"
	]

	let root = HTMLLiteElement(tag: "#root", attributes: [:], selfClosing: false)
	private lazy var stack: [HTMLLiteElement] = [root]

	func htmlScanner(_ scanner: HTMLScanner,
	                 didStartTag name: ArraySlice<UInt8>,
	                 attributes: HTMLAttributes,
	                 selfClosing: Bool) {
		let tagName = String(decoding: name, as: UTF8.self).lowercased()
		let effectiveSelfClosing = selfClosing || Self.voidElements.contains(tagName)
		let element = HTMLLiteElement(tag: tagName, attributes: attributes.dictionary(), selfClosing: effectiveSelfClosing)

		stack[stack.count - 1].children.append(.element(element))

		if !effectiveSelfClosing {
			stack.append(element)
		}
	}

	func htmlScanner(_ scanner: HTMLScanner, didEndTag name: ArraySlice<UInt8>) {
		// Never pop the synthetic root -- an unmatched close tag (or a
		// void element close tag we correctly never pushed) is otherwise
		// liberally ignored, consistent with HTMLScanner's own stated
		// leniency elsewhere.
		guard stack.count > 1 else {
			return
		}
		stack.removeLast()
	}

	func htmlScanner(_ scanner: HTMLScanner, didFindCharacters bytes: ArraySlice<UInt8>) {
		let text = String(decoding: bytes, as: UTF8.self)
		stack[stack.count - 1].children.append(.text(text))
	}
}
