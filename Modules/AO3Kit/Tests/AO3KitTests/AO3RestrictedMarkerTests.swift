//
//  AO3RestrictedMarkerTests.swift
//  AO3Kit
//
//  Created for the Nectar fork.
//

import Foundation
import Testing
@testable import AO3Kit

@Suite struct AO3RestrictedMarkerTests {

	private func element(_ tag: String, _ attributes: [String: String]) -> HTMLLiteElement {
		HTMLLiteElement(tag: tag, attributes: attributes, selfClosing: true)
	}

	@Test func matchesTitleAttribute() {
		#expect(AO3HTMLHelpers.isRestrictedMarker(element("img", ["title": "Restricted"])))
	}

	@Test func matchesAltAttribute() {
		#expect(AO3HTMLHelpers.isRestrictedMarker(element("img", ["alt": "(Restricted)"])))
	}

	@Test func matchIsCaseInsensitive() {
		#expect(AO3HTMLHelpers.isRestrictedMarker(element("img", ["title": "RESTRICTED"])))
	}

	@Test func doesNotMatchOnSrcAlone() {
		#expect(!AO3HTMLHelpers.isRestrictedMarker(element("img", ["src": "/images/lockblue.png"])))
	}

	@Test func doesNotMatchNonImageElement() {
		#expect(!AO3HTMLHelpers.isRestrictedMarker(element("span", ["title": "Restricted"])))
	}

	@Test func doesNotMatchUnrelatedImage() {
		#expect(!AO3HTMLHelpers.isRestrictedMarker(element("img", ["alt": "Cover art", "title": "Cover"])))
	}

	@Test func blurbFixtureContainsLockMarker() {
		let root = parseHTMLLiteTree(htmlFixtureString("ao3-search-results-tdwp.html"))
		#expect(!descendants(of: root, where: AO3HTMLHelpers.isRestrictedMarker).isEmpty)
	}

	@Test func syntheticWorkFixtureContainsLockMarker() {
		// Synthetic: single-chapter fixture with the lock injected.
		let root = parseHTMLLiteTree(htmlFixtureString("ao3-work-restricted-synthetic.html"))
		#expect(descendants(of: root, where: AO3HTMLHelpers.isRestrictedMarker).count == 1)
	}
}
