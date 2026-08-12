//
//  AO3SessionStore.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login")
//  -- see docs/ao3-merged-plan-nectar.md.
//
//  Keychain-backed storage for a single AO3 session, captured via WKWebView
//  login (AO3LoginViewController, iOS app target) and replayed as a
//  manually attached Cookie header (AO3AuthenticatedFetcher) -- not a
//  second cookie-jar URLSession. No existing credentials wrapper exists
//  anywhere else in this tree (checked before writing this), so this is a
//  minimal one, scoped to exactly what AO3 login needs: a single session
//  for the app's one local account, no keychain access groups, no iCloud
//  Keychain sync, no generic "store any credential" API.
//
//  Originally login unlocked reading only, with no kudos/subscribe/
//  bookmark/comment support anywhere in this app. Task 6 (kudos-on-like)
//  adds the first of those -- see AO3KudosManager, which reads
//  cookieHeaderValue/isSignedIn here to decide guest vs. authenticated on
//  each kudos attempt -- but this store itself is unchanged: it still holds
//  nothing beyond the session, same Keychain-backed single-session shape
//  as before.
//

import Foundation
import Security

public enum AO3SessionStore {

	private static let service = "com.ranchero.Nectar.AO3Session"
	private static let account = "AO3SessionCookie"

	/// The Cookie header value to send with an authenticated AO3 request
	/// (see `AO3AuthenticatedFetcher`), or `nil` if no session is stored --
	/// either the person has never signed in, or `clearSession()` was
	/// called after a failed authenticated retry (see
	/// `AO3ChapterFetcher.retryAuthenticated(url:)`).
	public static var cookieHeaderValue: String? {
		guard let data = readKeychainData() else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	/// Whether a session is currently stored. Doesn't verify the session is
	/// still valid with AO3 -- that's only discoverable by actually making
	/// a request; see `AO3ChapterFetcher.retryAuthenticated(url:)`, which
	/// clears the session itself if AO3 rejects it.
	public static var isSignedIn: Bool {
		cookieHeaderValue != nil
	}

	/// Stores `cookieHeaderValue` as the session for future authenticated
	/// requests. Called by `AO3LoginViewController` once its WKWebView
	/// login succeeds. Replaces any previously stored session.
	public static func saveSession(cookieHeaderValue: String) {
		guard let data = cookieHeaderValue.data(using: .utf8) else {
			return
		}
		deleteKeychainItem()
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: data,
			// AfterFirstUnlock, not WhenUnlocked: AO3ChapterFetcher's
			// refresh-triggered fetches can happen while the device is
			// locked (background refresh), and shouldn't silently drop an
			// otherwise-valid session just because the screen is off.
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]
		SecItemAdd(query as CFDictionary, nil)
	}

	/// Clears the stored session. Called both from an explicit "Sign Out"
	/// action (`AO3AccountSettingsView`) and from
	/// `AO3ChapterFetcher.retryAuthenticated(url:)` when an authenticated
	/// retry itself comes back `.registrationRequired` -- the stored
	/// session is no longer valid (expired, or was revoked).
	public static func clearSession() {
		deleteKeychainItem()
	}

	private static func readKeychainData() -> Data? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]
		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess else {
			return nil
		}
		return result as? Data
	}

	private static func deleteKeychainItem() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account
		]
		SecItemDelete(query as CFDictionary)
	}
}
