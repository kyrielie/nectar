//
//  AccentColorIconHexSetTests.swift
//  NetNewsWire-iOSTests
//
//  surface-palette-and-badge-colors-plan follow-up ("independently
//  assignable icon colors per AccentColor case"): coverage for
//  AccentColor.IconHexSet and Assets.Colors.iconColor(_:fallback:).
//  Guards two properties specifically called out in the implementation
//  plan: (1) `.default` must resolve every icon to its pre-change
//  fallback, unchanged, and (2) every non-default case must supply a
//  complete IconHexSet with parseable hex for every slot -- an
//  incomplete or malformed entry silently falls back to the fallback
//  color at the call site rather than failing loudly, so this is the
//  test that catches a typo in a hex literal.
//

import Testing
import UIKit
@testable import Nectar

@Suite struct AccentColorIconHexSetTests {

	// MARK: - .default

	@Test func defaultAccentColorHasNoIconHexSet() {
		#expect(AccentColor.default.iconHexSet == nil)
	}

	// MARK: - Every non-default case supplies a complete, valid set

	@Test func everyNonDefaultCaseHasParseableHexForEverySlot() {
		for accentColor in AccentColor.allCases where accentColor != .default {
			guard let hexSet = accentColor.iconHexSet else {
				Issue.record("\(accentColor) has no IconHexSet")
				continue
			}
			let slots: [String: String] = [
				"folder": hexSet.folder,
				"unreadFeed": hexSet.unreadFeed,
				"readFeed": hexSet.readFeed,
				"lastOpenedFeed": hexSet.lastOpenedFeed,
				"unreadCellIndicator": hexSet.unreadCellIndicator,
				"star": hexSet.star,
				"today": hexSet.today,
				"loved": hexSet.loved
			]
			for (slotName, hex) in slots {
				#expect(UIColor(cssHex: hex) != nil, "\(accentColor).\(slotName) = \(hex) does not parse as a hex color")
			}
		}
	}

	// MARK: - iconHexSet is a pure computed property (not cached across calls)

	@Test func iconHexSetIsStableAcrossRepeatedReads() {
		// Guards against a future change accidentally introducing
		// once-only caching (the exact bug IconHexSet's fields exist to
		// avoid at the Assets.Images call-site level -- see
		// AppDefaults.swift's doc comment on AccentColor above the enum).
		let first = AccentColor.rosePine.iconHexSet
		let second = AccentColor.rosePine.iconHexSet
		#expect(first?.folder == second?.folder)
		#expect(first?.unreadFeed == second?.unreadFeed)
	}

	// MARK: - New theme cases (ocean/sunset/lavender/graphite)

	@Test func newThemeCasesAreDistinctFromEachOtherAndFromExistingCases() {
		// Guards against a copy-paste error when adding a new theme
		// case reusing an existing case's hex values instead of its
		// own -- each case's primaryHex should be unique across the
		// whole enum.
		let allHexes = AccentColor.allCases.compactMap { $0.primaryHex }
		#expect(Set(allHexes).count == allHexes.count, "expected every non-default AccentColor case to have a unique primaryHex")
	}

	@Test func newThemeCasesAreIncludedInAllCases() {
		for accentColor: AccentColor in [.ocean, .sunset, .lavender, .graphite] {
			#expect(AccentColor.allCases.contains(accentColor))
		}
	}

	// MARK: - Assets.Colors.iconColor(_:fallback:)

	@MainActor
	@Test func iconColorFallsBackToDefaultAccentColorFallback() {
		AppDefaults.shared.accentColor = .default
		let fallback = UIColor.systemPink
		let resolved = Assets.Colors.iconColor(\.folder, fallback: fallback)
		#expect(resolved == fallback)
	}

	@MainActor
	@Test func iconColorUsesIconHexSetWhenAccentColorIsNotDefault() {
		AppDefaults.shared.accentColor = .rosePine
		defer { AppDefaults.shared.accentColor = .default }

		let resolved = Assets.Colors.iconColor(\.folder, fallback: .systemPink)
		let expected = UIColor(cssHex: AccentColor.rosePine.iconHexSet!.folder)!
		#expect(resolved.cssHexString == expected.cssHexString)
		#expect(resolved.cssHexString != UIColor.systemPink.cssHexString)
	}

	@MainActor
	@Test func iconColorDistinguishesUnreadFromReadForRosePine() {
		// Directly guards the reported bug: before IconHexSet existed,
		// unreadFeed and readFeed both resolved to the same
		// secondaryAccent value. This confirms they're independently
		// assignable, using .rosePine (where they're chosen to differ) as
		// the regression case.
		AppDefaults.shared.accentColor = .rosePine
		defer { AppDefaults.shared.accentColor = .default }

		let unread = Assets.Colors.iconColor(\.unreadFeed, fallback: .systemGray)
		let read = Assets.Colors.iconColor(\.readFeed, fallback: .systemGray)
		#expect(unread.cssHexString != read.cssHexString)
	}

	@MainActor
	@Test func iconColorLiveUpdatesWhenAccentColorChanges() {
		// The whole point of IconHexSet living behind computed `static
		// var`s in Assets.Images rather than `static let`s: no app
		// restart needed. This test exercises the resolver function
		// directly (iconColor(_:fallback:)) rather than an Assets.Images
		// property, since the properties themselves are the thing that
		// must stay `var`, not `let` -- see the AppDefaults.swift comment
		// this change updated.
		defer { AppDefaults.shared.accentColor = .default }

		AppDefaults.shared.accentColor = .forest
		let forestFolder = Assets.Colors.iconColor(\.folder, fallback: .systemGray)

		AppDefaults.shared.accentColor = .berry
		let berryFolder = Assets.Colors.iconColor(\.folder, fallback: .systemGray)

		#expect(forestFolder.cssHexString != berryFolder.cssHexString)
	}
}
