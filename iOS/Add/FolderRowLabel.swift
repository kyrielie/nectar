//
//  FolderRowLabel.swift
//  Nectar
//
//  Wording for the "Folder" row in Add AO3 Feed and Import AO3 Work Links.
//

import Foundation

enum FolderRowLabel {

	/// The row's value when the destination is an account's top level rather than a
	/// folder. Without this the row shows the bare account name ("Library"), which
	/// reads as if a folder named "Library" were selected.
	static func topLevel(accountName: String) -> String {
		String(format: NSLocalizedString("%@ (top level)", comment: "Folder row value when the destination is the account's top level, not a folder"), accountName)
	}
}
