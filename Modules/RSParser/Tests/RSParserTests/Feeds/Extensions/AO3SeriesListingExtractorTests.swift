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

	// MARK: - workPermalinks (Phase 4a)

	/// `ao3-series-listing.html` is a single-page capture -- confirmed via
	/// `grep -c 'work-[0-9]*'`: **10** work rows are present. (An earlier
	/// version of this file's own header comment described the real
	/// archiveofourown.org/series/348731 series as having more works than
	/// that; that description was never about this checked-in fixture,
	/// which only captured page 1's 10 rows -- fixed rather than repeated
	/// here.)
	@Test func workPermalinksParsesAllTenRowsInDocumentOrder() {
		let html = htmlFixtureString("ao3-series-listing.html")
		let (works, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)

		#expect(works.count == 10)
		#expect(works.first?.workID == "4436639")
		#expect(works.first?.permalink == "https://archiveofourown.org/works/4436639")
		#expect(works.first?.title == "maybe i'm waking up")
		#expect(works.last?.workID == "7375126")
		#expect(works.last?.title == "no lightning, just thunder")

		// No `li.next` pagination widget on this single-page capture.
		#expect(hasNextPage == false)
		#expect(totalPages == nil)
	}

	/// Listing-metadata follow-up: `workPermalinks` now reuses
	/// `AO3SearchResultsExtractor`'s row-metadata helpers against the
	/// identical row shape, so the same fixture's first row (work
	/// 4436639, "maybe i'm waking up") should carry summary/fandom/tag/
	/// word-count data too, not just the original bare
	/// `(workID, permalink, title)`. Values below read directly off the
	/// fixture's own markup for that row.
	@Test func workPermalinksParsesRichMetadataFromRealCapturedRow() throws {
		let html = htmlFixtureString("ao3-series-listing.html")
		let (works, _, _) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)

		let first = try #require(works.first)
		#expect(first.workID == "4436639")
		#expect(first.wordCount == 157904)
		#expect(first.fandoms == ["Check Please! (Webcomic)"])
		#expect(first.ratings == ["Mature"])
		#expect(first.categories == ["M/M"])
		#expect(first.warnings == ["No Archive Warnings Apply"])
		#expect(first.summary?.isEmpty == false)
		#expect(first.freeformTags.contains("Angst"))
		#expect(first.characters.contains("Eric Bittle"))
		#expect(first.relationships.contains("Eric Bittle/Jack Zimmermann"))
	}

	@Test func workPermalinksReturnsEmptyOnPageWithNoWorkRows() {
		let (works, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: "<html><body><p>This series has no works yet.</p></body></html>")
		#expect(works.isEmpty)
		#expect(hasNextPage == false)
		#expect(totalPages == nil)
	}

	/// `longseries.html`: a real captured page 1 of
	/// archiveofourown.org/series/1207269 ("always in tandem", confirmed
	/// via the page's own `<dd class="works">133</dd>` stats row -- a
	/// genuine 133-work, 7-page series, 20 work rows per page here).
	/// Confirms `hasNextPage` reads a real, live `li.next > a[href]`
	/// (`?page=2`) rather than only the synthetic markup below -- direct
	/// coverage for the true case Phase 4c's own two-fetch-cap math
	/// depends on (`pageSize` is derived from this page's own row count,
	/// not hardcoded).
	@Test func workPermalinksOnRealMultiPageSeriesFirstPage() {
		let html = htmlFixtureString("longseries.html")
		let (works, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)

		#expect(works.count == 20)
		#expect(works.first?.workID == "6922927")
		#expect(works.first?.permalink == "https://archiveofourown.org/works/6922927")
		#expect(works.first?.title == "holy, holy")
		#expect(works.last?.workID == "8711230")
		#expect(works.last?.title == "new romantics")

		#expect(hasNextPage == true)
		#expect(totalPages == 7)
	}

	@Test func totalPagesOnRealLastPageCapture() {
		let html = htmlFixtureString("ao3-series-nav-lastpage.html")
		let (_, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)

		#expect(hasNextPage == false)
		#expect(totalPages == 3)
	}

	@Test func totalPagesNilOnRealSinglePageSeriesCapture() {
		let html = htmlFixtureString("ao3-series-nav-43794-page1.html")
		let (works, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)

		#expect(works.map(\.workID) == ["779826", "779835", "779840", "1836235", "2085420"])
		#expect(hasNextPage == false)
		#expect(totalPages == nil)
	}

	/// Confirms `hasNextPage` reads a live `li.next > a[href]` the same
	/// way `AO3SearchResultsExtractor.hasNextPage(_:)` already does --
	/// synthetic markup, for the false case a single-page fixture can't
	/// otherwise exercise directly (no captured real last-page sample is
	/// on hand -- see `AO3ListingPagination`'s own doc comment). Marked
	/// as such, per the project's "don't assert on guessed real-world
	/// markup" rule -- this only exercises the selector, not a claim
	/// about AO3's actual last-page shape.
	@Test func hasNextPageTrueWithLiveNextLink() {
		let html = """
		<html><body>
		<ol class="pagination actions" role="navigation">
		<li class="next"><a rel="next" href="/series/348731?page=2">Next →</a></li>
		</ol>
		<ul class="series work index group">
		<li id="work_1" class="work blurb group work-1 user-1" role="article">
		<h4 class="heading"><a href="/works/1">Only work on page one</a></h4>
		</li>
		</ul>
		</body></html>
		"""
		let (works, hasNextPage, totalPages) = AO3SeriesListingExtractor.workPermalinks(fromSeriesListingHTML: html)
		#expect(works.count == 1)
		#expect(hasNextPage == true)
		#expect(totalPages == nil)
	}
}
