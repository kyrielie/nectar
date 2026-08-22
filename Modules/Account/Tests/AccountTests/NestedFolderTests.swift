//
//  NestedFolderTests.swift
//  AccountTests
//
//  Folder reordering and up-to-3-level folder nesting.
//

import XCTest
import RSParser
@testable import Account

@MainActor final class NestedFolderTests: XCTestCase {

	private var account: Account!

	override func setUp() async throws {
		account = TestAccountManager.shared.createAccount(type: .onMyMac)
	}

	override func tearDown() async throws {
		TestAccountManager.shared.deleteAccount(account)
		account = nil
	}

	// MARK: - Folder reordering

	func testFoldersPreserveInsertionOrder() {
		let a = account.ensureFolder(with: "A")!
		let b = account.ensureFolder(with: "B")!
		let c = account.ensureFolder(with: "C")!
		XCTAssertEqual(account.folders.map { Array($0) }, [a, b, c])
	}

	func testReorderFolderMovesWithinAccount() {
		let a = account.ensureFolder(with: "A")!
		let b = account.ensureFolder(with: "B")!
		let c = account.ensureFolder(with: "C")!

		account.reorderFolder(c, toIndex: 0)
		XCTAssertEqual(account.folders.map { Array($0) }, [c, a, b])
	}

	func testAddFolderToTreeAtIndexInsertsAtPosition() {
		let a = account.ensureFolder(with: "A")!
		let b = account.ensureFolder(with: "B")!
		let inserted = Folder(account: account, name: "Inserted")
		account.addFolderToTree(inserted, at: 1)
		XCTAssertEqual(account.folders.map { Array($0) }, [a, inserted, b])
	}

	// MARK: - pathNames

	func testTopLevelFolderPathNamesIsJustItself() {
		let folder = account.ensureFolder(with: "Top")!
		XCTAssertEqual(folder.pathNames, ["Top"])
	}

	func testNestedFolderPathNamesIncludesAncestors() {
		let parent = account.ensureFolder(with: "Parent")!
		let child = parent.ensureChildFolder(named: "Child")!
		let grandchild = child.ensureChildFolder(named: "Grandchild")!

		XCTAssertEqual(parent.pathNames, ["Parent"])
		XCTAssertEqual(child.pathNames, ["Parent", "Child"])
		XCTAssertEqual(grandchild.pathNames, ["Parent", "Child", "Grandchild"])
	}

	func testExistingFolderWithPathFindsNestedFolder() {
		let parent = account.ensureFolder(with: "Parent")!
		let child = parent.ensureChildFolder(named: "Child")!

		XCTAssertEqual(account.existingFolder(withPath: ["Parent"]), parent)
		XCTAssertEqual(account.existingFolder(withPath: ["Parent", "Child"]), child)
		XCTAssertNil(account.existingFolder(withPath: ["Parent", "NoSuchChild"]))
		XCTAssertNil(account.existingFolder(withPath: ["NoSuchParent"]))
		XCTAssertNil(account.existingFolder(withPath: []))
	}

	func testEnsureFolderWithFolderNamesBuildsChain() {
		let leaf = account.ensureFolder(withFolderNames: ["Parent", "Child"])
		XCTAssertNotNil(leaf)
		XCTAssertEqual(leaf?.pathNames, ["Parent", "Child"])
		XCTAssertNotNil(account.existingFolder(withPath: ["Parent"]))
	}

	func testEnsureFolderWithFolderNamesReusesExistingChain() {
		let first = account.ensureFolder(withFolderNames: ["Parent", "Child"])
		let second = account.ensureFolder(withFolderNames: ["Parent", "Child"])
		XCTAssertEqual(first, second)
		XCTAssertEqual(account.folders?.count, 1) // one top-level "Parent", not two
	}

	// MARK: - moveFolder

	func testMoveFolderIntoAnotherFolderNestsIt() async throws {
		let parent = account.ensureFolder(with: "Parent")!
		let mover = account.ensureFolder(with: "Mover")!

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			account.moveFolder(mover, from: account, to: parent, targetIndex: nil) { result in
				continuation.resume(with: result)
			}
		}

