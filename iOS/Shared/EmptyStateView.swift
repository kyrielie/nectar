//
//  EmptyStateView.swift
//  NetNewsWire-iOS
//
//  Empty-state placeholder for SwiftUI screens. `ContentUnavailableView` is
//  iOS 17+, so this uses it where available (keeping the native look) and
//  falls back to `EmptyStateFallbackView` on iOS 16. Only the title, symbol
//  and optional description are supported; none of the call sites need actions.
//

import SwiftUI

struct EmptyStateView: View {

	let title: Text
	let systemImage: String
	let message: Text?

	init(title: Text, systemImage: String, description: Text? = nil) {
		self.title = title
		self.systemImage = systemImage
		self.message = description
	}

	var body: some View {
		if #available(iOS 17, *) {
			ContentUnavailableView {
				Label {
					title
				} icon: {
					Image(systemName: systemImage)
				}
			} description: {
				if let message {
					message
				}
			}
		} else {
			EmptyStateFallbackView(title: title, systemImage: systemImage, message: message)
		}
	}

	@ViewBuilder
	static func search(text: String) -> some View {
		if #available(iOS 17, *) {
			ContentUnavailableView.search(text: text)
		} else {
			EmptyStateFallbackView(
				title: Text("No Results for \"\(text)\""),
				systemImage: "magnifyingglass",
				message: Text("Check the spelling or try a new search.", comment: "Theme search empty state description")
			)
		}
	}
}

/// The iOS 16 look: a centered symbol, a semibold title and a secondary
/// description. Internal rather than private so tests can lay it out on any
/// runtime.
struct EmptyStateFallbackView: View {

	let title: Text
	let systemImage: String
	let message: Text?

	var body: some View {
		VStack(spacing: 8) {
			Image(systemName: systemImage)
				.font(.system(size: 48))
				.foregroundColor(.secondary)
				.accessibilityHidden(true)
			title
				.font(.title3.weight(.semibold))
			if let message {
				message
					.font(.subheadline)
					.foregroundColor(.secondary)
			}
		}
		.multilineTextAlignment(.center)
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityElement(children: .combine)
	}
}
