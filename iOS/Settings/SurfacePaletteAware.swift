//
//  SurfacePaletteAware.swift
//  NetNewsWire-iOS
//
//  See docs/app-chrome-palette.md ("Badge Colors"). SwiftUI counterpart to
//  SettingsPaletteBackgroundHosting: applies `settingsBackground`,
//  `settingsCellBackground`, and `accentColor` to SwiftUI Settings screens.
//

import SwiftUI
import UIKit

@MainActor
final class SurfacePaletteObserver: ObservableObject {
	@Published var settingsBackground: Color
	@Published var settingsCellBackground: Color
	@Published var accentColor: Color

	private nonisolated(unsafe) var accentObserver: NSObjectProtocol?
	private nonisolated(unsafe) var surfaceObserver: NSObjectProtocol?
	private var latestTraitCollection: UITraitCollection

	/// Takes an explicit trait collection rather than reading
	/// UITraitCollection.current -- see refresh(for:) below for why.
	init(traitCollection: UITraitCollection) {
		latestTraitCollection = traitCollection
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
				guard let self else { return }
				self.refresh(for: self.latestTraitCollection)
			}
		}
	}

	/// Called from the hosting controller's observeTraits
	/// handler when userInterfaceStyle changes, since light/dark HexSet
	/// selection depends on it.
	func refresh(for traitCollection: UITraitCollection) {
		latestTraitCollection = traitCollection
		settingsBackground = Color(Assets.Colors.settingsBackground(for: traitCollection))
		settingsCellBackground = Color(Assets.Colors.settingsCellBackground(for: traitCollection))
	}

	deinit {
		if let accentObserver { NotificationCenter.default.removeObserver(accentObserver) }
		if let surfaceObserver { NotificationCenter.default.removeObserver(surfaceObserver) }
	}
}

private struct SurfacePaletteObserverKey: EnvironmentKey {
	static let defaultValue: SurfacePaletteObserver? = nil
}

extension EnvironmentValues {
	var surfacePaletteObserver: SurfacePaletteObserver? {
		get { self[SurfacePaletteObserverKey.self] }
		set { self[SurfacePaletteObserverKey.self] = newValue }
	}
}

struct SurfacePaletteAware: ViewModifier {
	@ObservedObject var observer: SurfacePaletteObserver

	func body(content: Content) -> some View {
		content
			.scrollContentBackground(.hidden)
			.background(observer.settingsBackground.ignoresSafeArea())
			.tint(observer.accentColor)
			.environment(\.surfacePaletteObserver, observer)
	}
}

struct SurfacePaletteListContainer: ViewModifier {
	@Environment(\.surfacePaletteObserver) private var observer

	func body(content: Content) -> some View {
		if let observer {
			ObservedSurfacePaletteListContainer(observer: observer, content: content)
		} else {
			content
		}
	}
}

private struct ObservedSurfacePaletteListContainer<Content: View>: View {
	@ObservedObject var observer: SurfacePaletteObserver
	let content: Content

	var body: some View {
		content
			.scrollContentBackground(.hidden)
			.background(observer.settingsBackground.ignoresSafeArea())
			.tint(observer.accentColor)
	}
}

extension View {
	func surfacePaletteAware(observer: SurfacePaletteObserver) -> some View {
		modifier(SurfacePaletteAware(observer: observer))
	}

	func surfacePaletteListBackground() -> some View {
		modifier(SurfacePaletteListContainer())
	}
}
