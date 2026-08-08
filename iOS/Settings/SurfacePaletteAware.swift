//
//  SurfacePaletteAware.swift
//  NetNewsWire-iOS
//
//  surface-palette-followup-plan, Issue B. SwiftUI counterpart to
//  SettingsPaletteBackgroundHosting: that protocol assigns .backgroundColor
//  on a UIView outlet, which is structurally inapplicable to a SwiftUI
//  View. This gives the six UIHostingController-wrapped settings screens
//  (AboutView, AO3AccountSettingsView, ErrorLogView, AccountStatsView,
//  ActivityLogView, ArticleThemeListView) the same live palette/accent
//  tracking every UIKit settings screen already has.
//

import SwiftUI
import UIKit

@MainActor
final class SurfacePaletteObserver: ObservableObject {
	@Published var settingsBackground: Color
	@Published var settingsCellBackground: Color
	@Published var accentColor: Color

	// nonisolated(unsafe) because deinit for a @MainActor class runs
	// nonisolated -- these tokens are opaque, write-once-in-init,
	// read-once-in-deinit, and NotificationCenter.removeObserver is safe
	// to call off the main actor.
	private nonisolated(unsafe) var accentObserver: NSObjectProtocol?
	private nonisolated(unsafe) var surfaceObserver: NSObjectProtocol?

	/// Takes an explicit trait collection rather than reading
	/// UITraitCollection.current -- see refresh(for:) below for why.
	init(traitCollection: UITraitCollection) {
		settingsBackground = Color(Assets.Colors.settingsBackground(for: traitCollection))
		settingsCellBackground = Color(Assets.Colors.settingsCellBackground(for: traitCollection))
		accentColor = Color(Assets.Colors.primaryAccent)

		accentObserver = NotificationCenter.default.addObserver(forName: .accentColorDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.accentColor = Color(Assets.Colors.primaryAccent)
			}
		}
		surfaceObserver = NotificationCenter.default.addObserver(forName: .surfaceTintDidChange, object: nil, queue: .main) { [weak self] _ in
			Task { @MainActor in
				self?.refresh(for: traitCollection)
			}
		}
	}

	/// Called from the hosting controller's registerForTraitChanges
	/// handler when userInterfaceStyle changes, since light/dark HexSet
	/// selection depends on it.
	func refresh(for traitCollection: UITraitCollection) {
		settingsBackground = Color(Assets.Colors.settingsBackground(for: traitCollection))
		settingsCellBackground = Color(Assets.Colors.settingsCellBackground(for: traitCollection))
	}

	deinit {
		if let accentObserver { NotificationCenter.default.removeObserver(accentObserver) }
		if let surfaceObserver { NotificationCenter.default.removeObserver(surfaceObserver) }
	}
}

struct SurfacePaletteAware: ViewModifier {
	@ObservedObject var observer: SurfacePaletteObserver
	func body(content: Content) -> some View {
		content
			.scrollContentBackground(.hidden)
			.background(observer.settingsBackground)
			.tint(observer.accentColor)
	}
}

extension View {
	func surfacePaletteAware(observer: SurfacePaletteObserver) -> some View {
		modifier(SurfacePaletteAware(observer: observer))
	}
}
