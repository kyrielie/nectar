//
//  OrderedSetTests.swift
//  RSCoreTests
//
//  Created for feed reordering.
//

import Testing
@testable import RSCore

@Suite struct OrderedSetTests {

	@Test("Insert appends in order")
	func insertAppendsInOrder() {
		var set = OrderedSet<Int>()
		set.insert(3)
		set.insert(1)
		set.insert(2)
		#expect(Array(set) == [3, 1, 2])
	}

	@Test("Insert returns false and no-ops when element already present")
	func insertAlreadyPresentIsNoOp() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		let inserted = set.insert(1)
		#expect(inserted == false)
		#expect(Array(set) == [1, 2])
	}

	@Test("Insert at index places element at that position")
	func insertAtIndex() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		set.insert(3)
		set.insert(99, at: 1)
		#expect(Array(set) == [1, 99, 2, 3])
	}

	@Test("Insert at index clamps out-of-range indices")
	func insertAtIndexClamps() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		set.insert(99, at: 999)
		#expect(Array(set) == [1, 2, 99])

		var set2 = OrderedSet<Int>()
		set2.insert(1)
		set2.insert(2)
		set2.insert(-1, at: -5)
		#expect(Array(set2) == [-1, 1, 2])
	}

	@Test("Insert at index when already present is a no-op and position is unchanged")
	func insertAtIndexAlreadyPresentIsNoOp() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		set.insert(3)
		let inserted = set.insert(1, at: 2)
		#expect(inserted == false)
		#expect(Array(set) == [1, 2, 3])
	}

	@Test("Remove deletes the element and leaves order of the rest intact")
	func remove() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		set.insert(3)
		set.remove(2)
		#expect(Array(set) == [1, 3])
		#expect(set.contains(2) == false)
	}

	@Test("Remove of an absent element is a no-op")
	func removeAbsentIsNoOp() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.remove(42)
		#expect(Array(set) == [1])
	}

	@Test("Contains reflects membership")
	func contains() {
		var set = OrderedSet<Int>()
		set.insert(1)
		#expect(set.contains(1) == true)
		#expect(set.contains(2) == false)
	}

	@Test("formUnion appends new elements in the order given, skipping duplicates")
	func formUnion() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.formUnion([2, 1, 3])
		#expect(Array(set) == [1, 2, 3])
	}

	@Test("subtract removes all given elements")
	func subtract() {
		var set = OrderedSet<Int>()
		set.insert(1)
		set.insert(2)
		set.insert(3)
		set.subtract([2, 3])
		#expect(Array(set) == [1])
	}

	@Test("Sequence/Collection conformance produces expected order")
	func sequenceAndCollectionConformance() {
		var set = OrderedSet<Int>()
		set.insert(10)
		set.insert(20)
		set.insert(30)

		#expect(Array(set) == [10, 20, 30])
		#expect(set.count == 3)
		#expect(set.isEmpty == false)
		#expect(set[0] == 10)
		#expect(set[2] == 30)

		var iteratedViaForLoop = [Int]()
		for element in set {
			iteratedViaForLoop.append(element)
		}
		#expect(iteratedViaForLoop == [10, 20, 30])
	}

	@Test("Empty OrderedSet is empty")
	func emptySet() {
		let set = OrderedSet<Int>()
		#expect(set.isEmpty == true)
		#expect(set.count == 0)
		#expect(Array(set) == [])
	}

	@Test("init(_:) built from a sequence preserves first-seen order and dedups")
	func initFromSequence() {
		let set = OrderedSet([3, 1, 3, 2, 1])
		#expect(Array(set) == [3, 1, 2])
	}
}
