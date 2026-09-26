//
//  AO3LinkTests.swift
//  AO3Kit
//
//  Coverage for AO3Link: host recognition vs. credential eligibility,
//  cookie domains, work/series id parsing, URL builders, and the listing
//  classifiers (moved here from LocalAccountRefresherRoutingTests with the
//  same URLs).
//

import Foundation
import Testing
@testable import AO3Kit

private func url(_ string: String) -> URL {
	URL(string: string)!
}

// MARK: - Hosts

@Suite struct AO3LinkHostTests {

	/// AO3's own `permitted_hosts` list, copied from the fixtures. Pinned
	/// here as a literal so a change to `recognizedHosts` has to be made
	/// on purpose.
	private static let declaredHosts: Set<String> = [
		"104.153.64.122", "208.85.241.152", "208.85.241.157", "ao3.org",
		"archiveofourown.com", "archiveofourown.gay", "archiveofourown.net", "archiveofourown.org",
		"download.archiveofourown.org", "insecure.archiveofourown.org", "secure.archiveofourown.org",
		"www.archiveofourown.com", "www.archiveofourown.net", "www.archiveofourown.org",
		"www.ao3.org", "archive.transformativeworks.org"
	]

	@Test func recognizedHostsIsExactlyAO3sDeclaredList() {
		#expect(AO3Link.recognizedHosts == Self.declaredHosts)
		#expect(AO3Link.recognizedHosts.count == 16)
	}

	@Test(arguments: AO3LinkHostTests.declaredHosts)
	func everyRecognizedHostIsAccepted(host: String) {
		#expect(AO3Link.isAO3Host(host))
		#expect(AO3Link.isAO3Host(url("https://\(host)/works/1")))
	}

	@Test(arguments: [
		"https://archiveofourown.org.evil.example/works/1",
		"https://evil.example/archiveofourown.org/works/1",
		"https://notarchiveofourown.org/works/1",
		"https://sub.archiveofourown.org/works/1",
		"https://archiveofourown.org@evil.example/works/1",
		"https://example.com/works/1"
	])
	func nonRecognizedHostsAreRejected(urlString: String) {
		#expect(!AO3Link.isAO3Host(url(urlString)))
	}

	@Test func hostMatchIsCaseInsensitive() {
		#expect(AO3Link.isAO3Host(url("https://ArchiveOfOurOwn.ORG/works/1")))
		#expect(AO3Link.isAO3Host("WWW.ArchiveOfOurOwn.org"))
	}

	@Test func urlWithoutHostIsRejected() {
		#expect(!AO3Link.isAO3Host(url("/works/1")))
		#expect(!AO3Link.isAO3Host(url("mailto:someone@example.com")))
	}

	// MARK: Credential eligibility

	@Test(arguments: [
		"https://archiveofourown.org/x",
		"https://www.archiveofourown.org/x",
		"https://ao3.org/x",
		"https://archive.transformativeworks.org/x"
	])
	func httpsCredentialHostsMayReceiveSession(urlString: String) {
		#expect(AO3Link.mayReceiveSession(url(urlString)))
	}

	@Test(arguments: [
		"http://archiveofourown.org/x",
		"https://104.153.64.122/x",
		"https://insecure.archiveofourown.org/x",
		"https://download.archiveofourown.org/x",
		"https://archiveofourown.org.evil.example/x",
		"https://example.com/x"
	])
	func othersMayNotReceiveSession(urlString: String) {
		#expect(!AO3Link.mayReceiveSession(url(urlString)))
	}

	@Test func credentialHostsIsSubsetOfRecognizedHosts() {
		#expect(AO3Link.credentialHosts.isSubset(of: AO3Link.recognizedHosts))
		#expect(AO3Link.credentialHosts.count == 10)
	}

	@Test func sessionURLKeepsHTTPSAsIs() {
		let original = url("https://archiveofourown.org/users/x/subscriptions?page=2")
		#expect(AO3Link.sessionURL(for: original) == original)
	}

