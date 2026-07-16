//
//  AmbrosiaSQLiteTransferWalkState.swift
//  NetNewsWire
//
//  Nectar Implementation Plan, Phase 2, section 3a "Durable per-walk progress
//  state."
//
//  A small persisted record, keyed by feed ID, tracking exactly how far a
//  paginated `.sqlite` transfer walk has gotten. Written after every page
//  import (not just held in memory) so an app relaunch, background
//  suspension, or crash mid-walk doesn't lose "we were on page 4 of 20 for
//  this feed" -- without this, a multi-page transfer either silently
//  restarts from page 1 every time the app is backgrounded mid-walk
//  (wasteful), or a half-completed import could be mistaken for a finished
//  one with no record that later pages never arrived.
//
//  UserDefaults-backed (the plan's alternative to a SwiftData model), using
//  the same app-group suite AmbrosiaTransferFormatPreference already uses --
//  this is scratch per-feed progress bookkeeping, not user data that needs a
//  schema migration story of its own.
//

import Foundation

public enum AmbrosiaSQLiteTransferWalkStatus: String, Codable, Sendable {
	case inProgress
	case complete
	case incomplete
}

public struct AmbrosiaSQLiteTransferWalkState: Codable, Sendable {
	public let feedID: String
	public var walkID: String
	public var lastImportedPage: Int
	public var expectedTotalRowCount: Int
	public var importedRowCountSoFar: Int
	public var status: AmbrosiaSQLiteTransferWalkStatus

	public init(feedID: String, walkID: String, lastImportedPage: Int, expectedTotalRowCount: Int, importedRowCountSoFar: Int, status: AmbrosiaSQLiteTransferWalkStatus) {
		self.feedID = feedID
		self.walkID = walkID
		self.lastImportedPage = lastImportedPage
		self.expectedTotalRowCount = expectedTotalRowCount
		self.importedRowCountSoFar = importedRowCountSoFar
		self.status = status
	}
}

public enum AmbrosiaSQLiteTransferWalkStateStore {

	private static let keyPrefix = "ambrosiaSQLiteTransferWalkState."

	// UserDefaults is internally thread-safe but isn't marked Sendable, so a
	// global `let` of it still trips the concurrency checker; nonisolated(unsafe)
	// reflects the actual (safe) runtime behavior here -- same rationale as
	// AmbrosiaTransferFormatPreference's `store`.
	private nonisolated(unsafe) static let store: UserDefaults = {
		if let appIdentifierPrefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
		   let bundleIdentifier = Bundle.main.bundleIdentifier,
		   let suiteDefaults = UserDefaults(suiteName: "\(appIdentifierPrefix)group.\(bundleIdentifier)") {
			return suiteDefaults
		}
		return .standard
	}()

	public static func load(feedID: String) -> AmbrosiaSQLiteTransferWalkState? {
		guard let data = store.data(forKey: keyPrefix + feedID) else {
			return nil
		}
		return try? JSONDecoder().decode(AmbrosiaSQLiteTransferWalkState.self, from: data)
	}

	public static func save(_ state: AmbrosiaSQLiteTransferWalkState) {
		guard let data = try? JSONEncoder().encode(state) else {
			return
		}
		store.set(data, forKey: keyPrefix + state.feedID)
	}

	public static func clear(feedID: String) {
		store.removeObject(forKey: keyPrefix + feedID)
	}
}
