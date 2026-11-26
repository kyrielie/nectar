//
//  SettingsSearchIndex.swift
//  NetNewsWire-iOS
//
//  Searchable index of settings items and nested subpage paths for `SettingsView`,
//  providing Aidoku-style breadcrumb results when searching.
//

import SwiftUI

struct SettingsSearchItem: Identifiable {
	let id: String
	let title: String
	let breadcrumb: [String]
	let keywords: [String]
	let systemImage: String
	let badgeColor: Color
	let destination: SettingsDestination

	func matches(_ query: String) -> Bool {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return false }
		if title.localizedCaseInsensitiveContains(trimmed) { return true }
		if breadcrumb.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
		return keywords.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
	}
}

enum SettingsSearchIndex {

	static let allItems: [SettingsSearchItem] = [
		// Archive of Our Own
		SettingsSearchItem(
			id: "ao3-account",
			title: NSLocalizedString("Archive of Our Own Account", comment: "AO3 account row"),
			breadcrumb: ["Archive of Our Own"],
			keywords: ["ao3", "login", "sign in", "session", "kudos", "cloudflare", "verification", "ignore", "attention"],
			systemImage: "person.crop.circle.fill",
			badgeColor: .red,
			destination: .ao3Account
		),
		SettingsSearchItem(
			id: "ao3-attention",
			title: NSLocalizedString("Works Needing Attention", comment: "AO3 settings: works needing attention row title"),
			breadcrumb: ["Archive of Our Own", "Account"],
			keywords: ["ao3", "pending", "regression", "missing", "retry"],
			systemImage: "exclamationmark.triangle.fill",
			badgeColor: .orange,
			destination: .ao3WorksNeedingAttention
		),
		SettingsSearchItem(
			id: "ao3-ignore",
			title: NSLocalizedString("Ignored Works and Authors", comment: "AO3 settings: ignore list row title"),
			breadcrumb: ["Archive of Our Own", "Account"],
			keywords: ["ao3", "block", "mute", "ignore", "author"],
			systemImage: "eye.slash.fill",
			badgeColor: .gray,
			destination: .ao3IgnoreList
		),

		// Timeline
		SettingsSearchItem(
			id: "timeline-layout",
			title: NSLocalizedString("Timeline Layout", comment: "Timeline Layout"),
			breadcrumb: ["Timeline"],
			keywords: ["lines", "tags", "badges", "stats", "word count", "preview"],
			systemImage: "list.bullet.rectangle.fill",
			badgeColor: .indigo,
			destination: .timelineLayout
		),

		// Reader
		SettingsSearchItem(
			id: "works-theme",
			title: NSLocalizedString("Theme", comment: "Theme"),
			breadcrumb: ["Reader"],
			keywords: ["font", "serif", "sans", "size", "line spacing", "margins", "colors", "creator style", "dark mode"],
			systemImage: "doc.richtext.fill",
			badgeColor: .purple,
			destination: .articleTheme
		),
		SettingsSearchItem(
			id: "works-toolbars",
			title: NSLocalizedString("Toolbars", comment: "Toolbars"),
			breadcrumb: ["Reader"],
			keywords: ["top bar", "bottom bar", "overflow", "buttons", "reorder", "reset"],
			systemImage: "menubar.rectangle",
			badgeColor: .indigo,
			destination: .toolbars
		),
		SettingsSearchItem(
			id: "works-fullscreen",
			title: NSLocalizedString("Full Screen Reading", comment: "Full Screen Reading"),
			breadcrumb: ["Reader"],
			keywords: ["swipe", "paging", "context menu", "scrollbar", "page counter", "notch"],
			systemImage: "arrow.up.left.and.arrow.down.right",
			badgeColor: .green,
			destination: .fullScreenReading
		),
		SettingsSearchItem(
			id: "works-text-replacement",
			title: NSLocalizedString("Text Replacement", comment: "Text Replacement"),
			breadcrumb: ["Reader"],
			keywords: ["y/n", "reader insert", "typos", "quotes", "find and replace"],
			systemImage: "textformat.abc",
			badgeColor: .pink,
			destination: .textReplacement
		),

		// Reading Activity
		SettingsSearchItem(
			id: "works-reading-time",
			title: NSLocalizedString("Reading Time", comment: "Reading Time"),
			breadcrumb: ["Reading Activity"],
			keywords: ["daily limit", "bedtime", "break", "reminder", "indicator", "lockout"],
			systemImage: "hourglass",
			badgeColor: .cyan,
			destination: .readingTime
		),
		SettingsSearchItem(
			id: "works-reading-stats",
			title: NSLocalizedString("Reading Stats", comment: "Reading Stats"),
			breadcrumb: ["Reading Activity"],
			keywords: ["words", "streak", "heatmap", "fandom", "tags", "monthly"],
			systemImage: "chart.bar.fill",
			badgeColor: .indigo,
			destination: .readingStats
		),
		SettingsSearchItem(
			id: "works-annotations",
			title: NSLocalizedString("Highlights & Notes", comment: "Highlights & Notes"),
			breadcrumb: ["Reading Activity"],
			keywords: ["annotations", "highlight", "palette", "popup", "export", "csv"],
			systemImage: "highlighter",
			badgeColor: .orange,
			destination: .annotations
		),

		// Appearance
		SettingsSearchItem(
			id: "appearance-palette",
			title: NSLocalizedString("Color Palette", comment: "Color Palette"),
			breadcrumb: ["Appearance"],
			keywords: ["dark", "light", "automatic", "surface", "toolbar style", "blend", "tinted"],
			systemImage: "paintpalette.fill",
			badgeColor: .pink,
			destination: .colorPalette
		),
		SettingsSearchItem(
			id: "appearance-accent",
			title: NSLocalizedString("Accent Color", comment: "Accent Color"),
			breadcrumb: ["Appearance"],
			keywords: ["tint", "badge colors", "rose pine", "slate", "forest", "berry", "ocean"],
			systemImage: "drop.halffull",
			badgeColor: .blue,
			destination: .accentColor
		),

		// Troubleshooting
		SettingsSearchItem(
			id: "troubleshooting-errors",
			title: NSLocalizedString("Error Log", comment: "Error Log"),
			breadcrumb: ["Troubleshooting"],
			keywords: ["errors", "diagnostics", "copy"],
			systemImage: "exclamationmark.bubble.fill",
			badgeColor: .red,
			destination: .errorLog
		),
		SettingsSearchItem(
			id: "troubleshooting-activity",
			title: NSLocalizedString("Activity Log", comment: "Activity Log"),
			breadcrumb: ["Troubleshooting"],
			keywords: ["network", "refresh", "sync", "history"],
			systemImage: "clock.arrow.circlepath",
			badgeColor: .orange,
			destination: .activityLog
		),
		SettingsSearchItem(
			id: "troubleshooting-stats",
			title: NSLocalizedString("Library Stats", comment: "Library Stats"),
			breadcrumb: ["Troubleshooting"],
			keywords: ["database", "vacuum", "feeds", "works", "size"],
			systemImage: "internaldrive.fill",
			badgeColor: .gray,
			destination: .accountStats
		),
		SettingsSearchItem(
			id: "troubleshooting-dinosaurs",
			title: NSLocalizedString("Dinosaurs", comment: "Dinosaurs"),
			breadcrumb: ["Troubleshooting"],
			keywords: ["inactive", "stale", "feeds"],
			systemImage: "fossil.shell.fill",
			badgeColor: .green,
			destination: .dinosaurs
		),

		// Storage & Backup
		SettingsSearchItem(
			id: "storage-manage",
			title: NSLocalizedString("Manage Storage", comment: "Manage Storage"),
			breadcrumb: ["Storage & Backup"],
			keywords: ["cache", "delete", "html", "space", "size"],
			systemImage: "externaldrive.fill.badge.minus",
			badgeColor: .gray,
			destination: .manageStorage
		),

		// Help
		SettingsSearchItem(
			id: "help-about",
			title: NSLocalizedString("About Nectar", comment: "About Nectar"),
			breadcrumb: ["Help"],
			keywords: ["version", "credits", "license", "open source"],
			systemImage: "info.circle.fill",
			badgeColor: .gray,
			destination: .about
		)
	]

	static func results(for query: String) -> [SettingsSearchItem] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return [] }
		return allItems.filter { $0.matches(trimmed) }
	}
}
