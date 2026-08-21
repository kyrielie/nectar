//
//  OrderedSet.swift
//  RSCore
//
//  Created for feed reordering.
//

import Foundation

/// A `Set`-like collection that preserves insertion order.
///
/// Matches `Set`'s membership semantics (an already-present element cannot
/// be inserted again, and insertion is a no-op that leaves the existing
/// element at its existing position) while additionally supporting
/// positional insertion and stable iteration order.
///
/// Deliberately not `Sendable`, even conditionally on `Element: Sendable`:
/// its only current use is `OrderedSet<Feed>`, and `Feed`'s `Hashable`
/// conformance is `@MainActor`-isolated (`Feed` itself is a `@MainActor`
/// class), which the compiler cannot fit into a `Sendable` conformance's
/// requirements regardless of `Element`'s own `Sendable` status. `Container`
/// and everything that touches `topLevelFeeds` is `@MainActor`-isolated
/// already, so this costs nothing in practice.
public struct OrderedSet<Element: Hashable> {
	private var array: [Element] = []
	private var set: Set<Element> = []

	public init() {}
	public init(_ elements: some Sequence<Element>) {
		for e in elements { self.insert(e) }
	}

	public var count: Int { array.count }
	public var isEmpty: Bool { array.isEmpty }

	/// Matches Set semantics: inserting an already-present element is a
	/// no-op that leaves it at its existing position (does not move it,
	/// does not replace the stored instance).
	@discardableResult
	public mutating func insert(_ element: Element) -> Bool {
		guard set.insert(element).inserted else { return false }
		array.append(element)
		return true
	}

	/// Insert at a specific position — the operation a bare `Set<Feed>`
	/// had no way to express. Same no-op-if-present semantics as the
	/// zero-argument insert above: an already-present element is left
	/// at its existing position, `index` is ignored in that case.
	@discardableResult
	public mutating func insert(_ element: Element, at index: Int) -> Bool {
		guard set.insert(element).inserted else { return false }
		array.insert(element, at: Swift.min(Swift.max(index, 0), array.count))
		return true
	}

	public mutating func remove(_ element: Element) {
		guard set.remove(element) != nil else { return }
		array.removeAll { $0 == element }   // O(n); fine at sidebar-list scale
	}

	public mutating func formUnion(_ other: some Sequence<Element>) {
		for e in other { insert(e) }
	}

	public mutating func subtract(_ other: some Sequence<Element>) {
		for e in other { remove(e) }
	}

	public func contains(_ element: Element) -> Bool { set.contains(element) }
}

extension OrderedSet: Sequence {
	public func makeIterator() -> IndexingIterator<[Element]> { array.makeIterator() }
}

extension OrderedSet: Collection {
	public var startIndex: Int { array.startIndex }
	public var endIndex: Int { array.endIndex }
	public subscript(position: Int) -> Element { array[position] }
	public func index(after i: Int) -> Int { array.index(after: i) }
}