	@Test func sessionURLUpgradesHTTPOnCredentialHosts() {
		#expect(AO3Link.sessionURL(for: url("http://archiveofourown.org/users/x/subscriptions?page=2#top"))?.absoluteString
			== "https://archiveofourown.org/users/x/subscriptions?page=2#top")
		#expect(AO3Link.sessionURL(for: url("http://www.ao3.org/works/1"))?.absoluteString == "https://www.ao3.org/works/1")
	}

	@Test(arguments: [
		"http://archiveofourown.org:8080/x",
		"http://104.153.64.122/x",
		"http://insecure.archiveofourown.org/x",
		"https://download.archiveofourown.org/x",
		"https://archiveofourown.org.evil.example/x",
		"ftp://archiveofourown.org/x",
		"https://example.com/x"
	])
	func sessionURLRefusesEverythingElse(urlString: String) {
		#expect(AO3Link.sessionURL(for: url(urlString)) == nil)
	}

	// MARK: Cookie domains

	@Test(arguments: [
		"archiveofourown.org", ".archiveofourown.org",
		"www.archiveofourown.org", ".www.archiveofourown.org", "ao3.org", "ArchiveOfOurOwn.org"
	])
	func acceptedCookieDomains(domain: String) {
		#expect(AO3Link.isAO3CookieDomain(domain))
	}

	@Test(arguments: [
		"archiveofourown.org.evil.example", ".evil.example",
		"evilarchiveofourown.org", "104.153.64.122", "insecure.archiveofourown.org", "", "."
	])
	func rejectedCookieDomains(domain: String) {
		#expect(!AO3Link.isAO3CookieDomain(domain))
	}
}

// MARK: - Ids

@Suite struct AO3LinkIDTests {

	private static let cases: [(input: String, expected: String?)] = [
		("https://archiveofourown.org/works/123", "123"),
		("https://archiveofourown.org/works/123/", "123"),
		("https://archiveofourown.org/works/123/chapters/456", "123"),
		("https://archiveofourown.org/works/123?view_adult=true#kudos", "123"),
		("https://archiveofourown.org/works/123/bookmarks", "123"),
		("https://archiveofourown.org/collections/C/works/55", "55"),
		("https://archiveofourown.org/collections/C/works/55/chapters/1", "55"),
		("https://archiveofourown.org/works/123abc", "123"),
		("https://archiveofourown.org/works/123.", "123"),
		("https://archiveofourown.org/tags/Foo/works", nil),
		("https://archiveofourown.org/tags/Foo/works/9", nil),
		("https://archiveofourown.org/users/a/works/77", nil),
		("https://archiveofourown.org/login?return_to=/works/999", nil),
		("https://archiveofourown.org/works/", nil),
		("https://archiveofourown.org/works/abc", nil),
		("https://archiveofourown.org/works/\u{0663}", nil),
		("https://example.com/works/123", nil),
		("/works/123", nil),
		("", nil)
	]

	@Test func workIDFromPermalinkTable() {
		for (input, expected) in Self.cases {
			#expect(AO3Link.workID(fromPermalink: input) == expected, "input: \(input)")
		}
		#expect(AO3Link.workID(fromPermalink: nil) == nil)
	}

	@Test func workIDFromPermalinkTrimsWhitespace() {
		#expect(AO3Link.workID(fromPermalink: "  https://archiveofourown.org/works/123 \n") == "123")
	}

	@Test func workIDFromURLMatchesPermalinkForm() {
		for (input, expected) in Self.cases {
			guard let parsed = URL(string: input) else { continue }
			#expect(AO3Link.workID(from: parsed) == expected, "input: \(input)")
		}
	}

	@Test(arguments: AO3Link.recognizedHosts)
	func everyRecognizedHostYieldsAWorkID(host: String) {
		#expect(AO3Link.workID(fromPermalink: "https://\(host)/works/1") == "1")
	}

	@Test func seriesIDFromHref() {
		#expect(AO3Link.seriesID(fromHref: "/series/45") == "45")
		#expect(AO3Link.seriesID(fromHref: "https://archiveofourown.org/series/45?page=2") == "45")
		#expect(AO3Link.seriesID(fromHref: "/series/") == nil)
		#expect(AO3Link.seriesID(fromHref: "/series/abc") == nil)
		#expect(AO3Link.seriesID(fromHref: "/works/1") == nil)
		#expect(AO3Link.seriesID(fromHref: "/users/a/series/45") == nil)
		#expect(AO3Link.seriesID(fromHref: nil) == nil)
	}
}

// MARK: - Builders

@Suite struct AO3LinkBuilderTests {

