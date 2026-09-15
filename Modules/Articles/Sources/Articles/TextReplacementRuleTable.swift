//
//  TextReplacementRuleTable.swift
//  Articles
//
//  The shared word-boundary/case-insensitive matching engine behind two of
//  the text-replacement feature's four categories (see docs/annotations.md
//  and the feature's own implementation plan, "Categorizing the edit
//  types"): automatic safe fixes (a shipped, person-editable typo table)
//  and reader-insert/word replacement (Y/N, F/N, etc., also person-
//  editable, plus a per-work override layered on top -- see
//  TextReplacementPerWorkOverride). Both categories share this exact
//  matching mechanism; only the shipped defaults and the override differ.
//
//  Deliberately excludes category 2 (British->American quote conversion,
//  see TextReplacementQuoteConversion) -- that transform needs real
//  quote-pair detection, not a token find/replace, and is built
//  independently per the plan's own instruction not to conflate the two.
//
//  Pure and storage-agnostic: this type has no UserDefaults/AppDefaults
//  dependency, matching TextReplacementOffsetShift's reasoning for living
//  in this module. AppDefaults (iOS target) is where the shipped default
//  tables are actually persisted/exposed, via the same Codable-in-
//  UserDefaults pattern ArticleThemeOverrides already establishes.
//

import Foundation

/// A single person-editable find/replace rule: one or more comma-
/// separated input tokens sharing one replacement, matched case-
/// insensitively with word boundaries (`\btoken\b`) against a paragraph
/// of text. Mirrors the reference userscript's `{in, out}` pair shape
/// (see the plan's "Word/placeholder replacement" section) -- `in` is
/// stored as the raw, comma-separated, still-unescaped tokens exactly as
/// a person typed them; `TextReplacementRuleEngine` does the regex-
/// escaping and matching.
public struct TextReplacementRule: Codable, Sendable, Hashable, Identifiable {
	public let id: UUID
	/// Comma-separated input tokens, e.g. "(Y/N), Y/N, (F/N), F/N". Split
	/// and trimmed by the engine at match time, not pre-split here, so
	/// the raw person-edited string round-trips through a text field
	/// without lossy re-joining.
	public var input: String
	public var output: String

	public init(id: UUID = UUID(), input: String, output: String) {
		self.id = id
		self.input = input
		self.output = output
	}
}

/// A named, ordered collection of rules -- one instance each for the
/// shipped typo table (category 1) and the shipped/person-edited
/// reader-insert table (category 3). See docs/annotations.md's "Storage
/// shape": running a table against an article's canonical text produces
/// one edit row per match, always `hasHighlight = false`.
public struct TextReplacementRuleTable: Codable, Sendable, Hashable {
	public var rules: [TextReplacementRule]

	public init(rules: [TextReplacementRule] = []) {
		self.rules = rules
	}

	/// The shipped default typo table (category 1): common, unambiguous,
	/// mechanical errors. Person-editable afterward -- this is only the
	/// initial seed, not a fixed table re-applied on every launch
	/// regardless of edits.
	public static let defaultTypoTable = TextReplacementRuleTable(rules: [
		TextReplacementRule(input: "urself", output: "yourself"),
		TextReplacementRule(input: "teh", output: "the"),
		TextReplacementRule(input: "alot", output: "a lot"),
		TextReplacementRule(input: "wich", output: "which"),
		TextReplacementRule(input: "definately", output: "definitely"),
		TextReplacementRule(input: "recieve", output: "receive"),
		TextReplacementRule(input: "seperate", output: "separate"),
		TextReplacementRule(input: "occured", output: "occurred"),
	])

	/// The shipped default reader-insert/placeholder table (category 3),
	/// per the plan's extracted-from-the-reference-userscript defaults.
	/// `output` is left empty -- there is no sensible global default for
	/// a reader's own name; the person fills these in (or sets a
	/// per-work override) before this table does anything. An empty
	/// `output` rule is simply never applied by the engine (see
	/// TextReplacementRuleEngine.apply(_:to:) below), so shipping these
	/// rows with an empty output is safe by construction, not just by
	/// convention.
	public static let defaultReaderInsertTable = TextReplacementRuleTable(rules: [
		TextReplacementRule(input: "(Y/N), Y/N, (F/N), F/N, (G/N), G/N", output: ""),
		TextReplacementRule(input: "(Y/L/N), Y/L/N, (L/N), L/N", output: ""),
	])
}

