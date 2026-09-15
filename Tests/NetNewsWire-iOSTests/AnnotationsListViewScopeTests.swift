//
//  AnnotationsListViewScopeTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for the text-replacement feature's "Consolidated viewer"
//  tab-switcher requirement (see the feature's own implementation
//  plan's "Tests" section: "the combined viewer... defaults to This
//  book; opened from Settings defaults to All; both tabs are reachable
//  and correctly scoped from either entry point").
//
//  Exercises AnnotationsListView.resolvedBookKey(for:)/
//  showsTabSwitcher(bookKey:) directly -- static functions, not
//  instance methods -- rather than constructing a real
//  AnnotationsListView. Constructing one requires a
//  real Account, and Account's only initializer is internal to the
//  Account module; the one existing factory for a real, disk-backed
//  test Account (TestAccountManager, Modules/Account/Tests/AccountTests)
//  lives inside that module's own test target and isn't reachable from
//  this one, and this target has no working precedent for constructing
//  an Account otherwise (confirmed: no other file under
//  Tests/NetNewsWire-iOSTests does). These two static functions carry
//  the entire "which tab does this default to, and is the switcher even
//  offered" decision the plan's requirement is actually about, so
//  testing them directly is equivalent coverage without that
//  dependency -- see each function's own doc comment in
//  AnnotationsListView.swift.
//

import Testing
import Foundation
@testable import Nectar

@MainActor @Suite struct AnnotationsListViewScopeTests {

	@Test("scope: .book(bookKey:) resolves to that bookKey")
	func bookScopeResolvesToItsBookKey() {
		#expect(AnnotationsListView.resolvedBookKey(for: .book(bookKey: "test-book-key")) == "test-book-key")
	}

	@Test("scope: .everything resolves to a nil bookKey")
	func everythingScopeResolvesToNilBookKey() {
		#expect(AnnotationsListView.resolvedBookKey(for: .everything) == nil)
	}

	@Test("a non-nil bookKey (the in-context toolbar entry point) offers the tab switcher")
	func nonNilBookKeyOffersTabSwitcher() {
		#expect(AnnotationsListView.showsTabSwitcher(bookKey: "test-book-key") == true)
	}

	@Test("a nil bookKey (the Settings entry point) does not offer the tab switcher -- there is no This Book to switch to")
	func nilBookKeyHidesTabSwitcher() {
		#expect(AnnotationsListView.showsTabSwitcher(bookKey: nil) == false)
	}
}
