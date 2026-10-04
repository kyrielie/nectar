//
//  AO3SettingsModelTests.swift
//  NetNewsWire-iOSTests
//
//  AO3SettingsModel refreshes on session, rate-limit and app-active
//  notifications, shows and clears the cooldown row, and drops
//  `sessionEnded` once a new session is saved. Sources are injected, so
//  most tests use a private NotificationCenter and no Keychain.
//

import Testing
import Foundation
import UIKit
import AO3Kit
import RSWeb
@testable import Nectar

@MainActor @Suite(.serialized) struct AO3SettingsModelTests {

	private final class Sources {
		var isSignedIn = false
		var sessionEnded: (date: Date, reason: AO3SessionEndReason)?
		var resumeDate: Date?
		var challengeCapturedAt: Date?
		var currentDate = Date()
		var sleeperContinuations = [CheckedContinuation<Void, Never>]()
	}

	private func makeModel(_ sources: Sources, center: NotificationCenter) -> AO3SettingsModel {
		AO3SettingsModel(
			isSignedIn: { sources.isSignedIn },
			sessionEnded: { sources.sessionEnded },
			rateLimitResumeDate: { sources.resumeDate },
			challengeCapturedAt: { sources.challengeCapturedAt },
			now: { sources.currentDate },
			sleeper: { _ in
				await withCheckedContinuation { continuation in
					sources.sleeperContinuations.append(continuation)
				}
			},
			notificationCenter: center
		)
	}

	/// Notification observers on `.main` run on a later main-queue turn.
	private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			if condition() {
				return true
			}
			try? await Task.sleep(for: .milliseconds(10))
		}
		return condition()
	}

	@Test func initialStateReadsSources() {
		let sources = Sources()
		sources.isSignedIn = true
		let captured = Date(timeIntervalSince1970: 1_000)
		sources.challengeCapturedAt = captured

		let model = makeModel(sources, center: NotificationCenter())

		#expect(model.isSignedIn)
		#expect(model.sessionEnded == nil)
		#expect(model.rateLimitResumeDate == nil)
		#expect(model.challengeCapturedAt == captured)
	}

	@Test func sessionNotificationRefreshesSignInState() async {
		let sources = Sources()
		let center = NotificationCenter()
		let model = makeModel(sources, center: center)
		#expect(!model.isSignedIn)

		sources.isSignedIn = true
		center.post(name: .ao3SessionDidChange, object: nil)

		#expect(await waitUntil { model.isSignedIn })
	}

	@Test func sessionEndedAppearsOnNotification() async {
		let sources = Sources()
		let center = NotificationCenter()
		let model = makeModel(sources, center: center)

		let endedDate = Date(timeIntervalSince1970: 2_000)
		sources.sessionEnded = (endedDate, .rejectedByAO3)
		center.post(name: .ao3SessionDidChange, object: nil)

		#expect(await waitUntil { model.sessionEnded?.date == endedDate })
		#expect(model.sessionEnded?.reason == .rejectedByAO3)
	}

	@Test func appBecomingActiveRefreshes() async {
		let sources = Sources()
		let center = NotificationCenter()
		let model = makeModel(sources, center: center)

		let captured = Date(timeIntervalSince1970: 3_000)
		sources.challengeCapturedAt = captured
		center.post(name: UIApplication.didBecomeActiveNotification, object: nil)

		#expect(await waitUntil { model.challengeCapturedAt == captured })
	}

	@Test func cooldownRowAppearsOnRateLimitNotificationAndClearsAfterSleep() async {
		let sources = Sources()
		let center = NotificationCenter()
		let model = makeModel(sources, center: center)
		#expect(model.rateLimitResumeDate == nil)

		let resume = sources.currentDate.addingTimeInterval(60)
		sources.resumeDate = resume
		center.post(name: .hostRateLimitDidChange, object: nil)

		#expect(await waitUntil { model.rateLimitResumeDate == resume })
		#expect(await waitUntil { !sources.sleeperContinuations.isEmpty }, "one sleep is scheduled to the resume date")

		// The cooldown ends: the source stops reporting it, time passes,
		// and the scheduled sleep finishes.
		sources.resumeDate = nil
		sources.currentDate = resume.addingTimeInterval(1)
		for continuation in sources.sleeperContinuations {
			continuation.resume()
		}
		sources.sleeperContinuations.removeAll()

		#expect(await waitUntil { model.rateLimitResumeDate == nil })
	}

	@Test func expiredResumeDateIsNotShown() {
		let sources = Sources()
		sources.resumeDate = sources.currentDate.addingTimeInterval(-5)

		let model = makeModel(sources, center: NotificationCenter())

		#expect(model.rateLimitResumeDate == nil)
	}

	@Test func stopCancelsPendingSleepWithoutRefreshing() async {
		let sources = Sources()
		sources.resumeDate = sources.currentDate.addingTimeInterval(60)
		let model = makeModel(sources, center: NotificationCenter())
		#expect(await waitUntil { !sources.sleeperContinuations.isEmpty })

		model.stop()
		sources.resumeDate = nil
		for continuation in sources.sleeperContinuations {
			continuation.resume()
		}
		sources.sleeperContinuations.removeAll()
		try? await Task.sleep(for: .milliseconds(50))

		#expect(model.rateLimitResumeDate != nil, "a cancelled sleep must not refresh")
	}

	@Test func savingASessionClearsSessionEnded() async {
		AO3SessionStore.clearSession()
		defer { AO3SessionStore.clearSession() }
		AO3SessionStore.endSession(reason: .rejectedByAO3)
		let model = AO3SettingsModel()
		#expect(model.sessionEnded != nil)

		AO3SessionStore.saveSession(cookieHeaderValue: "a=1")

		#expect(await waitUntil { model.sessionEnded == nil })
	}
}
