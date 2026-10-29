//
//  ArticleThemePickerView.swift
//  NetNewsWire-iOS
//
//  Dedicated searchable theme picker supporting built-in and installed themes,
//  visual color swatches, and appearance capability badges.
//

import SwiftUI
import UniformTypeIdentifiers
import ArticleTheming
import HexColor

struct ArticleThemePickerView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var searchText = ""
	@State private var isImporterPresented = false
	@State private var refreshToggle = false

	private var currentThemeName: String {
		ArticleThemesManager.shared.currentThemeName
	}

	private var allThemeNames: [String] {
		var seen = Set<String>()
		return ([ArticleTheme.defaultTheme.name] + ArticleThemesManager.shared.themeNames)
			.filter { $0 != ArticleThemesManager.defaultThemeName && seen.insert($0).inserted }
	}

	private var filteredBuiltInThemes: [String] {
		allThemeNames.filter { name in
			ArticleThemesManager.shared.isBuiltInThemeName(name) && matchesSearch(name)
		}
	}

	private var filteredInstalledThemes: [String] {
		allThemeNames.filter { name in
			!ArticleThemesManager.shared.isBuiltInThemeName(name) && matchesSearch(name)
		}
	}

	var body: some View {
		List {
			if !filteredBuiltInThemes.isEmpty {
				Section {
					ForEach(filteredBuiltInThemes, id: \.self) { name in
						themeRow(for: name)
					}
				} header: {
					Text("Built-in Themes", comment: "Built-in Themes section header")
				}
			}

			if !filteredInstalledThemes.isEmpty {
				Section {
					ForEach(filteredInstalledThemes, id: \.self) { name in
						themeRow(for: name)
					}
				} header: {
					let format = NSLocalizedString("Installed Themes (%d)", comment: "Installed Themes section header with count")
					Text(String(format: format, filteredInstalledThemes.count))
				}
			}

			if filteredBuiltInThemes.isEmpty && filteredInstalledThemes.isEmpty {
				ContentUnavailableView.search(text: searchText)
			}
		}
		.navigationTitle(Text("Choose Theme", comment: "Choose Theme navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search Themes", comment: "Search Themes prompt"))
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					isImporterPresented = true
				} label: {
					Image(systemName: "plus")
				}
				.accessibilityLabel(Text("Import Theme", comment: "Import Theme toolbar button"))
			}
		}
		.fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [UTType.netNewsWireTheme]) { result in
			guard case .success(let url) = result else { return }
			importTheme(url: url)
		}
		.onReceive(NotificationCenter.default.publisher(for: .ArticleThemeNamesDidChangeNotification)) { _ in
			refreshToggle.toggle()
		}
		.onReceive(NotificationCenter.default.publisher(for: .CurrentArticleThemeDidChangeNotification)) { _ in
			refreshToggle.toggle()
		}
	}

	// MARK: - Row Rendering

	private func themeRow(for name: String) -> some View {
		let isSelected = name == currentThemeName
		let theme = ArticleThemesManager.shared.articleThemeWithThemeName(name)
		let colors = theme.map { ArticleThemeColorStore.colors(for: $0) }
		let hasDarkMode = colors?.hasDarkModeVariant ?? false

		return Button {
			ArticleThemesManager.shared.currentThemeName = name
		} label: {
			HStack(spacing: 12) {
				// Visual preview chips: page background circle with text color dot
				if let colors {
					colorChips(backgroundColor: Color(uiColor: colors.backgroundColor), textColor: Color(uiColor: colors.textColor))
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(name)
						.font(.body)
						.foregroundStyle(.primary)

					Text(hasDarkMode ? NSLocalizedString("Light & Dark", comment: "Light and dark theme badge") : NSLocalizedString("Single Palette", comment: "Single palette theme badge"))
						.font(.caption2)
						.foregroundStyle(.secondary)
				}

				Spacer()

				if isSelected {
					Image(systemName: "checkmark")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}

	private func colorChips(backgroundColor: Color, textColor: Color) -> some View {
		ZStack {
			Circle()
				.fill(backgroundColor)
				.frame(width: 28, height: 28)
				.overlay(Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5))

			Circle()
				.fill(textColor)
				.frame(width: 10, height: 10)
		}
	}

	private func matchesSearch(_ name: String) -> Bool {
		guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return true
		}
		return name.localizedCaseInsensitiveContains(searchText)
	}

	// MARK: - Import

	private func importTheme(url: URL) {
		guard let controller = UIApplication.shared.firstKeyWindow?.topViewController else { return }

		if url.startAccessingSecurityScopedResource() {
			defer {
				url.stopAccessingSecurityScopedResource()
			}

			do {
				try ArticleThemeImporter.importTheme(controller: controller, url: url)
			} catch {
				NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
			}
		}
	}
}

private extension UIApplication {
	var firstKeyWindow: UIWindow? {
		connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap { $0.windows }
			.first { $0.isKeyWindow }
	}
}
