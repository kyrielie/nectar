//
//  AO3ChallengeSessionStore.swift
//  Account
//
//  Nectar AO3 direct-reading support -- Cloudflare-challenge pass-through.
//
//  Keychain-backed storage for a Cloudflare-clearance cookie, captured via
//  WKWebView (AO3ChallengeSolverViewController, iOS app target) the same
//  way AO3SessionStore captures an AO3 login session -- see that file's
//  header comment, which this mirrors. Kept as a separate store rather than
//  folded into AO3SessionStore because the two represent genuinely
//  different things with different lifetimes: an AO3 session cookie is
//  account-scoped and effectively long-lived until sign-out; a Cloudflare
//  clearance cookie is anonymous (proves "this is a real browser", not
//  "this is a signed-in person") and short-lived by design on Cloudflare's
//  side, which is why this store tracks a captured-at date and refuses to
//  hand back a stale cookie -- see `cookieHeaderValueIfFresh`.
//

import Foundation
import Security

public enum AO3ChallengeSessionStore {

	private static let service = "com.ranchero.Nectar.AO3ChallengeSession"
	private static let cookieAccount = "AO3ChallengeCookie"
	private static let capturedAtAccount = "AO3ChallengeCapturedAt"

	/// Conservative freshness window for a captured clearance cookie.
	/// Cloudflare's own `cf_clearance` lifetime is configurable per site and
	/// not published by AO3, so this is deliberately shorter than any
	/// commonly-cited default (usually on the order of 30+ minutes) rather
	/// than assumed equal to it: serving a request with a cookie
	/// Cloudflare's already expired just means one more challenge, but
	/// treating an expired cookie as fresh would silently blind
	/// AO3SearchResultsFetcher to a wall it should be reporting.
	private static let freshnessWindow: TimeInterval = 20 * 60

	/// The Cookie header value to attach to an AO3 request, or `nil` if
	/// either no challenge has ever been solved or the one on file is
	/// older than `freshnessWindow`. Doesn't verify against AO3/Cloudflare
	/// itself -- that's only discoverable by making the request; see
	/// AO3SearchResultsFetcher, which clears the stored session if a
	/// request sent with this cookie still comes back challenged.
	public static var cookieHeaderValueIfFresh: String? {
		guard let capturedAt, Date().timeIntervalSince(capturedAt) < freshnessWindow else {
			return nil
		}
		guard let data = readKeychainData(account: cookieAccount) else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	/// Stores `cookieHeaderValue` as the current clearance cookie, captured
	/// just now. Called by AO3ChallengeSolverViewController once its
	/// WKWebView confirms the challenge page is gone.
	public static func saveSession(cookieHeaderValue: String) {
		guard let cookieData = cookieHeaderValue.data(using: .utf8),
			  let dateData = ISO8601DateFormatter().string(from: Date()).data(using: .utf8) else {
			return
		}
		deleteKeychainItem(account: cookieAccount)
		deleteKeychainItem(account: capturedAtAccount)
		writeKeychainData(cookieData, account: cookieAccount)
		writeKeychainData(dateData, account: capturedAtAccount)
	}

	/// Clears the stored clearance cookie. Called both when
	/// AO3SearchResultsFetcher finds a "fresh" cookie no longer satisfies
	/// Cloudflare (expired early, or revoked) and from Settings as an
	/// explicit reset.
	public static func clearSession() {
		deleteKeychainItem(account: cookieAccount)
		deleteKeychainItem(account: capturedAtAccount)
	}

	/// When the current cookie (if any) was captured, regardless of
	/// freshness -- used by Settings to show "Verified 12 minutes ago"
	/// rather than only a binary signed-in-style status.
	public static var capturedAt: Date? {
		guard let data = readKeychainData(account: capturedAtAccount),
			  let string = String(data: data, encoding: .utf8) else {
			return nil
		}
		return ISO8601DateFormatter().date(from: string)
	}

	private static let lastChallengedURLDefaultsKey = "AO3ChallengeSessionStore.lastChallengedURL"

	/// The most recent AO3 search-results URL AO3SearchResultsFetcher saw
	/// challenged -- recorded by LocalAccountRefresher's `.cloudflareChallenge`
	/// case, read by Settings to default the solver screen (below) to the
	/// actual gated URL. Plain UserDefaults rather than Keychain: this is a
	/// public AO3 URL, not a credential, and needing to survive a device
	/// wipe/restore the way a Keychain item with `.afterFirstUnlock` would
	/// isn't warranted for something this disposable -- it's overwritten by
	/// the next challenge anyway.
	///
	/// Exists because the generic `archiveofourown.org/works` listing turned
	/// out not to be a reliable stand-in: verified against real usage, AO3's
	/// Cloudflare rule (or AO3's own WAF) gates specific `work_search[...]`
	/// queries in a way the bare listing page didn't trigger at all -- so a
	/// solver screen defaulting to the generic listing could report "cleared"
	/// without ever having exercised the actual gate a feed hit.
	public static var lastChallengedURL: URL? {
		get {
			guard let string = UserDefaults.standard.string(forKey: lastChallengedURLDefaultsKey) else {
				return nil
			}
			return URL(string: string)
		}
		set {
			UserDefaults.standard.set(newValue?.absoluteString, forKey: lastChallengedURLDefaultsKey)
		}
	}

	private static func readKeychainData(account: String) -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess else {
			return nil
		}
		return result as? Data
	}

	private static func writeKeychainData(_ data: Data, account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: data,
			// AfterFirstUnlock, matching AO3SessionStore: AO3SearchResultsFetcher
			// can run during a background refresh while the device is locked.
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
		]
		SecItemAdd(query as CFDictionary, nil)
	}

	private static func deleteKeychainItem(account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
	}
}
