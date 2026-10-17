//
//  ArticleThemeColorProbeLogicTests.swift
//  ArticleThemingTests
//
//  The probe's pure logic: decoding the read-back, alpha compositing, the
//  page, ink, link and sanity rules and hex output. No web view needed. The rendering side is
//  covered in the app's ArticleThemeColorProbeTests.
//

import Testing
import Foundation
@testable import ArticleTheming

struct ArticleThemeColorProbeLogicTests {

	private typealias Logic = ThemeColorProbeLogic

	private func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> Logic.RGBA {
		Logic.RGBA(r: r, g: g, b: b, a: a)
	}

	private func rgb(_ r: Int, _ g: Int, _ b: Int) -> Logic.RGB {
		Logic.RGB(r: r, g: g, b: b)
	}

	private func raw(html: Logic.RGBA? = nil, body: Logic.RGBA? = nil, ink: Logic.RGBA? = nil,
	                 link: Logic.RGBA? = nil, linkBackground: Logic.RGBA? = nil, dark: Bool = false, error: String? = nil) -> Logic.RawPass {
		Logic.RawPass(html: html ?? rgba(0, 0, 0, 0), body: body ?? rgba(0, 0, 0, 0),
					  ink: ink ?? rgba(0, 0, 0), link: link, dark: dark, error: error, linkBackground: linkBackground)
	}

	// MARK: Decoding

	@Test func decodesReadbackJSONWithNullLink() throws {
		let json = #"{"html":{"r":1,"g":2,"b":3,"a":255},"body":{"r":0,"g":0,"b":0,"a":0},"ink":{"r":9,"g":8,"b":7,"a":255},"link":null,"dark":true}"#
		let decoded = try JSONDecoder().decode(Logic.RawPass.self, from: Data(json.utf8))
		#expect(decoded.html == rgba(1, 2, 3))
		#expect(decoded.link == nil)
		#expect(decoded.dark == true)
		#expect(decoded.error == nil)
	}

