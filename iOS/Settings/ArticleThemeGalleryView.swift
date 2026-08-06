//
//  ArticleThemeGalleryView.swift
//  NetNewsWire-iOS
//
//  Created for Settings → Theme (Gallery). Split from the former single
//  ArticleThemeListView.swift per theme-settings-implementation-plan.md:
//  this screen picks a theme; ArticleThemeCustomizeView adjusts overrides
//  for whichever theme is current.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
	static var netNewsWireTheme: UTType { UTType(importedAs: "com.ranchero.netnewswire.theme") }
}

/// A `LazyVGrid` of cheap color-swatch cells -- no `WKWebView` per cell, since
/// rendering 30+ simultaneous web views to preview every theme at once would be far
/// too expensive. Each cell reuses `ArticleThemeColorExtractor.colors(for:)`, the
/// same color-extraction path `ArticleThemeCustomizeView` already uses to seed its
/// color pickers, so there's no second extraction code path to keep in sync.
struct ArticleThemeGalleryView: View {

	/// Set by the caller after init -- a `UIHostingController(rootView:)` can't see
	/// the `navigationController` it's about to be pushed into, so the second push
	/// (to Customize) has to be handed in as a closure rather than expressed as a
	/// `NavigationLink`, which would require a `NavigationStack` ancestor this
	/// screen doesn't have (it's pushed directly onto an existing
	/// `UINavigationController`, the same one-level relationship
	/// `ArticleThemeListView` relied on before this split).
	var onCustomizeCurrentTheme: (() -> Void)?

	@Environment(\.dismiss) private var dismiss

	@State private var isImporterPresented = false
	@State private var themeNamesRefreshToken = false
	@State private var themeToDelete: String?
	@State private var isDeleteAlertPresented = false
	@State private var searchText = ""

	private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

