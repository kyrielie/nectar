//
//  AO3LinkListImportView.swift
//  Nectar
//
//  Pasted AO3 link-list import (one-time, no refreshable feed) -- see
//  Account.importAO3Links(_:destination:) and the `nectar-import://`
//  handling described in docs/ao3-feeds.md and docs/refresh-throttling.md.
//
//  The "Add to" destination picker below (shared top-level / new dated
//  folder / choose an existing folder) implements the mockup approved for
//  this redesign: defaults to the shared list so today's plain-paste
//  behavior stays a single tap away, offers a same-day dated folder as a
//  lighter-weight alternative to hunting for an existing one, and reuses
//  the exact folder picker Add Feed uses (`FolderPickerView`, scoped here
//  to just the chosen account) rather than a separate implementation --
//  see docs/nested-folders.md's note on that component.
//

import SwiftUI
import Account
import RSCore

struct AO3LinkListImportView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var pastedText = ""
	@State private var selectedAccount: Account?
	@State private var isImporting = false
	@State private var resultMessage: String?
	@State private var importSummary: ImportSummary?

	/// What a successful import reports back on this sheet, in place of closing
	/// it immediately, so the person sees how many works landed and can jump to them.
	private struct ImportSummary {
		let newCount: Int
		let alreadyImportedCount: Int
		let feed: Feed?
	}

	private enum DestinationMode: Equatable {
		case sharedTopLevel
		case newFolder
		case existingFolder
	}

	@State private var destinationMode: DestinationMode = .sharedTopLevel
	@State private var newFolderName = Self.defaultNewFolderName()
	@State private var chosenFolder: Container?
	@State private var isPresentingFolderPicker = false
	@FocusState private var isNewFolderNameFocused: Bool

	private let accounts = AccountManager.shared.sortedActiveAccounts

	private static func defaultNewFolderName() -> String {
		// ISO order (2026-10-15): unambiguous outside the US and sorts by date.
		// A folder an earlier version named in MM-dd-yy won't be matched by name
		// for same-day re-imports, which is harmless.
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter.string(from: Date())
	}

	/// What `importTapped()` actually passes to
	/// `Account.importAO3Links(_:destination:)`. `.existingFolder`
	/// without a `chosenFolder` yet (shouldn't happen -- the picker sets
	/// both together -- but this keeps the mapping total) falls back to
	/// the shared list rather than silently doing nothing.
	private var destination: Account.AO3LinkImportDestination {
		switch destinationMode {
		case .sharedTopLevel:
			return .sharedTopLevel
		case .newFolder:
			let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
			return trimmedName.isEmpty ? .sharedTopLevel : .newFolder(name: trimmedName)
		case .existingFolder:
			if let chosenFolder {
				return .existingContainer(chosenFolder)
			}
			return .sharedTopLevel
		}
	}

	private var chosenFolderLabel: String {
		guard destinationMode == .existingFolder, let container = chosenFolder else {
			// Before anything's been explicitly picked, show the
			// account's own root -- the same default Add Feed's own
			// folder row shows (via AddFeedDefaultContainer) -- rather
			// than a placeholder instruction like "Choose folder".
			return rootFolderLabel
		}
		if let folder = container as? Folder {
			return folder.pathNames.joined(separator: " / ")
		}
		// The account's own root container (see FolderPickerView/
		// AddFeedFolderViewController) -- not a Folder, so it has no
		// pathNames. Matches Add Feed's own folderLabel, which likewise
		// falls back to the container's display name outside the
		// Folder case.
		if let accountName = (container as? DisplayNameProvider)?.nameForDisplay {
			return FolderRowLabel.topLevel(accountName: accountName)
		}
		return rootFolderLabel
	}

	private var rootFolderLabel: String {
		selectedAccount.map { FolderRowLabel.topLevel(accountName: $0.nameForDisplay) } ?? NSLocalizedString("Folder", comment: "Choose-folder import destination row label, no account chosen yet")
	}

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
					destinationRow(
						title: NSLocalizedString("Imported Links", comment: "Shared top-level import destination name"),
						isSelected: destinationMode == .sharedTopLevel
					) {
						destinationMode = .sharedTopLevel
					}

					newFolderRow

					chooseFolderRow
				} header: {
					Text(NSLocalizedString("Add to", comment: "Import destination section header"))
				}

				Section {
					Text(NSLocalizedString("One-time import, not a shelf. Works won’t update on their own.", comment: "Pasted AO3 link-list import: what kind of import this is"))
						.font(.footnote)
						.foregroundStyle(.secondary)

					TextEditor(text: $pastedText)
						.frame(minHeight: 180)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
						.overlay(alignment: .topLeading) {
							if pastedText.isEmpty {
								Text(NSLocalizedString("Paste links here. Other text is ignored.", comment: "Pasted AO3 link-list import text box placeholder"))
									.foregroundStyle(.tertiary)
									.padding(.top, 8)
									.padding(.leading, 5)
									.allowsHitTesting(false)
							}
						}
				} header: {
					HStack {
						Text(NSLocalizedString("Paste AO3 Work Links", comment: "Pasted AO3 link-list import text box header"))
						Spacer()
						// PasteButton reads the clipboard only on tap and doesn't
						// raise the system paste-permission prompt.
						PasteButton(payloadType: String.self) { strings in
							appendPasted(strings)
						}
						.labelStyle(.titleAndIcon)
						.buttonBorderShape(.capsule)
					}
				} footer: {
					Text(NSLocalizedString("Only archiveofourown.org work links are imported. Imported works show their ID as the title until you open them.", comment: "Pasted AO3 link-list import footer"))
				}

				if let importSummary {
					Section {
						Text(importedLine(for: importSummary.newCount))
						if importSummary.alreadyImportedCount > 0 {
							Text(String(format: NSLocalizedString("%d already imported.", comment: "Pasted AO3 link-list import: how many pasted works were imported before"), importSummary.alreadyImportedCount))
								.foregroundStyle(.secondary)
						}
						if let feed = importSummary.feed {
							Button(NSLocalizedString("Open Imported Links", comment: "Pasted AO3 link-list import: go to the feed the works landed in")) {
								showImportedFeed(feed)
							}
						}
					}
				} else if let resultMessage {
					Section {
						Text(resultMessage)
							.foregroundStyle(.secondary)
					}
				}
			}
			.navigationTitle(Text(NSLocalizedString("Import AO3 Work Links", comment: "Pasted AO3 link-list import sheet title")))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					if importSummary != nil {
						Button(NSLocalizedString("Done", comment: "Close the import sheet after a successful import")) {
							dismiss()
						}
					} else {
						Button(NSLocalizedString("Import", comment: "Import AO3 links button")) {
							importTapped()
						}
						.disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAccount == nil || isImporting)
					}
				}
			}
			.onAppear {
				if selectedAccount == nil {
					selectedAccount = accounts.first
				}
			}
			.onChange(of: pastedText) { _, _ in
				// A result describes the text that produced it. Editing or
				// pasting more makes it stale, and returns the toolbar to Import.
				resultMessage = nil
				importSummary = nil
			}
			.onChange(of: selectedAccount) { _, _ in
				// A folder chosen under one account means nothing under
				// another -- fall back to the always-valid shared
				// destination rather than carrying a stale Container
				// reference across the switch.
				destinationMode = .sharedTopLevel
				chosenFolder = nil
			}
			.onChange(of: destinationMode) { _, newMode in
				// Selecting a different destination row (e.g. tapping
				// "Imported Links") doesn't itself resign the date
				// field's focus -- @FocusState only reacts to the
				// property being set, not to an unrelated tap elsewhere
				// in the Form. Without this, switching away from the
				// date row left its text field still focused (cursor
				// still blinking) even though its row no longer showed
				// as selected. Keeping focus in lockstep with mode here
				// covers every path that can change destinationMode,
				// not just the row's own tap handler.
				if newMode != .newFolder {
					isNewFolderNameFocused = false
				}
			}
			.sheet(isPresented: $isPresentingFolderPicker) {
				FolderPickerView(initialContainer: chosenFolder, accountFilter: selectedAccount) { container in
					chosenFolder = container
					destinationMode = .existingFolder
					isPresentingFolderPicker = false
				}
			}
		}
	}

	// Single-line, no subtitle -- matches Add Feed's own rows. Unselected
	// rows fade to secondary text (rather than every row reading the
	// same weight regardless of which one is actually active) so the
	// three options read as a radio group: picking one visibly demotes
	// the other two instead of just adding a checkmark next to an
	// otherwise-identical row.
	@ViewBuilder
	private var newFolderRow: some View {
		HStack {
			TextField(NSLocalizedString("Folder name", comment: "New dated folder name field placeholder"), text: $newFolderName)
				.foregroundStyle(destinationMode == .newFolder ? .primary : .secondary)
				.focused($isNewFolderNameFocused)
				.onChange(of: isNewFolderNameFocused) { _, isFocused in
					if isFocused {
						destinationMode = .newFolder
					}
				}
			Spacer()
			if destinationMode == .newFolder {
				Image(systemName: "checkmark")
					.foregroundStyle(Color.accentColor)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture {
			// Reached when the tap lands outside the text field itself
			// (the row background or checkmark space) -- tapping inside
			// the field is handled by the focus observer above instead,
			// since a TextField consumes its own taps before a sibling
			// gesture recognizer sees them.
			destinationMode = .newFolder
			isNewFolderNameFocused = true
		}
	}

	// Matches Add Feed's own folder row (AddFeedSelectFolderTableViewCell:
	// a static "Folder" label plus a detail label showing the current
	// selection) rather than a "Choose folder" disclosure row -- same
	// picker (FolderPickerView), same presentation, and the detail
	// label defaults to the account's own root name ("Collections")
	// instead of a placeholder instruction. The "Folder" label itself
	// always reads in the normal text color: unlike the other two rows,
	// this destination isn't mutually exclusive with them in the same
	// visual sense -- it's always a live, ready-to-use choice, not one
	// that should look demoted just because a different option happens
	// to be selected right now.
	@ViewBuilder
	private var chooseFolderRow: some View {
		Button {
			isPresentingFolderPicker = true
		} label: {
			HStack {
				Text(NSLocalizedString("Folder", comment: "Choose-folder import destination row label"))
				Spacer()
				Text(chosenFolderLabel)
					.foregroundStyle(.secondary)
				if destinationMode == .existingFolder {
					Image(systemName: "checkmark")
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func destinationRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack {
				Text(title)
					.foregroundStyle(isSelected ? .primary : .secondary)
				Spacer()
				if isSelected {
					Image(systemName: "checkmark")
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.buttonStyle(.plain)
	}

	private func importTapped() {
		guard let selectedAccount else {
			return
		}
		isImporting = true
		let destination = self.destination
		Task { @MainActor in
			let result = await selectedAccount.importAO3Links(pastedText, destination: destination)
			isImporting = false
			if result.recognizedCount == 0 {
				resultMessage = NSLocalizedString("No AO3 work links found in the pasted text.", comment: "Pasted AO3 link-list import: no work links recognized")
			} else if result.newCount == 0 {
				resultMessage = result.recognizedCount == 1
					? NSLocalizedString("That work is already imported.", comment: "Pasted AO3 link-list import: the one pasted work was imported before")
					: String(format: NSLocalizedString("All %d works are already imported.", comment: "Pasted AO3 link-list import: every pasted work was imported before"), result.recognizedCount)
			} else {
				resultMessage = nil
				importSummary = ImportSummary(newCount: result.newCount, alreadyImportedCount: result.recognizedCount - result.newCount, feed: result.feed)
			}
		}
	}

	private func importedLine(for count: Int) -> String {
		if count == 1 {
			return NSLocalizedString("Imported 1 work.", comment: "Pasted AO3 link-list import: one work added")
		}
		return String(format: NSLocalizedString("Imported %d works.", comment: "Pasted AO3 link-list import: several works added"), count)
	}

	/// Appends pasted clipboard text on its own line, so a second paste doesn't
	/// run onto the end of the last link.
	private func appendPasted(_ strings: [String]) {
		let addition = strings.joined(separator: "\n")
		guard !addition.isEmpty else {
			return
		}
		if pastedText.isEmpty || pastedText.hasSuffix("\n") {
			pastedText += addition
		} else {
			pastedText += "\n" + addition
		}
	}

	/// Closes the sheet, then asks the sidebar to show the feed, the same way a
	/// newly added feed is revealed (`SceneCoordinator.userDidAddFeed`).
	private func showImportedFeed(_ feed: Feed) {
		dismiss()
		NotificationCenter.default.post(name: .UserDidAddFeed, object: nil, userInfo: [UserInfoKey.feed: feed])
	}
}

#Preview {
	AO3LinkListImportView()
}
