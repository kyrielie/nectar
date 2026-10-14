//
//  ArticleThemesManagerGateTests.swift
//  NetNewsWire-iOSTests
//
//  The theme gate in `ArticleThemesManager.updateCurrentTheme` (plan WP6): a measured
//  theme switches synchronously, an unmeasured one waits for its measurement, a stale
//  result is dropped, repeated file-presenter callbacks start one measurement, and the
//  launch path assigns scanner colors at once and corrects once. The measurer is
//  injected, so no web view is involved. Uses bundled themes, so it needs the app
//  host's `Bundle.main`. Written without being run in Xcode.
//

import Testing
import Foundation
import UIKit
@testable import Nectar
@testable import ArticleTheming

@MainActor @Suite(.serialized) struct ArticleThemesManagerGateTests {

	// MARK: Helpers

	private final class StubNameStorage: ArticleThemeNameStoring, @unchecked Sendable {
		var currentThemeName: String?
	}

	private final class Counter: @unchecked Sendable {
		var value = 0
	}

	/// A measurer that does not return until `open()` is called.
	@MainActor private final class MeasurerGate {
		private var waiting = [CheckedContinuation<Void, Never>]()
		private var isOpen = false
		private(set) var calls = 0

		func wait() async {
			calls += 1
			if isOpen {
				return
			}
			await withCheckedContinuation { waiting.append($0) }
		}

		func open() {
			isOpen = true
			let pending = waiting
			waiting = []
			pending.forEach { $0.resume() }
		}
	}

	private static func measurement(page: String) -> ArticleThemeColorMeasurement {
		ArticleThemeColorMeasurement(pageLight: page, pageDark: "#000000", inkLight: "#111111", inkDark: "#EEEEEE",
									 linkLight: "#0000CC", linkDark: "#99CCFF",
									 pageWasPaintedLight: true, pageWasPaintedDark: true, hasDarkModeVariant: true)
	}

