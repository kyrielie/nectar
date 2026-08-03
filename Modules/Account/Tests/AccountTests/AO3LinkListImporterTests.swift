//
//  AO3LinkListImporterTests.swift
//  AccountTests
//
//  Nectar AO3 direct-reading support -- pasted-link-list import (Task 3).
//

import XCTest
@testable import Account

final class AO3LinkListImporterTests: XCTestCase {

	// MARK: - Recognized links

	func testSingleWorkLink() {
		let text = "Check out this fic: https://archiveofourown.org/works/12345678"
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.count, 1)
		XCTAssertEqual(links.first?.ao3WorkID, "12345678")
		XCTAssertEqual(links.first?.permalink, "https://archiveofourown.org/works/12345678")
	}

	func testChapterSpecificLinkStillExtractsWorkID() {
		// AO3SummaryExtractor.ao3WorkID(fromPermalink:) already handles
		// chapter-specific URLs -- reused here, not reimplemented.
		let text = "https://archiveofourown.org/works/12345678/chapters/98765432"
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.count, 1)
		XCTAssertEqual(links.first?.ao3WorkID, "12345678")
	}

	func testMultipleDistinctLinks() {
		let text = """
		Some recs:
		https://archiveofourown.org/works/111
		https://archiveofourown.org/works/222
		https://www.archiveofourown.org/works/333
		"""
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.map(\.ao3WorkID), ["111", "222", "333"])
	}

	// MARK: - Dedup

	func testDuplicateWorkIDsAreDeduped() {
		let text = """
		https://archiveofourown.org/works/12345678
		Check this one too: https://archiveofourown.org/works/12345678/chapters/1
		"""
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.count, 1)
		XCTAssertEqual(links.first?.ao3WorkID, "12345678")
	}

	func testFirstOccurrenceWinsOnDuplicate() {
		let text = """
		https://archiveofourown.org/works/12345678
		https://archiveofourown.org/works/12345678/chapters/999
		"""
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.count, 1)
		// The plain work permalink (first occurrence) is kept, not the chapter-specific one.
		XCTAssertEqual(links.first?.permalink, "https://archiveofourown.org/works/12345678")
	}

	// MARK: - Host allowlist

	func testKnownAO3HostVariantsAreAccepted() {
		let hosts = [
			"archiveofourown.org", "www.archiveofourown.org",
			"ao3.org", "www.ao3.org",
			"archiveofourown.com", "archiveofourown.net",
			"archiveofourown.gay",
			"download.archiveofourown.org", "insecure.archiveofourown.org", "secure.archiveofourown.org",
			"archive.transformativeworks.org"
		]
		for host in hosts {
			let text = "https://\(host)/works/42"
			let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
			XCTAssertEqual(links.count, 1, "expected a match for host \(host)")
		}
	}

	func testBareIPHostsAreAccepted() {
		for ip in ["104.153.64.122", "208.85.241.152", "208.85.241.157"] {
			let text = "http://\(ip)/works/42"
			let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
			XCTAssertEqual(links.count, 1, "expected a match for IP \(ip)")
		}
	}

	func testMirrorOrProxyHostsAreRejected() {
		// Explicitly not on the allowlist -- AO3 disclaims responsibility for
		// mirrors/proxies, and treating them as "known AO3" would work against that.
		let text = "https://archiveofourown.org.some-mirror.example/works/42"
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertTrue(links.isEmpty)
	}

	func testUnrelatedHostsAreIgnored() {
		let text = """
		https://example.com/works/12345678
		https://fanfiction.net/s/12345678/1/Some-Fic
		"""
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertTrue(links.isEmpty)
	}

	// MARK: - Non-work links and junk

	func testNonWorkAO3LinksAreIgnored() {
		// A valid AO3 host, but no /works/ path -- ao3WorkID(fromPermalink:) returns nil.
		let text = "https://archiveofourown.org/users/someone/pseuds/someone"
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertTrue(links.isEmpty)
	}

	func testPlainTextWithNoLinksReturnsEmpty() {
		let text = "just some notes, no links here at all"
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertTrue(links.isEmpty)
	}

	func testEmptyStringReturnsEmpty() {
		XCTAssertTrue(AO3LinkListImporter.importedLinks(fromPastedText: "").isEmpty)
	}

	func testMixedKnownAndUnknownHostsOnlyKeepsKnown() {
		let text = """
		https://example.com/works/999
		https://archiveofourown.org/works/111
		https://fanfiction.net/s/222
		https://archiveofourown.org/works/333
		"""
		let links = AO3LinkListImporter.importedLinks(fromPastedText: text)
		XCTAssertEqual(links.map(\.ao3WorkID), ["111", "333"])
	}
}
