//
//  AO3Link.swift
//  AO3Kit
//
//  The one place that decides what an AO3 URL is: which hosts count as AO3,
//  which of those may be sent a stored credential, how work/series ids are
//  read out of a link, how AO3 URLs are built, and which listing shapes a
//  feed URL can have. Pure static functions and `Sendable` constants; no
//  state, no networking.
//
//  Recognizing a link as AO3 and trusting a host with a cookie are different
//  jobs, so there are two host lists (see `recognizedHosts` and
//  `credentialHosts`).
//

import Foundation
import RSParser

public enum AO3Link {

	/// The host every URL this app builds itself points at.
	public static let canonicalHost = "archiveofourown.org"

	private static let baseURLString = "https://archiveofourown.org"

	// MARK: - Hosts

	/// Every host AO3 itself declares as "the Archive" (the
	/// `permitted_hosts` list in its own work-skin proxy-detection script;
	/// the work and series pages in `AO3KitTests/Resources` embed it, and it
	/// is cross-checked against AO3's public Accessing Fanworks FAQ). Used to
	/// RECOGNIZE a link or feed as AO3, never on its own to decide where a
	/// credential may go -- see `credentialHosts`. Exact match only (no
	/// subdomain or suffix matching), case-insensitive. Deliberately
	/// excludes mirror/proxy domains: AO3 itself disclaims responsibility
	/// for those. The three raw IPs are AO3's own published server
	/// addresses, not Ambrosia's.
	public static let recognizedHosts: Set<String> = [
		"104.153.64.122", "208.85.241.152", "208.85.241.157",
		"ao3.org", "www.ao3.org",
		"archiveofourown.com", "www.archiveofourown.com",
		"archiveofourown.net", "www.archiveofourown.net",
		"archiveofourown.org", "www.archiveofourown.org",
		"archiveofourown.gay",
		"download.archiveofourown.org", "insecure.archiveofourown.org", "secure.archiveofourown.org",
		"archive.transformativeworks.org"
	]

	/// Hosts that may be sent a stored AO3 cookie. A subset of
	/// `recognizedHosts`: it leaves out the three raw IPs (a raw IP cannot
	/// present a hostname-matched certificate), `insecure.` (its name
	/// states its purpose, non-TLS access) and `download.` (serves files,
	/// not logged-in pages). Requests to these must also be HTTPS -- see
	/// `mayReceiveSession(_:)`.
	public static let credentialHosts: Set<String> = [
		"ao3.org", "www.ao3.org",
		"archiveofourown.com", "www.archiveofourown.com",
		"archiveofourown.net", "www.archiveofourown.net",
		"archiveofourown.org", "www.archiveofourown.org",
		"archiveofourown.gay",
		"archive.transformativeworks.org"
	]

	/// `url`'s host is one of `recognizedHosts`.
	public static func isAO3Host(_ url: URL) -> Bool {
		guard let host = url.host() else {
			return false
		}
		return isAO3Host(host)
	}

	public static func isAO3Host(_ host: String) -> Bool {
		recognizedHosts.contains(host.lowercased())
	}

	/// `url` is HTTPS and on one of `credentialHosts`. The single gate every
	/// request carrying a stored AO3 cookie must pass, including each
	/// redirect hop.
	public static func mayReceiveSession(_ url: URL) -> Bool {
		guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else {
			return false
		}
		return credentialHosts.contains(host)
	}

