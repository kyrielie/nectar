//
//  DinosaursViewModelObservationTests.swift
//  NetNewsWire-iOSTests
//
//  `DinosaursView` owns its model with `@StateObject`, so a change to the
//  published `monthThreshold` (bound to the picker) must announce itself
//  through `objectWillChange`. This pins the invalidation contract that
//  `@Observable` used to provide.
//

import Combine
import Testing
@testable import Nectar

@MainActor @Suite struct DinosaursViewModelObservationTests {

	@Test func monthThresholdChangeSendsObjectWillChange() {
		let model = DinosaursViewModel()
		var changeCount = 0
		let subscription = model.objectWillChange.sink { changeCount += 1 }
		defer { subscription.cancel() }

		model.monthThreshold = 12

		#expect(changeCount == 1)
		#expect(model.monthThreshold == 12)
	}
}
