//
//  StrictLimitConfirmationTests.swift
//  NetNewsWire-iOSTests
//
//  The daily-limit detail screen asks for confirmation when a limit is
//  lowered from 120 minutes or more to below 120. On iOS 16 `onChange`
//  reports only the new value, so the decision was extracted into a pure
//  function; these tests pin its contract.
//

import Testing
@testable import Nectar

@Suite struct StrictLimitConfirmationTests {

	@Test func crossingBelowThresholdNeedsConfirmation() {
		#expect(StrictLimitConfirmation.needsConfirmation(from: 120, to: 119))
		#expect(StrictLimitConfirmation.needsConfirmation(from: 180, to: 30))
	}

	@Test func stayingAboveThresholdDoesNot() {
		#expect(!StrictLimitConfirmation.needsConfirmation(from: 180, to: 120))
		#expect(!StrictLimitConfirmation.needsConfirmation(from: 121, to: 240))
	}

	@Test func alreadyBelowThresholdDoesNot() {
		#expect(!StrictLimitConfirmation.needsConfirmation(from: 90, to: 60))
		#expect(!StrictLimitConfirmation.needsConfirmation(from: 119, to: 118))
	}

	@Test func raisingBackAboveThresholdDoesNot() {
		#expect(!StrictLimitConfirmation.needsConfirmation(from: 60, to: 120))
	}
}
