//
//  TextReplacementQuoteConversion.swift
//  Articles
//
//  Category 2 of the text-replacement feature (see docs/annotations.md and
//  the feature's own implementation plan, "Categorizing the edit types" and
//  "Quote conversion is a harder transform than the other categories"):
//  converts British-style single-quote dialogue ('like this') to American
//  double-quote dialogue ("like this"). Deliberately NOT built on top of
//  TextReplacementRuleTable/TextReplacementRuleEngine -- the `'` glyph is
//  identical between a dialogue quote mark and an apostrophe (contraction,
//  possessive), so this needs real balanced-pair detection with heuristics
//  for what "looks like dialogue," not a token find/replace. Produces the
//  same kind of match (TextReplacementMatch, from TextReplacementRuleTable
//  .swift) as the shared engine so callers (Account/WebViewController
//  orchestration) can treat both categories' output identically once
//  matches are found -- only the *finding* differs.
//

import Foundation

/// Pure, storage-agnostic balanced-quote-pair detector. No UserDefaults/
/// AppDefaults dependency, matching TextReplacementRuleTable/
/// TextReplacementOffsetShift's reasoning for living in this module.
public enum TextReplacementQuoteConversion {

	/// Finds every genuine dialogue-quote span delimited by `'...'` in
	/// `text` and returns one TextReplacementMatch per pair, converting
	/// the opening and closing `'` to `"` while leaving the quoted
	/// content between them untouched. Contractions (`don't`) and
	/// possessives (`Sarah's`) are never matched, because they are never
	/// *paired* -- a lone apostrophe mid-word has no plausible partner
	/// closing quote, so the pairing scan below simply never proposes
	/// them as a candidate span in the first place.
	///
	/// Detection heuristic (per the plan's own description, not
	/// invented independently of it): a candidate *opening* `'` is one
	/// that is either at the very start of `text` or immediately
	/// preceded by whitespace, an opening punctuation mark (`(`, `"`,
	/// `“`, `—`, `-`), or a paragraph boundary (`\n`) -- i.e. it starts a
	/// new quoted span rather than sitting inside a word. A candidate
	/// *closing* `'` is one immediately followed by whitespace, terminal
	/// punctuation (`.`, `,`, `!`, `?`, `;`, `:`), a closing punctuation
	/// mark (`)`, `"`, `”`), or the end of `text` -- i.e. it plausibly
	/// ends a quoted span rather than sitting inside a word
	/// (contraction/possessive). A `'` that is neither is never treated
	/// as a pair boundary at all (e.g. the `'` in `it's` is followed by
	/// `s`, which is neither whitespace nor punctuation, so it's never a
	/// closing-candidate, and per-plan it's also never an
	/// opening-candidate since it's preceded by `t`).
	///
	/// Pairing: for each opening-candidate, the *nearest* subsequent
	/// closing-candidate is used to close the span (greedy, left to
	/// right, non-overlapping) -- this handles the common single-level
	/// dialogue case correctly. Nested quotes (a quote-within-a-quote,
	/// conventionally rendered with double marks inside single in
	/// British typesetting, e.g. `'She said "hello" to me'`) are exactly
	/// the outer pair here; this function only ever converts `'...'`
	/// spans, never touches literal `"..."` content already present
	/// inside one, so a pre-existing nested double-quote survives
	/// unchanged as content, not as a boundary this scan reacts to.
	///
	/// A span is further required to "plausibly contain a space" (per
	/// the plan) before being treated as real dialogue rather than, say,
	/// a short quoted single word that's ambiguous either way -- an
	/// opening/closing pair whose content has no whitespace at all is
	/// rejected as a candidate and left unconverted, erring toward
	/// under-matching over corrupting a possessive/contraction pattern
	/// this heuristic didn't anticipate.
	///
	/// An opening-candidate with no valid subsequent closing-candidate
	/// before `text` ends (an unpaired `'`) produces no match for that
	/// `'` at all -- it is left exactly as-is, per "an unpaired `'` with
	/// no matching close" in the plan's own test-corpus description.
	public static func findMatches(in text: String) -> [TextReplacementMatch] {
		guard !text.isEmpty else { return [] }
		let nsText = text as NSString
		let length = nsText.length
		guard length > 0 else { return [] }

		// Fixed, deterministic ruleID for every quote-conversion match --
		// there is no person-editable "rule" behind this category (unlike
		// categories 1/3), so TextReplacementMatch's ruleID (which exists
		// to let the shared engine's overlap logic and any future
		// per-rule UI identify which rule produced a match) has nothing
		// meaningful to point to. A single fixed UUID, rather than
		// UUID() per match, makes every quote-conversion match
		// identifiable as belonging to this category if a caller ever
		// needs to distinguish "which category produced this row" from
		// ruleID alone.
		let quoteConversionRuleID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!

		var matches: [TextReplacementMatch] = []
		var searchStart = 0

		while searchStart < length {
			guard let openLocation = nextOpeningCandidate(in: nsText, from: searchStart) else {
				break
			}
			guard let closeLocation = nextClosingCandidate(in: nsText, after: openLocation) else {
				// No valid close for this open anywhere in the rest of
				// the text -- unpaired, leave as-is, and there is no
				// later opening-candidate that could possibly pair
				// either (any candidate after this one still has no
				// close), so stop scanning entirely rather than just
				// advancing past this one open.
				break
			}

			let contentRange = NSRange(location: openLocation + 1, length: closeLocation - openLocation - 1)
			let content = nsText.substring(with: contentRange)

			guard content.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else {
				// No whitespace in the candidate span -- per the plan,
				// not plausible dialogue. Don't consume this open; a
				// later, better-fitting open/close pair might still
				// start after it. Advance past just this open and keep
				// scanning from there.
				searchStart = openLocation + 1
				continue
			}

			let fullRange = NSRange(location: openLocation, length: closeLocation - openLocation + 1)
			let originalText = nsText.substring(with: fullRange)
			let replacementText = "\"" + content + "\""

			matches.append(TextReplacementMatch(
				startOffset: fullRange.location,
				endOffset: fullRange.location + fullRange.length,
				originalText: originalText,
				replacementText: replacementText,
				ruleID: quoteConversionRuleID
			))

			searchStart = closeLocation + 1
		}

		return matches
	}