	/// The URL a session-bearing request for `url` should actually use, or
	/// nil if `url` is not on a credential host at all. An `http` URL on a
	/// credential host (a feed pasted as `http://archiveofourown.org/...`
	/// is stored verbatim) is upgraded to `https` rather than refused, so
	/// such a feed keeps working while the cookie never travels in
	/// cleartext. A URL with an explicit port is not upgraded (nil), since
	/// swapping the scheme would leave the port pointing at the wrong
	/// service.
	public static func sessionURL(for url: URL) -> URL? {
		guard let host = url.host()?.lowercased(), credentialHosts.contains(host) else {
			return nil
		}
		switch url.scheme?.lowercased() {
		case "https":
			return url
		case "http":
			guard url.port == nil, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
				return nil
			}
			components.scheme = "https"
			return components.url
		default:
			return nil
		}
	}

	/// Whether a cookie captured from a `WKWebView` belongs to an AO3
	/// credential host. WebKit reports domains both with and without a
	/// leading dot (`.archiveofourown.org` / `archiveofourown.org`); one
	/// leading dot is ignored, the rest must match `credentialHosts`
	/// exactly (so `archiveofourown.org.evil.example` does not).
	public static func isAO3CookieDomain(_ domain: String) -> Bool {
		var normalized = domain.lowercased()
		if normalized.hasPrefix(".") {
			normalized.removeFirst()
		}
		return credentialHosts.contains(normalized)
	}

	// MARK: - Ids

	/// The work id in an AO3 work URL. Requires an AO3 host and a path that
	/// begins `/works/<id>` or `/collections/<name>/works/<id>`; only the
	/// path takes part, so a query or fragment naming `/works/...`
	/// (`/login?return_to=/works/9`) never yields an id, and neither do
	/// `/tags/x/works/9` or `/users/x/works/9`. From `<id>` the leading run
	/// of ASCII digits is used and any trailing text ignored (`123abc` is
	/// `123`), because pasted links are messy.
	public static func workID(from url: URL) -> String? {
		guard isAO3Host(url) else {
			return nil
		}
		let components = pathComponents(of: url)
		if components.count >= 2, components[0] == "works" {
			return leadingASCIIDigits(of: components[1])
		}
		if components.count >= 4, components[0] == "collections", components[2] == "works" {
			return leadingASCIIDigits(of: components[3])
		}
		return nil
	}

	/// `workID(from:)` for the `String?` call shape feed entries and pasted
	/// text have. Trims surrounding whitespace first; a string that is not
	/// an absolute AO3 URL (including a host-less `/works/123`) is nil.
	public static func workID(fromPermalink permalink: String?) -> String? {
		guard let trimmed = permalink?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !trimmed.isEmpty,
			  let url = URL(string: trimmed) else {
			return nil
		}
		return workID(from: url)
	}

	/// The series id in an `/series/<id>` href. Deliberately does not check
	/// the host: it is fed raw markup hrefs like `/series/45`.
	public static func seriesID(fromHref href: String?) -> String? {
		guard let href, let url = URL(string: href) else {
			return nil
		}
		let components = pathComponents(of: url)
		guard components.count >= 2, components[0] == "series" else {
			return nil
		}
		return leadingASCIIDigits(of: components[1])
	}

	// MARK: - Builders

	/// `https://archiveofourown.org/works/<id>`, optionally with the
	/// `view_full_work` / `view_adult` query items (in that order). Nil
	/// unless `id` is one or more ASCII digits, so an id carrying `?`, `#`
	/// or `/` fails the request instead of altering it.
	public static func workURL(id: String, fullWork: Bool = false, adultView: Bool = false) -> URL? {
		guard isDigitsOnly(id) else {
			return nil
		}
		var queryItems: [URLQueryItem] = []
		if fullWork {
			queryItems.append(URLQueryItem(name: "view_full_work", value: "true"))
		}
		if adultView {
			queryItems.append(URLQueryItem(name: "view_adult", value: "true"))
		}
		return canonicalURL(path: "/works/\(id)", queryItems: queryItems)
	}

	/// `https://archiveofourown.org/series/<id>`, with `?page=<n>` only for
	/// `page > 1` (AO3's page-1-is-the-bare-URL convention). Nil unless `id`
	/// is one or more ASCII digits.
	public static func seriesURL(id: String, page: Int = 1) -> URL? {
		guard isDigitsOnly(id) else {
			return nil
		}
		let queryItems = page > 1 ? [URLQueryItem(name: "page", value: String(page))] : []
		return canonicalURL(path: "/series/\(id)", queryItems: queryItems)
	}

	/// AO3's `.js` (XHR) kudos endpoint.
	public static let kudosURL = URL(string: "https://archiveofourown.org/kudos.js")!

	/// The `referer` value the kudos POST sends for `id`: the work's plain
	/// URL. Nil for a malformed id.
	public static func workReferer(id: String) -> String? {
		workURL(id: id)?.absoluteString
	}

	/// Resolves a possibly-relative AO3 `href` to an absolute URL string.
	/// Already absolute (`http(s)://`) hrefs pass through unchanged. A
	/// `//host/x` href is treated as root-relative on purpose: it yields
	/// the AO3 base followed by `//host/x` (a same-host URL with a double
	/// slash), never a jump to `host`.
	public static func absoluteURL(_ href: String?) -> String? {
		guard let href, !href.isEmpty else {
			return nil
		}
		if href.hasPrefix("http://") || href.hasPrefix("https://") {
			return href
		}
		if href.hasPrefix("/") {
			return baseURLString + href
		}
		return baseURLString + "/" + href
	}

	// MARK: - bookKey

	/// The work id in an `ao3-work:<id>` bookKey, or nil for any other
	/// shape (including the bare prefix with no id, and any other
	/// `BookKeyPrefix`). `ao3SeriesID` and `calibreSeries` bookKeys never
	/// resolve to a work id: there's no single AO3 work URL for a
	/// Calibre-merged compilation of several separate works.
	public static func workID(fromBookKey bookKey: String) -> String? {
		guard bookKey.hasPrefix(BookKeyPrefix.ao3Work) else {
			return nil
		}
		let workID = String(bookKey.dropFirst(BookKeyPrefix.ao3Work.count))
		return workID.isEmpty ? nil : workID
	}

	/// The reverse of `workID(fromBookKey:)`. Nil unless `id` is one or
	/// more ASCII digits, so a malformed Ambrosia `ao3_work_id` cannot
	/// yield a bookKey from this helper. `ParsedItem.bookKey` itself keeps
	/// accepting any non-empty id, unchanged -- this guard applies only to
	/// callers going through `AO3Link`.
	public static func workBookKey(forWorkID id: String) -> String? {
		guard isDigitsOnly(id) else {
			return nil
		}
		return "\(BookKeyPrefix.ao3Work)\(id)"
	}

	// MARK: - Listing classification

	/// Whether `url` is an AO3 listing page that can be subscribed to as a
	/// feed and paged through generically -- search/tag results, an
	/// author's works, someone's bookmarks, marked-for-later/reading
	/// history, subscriptions, a public collection's works, or a series.
	///
	/// Matched on host (`recognizedHosts`) plus path shape, deliberately
	/// not by file extension. Exact shapes (sourced from `ao3downloader`,
	/// since AO3 itself documents none of this):
	///
	/// - `/works?work_search[...]` -- requires a `work_search[`-prefixed
	///   query key (matched with `hasPrefix`, since AO3 search URLs carry
	///   many distinct bracketed keys).
	/// - `/tags/<tag>/works` -- path shape alone.
	/// - `/users/<name>/works` and the pseud-scoped
	///   `/users/<name>/pseuds/<pseud>/works`.
	/// - `/users/<name>/bookmarks` -- public, or gated behind login at
	///   fetch time (see `isAlwaysAuthenticatedListing(_:)`).
	/// - `/users/<name>/readings` with a `show=to-read` query --
	///   marked for later. `/users/<name>/readings` alone is a different
	///   AO3 page and is deliberately not matched.
	/// - `/users/<name>/subscriptions` -- query string and trailing slash
	///   ignored.
	/// - `/collections/<name>/works` -- a public collection's works.
	/// - `/series/<digits>` -- a series. Scoped to this classifier's own
	///   call sites (create-feed, refresh-skip, the load-more footer):
	///   `AO3SeriesListingExtractor`/`AO3SeriesNavigator`'s inline series
	///   navigation never calls it, so widening the match cannot turn a
	///   series-navigation fetch into a feed subscription.
	public static func isListingFeed(_ url: URL) -> Bool {
		guard isAO3Host(url) else {
			return false
		}

		let path = url.path

		if path.hasPrefix("/tags/") && path.hasSuffix("/works") {
			return true
		}

		if path == "/works" {
			guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
				return false
			}
			return queryItems.contains { $0.name.hasPrefix("work_search[") }
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/works") {
			// Covers both `/users/<name>/works` and the pseud-scoped
			// `/users/<name>/pseuds/<pseud>/works` -- both end in
			// `/works` with no further shape distinction needed.
			return true
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/bookmarks") {
			return true
		}

		if path.hasPrefix("/users/") && path.hasSuffix("/readings") {
			return hasToReadQuery(url)
		}

		if path.hasPrefix("/users/") && trimmingTrailingSlash(path).hasSuffix("/subscriptions") {
			return true
		}

		if path.hasPrefix("/collections/") && path.hasSuffix("/works") {
			return true
		}

		if path.hasPrefix("/series/") {
			let digits = path.dropFirst("/series/".count)
			return !digits.isEmpty && digits.allSatisfy(\.isNumber)
		}

		return false
	}

	/// Whether `url` is one of the two AO3 listing shapes that are
	/// always-yours and always-private -- subscriptions and
	/// marked-for-later -- and therefore must go through
	/// `AO3SearchResultsFetcher.fetchRequiringSignIn` rather than the plain
	/// anonymous fetch. A static, page-type-level property, not something
	/// detected from a response. Someone's bookmarks are only sometimes
	/// gated (public vs. private per user) and are deliberately not
	/// included. Checks the host itself, so it does not depend on the
	/// caller having called `isListingFeed(_:)` first.
	public static func isAlwaysAuthenticatedListing(_ url: URL) -> Bool {
		guard isAO3Host(url) else {
			return false
		}
		let path = url.path
		guard path.hasPrefix("/users/") else {
			return false
		}
		if path.hasSuffix("/readings") {
			return hasToReadQuery(url)
		}
		return trimmingTrailingSlash(path).hasSuffix("/subscriptions")
	}

	// MARK: - Private

	private static func canonicalURL(path: String, queryItems: [URLQueryItem]) -> URL? {
		var components = URLComponents()
		components.scheme = "https"
		components.host = canonicalHost
		components.path = path
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}
		return components.url
	}

	/// `url.pathComponents` without the leading `"/"` element.
	private static func pathComponents(of url: URL) -> [String] {
		var components = url.pathComponents
		if components.first == "/" {
			components.removeFirst()
		}
		return components
	}

	private static func isASCIIDigit(_ byte: UInt8) -> Bool {
		byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
	}

	private static func isDigitsOnly(_ string: String) -> Bool {
		!string.isEmpty && string.utf8.allSatisfy(isASCIIDigit)
	}

	/// The leading run of ASCII digits (`0-9` only -- not
	/// `Character.isNumber`, which also accepts Arabic-Indic and other
	/// non-ASCII digits), or nil if there is none.
	private static func leadingASCIIDigits(of string: String) -> String? {
		let digits = String(decoding: string.utf8.prefix(while: isASCIIDigit), as: UTF8.self)
		return digits.isEmpty ? nil : digits
	}

	private static func hasToReadQuery(_ url: URL) -> Bool {
		guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
			return false
		}
		return queryItems.contains { $0.name == "show" && $0.value == "to-read" }
	}

	private static func trimmingTrailingSlash(_ path: String) -> String {
		path.hasSuffix("/") ? String(path.dropLast()) : path
	}
}
