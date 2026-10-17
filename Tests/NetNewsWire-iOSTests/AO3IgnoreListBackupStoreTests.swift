//
//  AO3IgnoreListBackupStoreTests.swift
//  NetNewsWire-iOSTests
//
//  The app-side adapter between `AO3IgnoreList` and the BackupRestore package: what a backup
//  captures from the live ignore list, and what a restore writes back. Serialized, and the live
//  values are saved and restored around each test, since `AO3IgnoreList` is global state.
//

import AO3Kit
import BackupRestore
import Testing
@testable import Nectar

@Suite(.serialized) struct AO3IgnoreListBackupStoreTests {

	private func preservingIgnoreList(_ body: () -> Void) {
		let works = AO3IgnoreList.ignoredWorkIDs
		let authors = AO3IgnoreList.ignoredAuthorURLs
		let workLabels = AO3IgnoreList.ignoredWorkLabels
		let authorLabels = AO3IgnoreList.ignoredAuthorLabels
		defer {
			AO3IgnoreList.ignoredWorkIDs = works
			AO3IgnoreList.ignoredAuthorURLs = authors
			AO3IgnoreList.ignoredWorkLabels = workLabels
			AO3IgnoreList.ignoredAuthorLabels = authorLabels
		}
		AO3IgnoreList.ignoredWorkIDs = []
		AO3IgnoreList.ignoredAuthorURLs = []
		AO3IgnoreList.ignoredWorkLabels = [:]
		AO3IgnoreList.ignoredAuthorLabels = [:]
		body()
	}

	@Test func snapshotReflectsTheLiveIgnoreList() {
		preservingIgnoreList {
			AO3IgnoreList.ignoreWork(id: "200", label: "Second")
			AO3IgnoreList.ignoreWork(id: "100")
			AO3IgnoreList.ignoreAuthor(url: "https://archiveofourown.org/users/someone", label: "Someone")

			let snapshot = AO3IgnoreListBackupStore().snapshot()

			#expect(snapshot.workIDs == ["100", "200"])
			#expect(snapshot.authorURLs == ["https://archiveofourown.org/users/someone"])
			#expect(snapshot.workLabels == ["200": "Second"])
			#expect(snapshot.authorLabels == ["https://archiveofourown.org/users/someone": "Someone"])
		}
	}

	@Test func applyWritesTheSnapshotToTheLiveIgnoreList() {
		preservingIgnoreList {
			let snapshot = BackupIgnoreListSnapshot(workIDs: ["1", "2"], authorURLs: ["https://archiveofourown.org/users/a"], workLabels: ["1": "One"], authorLabels: ["https://archiveofourown.org/users/a": "A"])

			AO3IgnoreListBackupStore().apply(snapshot)

			#expect(AO3IgnoreList.ignoredWorkIDs == ["1", "2"])
			#expect(AO3IgnoreList.ignoredAuthorURLs == ["https://archiveofourown.org/users/a"])
			#expect(AO3IgnoreList.workDisplayName(id: "1") == "One")
			#expect(AO3IgnoreList.workDisplayName(id: "2") == "2")
			#expect(AO3IgnoreList.authorDisplayName(url: "https://archiveofourown.org/users/a") == "A")
		}
	}

	@Test func mergingABackupKeepsLocalRulesAndLabels() {
		preservingIgnoreList {
			AO3IgnoreList.ignoreWork(id: "1", label: "Local One")
			let store = AO3IgnoreListBackupStore()
			let backup = BackupIgnoreListSnapshot(workIDs: ["1", "2"], workLabels: ["1": "Backup One", "2": "Backup Two"])

			let merged = backup.merged(into: store.snapshot().normalized())
			store.apply(merged.result)

			#expect(merged.rulesAdded == 1)
			#expect(AO3IgnoreList.ignoredWorkIDs == ["1", "2"])
			#expect(AO3IgnoreList.workDisplayName(id: "1") == "Local One")
			#expect(AO3IgnoreList.workDisplayName(id: "2") == "Backup Two")
		}
	}
}
