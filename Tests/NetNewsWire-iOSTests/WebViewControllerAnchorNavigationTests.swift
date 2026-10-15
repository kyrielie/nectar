//
//  WebViewControllerAnchorNavigationTests.swift
//  NetNewsWire-iOSTests
//
//  Coverage for WebViewController.isSameDocumentFragmentNavigation(url:documentURL:), the
//  pure seam behind the reader's same-document link handling (AO3's "more notes" pointer,
//  Calibre split-file links rewritten to "#id"). WebViewController itself cannot be built in
//  this target (see WebViewControllerAppearanceToggleTests), so only the seam is tested.
//

import Testing
import Foundation
@testable import Nectar

@Suite struct WebViewControllerAnchorNavigationTests {

	private let document = URL(string: "https://archiveofourown.org/works/1/chapters/2")!

	@Test func sameURLPlusFragmentIsSameDocument() {
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/2#work_endnotes")!
		#expect(WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: document))
	}

	@Test func noFragmentIsNotSameDocument() {
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: document, documentURL: document))
	}

	@Test func emptyFragmentIsNotSameDocument() {
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/2#")!
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: document))
	}

	@Test func differentPathIsNotSameDocument() {
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/3#work_endnotes")!
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: document))
	}

	@Test func differentQueryIsNotSameDocument() {
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/2?view_adult=true#work_endnotes")!
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: document))
	}

	@Test func nilDocumentURLIsNotSameDocument() {
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/2#work_endnotes")!
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: nil))
	}

	@Test func documentURLCarryingItsOwnFragmentStillMatches() {
		let documentWithFragment = URL(string: "https://archiveofourown.org/works/1/chapters/2#top")!
		let url = URL(string: "https://archiveofourown.org/works/1/chapters/2#work_endnotes")!
		#expect(WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: documentWithFragment))
	}

	@Test func differentHostIsNotSameDocument() {
		let url = URL(string: "https://example.com/works/1/chapters/2#work_endnotes")!
		#expect(!WebViewController.isSameDocumentFragmentNavigation(url: url, documentURL: document))
	}
}
