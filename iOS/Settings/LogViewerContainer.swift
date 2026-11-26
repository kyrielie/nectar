//
//  LogViewerContainer.swift
//  NetNewsWire-iOS
//
//  Shared SwiftUI layout for ErrorLogView and ActivityLogView.
//

import SwiftUI

struct LogViewerContainer<Content: View>: View {
	let isEmpty: Bool
	let emptyTitle: String
	let privacyWarningText: String
	let helpFooterText: String
	let navigationTitleText: String
	let plainText: String
	@ViewBuilder let content: () -> Content

	var body: some View {
		VStack(spacing: 0) {
			if isEmpty {
				EmptyStateView(
					title: Text(verbatim: emptyTitle),
					systemImage: "checkmark.circle"
				)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				Text(privacyWarningText)
					.font(.footnote)
					.foregroundStyle(.secondary)
					.padding()
				Divider()
				ScrollView {
					content()
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding()
				}
			}
			Divider()
			Text(helpFooterText)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal)
				.padding(.vertical, 12)
		}
		.navigationTitle(navigationTitleText)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button("Copy Contents") {
					UIPasteboard.general.string = plainText
				}
				.disabled(isEmpty)
			}
		}
	}
}
