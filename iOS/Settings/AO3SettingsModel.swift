//
//  AO3SettingsModel.swift
//  NetNewsWire-iOS
//
//  Observable state behind the AO3 settings screen: sign-in, whether the
//  session ended on its own, an active AO3 rate limit, and the browser
//  verification time. It owns no preference values; those stay in
//  `AO3AccountSettingsView` as `@State`.
//
//  Every source is an injected closure so tests need no Keychain or
//  network. The model refreshes on `.ao3SessionDidChange`,
//  `.hostRateLimitDidChange` and the app becoming active, and while a
//  cooldown is active it sleeps once until the resume date and refreshes
//  again so the row clears on its own.
//

import Foundation
import Observation
import UIKit
import AO3Kit
import RSWeb

@MainActor @Observable final class AO3SettingsModel {

	private(set) var isSignedIn: Bool
	private(set) var sessionEnded: (date: Date, reason: AO3SessionEndReason)?
	private(set) var rateLimitResumeDate: Date?
	private(set) var challengeCapturedAt: Date?

	@ObservationIgnored private let isSignedInProvider: @MainActor () -> Bool
	@ObservationIgnored private let sessionEndedProvider: @MainActor () -> (date: Date, reason: AO3SessionEndReason)?
	@ObservationIgnored private let rateLimitProvider: @MainActor () -> Date?
	@ObservationIgnored private let challengeCapturedAtProvider: @MainActor () -> Date?
	@ObservationIgnored private let now: @MainActor () -> Date
	@ObservationIgnored private let sleeper: @MainActor (Date) async -> Void

	// Touched from `deinit`, which is nonisolated.
	@ObservationIgnored nonisolated(unsafe) private var observers = [NSObjectProtocol]()
	@ObservationIgnored nonisolated(unsafe) private var sleepTask: Task<Void, Never>?

	init(
		isSignedIn: @escaping @MainActor () -> Bool = { AO3SessionStore.isSignedIn },
		sessionEnded: @escaping @MainActor () -> (date: Date, reason: AO3SessionEndReason)? = { AO3SessionStore.lastEnded },
		rateLimitResumeDate: @escaping @MainActor () -> Date? = { AO3RateLimit.activeResumeDate() },
		challengeCapturedAt: @escaping @MainActor () -> Date? = { AO3ChallengeSessionStore.capturedAt },
		now: @escaping @MainActor () -> Date = { Date() },
		sleeper: @escaping @MainActor (Date) async -> Void = { date in
			let seconds = max(0, date.timeIntervalSinceNow)
			try? await Task.sleep(for: .seconds(seconds))
		},
		notificationCenter: NotificationCenter = .default
	) {
		self.isSignedInProvider = isSignedIn
		self.sessionEndedProvider = sessionEnded
		self.rateLimitProvider = rateLimitResumeDate
		self.challengeCapturedAtProvider = challengeCapturedAt
		self.now = now
		self.sleeper = sleeper

		self.isSignedIn = isSignedIn()
		self.sessionEnded = sessionEnded()
		self.rateLimitResumeDate = nil
		self.challengeCapturedAt = challengeCapturedAt()

		let names: [Notification.Name] = [.ao3SessionDidChange, .hostRateLimitDidChange, UIApplication.didBecomeActiveNotification]
		observers = names.map { name in
			notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.refresh()
				}
			}
		}

		refresh()
	}

	deinit {
		sleepTask?.cancel()
		for observer in observers {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	/// Re-reads every source. Called on notifications, on appear, and
	/// after a sign-in or verification sheet closes.
	func refresh() {
		isSignedIn = isSignedInProvider()
		sessionEnded = sessionEndedProvider()
		challengeCapturedAt = challengeCapturedAtProvider()

		let resumeDate = rateLimitProvider()
		if let resumeDate, resumeDate > now() {
			rateLimitResumeDate = resumeDate
		} else {
			rateLimitResumeDate = nil
		}
		scheduleCooldownExpiry()
	}

	/// Cancels the pending cooldown refresh. Call when the screen goes away;
	/// `refresh()` on the next appearance schedules a new one if needed.
	func stop() {
		sleepTask?.cancel()
		sleepTask = nil
	}

	private func scheduleCooldownExpiry() {
		sleepTask?.cancel()
		sleepTask = nil
		guard let resumeDate = rateLimitResumeDate else {
			return
		}
		let sleeper = self.sleeper
		sleepTask = Task { @MainActor [weak self] in
			await sleeper(resumeDate)
			guard !Task.isCancelled else {
				return
			}
			self?.refresh()
		}
	}
}
