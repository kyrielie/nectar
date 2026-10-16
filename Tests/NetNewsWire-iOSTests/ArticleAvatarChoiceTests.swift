//
//  ArticleAvatarChoiceTests.swift
//  NetNewsWire-iOSTests
//
//  Covers the pure AO3-by-link decision the reader's nnwimageicon: avatar uses
//  (ArticleIconSchemeHandler via IconImageCache.imageForArticleAvatar). The image
//  drawing itself needs a live web view and is a device check.
//

import Testing
import Foundation
@testable import Nectar

struct ArticleAvatarChoiceTests {

	@Test func ao3HostLinkUsesTheMark() {
		#expect(ArticleAvatarChoice.usesAO3Mark(articleLink: "https://archiveofourown.org/works/123/chapters/456"))
		#expect(ArticleAvatarChoice.usesAO3Mark(articleLink: "https://www.archiveofourown.org/works/123"))
	}

	@Test func nonAO3HostLinkDoesNot() {
		#expect(!ArticleAvatarChoice.usesAO3Mark(articleLink: "https://example.com/works/123"))
		#expect(!ArticleAvatarChoice.usesAO3Mark(articleLink: "https://archiveofourown.org.evil.example/works/1"))
	}

	@Test func nilOrUnparseableLinkDoesNot() {
		#expect(!ArticleAvatarChoice.usesAO3Mark(articleLink: nil))
		#expect(!ArticleAvatarChoice.usesAO3Mark(articleLink: ""))
	}
}
