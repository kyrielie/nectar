//
//  AO3LinkListImportView.swift
//  Nectar
//
//  Pasted AO3 link-list import (one-time, no refreshable feed) -- see
//  Account.importPastedAO3Links(_:) and the `nectar-import://` handling
//  described in docs/ao3-feeds.md and docs/refresh-throttling.md.
//

import SwiftUI
import Account

struct AO3LinkListImportView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var pastedText = ""
	@State private var selectedAccount: Account?
	@State private var isImporting = false
	@State private var resultMessage: String?

	private let accounts = AccountManager.shared.sortedActiveAccounts

	var body: some View {
		NavigationStack {
			Form {
				if accounts.isEmpty {
					Section {
						Text(NSLocalizedString("You must have at least one active account.", comment: "Missing active account"))
							.foregroundStyle(.secondary)
					}
				}

				if accounts.count > 1 {
					Section {
						Picker(NSLocalizedString("Account", comment: "Import destination account picker label"), selection: $selectedAccount) {
							ForEach(accounts, id: \.accountID) { account in
								Text(account.nameForDisplay).tag(Optional(account))
							}
						}
					}
				}

				Section {
					TextEditor(text: $pastedText)
						.frame(minHeight: 180)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
				} header: {
					Text(NSLocalizedString("Paste AO3 Links", comment: "Pasted AO3 link-list import text box header"))
				} footer: {
					Text(NSLocalizedString("Paste any text containing archiveofourown.org work links -- everything else is ignored. This is a one-time import, not a feed: pasted works won't refresh with new stats or chapters until you open them.", comment: "Pasted AO3 link-list import footer"))
				}

				if let resultMessage {
					Section {
						Text(resultMessage)
							.foregroundStyle(.secondary)
					}
				}
			}
			.navigationTitle(Text(NSLocalizedString("Import AO3 Links", comment: "Pasted AO3 link-list import sheet title")))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(NSLocalizedString("Import", comment: "Import AO3 links button")) {
						importTapped()
					}
					.disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAccount == nil || isImporting)
				}
			}
			.onAppear {
				if selectedAccount == nil {
					selectedAccount = accounts.first
				}
			}
		}
	}

	private func importTapped() {
		guard let selectedAccount else {
			return
		}
		isImporting = true
		Task { @MainActor in
			let newCount = await selectedAccount.importPastedAO3Links(pastedText)
			isImporting = false
			if newCount == 0 {
				resultMessage = NSLocalizedString("No new AO3 work links found in the pasted text.", comment: "Pasted AO3 link-list import: nothing new found")
			} else {
				dismiss()
			}
		}
	}
}

#Preview {
	AO3LinkListImportView()
}