		XCTAssertFalse(account.folders?.contains(mover) ?? true)
		XCTAssertTrue(parent.folders?.contains(mover) ?? false)
		XCTAssertEqual(mover.pathNames, ["Parent", "Mover"])
	}

	func testMoveFolderRejectsExceedingDepthCap() async throws {
		// Build a chain 3 levels deep: Level1/Level2/Level3.
		let level3 = account.ensureFolder(withFolderNames: ["Level1", "Level2", "Level3"])!
		let mover = account.ensureFolder(with: "Mover")!

		// Moving "Mover" into Level3 (itself already at depth 3) would put
		// Mover at depth 4, which exceeds the cap.
		do {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				account.moveFolder(mover, from: account, to: level3, targetIndex: nil) { result in
					continuation.resume(with: result)
				}
			}
			XCTFail("Expected move to be rejected for exceeding the depth cap")
		} catch {
			// Expected -- AccountError.invalidParameter.
		}

		// Mover should be untouched -- still at the top level.
		XCTAssertTrue(account.folders?.contains(mover) ?? false)
	}

	func testMoveFolderRejectsExceedingDepthCapWhenMovedFolderHasItsOwnSubfolders() async throws {
		// "Group" itself has a child, so moving Group under an
		// already-nested folder can exceed the cap even though Group
		// alone is only depth 1.
		let group = account.ensureFolder(with: "Group")!
		_ = group.ensureChildFolder(named: "GroupChild")! // group.maxDescendantDepth == 1

		let destination = account.ensureFolder(withFolderNames: ["Level1", "Level2"])! // depth 2

		do {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				account.moveFolder(group, from: account, to: destination, targetIndex: nil) { result in
					continuation.resume(with: result)
				}
			}
			XCTFail("Expected move to be rejected: destination depth 2 + 1 + group's own depth 1 == 4")
		} catch {
			// Expected.
		}
	}

	func testIsAncestorOfDetectsSelfAndDescendants() {
		let parent = account.ensureFolder(with: "Parent")!
		let child = parent.ensureChildFolder(named: "Child")!
		let unrelated = account.ensureFolder(with: "Unrelated")!

		XCTAssertTrue(parent.isAncestor(of: parent))
		XCTAssertTrue(parent.isAncestor(of: child))
		XCTAssertFalse(parent.isAncestor(of: unrelated))
		XCTAssertFalse(child.isAncestor(of: parent))
	}

	// MARK: - Delete/restore preserves nesting

	func testRemoveThenRestoreNestedFolderReturnsItToItsParent() async throws {
		let parent = account.ensureFolder(with: "Parent")!
		let child = parent.ensureChildFolder(named: "Child")!

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			account.removeFolder(child) { result in
				continuation.resume(with: result)
			}
		}
		XCTAssertFalse(parent.folders?.contains(child) ?? true, "Child should be detached from Parent after removal")

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			account.restoreFolder(child) { result in
				continuation.resume(with: result)
			}
		}
		XCTAssertTrue(parent.folders?.contains(child) ?? false, "Child should be restored to Parent, not the account's top level")
		XCTAssertFalse(account.folders?.contains(child) ?? false, "Child should not end up at the account's top level")
		XCTAssertEqual(child.pathNames, ["Parent", "Child"])
	}

	// MARK: - OPML round-trip nesting

	private func opmlFolderItem(title: String, children: [OPMLItem] = []) -> OPMLItem {
		let item = OPMLItem(attributes: ["title": title])
		for child in children {
			item.addChild(child)
		}
		return item
	}

	private func opmlFeedItem(title: String, url: String) -> OPMLItem {
		return OPMLItem(attributes: ["title": title, "text": title, "xmlUrl": url])
	}

	func testOPMLImportPreservesTwoLevelsOfNesting() {
		let feed = opmlFeedItem(title: "Feed", url: "https://example.com/feed.xml")
		let child = opmlFolderItem(title: "Child", children: [feed])
		let parent = opmlFolderItem(title: "Parent", children: [child])

		account.loadOPMLItems([parent])

		let parentFolder = account.existingFolder(withPath: ["Parent"])
		XCTAssertNotNil(parentFolder)

		let childFolder = account.existingFolder(withPath: ["Parent", "Child"])
		XCTAssertNotNil(childFolder, "Nested folder must survive import, not be flattened into its parent")

		XCTAssertTrue(parentFolder?.topLevelFeeds.isEmpty ?? false, "Feed belongs to Child, not Parent")
		XCTAssertEqual(childFolder?.topLevelFeeds.count, 1)
		XCTAssertEqual(childFolder?.topLevelFeeds.first?.url, "https://example.com/feed.xml")
	}

	func testOPMLImportPreservesThreeLevelsOfNesting() {
		let feed = opmlFeedItem(title: "Feed", url: "https://example.com/deep.xml")
		let level3 = opmlFolderItem(title: "Level3", children: [feed])
		let level2 = opmlFolderItem(title: "Level2", children: [level3])
		let level1 = opmlFolderItem(title: "Level1", children: [level2])

		account.loadOPMLItems([level1])

		let level3Folder = account.existingFolder(withPath: ["Level1", "Level2", "Level3"])
		XCTAssertNotNil(level3Folder)
		XCTAssertEqual(level3Folder?.topLevelFeeds.first?.url, "https://example.com/deep.xml")
	}

	func testOPMLImportBeyondDepthCapFlattensIntoDepthThreeFolder() {
		// A 4th named folder level should not create an illegal depth-4
		// folder -- its feed should land inside the depth-3 folder
		// instead of being silently dropped.
		let feed = opmlFeedItem(title: "Feed", url: "https://example.com/toodeep.xml")
		let level4 = opmlFolderItem(title: "Level4", children: [feed])
		let level3 = opmlFolderItem(title: "Level3", children: [level4])
		let level2 = opmlFolderItem(title: "Level2", children: [level3])
		let level1 = opmlFolderItem(title: "Level1", children: [level2])

		account.loadOPMLItems([level1])

		let level3Folder = account.existingFolder(withPath: ["Level1", "Level2", "Level3"])
		XCTAssertNotNil(level3Folder)
		XCTAssertNil(account.existingFolder(withPath: ["Level1", "Level2", "Level3", "Level4"]), "No depth-4 folder should be created")
		XCTAssertEqual(level3Folder?.topLevelFeeds.count, 1, "Level4's feed should be flattened into Level3, not dropped")
		XCTAssertEqual(level3Folder?.topLevelFeeds.first?.url, "https://example.com/toodeep.xml")
	}

	func testOPMLExportRoundTripsNestedFolders() {
		let feed = opmlFeedItem(title: "Feed", url: "https://example.com/roundtrip.xml")
		let child = opmlFolderItem(title: "Child", children: [feed])
		let parent = opmlFolderItem(title: "Parent", children: [child])
		account.loadOPMLItems([parent])

		let opmlString = account.OPMLString(indentLevel: 0, allowCustomAttributes: false)

		XCTAssertTrue(opmlString.contains("Parent"))
		XCTAssertTrue(opmlString.contains("Child"))
		// The Child outline must be nested inside Parent's own
		// <outline>...</outline> span, not a sibling of it.
		guard let parentRange = opmlString.range(of: "text=\"Parent\""),
			  let parentCloseRange = opmlString.range(of: "</outline>", range: parentRange.upperBound..<opmlString.endIndex) else {
			XCTFail("Could not locate Parent outline in exported OPML")
			return
		}
		let childTitleRange = opmlString.range(of: "text=\"Child\"")
		XCTAssertNotNil(childTitleRange)
		if let childTitleRange {
			XCTAssertTrue(parentRange.upperBound < childTitleRange.lowerBound && childTitleRange.lowerBound < parentCloseRange.lowerBound,
						   "Child outline must appear nested within Parent's outline span")
		}
	}
}
