//
//  CSSImportExtractor.swift
//  NetNewsWire
//
//  Created by OpenAI on 8/6/26.
//

import Foundation

struct CSSImportExtraction: Equatable {
	let importCSS: String
	let remainingCSS: String
}

enum CSSImportExtractor {

	static func extract(from css: String) -> CSSImportExtraction {
		var index = css.startIndex
		var importBlockEnd = css.startIndex
		var foundImport = false

		while index < css.endIndex {
			if let whitespaceEnd = scanWhitespace(in: css, from: index) {
				index = whitespaceEnd
				importBlockEnd = index
				continue
			}

			if let commentEnd = scanComment(in: css, from: index) {
				index = commentEnd
				importBlockEnd = index
				continue
			}

			if let importEnd = scanImport(in: css, from: index) {
				index = importEnd
				importBlockEnd = index
				foundImport = true
				continue
			}

			break
		}

		guard foundImport else {
			return CSSImportExtraction(importCSS: "", remainingCSS: css)
		}

		return CSSImportExtraction(
			importCSS: String(css[..<importBlockEnd]),
			remainingCSS: String(css[importBlockEnd...])
		)
	}
}

private extension CSSImportExtractor {

	static func scanWhitespace(in css: String, from index: String.Index) -> String.Index? {
		guard index < css.endIndex, css[index].isWhitespace else {
			return nil
		}

		var current = index
		while current < css.endIndex, css[current].isWhitespace {
			current = css.index(after: current)
		}
		return current
	}

	static func scanComment(in css: String, from index: String.Index) -> String.Index? {
		guard css[index...].hasPrefix("/*") else {
			return nil
		}

		guard let endRange = css[index...].range(of: "*/") else {
			return css.endIndex
		}
		return endRange.upperBound
	}

	static func scanImport(in css: String, from index: String.Index) -> String.Index? {
		guard css[index...].hasPrefix("@import") else {
			return nil
		}

		var current = css.index(index, offsetBy: "@import".count)
		guard current == css.endIndex || isCSSIdentifierBoundary(css[current]) else {
			return nil
		}

		var quote: Character?
		var previousWasBackslash = false

		while current < css.endIndex {
			let character = css[current]
			defer {
				previousWasBackslash = character == "\\" && !previousWasBackslash
				current = css.index(after: current)
			}

			if let activeQuote = quote {
				if character == activeQuote && !previousWasBackslash {
					quote = nil
				}
				continue
			}

			if character == "\"" || character == "'" {
				quote = character
				continue
			}

			if character == ";" {
				return css.index(after: current)
			}
		}

		return nil
	}

	static func isCSSIdentifierBoundary(_ character: Character) -> Bool {
		if character.isLetter || character.isNumber {
			return false
		}
		return character != "-" && character != "_"
	}
}
