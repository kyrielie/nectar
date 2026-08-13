//
//  TestAccountManager.swift
//  AccountTests
//
//  Created by Maurice Parker on 5/4/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSWeb

@testable import Account

@MainActor final class TestAccountManager {

	nonisolated static let shared = TestAccountManager()

	var accountsFolder: URL {
		return try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

	}

	func createAccount(type: AccountType, username: String? = nil, password: String? = nil) -> Account {

		let accountID = UUID().uuidString
		let accountFolder = accountsFolder.appendingPathComponent("\(type.rawValue)_\(accountID)")

		do {
			try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true, attributes: nil)
		} catch {
			assertionFailure("Could not create folder for \(accountID) account.")
			abort()
		}

		let account = Account(dataFolder: accountFolder.absoluteString, type: type, accountID: accountID)

		// AO3ChapterFetcher (and anything else that round-trips through
		// an accountID rather than holding the Account directly) looks
		// accounts up via AccountManager.shared.existingAccount(accountID:).
		// This standalone Account isn't otherwise known to that registry,
		// so register it here or any such lookup fails with "Account no
		// longer exists" even though the account is very much alive.
		AccountManager.shared.testOnly_registerAccount(account)

		return account

	}

	func deleteAccount(_ account: Account) {

		account.deleteSettings()

		do {
			try FileManager.default.removeItem(atPath: account.dataFolder)
		}
		catch let error as CocoaError where error.code == .fileNoSuchFile {

		}
		catch {
			assertionFailure("Could not delete folder at: \(account.dataFolder) because \(error)")
			abort()
		}

	}

}
