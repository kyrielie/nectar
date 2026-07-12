//
//  ArticleStatus.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/1/17.
//  Copyright © 2017 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os

public final class ArticleStatus: Hashable, Sendable {

	/// ~6 months. Used for marking old articles as read on arrival
	/// and for detecting stale CloudKit status records.
	public static let staleIntervalInSeconds: TimeInterval = 183 * 24 * 60 * 60
	public enum Key: String, Sendable {
		case read
		case starred
		case loved
	}

	public let articleID: String
	public let dateArrived: Date

	private struct State: Sendable {
		var read: Bool
		var starred: Bool
		var readingProgress: Double?
		var loved: Bool
	}

	private let state: OSAllocatedUnfairLock<State>

	public var read: Bool {
		get {
			state.withLock { $0.read }
		}
		set {
			state.withLock { $0.read = newValue }
		}
	}

	public var starred: Bool {
		get {
			state.withLock { $0.starred }
		}
		set {
			state.withLock { $0.starred = newValue }
		}
	}

	/// Fraction (0...1) of the article read, derived from scroll position. nil means
	/// never computed (article never opened, or opened before this feature existed) --
	/// distinct from 0, which means computed and confirmed at the very top. Unlike
	/// `read`/`starred`, this isn't part of the `ArticleStatus.Key` mark/sync system --
	/// it's local UI state, same treatment as scroll position (Phase 2).
	public var readingProgress: Double? {
		get {
			state.withLock { $0.readingProgress }
		}
		set {
			state.withLock { $0.readingProgress = newValue }
		}
	}

	public var loved: Bool {
		get {
			state.withLock { $0.loved }
		}
		set {
			state.withLock { $0.loved = newValue }
		}
	}

	public init(articleID: String, read: Bool, starred: Bool, dateArrived: Date, readingProgress: Double? = nil, loved: Bool = false) {
		self.articleID = articleID
		self.state = OSAllocatedUnfairLock(initialState: State(read: read, starred: starred, readingProgress: readingProgress, loved: loved))
		self.dateArrived = dateArrived
	}

	public convenience init(articleID: String, read: Bool, dateArrived: Date) {
		self.init(articleID: articleID, read: read, starred: false, dateArrived: dateArrived)
	}

	public func boolStatus(forKey key: ArticleStatus.Key) -> Bool {
		switch key {
		case .read:
			return read
		case .starred:
			return starred
		case .loved:
			return loved
		}
	}

	public func setBoolStatus(_ status: Bool, forKey key: ArticleStatus.Key) {
		switch key {
		case .read:
			read = status
		case .starred:
			starred = status
		case .loved:
			loved = status
		}
	}

	// MARK: - Hashable

	public func hash(into hasher: inout Hasher) {
		hasher.combine(articleID)
	}

	// MARK: - Equatable

	public static func ==(lhs: ArticleStatus, rhs: ArticleStatus) -> Bool {
		return lhs.articleID == rhs.articleID && lhs.dateArrived == rhs.dateArrived && lhs.read == rhs.read && lhs.starred == rhs.starred && lhs.readingProgress == rhs.readingProgress && lhs.loved == rhs.loved
	}
}

public extension Set where Element == ArticleStatus {

	func articleIDs() -> Set<String> {
		return Set<String>(map { $0.articleID })
	}
}

public extension Array where Element == ArticleStatus {

	func articleIDs() -> [String] {
		return map { $0.articleID }
	}
}