	@Test func workURLPlain() {
		#expect(AO3Link.workURL(id: "123")?.absoluteString == "https://archiveofourown.org/works/123")
	}

	/// Expected string copied from the literal `AO3ChapterFetcher.download`
	/// built before this type existed, not derived from the new code.
	@Test func workURLFullWorkAdultMatchesTodaysLiteral() {
		#expect(AO3Link.workURL(id: "123", fullWork: true, adultView: true)?.absoluteString
			== "https://archiveofourown.org/works/123?view_full_work=true&view_adult=true")
	}

	@Test func seriesURLPageOneOmitsPage() {
		#expect(AO3Link.seriesURL(id: "45")?.absoluteString == "https://archiveofourown.org/series/45")
		#expect(AO3Link.seriesURL(id: "45", page: 1)?.absoluteString == "https://archiveofourown.org/series/45")
		#expect(AO3Link.seriesURL(id: "45", page: 0)?.absoluteString == "https://archiveofourown.org/series/45")
	}

	@Test func seriesURLPageTwoAddsPage() {
		#expect(AO3Link.seriesURL(id: "45", page: 2)?.absoluteString == "https://archiveofourown.org/series/45?page=2")
	}

	@Test(arguments: ["", "12a", "1/2", "1?x", "1#x", " 1", "\u{0663}", "../1", "1\n"])
	func buildersRejectMalformedIDs(id: String) {
		#expect(AO3Link.workURL(id: id) == nil)
		#expect(AO3Link.seriesURL(id: id) == nil)
		#expect(AO3Link.workReferer(id: id) == nil)
	}

	@Test func kudosURLIsKudosJS() {
		#expect(AO3Link.kudosURL.absoluteString == "https://archiveofourown.org/kudos.js")
	}

	@Test func workRefererIsThePlainWorkURL() {
		#expect(AO3Link.workReferer(id: "12345") == "https://archiveofourown.org/works/12345")
	}

	@Test func absoluteURLPassesThroughHTTPAndHTTPS() {
		#expect(AO3Link.absoluteURL("https://archiveofourown.org/works/1") == "https://archiveofourown.org/works/1")
		#expect(AO3Link.absoluteURL("http://example.com/x") == "http://example.com/x")
	}

	@Test func absoluteURLResolvesRelativeForms() {
		#expect(AO3Link.absoluteURL("/works/1") == "https://archiveofourown.org/works/1")
		#expect(AO3Link.absoluteURL("works/1") == "https://archiveofourown.org/works/1")
	}

	/// Pinned so the behavior stays deliberate: `//host/x` is not a
	/// protocol-relative jump, it stays on AO3 with a double slash.
	@Test func absoluteURLDoubleSlashStaysOnAO3() {
		#expect(AO3Link.absoluteURL("//evil.example/x") == "https://archiveofourown.org//evil.example/x")
	}

	@Test func absoluteURLNilAndEmpty() {
		#expect(AO3Link.absoluteURL(nil) == nil)
		#expect(AO3Link.absoluteURL("") == nil)
	}
}

// MARK: - Listing classifiers

@Suite struct AO3LinkClassifierTests {

	private static let listingURLs = [
		"https://archiveofourown.org/tags/Some%20Fandom/works",
		"https://archiveofourown.org/works?work_search%5Bquery%5D=test",
		"https://archiveofourown.org/users/someauthor/works",
		"https://archiveofourown.org/users/someauthor/pseuds/somepseud/works",
		"https://archiveofourown.org/users/someuser/bookmarks",
		"https://archiveofourown.org/users/someuser/readings?show=to-read",
		"https://archiveofourown.org/users/someuser/subscriptions",
		"https://archiveofourown.org/users/someuser/subscriptions/",
		"https://archiveofourown.org/users/someuser/subscriptions?page=2",
		"https://archiveofourown.org/collections/SomeCollection/works",
		"https://archiveofourown.org/series/348731",
		"https://www.archiveofourown.org/users/someuser/subscriptions",
		"https://archiveofourown.com/series/348731"
	]

	private static let nonListingURLs = [
		"https://archiveofourown.org/works",
		"https://archiveofourown.org/works?page=2",
		"https://archiveofourown.org/users/someuser/readings",
		"https://archiveofourown.org/users/someuser/readings?show=all",
		"https://archiveofourown.org/series/recommended",
		"https://archiveofourown.org/series/",
		"https://example.com/users/someuser/subscriptions",
		"https://example.com/series/348731",
		"https://archiveofourown.org.evil.example/users/someuser/subscriptions"
	]

