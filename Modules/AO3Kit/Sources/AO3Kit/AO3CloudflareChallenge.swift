//
//  AO3CloudflareChallenge.swift
//  AO3Kit
//
//  Marker-based detection of a Cloudflare interstitial, split out of
//  AO3SearchResultsFetcher.swift so the work-page classifier can use it
//  without reaching into the search fetcher's file.
//
import Foundation

/// Public (AO3SearchResultsFetcher itself is internal to this module, so a
/// `public` member on it wouldn't actually be reachable from outside it --
/// this is the standalone equivalent, used by
/// `AO3ChallengeSolverViewController` (iOS target) to sniff the same
/// markers out of a live WKWebView's rendered HTML, to know when an
/// interactive challenge has actually cleared rather than just that the
/// page finished loading (the challenge page itself "finishes loading"
/// too, before its own JS/redirect resolves). `AO3SearchResultsFetcher`'s
/// own `isCloudflareChallenge(_:)` forwards here rather than the reverse,
/// so there's exactly one copy of the marker list.
public enum AO3CloudflareChallenge {

	// "cdn-cgi/challenge-platform" was previously included here but was
	// dropped: it's Cloudflare's routine bot-management/JS-challenge
	// beacon, embedded on ordinary rendered pages under Bot Management,
	// not just interstitials -- it false-positived on real, fully-rendered
	// AO3 search-results pages (confirmed against a captured results page
	// with no "Just a moment..." title and no #signin wall). Both markers
	// below are specific to an actual interstitial: the literal title text
	// Cloudflare's block page uses, and a challenge-bypass link.
	private static let challengeMarkers = [
		"Just a moment...",
		"cf-chl-bypass"
	]

	public static func isChallengePage(_ html: String) -> Bool {
		challengeMarkers.contains { html.contains($0) }
	}
}
