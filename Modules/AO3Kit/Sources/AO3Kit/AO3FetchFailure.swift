//
//  AO3FetchFailure.swift
//  AO3Kit
//
//  One typed vocabulary for why an AO3 fetch did not produce content, shared
//  by the chapter fetcher, the search-results fetcher and the series
//  navigator. Replaces ad hoc English strings built at each call site.
//
//  The English message for each case reuses the string that call sites
//  already shipped, so any existing localization entries carry over. Cases
//  with no earlier string have new copy.
//
import Foundation

public enum AO3FetchFailure: Sendable, Equatable {
	/// AO3 or Cloudflare answered 429, or a cooldown from an earlier 429 is
	/// still active. `until` is the resume date when known.
	case rateLimited(until: Date?)
	/// A Cloudflare interstitial came back in place of the page.
	case challenge
	/// AO3's own "Error 503 - Service unavailable" page, which AO3 can serve
	/// with a non-503 status.
	case serviceUnavailable
	/// A stored session was sent and AO3 still demanded registration.
	case sessionEnded
	/// A listing that is always private (subscriptions, marked for later)
	/// was requested with no stored session.
	case signInRequired
	/// A single work is restricted to registered users.
	case registrationRequired
	/// A listing is restricted to registered users.
	case listingRestricted
	/// Positive evidence the work is gone: HTTP 404/410, or AO3's explicit
	/// not-found copy. Never inferred from an unrecognized page.
	case workMissing
	case permissionDenied
	/// An unrevealed challenge work.
	case hiddenUntilRevealed
	/// The adult content gate, which `view_adult=true` should have skipped.
	case adultGate
	/// A 2xx page that matched nothing known. Could be a deleted work with a
	/// page shape not seen before, so it is not evidence of anything.
	case unrecognizedPage
	/// AO3 silently dropped a long filtered search URL's filters.
	case filtersNotApplied
	case http(Int)
	case network(String)
	case accountMissing
	case articleMissing
	/// A Calibre-merged or AO3 series anthology, which has no single work
	/// page to refetch.
	case anthologyNotRefreshable

	public var localizedMessage: String {
		switch self {
		case .rateLimited:
			return NSLocalizedString("AO3 rate limit hit -- backing off before retrying", comment: "AO3 fetch failure: rate limited")
		case .challenge:
			return NSLocalizedString("Blocked by a Cloudflare challenge -- try again later", comment: "AO3 fetch failure: Cloudflare challenge")
		case .serviceUnavailable:
			return NSLocalizedString("AO3 is temporarily unavailable -- try again later", comment: "AO3 fetch failure: AO3 served its service-unavailable page")
		case .sessionEnded:
			return NSLocalizedString("Signed out of AO3 -- sign in again in Settings to read this work", comment: "AO3 fetch failure: stored session rejected")
		case .signInRequired:
			return NSLocalizedString("This shelf requires a signed-in AO3 account", comment: "AO3 fetch failure: listing needs sign-in")
		case .registrationRequired:
			return NSLocalizedString("This work is only available to registered AO3 users", comment: "AO3 fetch failure: work restricted to registered users")
		case .listingRestricted:
			return NSLocalizedString("Restricted to registered AO3 users", comment: "AO3 fetch failure: listing restricted to registered users")
		case .workMissing:
			return NSLocalizedString("This work was not found on AO3. It may have been deleted or moved.", comment: "AO3 fetch failure: work not found")
		case .permissionDenied:
			return NSLocalizedString("AO3 says you don't have permission to view this work", comment: "AO3 fetch failure: permission denied")
		case .hiddenUntilRevealed:
			return NSLocalizedString("This work is part of an AO3 challenge and hasn't been revealed yet", comment: "AO3 fetch failure: unrevealed challenge work")
		case .adultGate:
			return NSLocalizedString("Adult content gate encountered despite view_adult=true (unexpected)", comment: "AO3 fetch failure: adult content gate")
		case .unrecognizedPage:
			return NSLocalizedString("No chapter content found (gated or removed work)", comment: "AO3 fetch failure: page shape not recognized")
		case .filtersNotApplied:
			return NSLocalizedString("AO3 ignored this search's filters (URL too long)", comment: "AO3 fetch failure: filters dropped")
		case .http(let statusCode):
			return String(format: NSLocalizedString("Could not reach AO3 (HTTP %d)", comment: "AO3 fetch failure: unexpected HTTP status"), statusCode)
		case .network(let message):
			return message
		case .accountMissing:
			return NSLocalizedString("Account no longer exists", comment: "AO3 fetch failure: account removed mid-fetch")
		case .articleMissing:
			return NSLocalizedString("Article no longer exists", comment: "AO3 fetch failure: article removed mid-fetch")
		case .anthologyNotRefreshable:
			return NSLocalizedString("Combined AO3 series can't be refreshed individually -- showing imported content", comment: "AO3 fetch failure: anthology has no single work page")
		}
	}

	/// True only for positive evidence the work is gone. Everything else,
	/// including `.unrecognizedPage`, must never set a confirmed-missing flag.
	public var evidencesMissing: Bool {
		self == .workMissing
	}

	/// Worth trying again later without any change on the person's side.
	public var isTransient: Bool {
		switch self {
		case .rateLimited, .challenge, .serviceUnavailable, .network, .unrecognizedPage:
			return true
		case .http(let statusCode):
			return (500...599).contains(statusCode)
		case .sessionEnded, .signInRequired, .registrationRequired, .listingRestricted, .workMissing,
			 .permissionDenied, .hiddenUntilRevealed, .adultGate, .filtersNotApplied, .accountMissing, .articleMissing,
			 .anthologyNotRefreshable:
			return false
		}
	}
}

public extension AO3SearchResultsFetchOutcome {

	/// The failure this outcome represents, or nil for `.success` and
	/// `.noResults`.
	var failure: AO3FetchFailure? {
		switch self {
		case .success, .noResults:
			return nil
		case .registrationRequired:
			return .listingRestricted
		case .rateLimited:
			return .rateLimited(until: nil)
		case .cloudflareChallenge:
			return .challenge
		case .notSignedIn:
			return .signInRequired
		case .filtersNotApplied:
			return .filtersNotApplied
		}
	}
}

public extension AO3SearchResultsPaginator.PageOutcome {

	/// The failure this outcome represents, or nil for `.loaded` and
	/// `.noResults`. Callers that offer browser verification still switch
	/// on `.cloudflareChallenge` first to get the challenged URL.
	var failure: AO3FetchFailure? {
		switch self {
		case .loaded, .noResults:
			return nil
		case .registrationRequired:
			return .listingRestricted
		case .rateLimited:
			return .rateLimited(until: nil)
		case .cloudflareChallenge:
			return .challenge
		case .notSignedIn:
			return .signInRequired
		case .filtersNotApplied:
			return .filtersNotApplied
		}
	}
}

public extension AO3SearchResultsImporter.ImportOutcome {

	/// The failure this outcome represents, or nil for `.imported` and
	/// `.noResults`.
	var failure: AO3FetchFailure? {
		switch self {
		case .imported, .noResults:
			return nil
		case .registrationRequired:
			return .listingRestricted
		case .filtersNotApplied:
			return .filtersNotApplied
		}
	}
}

/// Result of fetching a listing-style AO3 page (series listing pages) as
/// raw HTML, where the caller does its own parsing.
public enum AO3ListingPageResult {
	case html(String)
	case failure(AO3FetchFailure)
}
