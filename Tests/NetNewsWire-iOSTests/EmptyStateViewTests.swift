//
//  EmptyStateViewTests.swift
//  NetNewsWire-iOSTests
//
//  `EmptyStateView` wraps `ContentUnavailableView` on iOS 17+ and falls back
//  to `EmptyStateFallbackView` on iOS 16. Both must lay out to a non-zero
//  size inside a hosting controller. The fallback is tested directly so it
//  is exercised on any runtime, not just iOS 16.
//

import SwiftUI
import Testing
import UIKit
@testable import Nectar

@Suite struct EmptyStateViewTests {

	@MainActor
	private func fittingSize<Content: View>(of view: Content) -> CGSize {
		let controller = UIHostingController(rootView: view)
		controller.loadViewIfNeeded()
		return controller.sizeThatFits(in: CGSize(width: 320, height: 480))
	}

	@MainActor
	@Test func wrapperWithDescriptionLaysOutToNonZeroSize() {
		let size = fittingSize(of: EmptyStateView(
			title: Text(verbatim: "Nothing Here"),
			systemImage: "checkmark.circle",
			description: Text(verbatim: "Come back later.")))
		#expect(size.width > 0)
		#expect(size.height > 0)
	}

	@MainActor
	@Test func wrapperWithoutDescriptionLaysOutToNonZeroSize() {
		let size = fittingSize(of: EmptyStateView(
			title: Text(verbatim: "Nothing Here"),
			systemImage: "checkmark.circle"))
		#expect(size.width > 0)
		#expect(size.height > 0)
	}

	@MainActor
	@Test func fallbackLaysOutToNonZeroSize() {
		let size = fittingSize(of: EmptyStateFallbackView(
			title: Text(verbatim: "Nothing Here"),
			systemImage: "bell.slash",
			message: Text(verbatim: "Enable Notifications in Settings")))
		#expect(size.width > 0)
		#expect(size.height > 0)
	}
}
