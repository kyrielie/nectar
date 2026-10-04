//
//  AO3SessionStoreTests.swift
//  AO3KitTests
//
//  Session end bookkeeping: `endSession(reason:)` records when and why, an
//  explicit `clearSession()` records nothing, and a new `saveSession` clears
//  the record. These assertions do not depend on the Keychain write
//  succeeding, so they run in unhosted test bundles too. State lives in
//  `NectarAppGroupUserDefaults.store` (the `.standard` fallback under test),
//  so the suite is serialized and resets it in each test.
//
import Foundation
import Testing
@testable import AO3Kit

@Suite(.serialized) struct AO3SessionStoreTests {

	/// Starts from "never ended": a save clears any earlier record.
	private func reset() {
		AO3SessionStore.saveSession(cookieHeaderValue: "reset")
		AO3SessionStore.clearSession()
	}

	@Test func endSessionRecordsDateAndReason() {
		reset()
		let before = Date()

		AO3SessionStore.endSession(reason: .rejectedByAO3)

		let lastEnded = AO3SessionStore.lastEnded
		#expect(lastEnded?.reason == .rejectedByAO3)
		#expect((lastEnded?.date ?? .distantPast) >= before.addingTimeInterval(-1))
		#expect(!AO3SessionStore.isSignedIn)
		reset()
	}

	@Test func explicitClearRecordsNothing() {
		reset()

		AO3SessionStore.clearSession()

		#expect(AO3SessionStore.lastEnded == nil)
	}

	@Test func savingASessionClearsTheEndedRecord() {
		reset()
		AO3SessionStore.endSession(reason: .rejectedByAO3)
		#expect(AO3SessionStore.lastEnded != nil)

		AO3SessionStore.saveSession(cookieHeaderValue: "_otwarchive_session=new")

		#expect(AO3SessionStore.lastEnded == nil)
		reset()
	}

	@Test func everyChangePostsANotification() async {
		reset()
		let center = NotificationCenter.default
		let counter = NotificationCounter()
		let token = center.addObserver(forName: .ao3SessionDidChange, object: nil, queue: nil) { _ in
			counter.increment()
		}
		defer { center.removeObserver(token) }

		AO3SessionStore.saveSession(cookieHeaderValue: "a")
		AO3SessionStore.endSession(reason: .rejectedByAO3)
		AO3SessionStore.clearSession()

		#expect(counter.value == 3)
		reset()
	}
}

private final class NotificationCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var count = 0

	func increment() {
		lock.lock()
		count += 1
		lock.unlock()
	}

	var value: Int {
		lock.lock()
		defer { lock.unlock() }
		return count
	}
}
