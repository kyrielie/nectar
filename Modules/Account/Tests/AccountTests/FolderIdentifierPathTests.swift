//
//  FolderIdentifierPathTests.swift
//  AccountTests
//
//  ContainerIdentifier.folder / SidebarItemIdentifier.folder now carry a
//  path ([String]) instead of a single folder name, to support nested
//  folders. userInfo persists that path as a single delimited string
//  (both types' userInfo is ultimately String-valued), not a nested
//  array -- these tests exercise that encode/decode round-trip and the
//  graceful-failure behavior for old-format (pre-nesting) userInfo.
//

import XCTest
@testable import Account

final class FolderIdentifierPathTests: XCTestCase {

	// MARK: - ContainerIdentifier

	func testContainerIdentifierFolderUserInfoRoundTripsSingleLevelPath() {
		let identifier = ContainerIdentifier.folder("account1", ["Top"])
		let userInfo = identifier.userInfo
		let decoded = ContainerIdentifier(userInfo: userInfo)
		XCTAssertEqual(decoded, identifier)
	}

	func testContainerIdentifierFolderUserInfoRoundTripsNestedPath() {
		let identifier = ContainerIdentifier.folder("account1", ["Parent", "Child", "Grandchild"])
		let userInfo = identifier.userInfo
		let decoded = ContainerIdentifier(userInfo: userInfo)
		XCTAssertEqual(decoded, identifier)
	}

	func testContainerIdentifierFolderUserInfoDoesNotUseOldFolderNameKey() {
		// The old single-name format used key "folderName". Confirm the
		// new format doesn't populate that key -- an app reading old
		// persisted data with the old key should not be silently misled
		// by a coincidentally-matching new key.
		let identifier = ContainerIdentifier.folder("account1", ["Top"])
		XCTAssertNil(identifier.userInfo["folderName"])
		XCTAssertNotNil(identifier.userInfo["folderPath"])
	}

	func testContainerIdentifierRejectsOldFormatUserInfoGracefully() {
		// Old-format persisted userInfo: has "folderName", not "folderPath".
		let oldFormatUserInfo: [AnyHashable: AnyHashable] = [
			"type": "folder",
			"accountID": "account1",
			"folderName": "Top"
		]
		XCTAssertNil(ContainerIdentifier(userInfo: oldFormatUserInfo), "Old-format userInfo should fail to decode rather than being misread")
	}

	func testContainerIdentifierEncodableDecodableRoundTrip() throws {
		let identifier = ContainerIdentifier.folder("account1", ["Parent", "Child"])
		let data = try JSONEncoder().encode(identifier)
		let decoded = try JSONDecoder().decode(ContainerIdentifier.self, from: data)
		XCTAssertEqual(decoded, identifier)
	}

	// MARK: - SidebarItemIdentifier

	func testSidebarItemIdentifierFolderUserInfoRoundTripsNestedPath() {
		let identifier = SidebarItemIdentifier.folder("account1", ["Parent", "Child"])
		let userInfo = identifier.userInfo
		let decoded = SidebarItemIdentifier(userInfo: userInfo)
		XCTAssertEqual(decoded, identifier)
	}

	func testSidebarItemIdentifierRejectsOldFormatUserInfoGracefully() {
		let oldFormatUserInfo: [String: String] = [
			"type": "folder",
			"accountID": "account1",
			"folderName": "Top"
		]
		XCTAssertNil(SidebarItemIdentifier(userInfo: oldFormatUserInfo), "Old-format userInfo should fail to decode rather than being misread")
	}

	func testSidebarItemIdentifierFeedStillRoundTrips() {
		// Unrelated case, unaffected by the folder-path change -- guard
		// against a regression in the shared userInfo/init? plumbing.
		let identifier = SidebarItemIdentifier.feed("account1", "feed1")
		let decoded = SidebarItemIdentifier(userInfo: identifier.userInfo)
		XCTAssertEqual(decoded, identifier)
	}
}