	var body: some View {
		content
			.searchable(text: $searchText)
			.navigationTitle(Text("Theme", comment: "Theme navigation title"))
			.toolbar { toolbarContent }
			.fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [UTType.netNewsWireTheme]) { result in
				guard case .success(let url) = result else { return }
				importTheme(url: url)
			}
			.alert(Text("Delete Theme?", comment: "Delete Theme"), isPresented: $isDeleteAlertPresented, presenting: themeToDelete) { themeName in
				deleteAlertActions(themeName)
			} message: { themeName in
				deleteAlertMessage(themeName)
			}
			.onReceive(NotificationCenter.default.publisher(for: .ArticleThemeNamesDidChangeNotification)) { _ in
				themeNamesRefreshToken.toggle()
			}
			.onReceive(NotificationCenter.default.publisher(for: .CurrentArticleThemeDidChangeNotification)) { _ in
				themeNamesRefreshToken.toggle()
			}
	}

	@ViewBuilder
	private var content: some View {
		// Reading themeNamesRefreshToken here (even though it isn't otherwise used)
		// forces this view to be re-evaluated when the notification observers below
		// flip it, since ArticleThemesManager itself isn't ObservableObject -- the
		// same pattern themesSection used in the pre-split ArticleThemeListView.
		// swiftlint:disable:next redundant_discardable_let
		let _ = themeNamesRefreshToken

		ScrollView {
			LazyVGrid(columns: columns, spacing: 16) {
				myThemesSection
				builtInSection
			}
			.padding()
		}
	}

	@ViewBuilder
	private var myThemesSection: some View {
		let importedThemeNames = grouped.singles.filter { !isAppTheme($0) }
		if !importedThemeNames.isEmpty {
			sectionHeader(Text("My Themes", comment: "My Themes gallery section header"))
			ForEach(importedThemeNames, id: \.self) { themeName in
				themeCell(themeName)
			}
		}
	}

	@ViewBuilder
	private var builtInSection: some View {
		let builtInThemeNames = grouped.singles.filter { isAppTheme($0) }
		sectionHeader(Text("Built-in", comment: "Built-in gallery section header"))
		ForEach(grouped.families, id: \.name) { family in
			familyCell(family)
		}
		ForEach(builtInThemeNames, id: \.self) { themeName in
			themeCell(themeName)
		}
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItem(placement: .primaryAction) {
			Button {
				isImporterPresented = true
			} label: {
				Image(systemName: "plus")
			}
			.accessibilityLabel(Text("Import Theme", comment: "Import Theme"))
		}
		ToolbarItem(placement: .secondaryAction) {
			Button {
				onCustomizeCurrentTheme?()
			} label: {
				Text("Customize", comment: "Customize current theme button")
			}
		}
	}

	@ViewBuilder
	private func deleteAlertActions(_ themeName: String) -> some View {
		Button(role: .cancel) { } label: {
			Text("Cancel", comment: "Cancel button")
		}
		Button(role: .destructive) {
			ArticleThemesManager.shared.deleteTheme(themeName: themeName)
		} label: {
			Text("Delete", comment: "Delete button")
		}
	}

	private func deleteAlertMessage(_ themeName: String) -> some View {
		let localizedMessageText = NSLocalizedString("Are you sure you want to delete the theme “%@”?.", comment: "Delete Theme Message")
		return Text(NSString.localizedStringWithFormat(localizedMessageText as NSString, themeName) as String)
	}

	// MARK: - Grouping

	private struct ThemeFamily {
		var name: String
		var variantThemeNames: [String]
	}

	/// Groups theme names by `ArticleTheme.family` (via `Info.plist`'s optional
	/// `Family` key), preserving `ArticleThemesManager`'s existing case-insensitive
	/// sort within each group and among families themselves. Families with only one
	/// member don't occur in practice (see Technotes/Themes.md's "Theme families"
	/// section: "don't add Family unless there are genuinely 2+ sibling bundles"),
	/// but if one ever did, it would fall through to `singles` here rather than
	/// render as a one-item family cell, since `familiesByName` filters those out.
	private var grouped: (families: [ThemeFamily], singles: [String]) {
		let allNames = [ArticleTheme.defaultTheme.name] + ArticleThemesManager.shared.themeNames
		let filtered = searchText.isEmpty ? allNames : allNames.filter { matchesSearch($0) }

		var familiesByName = [String: [String]]()
		var singles = [String]()

		for themeName in filtered {
			if let family = ArticleThemesManager.shared.articleThemeWithThemeName(themeName)?.family {
				familiesByName[family, default: []].append(themeName)
			} else {
				singles.append(themeName)
			}
		}

		let families = familiesByName
			.filter { $0.value.count > 1 }
			.map { ThemeFamily(name: $0.key, variantThemeNames: $0.value.sorted(by: caseInsensitiveLess)) }
			.sorted { caseInsensitiveLess($0.name, $1.name) }

		// Families with exactly one surviving match (e.g. search narrowed a family
		// down to one variant) fall back to being listed as a single, since a
		// one-item family cell would be confusing UI, not because Info.plist's
		// Family key itself only allows 2+.
		let strandedFamilyMembers = familiesByName.filter { $0.value.count == 1 }.flatMap { $0.value }

		return (families, (singles + strandedFamilyMembers).sorted(by: caseInsensitiveLess))
	}

	private func caseInsensitiveLess(_ lhs: String, _ rhs: String) -> Bool {
		lhs.compare(rhs, options: .caseInsensitive) == .orderedAscending
	}

	/// Matches by theme name and, for a family, by any variant's name -- typing
	/// "Dracula" or "Purple" both surface the Dracula family cell.
	private func matchesSearch(_ themeName: String) -> Bool {
		themeName.localizedCaseInsensitiveContains(searchText)
	}

	private func isAppTheme(_ themeName: String) -> Bool {
		ArticleThemesManager.shared.articleThemeWithThemeName(themeName)?.isAppTheme ?? true
	}

	// MARK: - Cells

	private func sectionHeader(_ text: Text) -> some View {
		text
			.font(.headline)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.top, 8)
	}

	private func swatchColors(for themeName: String) -> ArticleThemeColorExtractor.ThemeColors {
		guard let theme = ArticleThemesManager.shared.articleThemeWithThemeName(themeName) else {
			return ArticleThemeColorExtractor.colors(for: ArticleTheme.defaultTheme)
		}
		return ArticleThemeColorExtractor.colors(for: theme)
	}

	@ViewBuilder
	private func themeCell(_ themeName: String) -> some View {
		let isCurrent = themeName == ArticleThemesManager.shared.currentTheme.name
		let isImported = !isAppTheme(themeName)

		Button {
			ArticleThemesManager.shared.currentThemeName = themeName
		} label: {
			VStack(spacing: 6) {
				swatchGrid(for: themeName)
					.overlay(alignment: .topTrailing) {
						if isCurrent {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.white, .tint)
								.padding(6)
						}
					}
				Text(themeName)
					.font(.footnote)
					.foregroundStyle(.primary)
					.lineLimit(1)
			}
		}
		.buttonStyle(.plain)
		.swipeActions(edge: .trailing) {
			if isImported {
				Button(role: .destructive) {
					themeToDelete = themeName
					isDeleteAlertPresented = true
				} label: {
					Label {
						Text("Delete", comment: "Delete button")
					} icon: {
						Image(systemName: "trash")
					}
				}
			}
		}
	}

	@ViewBuilder
	private func familyCell(_ family: ThemeFamily) -> some View {
		// The currently-selected variant's swatch is the thumbnail, falling back to
		// the family's first variant if none is currently selected.
		let currentThemeName = ArticleThemesManager.shared.currentTheme.name
		let thumbnailThemeName = family.variantThemeNames.contains(currentThemeName)
			? currentThemeName
			: family.variantThemeNames.first!

		VStack(spacing: 6) {
			swatchGrid(for: thumbnailThemeName)
			Text(family.name)
				.font(.footnote)
				.foregroundStyle(.primary)
				.lineLimit(1)
			HStack(spacing: 4) {
				ForEach(family.variantThemeNames, id: \.self) { variantName in
					let colors = swatchColors(for: variantName)
					Button {
						ArticleThemesManager.shared.currentThemeName = variantName
					} label: {
						Circle()
							.fill(Color(colors.linkColor))
							.frame(width: 14, height: 14)
							.overlay {
								if variantName == currentThemeName {
									Circle().strokeBorder(.tint, lineWidth: 2)
								}
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel(Text(variantName))
				}
			}
		}
	}

	private func swatchGrid(for themeName: String) -> some View {
		let colors = swatchColors(for: themeName)
		return VStack(spacing: 0) {
			HStack(spacing: 0) {
				Color(colors.backgroundColor)
				Color(colors.textColor)
			}
			HStack(spacing: 0) {
				Color(colors.linkColor)
				Color(colors.backgroundColorDark)
			}
		}
		.frame(height: 72)
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.overlay {
			RoundedRectangle(cornerRadius: 10)
				.strokeBorder(.separator, lineWidth: 0.5)
		}
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

#Preview {
	NavigationStack {
		ArticleThemeGalleryView()
	}
}
