//
//  ErrorLogView.swift
//  NetNewsWire-iOS
//
//  Created by Brent Simmons on 3/13/26.
//

import SwiftUI
import Account
import ErrorLog
import RSCore

struct ErrorLogView: View {

	@State private var entries = [ErrorLogEntry]()
	@State private var plainText = ""

	private static let maxEntries = 200

	var body: some View {
		LogViewerContainer(
			isEmpty: entries.isEmpty,
			emptyTitle: NSLocalizedString("No Errors Logged", comment: "Error log empty state"),
			privacyWarningText: NSLocalizedString("Errors may contain feed URLs and other information you may not want to share publicly.", comment: "Error log privacy warning"),
			helpFooterText: NSLocalizedString("Recent errors from syncing, feed downloads, keychain access, and other operations, with the account, operation, and error message for each.", comment: "Error Log explainer"),
			navigationTitleText: NSLocalizedString("Error Log", comment: "Error Log screen title"),
			plainText: plainText
		) {
			Text(buildAttributedString(entries))
		}
		.task {
			let allEntries = await AccountManager.shared.errorLogDatabase.allEntries()
			entries = Array(allEntries.suffix(Self.maxEntries))
			plainText = buildPlainText(entries)
		}
		.onReceive(NotificationCenter.default.publisher(for: .appDidEncounterError)) { notification in
			guard let entry = ErrorLogEntry(notification: notification) else {
				return
			}
			entries.append(entry)
			if entries.count > Self.maxEntries {
				entries.removeFirst(entries.count - Self.maxEntries)
			}
			plainText = buildPlainText(entries)
		}
	}
}

// MARK: - Private

private extension ErrorLogView {

	func buildAttributedString(_ entries: [ErrorLogEntry]) -> AttributedString {
		var result = AttributedString()
		for entry in entries {
			result.append(attributedString(for: entry))
		}
		return result
	}

	func attributedString(for entry: ErrorLogEntry) -> AttributedString {
		var timestamp = AttributedString("[\(DateFormatter.logTimestamp.string(from: entry.date))] ")
		timestamp.foregroundColor = .secondary

		let sourceString: String
		if entry.operation.isEmpty {
			sourceString = "\(entry.sourceName): "
		} else {
			sourceString = "\(entry.sourceName) — \(entry.operation): "
		}
		var source = AttributedString(sourceString)
		source.foregroundColor = AccountType(rawValue: entry.sourceID)?.logColor ?? .secondary
		source.font = .system(.body, design: .monospaced).weight(.medium)

		var message = AttributedString(entry.errorMessage)
		message.foregroundColor = .primary

		var result = timestamp
		result.append(source)
		result.append(message)

		if !entry.functionName.isEmpty {
			var location = AttributedString(" (\(entry.fileName):\(entry.functionName):\(entry.lineNumber))")
			location.foregroundColor = Color(uiColor: .tertiaryLabel)
			result.append(location)
		}

		result.append(AttributedString("\n\n"))
		return result
	}

	func buildPlainText(_ entries: [ErrorLogEntry]) -> String {
		var result = ""
		for entry in entries {
			result += "[\(DateFormatter.logTimestamp.string(from: entry.date))] "
			if entry.operation.isEmpty {
				result += "\(entry.sourceName): "
			} else {
				result += "\(entry.sourceName) — \(entry.operation): "
			}
			result += entry.errorMessage
			if !entry.functionName.isEmpty {
				result += " (\(entry.fileName):\(entry.functionName):\(entry.lineNumber))"
			}
			result += "\n\n"
		}
		return result
	}
}