	private static let alwaysAuthenticatedURLs = [
		"https://archiveofourown.org/users/someuser/subscriptions",
		"https://archiveofourown.org/users/someuser/readings?show=to-read"
	]

	private static let notAlwaysAuthenticatedURLs = [
		"https://archiveofourown.org/users/someuser/bookmarks",
		"https://archiveofourown.org/users/someuser/works",
		"https://archiveofourown.org/series/348731",
		"https://archiveofourown.org/collections/SomeCollection/works",
		"https://archiveofourown.org/tags/Some%20Fandom/works",
		"https://archiveofourown.org/works?work_search%5Bquery%5D=test",
		"https://example.com/users/someuser/subscriptions",
		"https://example.com/users/someuser/readings?show=to-read"
	]

	@Test(arguments: AO3LinkClassifierTests.listingURLs)
	func listingShapesMatch(urlString: String) {
		#expect(AO3Link.isListingFeed(url(urlString)))
	}

	@Test(arguments: AO3LinkClassifierTests.nonListingURLs)
	func nonListingShapesDoNotMatch(urlString: String) {
		#expect(!AO3Link.isListingFeed(url(urlString)))
	}

	/// `AO3SeriesListingExtractor`/`AO3SeriesNavigator` operate on this same
	/// series URL shape; the classifier must agree it is a series URL.
	@Test func seriesURLShapeMatchesWhatInlineNavigationOperatesOn() {
		#expect(AO3Link.isListingFeed(url("https://archiveofourown.org/series/348731")))
		#expect(AO3Link.seriesURL(id: "348731").map(AO3Link.isListingFeed) == true)
	}

	@Test(arguments: AO3LinkClassifierTests.alwaysAuthenticatedURLs)
	func alwaysAuthenticatedShapesMatch(urlString: String) {
		#expect(AO3Link.isAlwaysAuthenticatedListing(url(urlString)))
	}

	@Test(arguments: AO3LinkClassifierTests.notAlwaysAuthenticatedURLs)
	func otherShapesAreNotAlwaysAuthenticated(urlString: String) {
		#expect(!AO3Link.isAlwaysAuthenticatedListing(url(urlString)))
	}

	/// Closes the missing host check the two old copies of this classifier
	/// had: a non-AO3 host is never "always authenticated".
	@Test func alwaysAuthenticatedRequiresAO3Host() {
		#expect(!AO3Link.isAlwaysAuthenticatedListing(url("https://example.com/users/x/subscriptions")))
	}

	@Test func alwaysAuthenticatedIsSubsetOfListing() {
		let corpus = Self.listingURLs + Self.nonListingURLs + Self.alwaysAuthenticatedURLs + Self.notAlwaysAuthenticatedURLs
		for string in corpus {
			let candidate = url(string)
			if AO3Link.isAlwaysAuthenticatedListing(candidate) {
				#expect(AO3Link.isListingFeed(candidate), "\(string)")
			}
		}
	}
}

// MARK: - bookKey helpers

@Suite struct AO3LinkBookKeyTests {

	@Test func workIDFromBookKeyAcceptsWorkKey() {
		#expect(AO3Link.workID(fromBookKey: "ao3-work:1") == "1")
	}

	@Test(arguments: ["ao3-work:", "ao3-series:1", "calibre-series:x", "ambrosia-book-1", ""])
	func workIDFromBookKeyRejectsOthers(bookKey: String) {
		#expect(AO3Link.workID(fromBookKey: bookKey) == nil)
	}

	@Test(arguments: ["", "1?x", "1/2", "\u{0663}"]) // "\u{0663}" is an Arabic-Indic digit, not ASCII
	func workBookKeyRejectsBadIDs(id: String) {
		#expect(AO3Link.workBookKey(forWorkID: id) == nil)
	}

	@Test func workBookKeyRoundTrips() {
		let bookKey = AO3Link.workBookKey(forWorkID: "12345")
		#expect(bookKey == "ao3-work:12345")
		#expect(bookKey.flatMap(AO3Link.workID(fromBookKey:)) == "12345")
	}
}
