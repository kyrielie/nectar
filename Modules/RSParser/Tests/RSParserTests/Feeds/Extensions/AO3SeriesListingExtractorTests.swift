//
//  AO3SeriesListingExtractorTests.swift
//  RSParser
//
//  Created for the Nectar fork.
//

import Foundation
import Testing
@testable import RSParser

@Suite struct AO3SeriesListingExtractorTests {

	@Test func firstWorkPermalinkOnRealCapturedSeries() {
		// archiveofourown.org/series/348731, "for all of the perfect
		// things that i doubt" -- Part 1 is work 4436639 (see this
		// extractor's own header comment).
		let html = htmlFixtureString("ao3-series-listing.html")
		let permalink = AO3SeriesListingExtractor.firstWorkPermalink(fromSeriesListingHTML: html)
		#expect(permalink == "https://archiveofourown.org/works/4436639")
	}

	@Test func nilOnPageWithNoWorkRows() {
		let permalink = AO3SeriesListingExtractor.firstWorkPermalink(fromSeriesListingHTML: "<html><body><p>This series has no works yet.</p></body></html>")
		#expect(permalink == nil)
	}
}