	@Test func decodesErrorPayload() throws {
		let decoded = try JSONDecoder().decode(Logic.RawPass.self, from: Data(#"{"error":"Error: unparsable color: foo"}"#.utf8))
		#expect(decoded.error != nil)
		#expect(decoded.html == nil)
	}

	// MARK: Page color

	@Test func unpaintedPageUsesLegacyFallback() throws {
		let light = try #require(Logic.resolve(raw(ink: rgba(10, 10, 10)), requestedDark: false))
		#expect(light.page == rgb(255, 255, 255))
		#expect(light.pageWasPainted == false)
		let dark = try #require(Logic.resolve(raw(ink: rgba(240, 240, 240), dark: true), requestedDark: true))
		#expect(dark.page == rgb(0, 0, 0))
		#expect(dark.pageWasPainted == false)
	}

	@Test func htmlColorPaintsWhenBodyIsTransparent() throws {
		let result = try #require(Logic.resolve(raw(html: rgba(10, 20, 30), ink: rgba(255, 255, 255)), requestedDark: false))
		#expect(result.page == rgb(10, 20, 30))
		#expect(result.pageWasPainted)
	}

	@Test func bodyPaintsOverHtml() throws {
		let result = try #require(Logic.resolve(raw(html: rgba(10, 20, 30), body: rgba(200, 210, 220), ink: rgba(0, 0, 0)), requestedDark: false))
		#expect(result.page == rgb(200, 210, 220))
	}

	@Test func translucentBodyCompositesOntoHtmlThenFallback() throws {
		// Black at alpha 255 * 0.5 over an opaque white html is mid gray.
		let overHtml = try #require(Logic.resolve(raw(html: rgba(255, 255, 255), body: rgba(0, 0, 0, 128), ink: rgba(0, 0, 0)), requestedDark: false))
		#expect(overHtml.page == rgb(127, 127, 127))
		// Translucent html over the white fallback.
		let overFallback = try #require(Logic.resolve(raw(html: rgba(0, 0, 0, 128), ink: rgba(0, 0, 0)), requestedDark: false))
		#expect(overFallback.page == rgb(127, 127, 127))
		#expect(overFallback.pageWasPainted)
	}

	// MARK: Ink and link

	@Test func translucentInkIsCompositedOntoPage() throws {
		let result = try #require(Logic.resolve(raw(html: rgba(255, 255, 255), ink: rgba(0, 0, 0, 128)), requestedDark: false))
		#expect(result.ink == rgb(127, 127, 127))
	}

	@Test func missingLinkFallsBackToInk() throws {
		let result = try #require(Logic.resolve(raw(html: rgba(255, 255, 255), ink: rgba(20, 30, 40), link: nil), requestedDark: false))
		#expect(result.link == result.ink)
	}

	@Test func linkIsKeptWhenPresent() throws {
		let result = try #require(Logic.resolve(raw(html: rgba(255, 255, 255), ink: rgba(20, 30, 40), link: rgba(0, 0, 200)), requestedDark: false))
		#expect(result.link == rgb(0, 0, 200))
	}

	// MARK: Rejection

	@Test func appearanceMismatchInvalidatesThePass() {
		#expect(Logic.resolve(raw(dark: false), requestedDark: true) == nil)
		#expect(Logic.resolve(raw(dark: true), requestedDark: false) == nil)
	}

	@Test func missingDarkFlagInvalidatesThePass() {
		var pass = raw()
		pass.dark = nil
		#expect(Logic.resolve(pass, requestedDark: false) == nil)
	}

	@Test func scriptErrorInvalidatesThePass() {
		#expect(Logic.resolve(raw(error: "unparsable color: x"), requestedDark: false) == nil)
	}

	@Test func missingOrOutOfRangeChannelsInvalidateThePass() {
		var missingInk = raw()
		missingInk.ink = nil
		#expect(Logic.resolve(missingInk, requestedDark: false) == nil)
		#expect(Logic.resolve(raw(html: rgba(256, 0, 0)), requestedDark: false) == nil)
		#expect(Logic.resolve(raw(link: rgba(0, -1, 0)), requestedDark: false) == nil)
	}

	// MARK: Sanity

	@Test func contrastRatioMatchesWCAGExtremes() {
		#expect(abs(Logic.contrastRatio(rgb(0, 0, 0), rgb(255, 255, 255)) - 21.0) < 0.0001)
		#expect(Logic.contrastRatio(rgb(40, 40, 40), rgb(40, 40, 40)) == 1.0)
	}

	@Test func sanityRejectsInkEqualToPage() {
		let pass = Logic.PassResult(page: rgb(51, 102, 153), ink: rgb(51, 102, 153), link: rgb(0, 0, 0), pageWasPainted: true)
		#expect(!Logic.isSane(pass))
	}

	@Test func sanityRejectsLowContrastInkOrLink() {
		let page = rgb(255, 255, 255)
		let lowInk = Logic.PassResult(page: page, ink: rgb(250, 250, 250), link: rgb(0, 0, 200), pageWasPainted: true)
		#expect(!Logic.isSane(lowInk))
		let lowLink = Logic.PassResult(page: page, ink: rgb(0, 0, 0), link: rgb(250, 250, 250), pageWasPainted: true)
		#expect(!Logic.isSane(lowLink))
	}

	@Test func sanityAcceptsOrdinaryColors() {
		let pass = Logic.PassResult(page: rgb(253, 246, 227), ink: rgb(51, 51, 51), link: rgb(6, 69, 173), pageWasPainted: true)
		#expect(Logic.isSane(pass))
	}

	@Test func sanityJudgesALinkChipAgainstItsOwnBackground() {
		// White link text on a black chip over a white page (1-Bit Desktop): fine, even though the link
		// color equals the page color.
		let chip = Logic.PassResult(page: rgb(255, 255, 255), ink: rgb(0, 0, 0), link: rgb(255, 255, 255), pageWasPainted: true, linkGround: rgb(0, 0, 0))
		#expect(Logic.isSane(chip))
		// A chip that does not contrast with its text is still rejected.
		let weak = Logic.PassResult(page: rgb(255, 255, 255), ink: rgb(0, 0, 0), link: rgb(250, 250, 250), pageWasPainted: true, linkGround: rgb(255, 255, 255))
		#expect(!Logic.isSane(weak))
	}

	@Test func resolveCompositesLinkBackgroundAndIgnoresTransparentOne() throws {
		let chip = try #require(Logic.resolve(raw(body: rgba(255, 255, 255), ink: rgba(0, 0, 0), link: rgba(255, 255, 255), linkBackground: rgba(0, 0, 0)), requestedDark: false))
		#expect(chip.linkGround == rgb(0, 0, 0))
		let plain = try #require(Logic.resolve(raw(body: rgba(255, 255, 255), ink: rgba(0, 0, 0), link: rgba(0, 0, 200), linkBackground: rgba(0, 0, 0, 0)), requestedDark: false))
		#expect(plain.linkGround == nil)
	}

	// MARK: Output

	@Test func hexIsUppercaseSixDigit() {
		#expect(rgb(0, 10, 255).hex == "#000AFF")
	}

	@Test func identicalLightAndDarkHasNoDarkVariant() {
		let pass = Logic.PassResult(page: rgb(245, 245, 245), ink: rgb(17, 17, 17), link: rgb(0, 51, 204), pageWasPainted: true)
		let measurement = Logic.assemble(light: pass, dark: pass)
		#expect(measurement.hasDarkModeVariant == false)
		#expect(measurement.pageLight == "#F5F5F5")
		#expect(measurement.linkDark == "#0033CC")
	}

	@Test func anyDifferenceMeansDarkVariant() {
		let light = Logic.PassResult(page: rgb(255, 255, 255), ink: rgb(0, 0, 0), link: rgb(0, 0, 200), pageWasPainted: true)
		var dark = light
		dark.link = rgb(100, 100, 255)
		#expect(Logic.assemble(light: light, dark: dark).hasDarkModeVariant)
	}

	@Test func measurementRoundTripsThroughCodable() throws {
		let measurement = ArticleThemeColorMeasurement(
			pageLight: "#FFFFFF", pageDark: "#000000", inkLight: "#111111", inkDark: "#EEEEEE",
			linkLight: "#0000CC", linkDark: "#99CCFF",
			pageWasPaintedLight: true, pageWasPaintedDark: false, hasDarkModeVariant: true)
		let data = try JSONEncoder().encode(measurement)
		#expect(try JSONDecoder().decode(ArticleThemeColorMeasurement.self, from: data) == measurement)
	}

	@Test func readbackScriptNeverTouchesTheNetwork() {
		for needle in ["fetch(", "XMLHttpRequest", "http://", "https://", "import("] {
			#expect(!Logic.readbackScript.contains(needle), "Read-back script must not reference \(needle)")
		}
	}
}