	private static func fixtureURL(_ name: String) throws -> URL {
		var url = URL(fileURLWithPath: #filePath)
		while url.pathComponents.count > 1 {
			url.deleteLastPathComponent()
			let candidate = url.appendingPathComponent("Tests/NetNewsWire-iOSTests/Fixtures/ThemeColorProbe/\(name).nnwtheme")
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		throw CocoaError(.fileNoSuchFile)
	}

	private static func settleNotifications() async {
		try? await Task.sleep(for: .milliseconds(50))
	}

	/// A fresh manager over an isolated store and stub name storage, with a counter of the
	/// current-theme notifications that manager posts. Restores the globals afterwards.
	private static func withManager(storedName: String?,
									_ body: (ArticleThemesManager, Counter) async throws -> Void) async throws {
		await ThemeColorStoreTestLock.shared.acquire()
		defer { ThemeColorStoreTestLock.shared.release() }
		let originalMeasurer = ArticleThemeColorStore.measurer
		let originalStorage = ArticleThemesManager.nameStorage
		let file = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeColors-\(UUID().uuidString).json")
		let storage = StubNameStorage()
		storage.currentThemeName = storedName
		ArticleThemesManager.nameStorage = storage
		ArticleThemeColorStore.core.resetForTesting(fileURL: file, bundledLoader: nil)

		let manager = ArticleThemesManager()
		manager.updateThemeNames()
		let notifications = Counter()
		let observer = NotificationCenter.default.addObserver(forName: .CurrentArticleThemeDidChangeNotification,
															  object: manager, queue: .main) { _ in
			notifications.value += 1
		}
		defer {
			NotificationCenter.default.removeObserver(observer)
			ArticleThemeColorStore.measurer = originalMeasurer
			ArticleThemesManager.nameStorage = originalStorage
			ArticleThemeColorStore.core.resetForTesting(fileURL: nil, bundledLoader: nil)
			try? FileManager.default.removeItem(at: file)
		}
		try await body(manager, notifications)
	}

	// MARK: Gate

	@Test func unmeasuredThemeWaitsForItsMeasurement() async throws {
		try await Self.withManager(storedName: nil) { manager, notifications in
			let gate = MeasurerGate()
			ArticleThemeColorStore.measurer = { _ in
				await gate.wait()
				return Self.measurement(page: "#ABCDEF")
			}
			let before = manager.currentTheme

			manager.currentThemeName = "Sepia"
			await Self.settleNotifications()
			#expect(manager.currentTheme == before)
			#expect(notifications.value == 0)

			gate.open()
			await manager.settleTaskForTesting?.value
			#expect(manager.currentTheme.name == "Sepia")
			await Self.settleNotifications()
			#expect(notifications.value == 1)
		}
	}

	@Test func measurementFailureStillSwitchesTheTheme() async throws {
		try await Self.withManager(storedName: nil) { manager, _ in
			ArticleThemeColorStore.measurer = { _ in nil }
			manager.currentThemeName = "Sepia"
			await manager.settleTaskForTesting?.value
			#expect(manager.currentTheme.name == "Sepia")
		}
	}

	@Test func cachedThemeSwitchesSynchronously() async throws {
		try await Self.withManager(storedName: nil) { manager, _ in
			let calls = Counter()
			ArticleThemeColorStore.measurer = { _ in
				calls.value += 1
				return Self.measurement(page: "#ABCDEF")
			}
			let sepia = try #require(manager.articleThemeWithThemeName("Sepia"))
			await ArticleThemeColorStore.ensureMeasured(sepia)
			#expect(calls.value == 1)

			manager.currentThemeName = "Sepia"
			// No await between the assignment and this check.
			#expect(manager.currentTheme.name == "Sepia")
			#expect(calls.value == 1)
		}
	}

	@Test func staleAsyncResultIsDropped() async throws {
		try await Self.withManager(storedName: nil) { manager, _ in
			let gate = MeasurerGate()
			ArticleThemeColorStore.measurer = { _ in
				await gate.wait()
				return Self.measurement(page: "#ABCDEF")
			}
			let tiqoe = try #require(manager.articleThemeWithThemeName("Tiqoe Dark"))
			ArticleThemeColorStore.core.store(Self.measurement(page: "#222222"), forKey: tiqoe.colorCacheKey)

			manager.currentThemeName = "Sepia"            // unmeasured: waits
			let sepiaTask = manager.settleTaskForTesting
			manager.currentThemeName = "Tiqoe Dark"       // measured: switches now
			#expect(manager.currentTheme.name == "Tiqoe Dark")

			gate.open()
			await sepiaTask?.value
			#expect(manager.currentTheme.name == "Tiqoe Dark")
		}
	}

	// MARK: Prewarm

	@Test func repeatedPresentedSubitemDidChangeStartsOneMeasurement() async throws {
		try await Self.withManager(storedName: nil) { manager, _ in
			let gate = MeasurerGate()
			ArticleThemeColorStore.measurer = { _ in
				await gate.wait()
				return Self.measurement(page: "#ABCDEF")
			}
			let name = "GateTest-\(UUID().uuidString)"
			let installed = URL(fileURLWithPath: manager.folderPath).appendingPathComponent("\(name).nnwtheme")
			try FileManager.default.copyItem(at: try Self.fixtureURL("LightOnly"), to: installed)
			defer { try? FileManager.default.removeItem(at: installed) }

			manager.presentedSubitemDidChange(at: installed)
			manager.presentedSubitemDidChange(at: installed.appendingPathComponent("stylesheet.css"))
			manager.presentedSubitemDidChange(at: installed)

			let tasks = manager.prewarmTasksForTesting
			#expect(tasks.count == 1)
			gate.open()
			for task in tasks {
				await task.value
			}
			#expect(gate.calls == 1)
			#expect(manager.prewarmTasksForTesting.isEmpty)
		}
	}

	@Test func changedURLMapsToItsThemeName() {
		let base = URL(fileURLWithPath: "/tmp/Themes")
		#expect(ArticleThemesManager.themeName(forChangedURL: base.appendingPathComponent("Foo.nnwtheme")) == "Foo")
		#expect(ArticleThemesManager.themeName(forChangedURL: base.appendingPathComponent("Foo.nnwtheme/stylesheet.css")) == "Foo")
		#expect(ArticleThemesManager.themeName(forChangedURL: base.appendingPathComponent("notes.txt")) == nil)
	}

	// MARK: Launch

	@Test func startWithColdCacheAssignsScannerColorsThenCorrectsOnce() async throws {
		try await Self.withManager(storedName: "Sepia") { manager, notifications in
			let gate = MeasurerGate()
			ArticleThemeColorStore.measurer = { _ in
				await gate.wait()
				return Self.measurement(page: "#ABCDEF")
			}
			manager.start()
			defer { NSFileCoordinator.removeFilePresenter(manager) }

			// Assigned at once, with scanner colors.
			#expect(manager.currentTheme.name == "Sepia")
			#expect(!ArticleThemeColorStore.hasMeasurement(for: manager.currentTheme))
			await Self.settleNotifications()
			#expect(notifications.value == 1)

			gate.open()
			await manager.settleTaskForTesting?.value
			await Self.settleNotifications()
			#expect(ArticleThemeColorStore.hasMeasurement(for: manager.currentTheme))
			#expect(notifications.value == 2)

			// Never again.
			await Self.settleNotifications()
			#expect(notifications.value == 2)
		}
	}
}