/// One match found by TextReplacementRuleEngine.findMatches(applying:to:)
/// -- the span in the original text a rule's input token matched, and
/// what it should become. Deliberately offset-only (not yet an
/// Annotation): the caller (Account/WebViewController orchestration,
/// not built as part of this type) is responsible for turning each match
/// into an edit row through the same offset-shift pipeline manual edits
/// use, applying matches in the same descending-offset order
/// TextReplacementOffsetShift.descendingApplicationOrder exists for --
/// this engine only finds matches against the original, unmodified text,
/// it does not itself compute cross-match shifting.
public struct TextReplacementMatch: Sendable, Equatable {
	public let startOffset: Int
	public let endOffset: Int
	public let originalText: String
	public let replacementText: String
	public let ruleID: UUID

	public init(startOffset: Int, endOffset: Int, originalText: String, replacementText: String, ruleID: UUID) {
		self.startOffset = startOffset
		self.endOffset = endOffset
		self.originalText = originalText
		self.replacementText = replacementText
		self.ruleID = ruleID
	}
}

/// Word-boundary/case-insensitive matching engine shared by categories 1
/// and 3 (see this file's header comment). A pure function over a
/// String and a rule table -- no article/database/JS dependency, so it's
/// directly unit-testable against plain strings.
public enum TextReplacementRuleEngine {

	/// Finds every non-overlapping match of every rule in `table` against
	/// `text`, in left-to-right document order. A rule whose `output` is
	/// empty (see `defaultReaderInsertTable`'s doc comment) is skipped
	/// entirely -- an unfilled placeholder rule is inert by construction,
	/// not merely "matches but no-ops."
	///
	/// Word-boundary handling: each of a rule's comma-separated input
	/// tokens is regex-escaped (`NSRegularExpression.escapedPattern`) and
	/// wrapped `\btoken\b`, matched case-insensitively. This is the same
	/// false-positive guard the plan's "Word/placeholder replacement"
	/// section requires -- a bare `Y/N` only matches as a standalone
	/// token, not as a substring of an unrelated longer word.
	///
	/// Overlap handling: if two different rules' tokens would match
	/// overlapping spans (a real possibility once a person adds custom
	/// rules alongside the shipped tables), the earlier rule in `table.rules`
	/// wins for that span and the later rule's overlapping candidate is
	/// dropped -- same "the app prevents the conflict rather than
	/// detecting it after the fact" reasoning the manual-edit overlap
	/// check uses, applied here at match-finding time instead of at
	/// edit-creation time since there's no existing annotation row to
	/// conflict against yet.
	public static func findMatches(applying table: TextReplacementRuleTable, to text: String) -> [TextReplacementMatch] {
		guard !text.isEmpty else { return [] }
		let nsText = text as NSString
		var claimedRanges: [NSRange] = []
		var matches: [TextReplacementMatch] = []

		for rule in table.rules {
			guard !rule.output.isEmpty else { continue }
			let tokens = rule.input
				.split(separator: ",")
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
			guard !tokens.isEmpty else { continue }

			for token in tokens {
				let escaped = NSRegularExpression.escapedPattern(for: token)
				guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
					continue
				}
				let fullRange = NSRange(location: 0, length: nsText.length)
				regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
					guard let result, let range = result.range.toOptionalRangeIfValid() else { return }
					guard !claimedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
					claimedRanges.append(range)
					let matchedText = nsText.substring(with: range)
					matches.append(TextReplacementMatch(
						startOffset: range.location,
						endOffset: range.location + range.length,
						originalText: matchedText,
						replacementText: rule.output,
						ruleID: rule.id
					))
				}
			}
		}

		return matches.sorted { $0.startOffset < $1.startOffset }
	}
}

private extension NSRange {
	/// NSRegularExpression can report NSNotFound ranges for an optional
	/// capture group; enumerateMatches' top-level result.range is never
	/// NSNotFound for an actual match, but this guard keeps the call site
	/// above from ever force-unwrapping that assumption.
	func toOptionalRangeIfValid() -> NSRange? {
		location == NSNotFound ? nil : self
	}
}
