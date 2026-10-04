//
//  AO3SessionStore.swift
//  Account
//
//  Nectar AO3 direct-reading support, Workstream 3 ("optional AO3 login").
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

/// Why a stored session was ended without the person asking. An explicit
/// Sign Out records no reason.
public enum AO3SessionEndReason: String, Sendable {
	/// AO3 returned its registered-users-only wall to a request that
	/// carried the stored session.
	case rejectedByAO3
}

public extension Notification.Name {
	/// Posted after the stored session is saved, cleared, or ended. Posted
	/// on the calling thread.
	static let ao3SessionDidChange = Notification.Name("AO3SessionDidChange")
}

public enum AO3SessionStore {

	private static let lastEndedDateKey = "ao3SessionLastEndedDate"
	private static let lastEndedReasonKey = "ao3SessionLastEndedReason"

	private static let service = "com.ranchero.Nectar.AO3Session"
	private static let account = "AO3SessionCookie"

	/// The Cookie header value to send with an authenticated AO3 request
	/// (see `AO3AuthenticatedFetcher`), or `nil` if no session is stored --
	/// either the person has never signed in, or the session was cleared
	/// (`clearSession()`) or ended after AO3 rejected it
	/// (`endSession(reason:)`).
	public static var cookieHeaderValue: String? {
		guard let data = readKeychainData() else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	/// Whether a session is currently stored. Doesn't verify the session is
	/// still valid with AO3 -- that's only discoverable by actually making
	/// a request; `AO3ChapterFetcher` and `AO3SearchResultsFetcher` end the
	/// session themselves (`endSession(reason:)`) if AO3 rejects it.
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
		clearLastEnded()
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
		NotificationCenter.default.post(name: .ao3SessionDidChange, object: nil)
	}

	/// Clears the stored session on an explicit "Sign Out"
	/// (`AO3AccountSettingsView`). Records no `lastEnded`, since the person
	/// asked for it. A session AO3 rejected goes through
	/// `endSession(reason:)` instead.
	public static func clearSession() {
		deleteKeychainItem()
		NotificationCenter.default.post(name: .ao3SessionDidChange, object: nil)
	}

	/// Ends the stored session because AO3 rejected it: deletes the Keychain
	/// item, records when and why in the app-group defaults so a banner can
	/// survive a relaunch, and posts `.ao3SessionDidChange`. Cleared by the
	/// next `saveSession`.
	public static func endSession(reason: AO3SessionEndReason) {
		deleteKeychainItem()
		let store = NectarAppGroupUserDefaults.store
		store.set(Date(), forKey: lastEndedDateKey)
		store.set(reason.rawValue, forKey: lastEndedReasonKey)
		NotificationCenter.default.post(name: .ao3SessionDidChange, object: nil)
	}

	/// When and why the session last ended without the person asking, or nil
	/// if it has not, or a later sign-in cleared it.
	public static var lastEnded: (date: Date, reason: AO3SessionEndReason)? {
		let store = NectarAppGroupUserDefaults.store
		guard let date = store.object(forKey: lastEndedDateKey) as? Date,
		      let rawReason = store.string(forKey: lastEndedReasonKey),
		      let reason = AO3SessionEndReason(rawValue: rawReason) else {
			return nil
		}
		return (date, reason)
	}

	private static func clearLastEnded() {
		let store = NectarAppGroupUserDefaults.store
		store.removeObject(forKey: lastEndedDateKey)
		store.removeObject(forKey: lastEndedReasonKey)
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