	/// UTF-16 code units that make a `'` immediately after them a
	/// plausible dialogue-open boundary. `\n`/`\t`/space cover
	/// whitespace and a paragraph boundary; the others are opening
	/// punctuation a quote would naturally follow. Matched as raw
	/// `UInt16` code units (not `Character`/`UnicodeScalar` conversions)
	/// since every member here is a single UTF-16 code unit and
	/// `NSString.character(at:)` already returns code units directly --
	/// this avoids constructing a `UnicodeScalar`/`Character` from an
	/// arbitrary `UInt16`, which is not guaranteed valid for every code
	/// unit (an unpaired surrogate isn't a valid scalar), a case this
	/// codebase's own "don't guess" convention says to route around
	/// rather than assume safe.
	private static let openingPrecedingCodeUnits: Set<UInt16> = [
		0x0020, 0x0009, 0x000A, 0x000D, // space, tab, \n, \r
		0x0028, // (
		0x0022, // "
		0x201C, // “
		0x2014, // —
		0x002D  // -
	]

	/// UTF-16 code units that make a `'` immediately before them a
	/// plausible dialogue-close boundary. Terminal/closing punctuation
	/// (and whitespace) a quote would naturally precede.
	private static let closingFollowingCodeUnits: Set<UInt16> = [
		0x0020, 0x0009, 0x000A, 0x000D, // space, tab, \n, \r
		0x002E, // .
		0x002C, // ,
		0x0021, // !
		0x003F, // ?
		0x003B, // ;
		0x003A, // :
		0x0029, // )
		0x0022, // "
		0x201D  // ”
	]

	private static let apostropheCodeUnit: UInt16 = 0x0027 // '

	/// Known leading elisions ('cause, 'til, 'em, etc.) that would
	/// otherwise be misread as a dialogue-opening `'` -- each of these is
	/// preceded by whitespace/opening punctuation exactly like a real
	/// opening quote would be, so `openingPrecedingCodeUnits` alone can't
	/// distinguish them. Checked case-insensitively against the run of
	/// letters immediately following the candidate `'`, up to the next
	/// word boundary. Hardcoded list per-decision (no NLTokenizer/
	/// NLLanguage framework involved) -- see docs/annotations.md's
	/// "British-quote conversion" section and this list's own research
	/// backing (Gruber's SmartyPants ships exactly one hardcoded
	/// exception, decades; the smart-quotes-plus Atom package ships a
	/// small curated word list for exactly this).
	private static let leadingElisions: Set<String> = [
		"cause", "til", "till", "em", "twas", "tis", "n", "round", "bout",
		"fraid", "course", "kay"
	]

	/// Scans forward from `from` for the next `'` that qualifies as an
	/// opening-candidate: start of text, or preceded by a code unit in
	/// `openingPrecedingCodeUnits`.
	private static func nextOpeningCandidate(in nsText: NSString, from: Int) -> Int? {
		var i = from
		let length = nsText.length
		while i < length {
			if nsText.character(at: i) == apostropheCodeUnit {
				if i == 0 || openingPrecedingCodeUnits.contains(nsText.character(at: i - 1)) {
					if !isLeadingElision(in: nsText, apostropheLocation: i) {
						return i
					}
				}
			}
			i += 1
		}
		return nil
	}

	/// True if the candidate opening `'` at `apostropheLocation` is
	/// immediately followed by a known leading elision (`'cause`, `'til`,
	/// `'80s`, etc.) rather than genuine dialogue -- checked against the
	/// run of letters/digits right after the `'`, up to the next word
	/// boundary (any code unit not a letter or digit).
	private static func isLeadingElision(in nsText: NSString, apostropheLocation: Int) -> Bool {
		let length = nsText.length
		var end = apostropheLocation + 1
		while end < length {
			let unit = nsText.character(at: end)
			let scalar = UnicodeScalar(unit)
			guard let scalar, CharacterSet.alphanumerics.contains(scalar) else {
				break
			}
			end += 1
		}
		guard end > apostropheLocation + 1 else { return false }

		let run = nsText.substring(with: NSRange(location: apostropheLocation + 1, length: end - apostropheLocation - 1))
		let lowercasedRun = run.lowercased()

		if leadingElisions.contains(lowercasedRun) {
			return true
		}

		// Decade pattern: '80s, '90s, '00s -- two digits followed by "s".
		if lowercasedRun.count == 3,
		   lowercasedRun.hasSuffix("s"),
		   lowercasedRun.prefix(2).allSatisfy({ $0.isNumber }) {
			return true
		}

		return false
	}

	/// Scans forward from just after `openLocation` for the next `'`
	/// that qualifies as a closing-candidate: end of text, or followed
	/// by a code unit in `closingFollowingCodeUnits`.
	private static func nextClosingCandidate(in nsText: NSString, after openLocation: Int) -> Int? {
		var i = openLocation + 1
		let length = nsText.length
		while i < length {
			if nsText.character(at: i) == apostropheCodeUnit {
				if i == length - 1 || closingFollowingCodeUnits.contains(nsText.character(at: i + 1)) {
					return i
				}
			}
			i += 1
		}
		return nil
	}
}
